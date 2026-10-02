"""Local HTTP / CONNECT / SOCKS5 fixtures. No external services required."""
import http.server
import base64
import hashlib
import json
import io
import math
import wave
import zlib
from pathlib import Path
import select
import socket
import socketserver
import struct
import threading
import time
import tls_fixture
from urllib.parse import urlsplit, parse_qs


class API(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        self.respond()

    def do_POST(self):
        self.respond()

    def do_PUT(self):
        self.respond()

    def respond(self):
        path = urlsplit(self.path)
        if path.path == '/websocket':
            self.websocket()
            return
        if path.path == '/events':
            data = b': heartbeat\r\nid: 1\r\nevent: update\r\ndata: {"value":42}\r\n\r\n'
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if path.path == '/oauth/token':
            body = parse_qs(self.rfile.read(int(self.headers.get('Content-Length', 0))).decode())
            valid = body.get('grant_type') == ['refresh_token'] and body.get('refresh_token') == ['fixture-refresh']
            data = json.dumps({'access_token': 'fixture-access', 'refresh_token': 'fixture-rotated', 'expires_in': 3600, 'token_type': 'Bearer'} if valid else {'error': 'invalid_grant'}).encode()
            self.send_response(200 if valid else 400)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if path.path == '/cookie-redirect':
            self.send_response(302)
            self.send_header('Location', '/echo')
            self.send_header('Set-Cookie', 'fixture=redirect; Path=/; HttpOnly')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return
        if path.path.startswith('/media/'):
            kind = path.path.rsplit('/', 1)[-1]
            mime, data = 'application/octet-stream', bytes(range(256))
            if kind == 'png':
                def chunk(name, value):
                    return struct.pack('!I', len(value)) + name + value + struct.pack('!I', zlib.crc32(name + value))
                data = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 64, 64, 8, 2, 0, 0, 0))
                        + chunk(b'IDAT', zlib.compress((b'\x00' + b'\x16\x7b\x67' * 64) * 64)) + chunk(b'IEND', b''))
                mime = 'image/png'
            elif kind == 'wav':
                buffer = io.BytesIO()
                with wave.open(buffer, 'wb') as sound:
                    sound.setnchannels(1)
                    sound.setsampwidth(2)
                    sound.setframerate(8000)
                    sound.writeframes(b''.join(struct.pack('<h', int(1200 * math.sin(i * math.pi * 440 / 4000))) for i in range(16000)))
                data, mime = buffer.getvalue(), 'audio/wav'
            elif kind == 'mp4':
                data, mime = Path(__file__).with_name('fixtures').joinpath('sample.mp4').read_bytes(), 'video/mp4'
            elif kind == 'fake-image':
                data, mime = b'not an image', 'image/png'
            elif kind == 'fake-audio':
                data, mime = b'not audio', 'audio/wav'
            self.send_response(200)
            self.send_header('Content-Type', mime)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if path.path in ['/tls-ca', '/tls-captures', '/client-identity']:
            with tls_fixture.lock:
                data = tls_fixture.ca_pem if path.path == '/tls-ca' else tls_fixture.client_p12 if path.path == '/client-identity' else json.dumps(tls_fixture.captures).encode()
            self.send_response(200)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if path.path == '/slow':
            time.sleep(4)
        if path.path in ['/redirect', '/cross-origin']:
            self.send_response(302)
            self.send_header('Location', '/echo' if path.path == '/redirect' else 'http://localhost:8766/echo')
            self.end_headers()
            return
        if path.path == '/oversize':
            self.send_response(200)
            self.send_header('Content-Length', '30000000')
            self.end_headers()
            self.wfile.write(b'x' * 1024)
            self.wfile.flush()
            time.sleep(1)
            return
        raw_body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        body = raw_body.decode(errors='replace')
        payload = {'message': 'Hello from Monkeytail', 'method': self.command,
                   'path': path.path, 'query': parse_qs(path.query),
                   'headers': dict(self.headers), 'body': body,
                   'data': {'name': 'Monkeytail', 'native': True, 'platforms': ['iPhone', 'iPhone Duo', 'iPad']}}
        if path.path == '/upload':
            import base64
            payload['bodyBase64'] = base64.b64encode(raw_body).decode()
        if path.path == '/body-layout':
            payload = {'aMessage': 'Hello from Monkeytail',
                       'items': [{'index': i, 'value': 'Response row'} for i in range(80)],
                       'longLine': '0123456789' * 100}
        encoded = json.dumps(payload, separators=(',', ':')).encode()
        if path.path == '/compact-body-layout':
            payload = {'message': 'Hello from Monkeytail', 'success': True, 'padding': ''}
            payload['padding'] = 'x' * (422 - len(json.dumps(payload, separators=(',', ':')).encode()))
            encoded = json.dumps(payload, separators=(',', ':')).encode()
        if path.path == '/captured-body-layout':
            # Shape and byte count of the reported response; all values sanitized.
            payload = {'onetimeCode': '#0000000', 'onetimeExpiredDate': '0000-00-00x00:00:00x',
                       'usedCoupons': [{'usedCouponId': '00000', 'expiredDate': '0000-00-00x00:00:00x',
                                        'dailyUsedFlag': False} for _ in range(4)]}
            encoded = json.dumps(payload, separators=(',', ':')).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(encoded)))
        self.send_header('X-Monkeytail-Fixture', 'true')
        self.end_headers()
        try:
            self.wfile.write(encoded)
        except BrokenPipeError:
            pass

    def websocket(self):
        self.protocol_version = 'HTTP/1.1'
        key = self.headers.get('Sec-WebSocket-Key')
        if not key:
            self.send_error(400)
            return
        accept = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
        self.send_response(101)
        self.send_header('Upgrade', 'websocket')
        self.send_header('Connection', 'Upgrade')
        self.send_header('Sec-WebSocket-Accept', accept)
        self.end_headers()
        self.connection.settimeout(10)
        try:
            while True:
                first = self.rfile.read(2)
                if len(first) != 2:
                    return
                opcode, size = first[0] & 15, first[1] & 127
                if size == 126:
                    size = struct.unpack('!H', self.rfile.read(2))[0]
                elif size == 127:
                    size = struct.unpack('!Q', self.rfile.read(8))[0]
                if size > 1024 * 1024:
                    return
                mask = self.rfile.read(4) if first[1] & 128 else b''
                data = self.rfile.read(size)
                if len(data) != size:
                    return
                if mask:
                    data = bytes(value ^ mask[i % 4] for i, value in enumerate(data))
                if opcode == 8:
                    return
                opcode = 10 if opcode == 9 else opcode
                header = bytes([128 | opcode, len(data)]) if len(data) < 126 else bytes([128 | opcode, 126]) + struct.pack('!H', len(data)) if len(data) < 65536 else bytes([128 | opcode, 127]) + struct.pack('!Q', len(data))
                self.wfile.write(header + data)
                self.wfile.flush()
        except (OSError, ValueError):
            return


