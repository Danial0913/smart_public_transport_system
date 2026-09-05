import json
import os
import socket
from pathlib import Path
from socketserver import ThreadingMixIn
from wsgiref.simple_server import make_server, WSGIRequestHandler, WSGIServer

from mailer import SmtpMailer
from recovery import RecoveryError, RecoveryService


def load_environment():
    path = Path(__file__).with_name('.env')
    if path.exists():
        for line in path.read_text(encoding='utf-8').splitlines():
            if line.strip() and not line.lstrip().startswith('#'):
                key, value = line.split('=', 1)
                os.environ.setdefault(key.strip(), value.strip())


class RecoveryApp:
    def __init__(self, service):
        self.service = service

    def __call__(self, env, start_response):
        status, content_type = 200, 'application/json'
        try:
            path, method = env['PATH_INFO'], env['REQUEST_METHOD']
            if method == 'GET' and path == '/health':
                body = b'{"status":"ok"}'
            elif method == 'GET' and path in ('/reset', '/reset.js', '/reset.css'):
                name, content_type = {
                    '/reset': ('reset.html', 'text/html; charset=utf-8'),
                    '/reset.js': ('reset.js', 'application/javascript'),
                    '/reset.css': ('reset.css', 'text/css'),
                }[path]
                body = Path(__file__).with_name('static').joinpath(name).read_bytes()
            elif method == 'POST' and path.startswith('/v1/recovery/'):
                if env.get('CONTENT_TYPE', '').split(';')[0] != 'application/json':
                    raise RecoveryError(415, 'JSON required')
                length = int(env.get('CONTENT_LENGTH') or 0)
                if length <= 0 or length > 4096:
                    raise RecoveryError(413, 'Invalid request size')
                data = json.loads(env['wsgi.input'].read(length))
                if not isinstance(data, dict) or any(not isinstance(v, str) or len(v) > 512 for v in data.values()):
                    raise RecoveryError(400, 'Invalid request')
                # Do not trust arbitrary X-Forwarded-For from public callers.
                ip = env.get('REMOTE_ADDR', 'unknown')
                request_id, token = data.get('requestId', ''), data.get('sessionToken', '')
                endpoint = path.rsplit('/', 1)[-1]
                if endpoint == 'request':
                    result = self.service.request(data.get('email', ''), ip)
                elif endpoint == 'resend':
                    result = self.service.resend(request_id, token, ip)
                elif endpoint == 'verify':
                    result = self.service.verify(request_id, token, data.get('otp', ''))
                elif endpoint == 'link':
                    result = self.service.confirm_link(request_id, data.get('token', ''))
                elif endpoint == 'status':
                    result = self.service.status(request_id, token)
                elif endpoint == 'complete':
                    result = self.service.complete(request_id, token, data.get('passwordDigest', ''))
                else:
                    raise RecoveryError(404, 'Not found')
                body = json.dumps(result).encode()
            else:
                raise RecoveryError(404, 'Not found')
        except RecoveryError as error:
            status, body = error.status, json.dumps({'error': str(error)}).encode()
        except (ValueError, TypeError):
            status, body = 400, b'{"error":"Invalid request"}'
        except Exception:
            status, body = 500, b'{"error":"Recovery service unavailable"}'
        labels = {200: 'OK', 400: 'Bad Request', 404: 'Not Found', 413: 'Content Too Large',
                  415: 'Unsupported Media Type', 429: 'Too Many Requests', 500: 'Internal Server Error', 503: 'Service Unavailable'}
        headers = [('Content-Type', content_type), ('Content-Length', str(len(body))),
                   ('Cache-Control', 'no-store'), ('Referrer-Policy', 'no-referrer'),
                   ('X-Content-Type-Options', 'nosniff'), ('X-Frame-Options', 'DENY'),
                   ('Content-Security-Policy', "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")]
        if status == 429:
            headers.append(('Retry-After', '60'))
        start_response(f'{status} {labels[status]}', headers)
        return [body]


def create_app():
    load_environment()
    return RecoveryApp(RecoveryService(
        os.environ.get('RECOVERY_DATABASE', str(Path(__file__).with_name('recovery.db'))),
        os.environ['RECOVERY_SECRET'], os.environ['PUBLIC_URL'], SmtpMailer(),
    ))


class QuietHandler(WSGIRequestHandler):
    def setup(self):
        # Discard idle browser preconnections and incomplete request bodies.
        self.request.settimeout(10)
        super().setup()

    def log_message(self, format, *args):
        pass


class LocalRecoveryServer(ThreadingMixIn, WSGIServer):
    daemon_threads = True
    allow_reuse_address = os.name != 'nt'

    def server_bind(self):
        # Windows SO_REUSEADDR can let two servers claim the same port.
        if os.name == 'nt':
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()


def create_local_server(application, port=8787):
    def threaded_application(env, start_response):
        env['wsgi.multithread'] = True
        return application(env, start_response)

    return make_server('127.0.0.1', port, threaded_application,
                       server_class=LocalRecoveryServer, handler_class=QuietHandler)


if __name__ == '__main__':
    application = create_app()
    # Local development only. Use an HTTPS reverse proxy and production WSGI
    # server for deployment. No OTP, link, body, or session token is logged.
    port = int(os.environ.get('PORT', '8787'))
    try:
        server = create_local_server(application, port)
    except OSError as error:
        raise SystemExit(f'Could not start recovery server on port {port}. '
                         'Stop the existing recovery server before restarting.') from error
    with server:
        print(f'Recovery server listening on loopback port {port} (concurrent requests enabled)', flush=True)
        server.serve_forever()
