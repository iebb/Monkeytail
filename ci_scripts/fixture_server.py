"""Local HTTP / CONNECT / SOCKS5 fixtures. No external services required."""
import http.server
import json
import select
import socket
import socketserver
import struct
import threading
import time
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
        body = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode()
        payload = {'message': 'Hello from Monkeytail', 'method': self.command,
                   'path': path.path, 'query': parse_qs(path.query),
                   'headers': dict(self.headers), 'body': body,
                   'data': {'name': 'Monkeytail', 'native': True, 'platforms': ['iPhone', 'iPhone Duo', 'iPad']}}
        if path.path == '/body-layout':
            payload = {'aMessage': 'Hello from Monkeytail',
                       'items': [{'index': i, 'value': 'Response row'} for i in range(80)],
                       'longLine': '0123456789' * 100}
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
               ThreadedTCP(('127.0.0.1', 8767), CONNECT), ThreadedTCP(('127.0.0.1', 8768), SOCKS)]
    for server in servers:
        threading.Thread(target=server.serve_forever, daemon=True).start()
    print('Fixture HTTP :8766 · CONNECT :8767 · SOCKS5 :8768', flush=True)
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        for server in servers:
            server.shutdown()