def relay(client, remote):
    with remote:
        while True:
            readable, _, _ = select.select([client, remote], [], [], 15)
            if not readable:
                return
            for current in readable:
                data = current.recv(65536)
                if not data:
                    return
                (remote if current is client else client).sendall(data)


class CONNECT(socketserver.StreamRequestHandler):
    def handle(self):
        first = self.rfile.readline().decode().strip()
        while self.rfile.readline().strip():
            pass
        if not first.startswith('CONNECT '):
            self.wfile.write(b'HTTP/1.1 405 Method Not Allowed\r\n\r\n')
            return
        target = first.split()[1]
        host, port = target.rsplit(':', 1)
        remote = socket.create_connection(('127.0.0.1' if host == 'monkeytail.test' else host, int(port)))
        self.wfile.write(b'HTTP/1.1 200 Connection Established\r\n\r\n')
        self.wfile.flush()
        relay(self.connection, remote)


class SOCKS(socketserver.StreamRequestHandler):
    def handle(self):
        version, count = self.rfile.read(2)
        self.rfile.read(count)
        self.wfile.write(b'\x05\x00'); self.wfile.flush()
        version, command, _, kind = self.rfile.read(4)
        if kind == 3:
            host = self.rfile.read(self.rfile.read(1)[0]).decode()
        elif kind == 1:
            host = socket.inet_ntop(socket.AF_INET, self.rfile.read(4))
        elif kind == 4:
            host = socket.inet_ntop(socket.AF_INET6, self.rfile.read(16))
        else:
            return
        port = struct.unpack('!H', self.rfile.read(2))[0]
        remote = socket.create_connection(('127.0.0.1' if host == 'monkeytail.test' else host, port))
        self.wfile.write(b'\x05\x00\x00\x01\x7f\x00\x00\x01\x22\x3e'); self.wfile.flush()
        relay(self.connection, remote)


class ThreadedTCP(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


if __name__ == '__main__':
    servers = [http.server.ThreadingHTTPServer(('127.0.0.1', 8766), API),
               ThreadedTCP(('127.0.0.1', 8767), CONNECT), ThreadedTCP(('127.0.0.1', 8768), SOCKS), tls_fixture.make_server()]
    for server in servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    print('Fixture HTTP :8766 · CONNECT :8767 · SOCKS5 :8768', flush=True)
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        for server in servers:
            server.shutdown()
