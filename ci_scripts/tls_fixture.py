"""Local TLS ClientHello and HTTP/2 capture. Test certificates never leave localhost."""
import json
import socket
import socketserver
import ssl
import struct
import subprocess
import tempfile
import threading
from pathlib import Path

captures = []
lock = threading.Lock()
ca_pem = b''
context = None
_certificate_directory = None


def u16(data):
    return int.from_bytes(data[:2], 'big')


def hello(data):
    # The fixtures inspect a complete, bounded first TLS handshake record.
    body = data[9:]
    offset = 34
    offset += 1 + body[offset]
    length = u16(body[offset:]); offset += 2
    ciphers = [u16(body[i:i+2]) for i in range(offset, offset+length, 2)]
    offset += length
    offset += 1 + body[offset]
    length = u16(body[offset:]); offset += 2
    end = offset + length
    extensions, groups, alpn = [], [], []
    while offset + 4 <= end:
        kind, length = struct.unpack('!HH', body[offset:offset+4]); offset += 4
        value = body[offset:offset+length]; offset += length
        extensions.append(kind)
        if kind == 10:
            groups = [u16(value[i:i+2]) for i in range(2, len(value), 2)]
        if kind == 16:
            i = 2
            while i < len(value):
                n = value[i]; i += 1
                alpn.append(value[i:i+n].decode()); i += n
    return {'ciphers': ciphers, 'extensions': extensions, 'groups': groups, 'alpn': alpn}


def exact(connection, length):
    output = b''
    while len(output) < length:
        chunk = connection.recv(length-len(output))
        if not chunk: raise EOFError()
        output += chunk
    return output


def frame(kind, flags, stream, payload=b''):
    return len(payload).to_bytes(3, 'big') + bytes([kind, flags]) + struct.pack('!I', stream) + payload


class Capture(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(5)
        try:
            prefix = self.request.recv(5, socket.MSG_PEEK | socket.MSG_WAITALL)
            size = 5 + u16(prefix[3:])
            if not 9 <= size <= 65536: return
            record = self.request.recv(size, socket.MSG_PEEK | socket.MSG_WAITALL)
            captured = hello(record)
            with lock: captures.append(captured)
            with context.wrap_socket(self.request, server_side=True) as connection:
                captured['negotiatedALPN'] = connection.selected_alpn_protocol()
                if captured['negotiatedALPN'] == 'h2':
                    if exact(connection, 24) != b'PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n': return
                    connection.sendall(frame(4, 0, 0))
                    for _ in range(100):
                        header = exact(connection, 9)
                        length = int.from_bytes(header[:3], 'big')
                        kind, flags, stream = header[3], header[4], int.from_bytes(header[5:], 'big')
                        if length > 1024*1024: return
                        payload = exact(connection, length)
                        if kind == 4 and not flags & 1:
                            captured['http2Settings'] = [[u16(payload[i:i+2]), int.from_bytes(payload[i+2:i+6], 'big')] for i in range(0, len(payload), 6)]
                            connection.sendall(frame(4, 1, 0))
                        if kind == 1:
                            data = json.dumps(captured).encode()
                            connection.sendall(frame(1, 4, stream, b'\x88') + frame(0, 1, stream, data))
                            return
                else:
                    exact(connection, 1)
                    connection.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}')
        except (OSError, ssl.SSLError, EOFError, IndexError, ValueError):
            pass


def make_server(port=8769):
    global context, ca_pem, _certificate_directory
    _certificate_directory = tempfile.TemporaryDirectory(prefix='monkeytail-test-ca-')
    root = Path(_certificate_directory.name)
    config = root/'certificate.cnf'
    config.write_text('''[req]
distinguished_name = dn
x509_extensions = extensions
prompt = no
[dn]
CN = Monkeytail Local Test CA
[extensions]
basicConstraints = critical,CA:true
keyUsage = critical,keyCertSign,digitalSignature,keyEncipherment
subjectAltName = DNS:localhost,IP:127.0.0.1
''')
    subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2', '-config', str(config), '-keyout', str(root/'key.pem'), '-out', str(root/'ca.pem')], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ca_pem = (root/'ca.pem').read_bytes()
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(str(root/'ca.pem'), str(root/'key.pem'))
    context.set_alpn_protocols(['h2', 'http/1.1'])
    class Server(socketserver.ThreadingTCPServer):
        allow_reuse_address = True
        daemon_threads = True
    return Server(('127.0.0.1', port), Capture)
