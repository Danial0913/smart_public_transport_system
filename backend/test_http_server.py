"""Exercise real HTTP connections without Gmail or the user's recovery database."""
import hashlib
import http.client
import json
import socket
import tempfile
import threading
import unittest
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from app import RecoveryApp, create_local_server
from recovery import RecoveryService


class RecoveryHttpTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.messages = []
        self.service = RecoveryService(
            str(Path(self.temp.name) / 'test.db'),
            'test-only-secret-with-at-least-32-characters',
            'https://recovery.example.com',
            lambda email, otp, link: self.messages.append((email, otp, link)),
        )
        self.server = create_local_server(RecoveryApp(self.service), port=0)
        self.port = self.server.server_port
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=3)
        self.temp.cleanup()

    def call(self, path, data=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=2)
        try:
            connection.request('GET' if data is None else 'POST', path,
                               body=None if data is None else json.dumps(data),
                               headers={'Content-Type': 'application/json'})
            response = connection.getresponse()
            body = response.read()
            self.assertEqual(response.status, 200, body)
            return json.loads(body)
        finally:
            connection.close()

    def test_idle_browser_connection_does_not_block_otp_or_link(self):
        # Browsers can preconnect without sending an HTTP request yet.
        accepted = threading.Event()
        original_get_request = self.server.get_request

        def observe_accept():
            request = original_get_request()
            accepted.set()
            return request

        self.server.get_request = observe_accept
        idle = socket.create_connection(('127.0.0.1', self.port), timeout=2)
        try:
            self.assertTrue(accepted.wait(timeout=2))
            self.assertEqual(self.call('/health'), {'status': 'ok'})
            for method in ('otp', 'link'):
                request = self.call('/v1/recovery/request', {'email': f'{method}@example.com'})
                session = {key: request[key] for key in ('requestId', 'sessionToken')}
                _, otp, link = self.messages[-1]
                if method == 'otp':
                    result = self.call('/v1/recovery/verify', {**session, 'otp': otp})
                else:
                    params = parse_qs(urlparse(link).fragment)
                    result = self.call('/v1/recovery/link', {
                        'requestId': params['requestId'][0], 'token': params['token'][0],
                    })
                self.assertTrue(result['verified'])
                self.assertTrue(self.call('/v1/recovery/status', session)['verified'])
                digest = hashlib.sha256(b'test-password-123').hexdigest()
                result = self.call('/v1/recovery/complete', {**session, 'passwordDigest': digest})
                self.assertTrue(result['completed'])
                self.assertEqual(result['passwordDigest'], digest)
        finally:
            idle.close()

    def test_second_server_cannot_claim_an_active_port(self):
        with self.assertRaises(OSError):
            with create_local_server(RecoveryApp(self.service), port=self.port):
                pass


if __name__ == '__main__':
    unittest.main()
