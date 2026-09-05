import hashlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from app import RecoveryApp
from recovery import RecoveryError, RecoveryService


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.now = 100000
        self.messages = []
        self.fail_mail = False
        def send(email, otp, link):
            if self.fail_mail:
                raise OSError('SMTP unavailable')
            self.messages.append((email, otp, link))
        self.service = RecoveryService(str(Path(self.temp.name) / 'recovery.db'),
                                       'test-only-secret-with-at-least-32-characters',
                                       'https://recovery.example.com', send, lambda: self.now)

    def request(self):
        return self.service.request('rider@example.com', 'test-ip')

    def args(self, request):
        return request['requestId'], request['sessionToken']

    def digest(self, password='new-password-123'):
        return hashlib.sha256(password.encode()).hexdigest()

    def test_otp_flow_completion_is_bound_and_idempotent(self):
        request = self.request()
        with self.assertRaises(RecoveryError):
            self.service.complete(*self.args(request), self.digest())
        self.service.verify(*self.args(request), self.messages[-1][1])
        result = self.service.complete(*self.args(request), self.digest())
        self.assertEqual(result['email'], 'rider@example.com')
        self.assertEqual(result, self.service.complete(*self.args(request), self.digest()))
        with self.assertRaises(RecoveryError):
            self.service.complete(*self.args(request), self.digest('other-password'))
        with self.assertRaises(RecoveryError):
            self.service.verify(*self.args(request), self.messages[-1][1])

    def test_email_link_is_single_use_and_requires_private_app_session(self):
        request = self.request()
        parts = urlparse(self.messages[-1][2])
        self.assertEqual(parts.query, '')
        params = parse_qs(parts.fragment)
        self.assertFalse(self.service.status(*self.args(request))['verified'])
        self.service.confirm_link(params['requestId'][0], params['token'][0])
        self.assertTrue(self.service.status(*self.args(request))['verified'])
        with self.assertRaises(RecoveryError):
            self.service.confirm_link(params['requestId'][0], params['token'][0])
        with self.assertRaises(RecoveryError):
            self.service.complete(request['requestId'], params['token'][0], self.digest())

    def test_expiry_rejects_otp_link_and_completion(self):
        request = self.request()
        self.service.verify(*self.args(request), self.messages[-1][1])
        params = parse_qs(urlparse(self.messages[-1][2]).fragment)
        self.now += self.service.TTL
        for operation in [
            lambda: self.service.verify(*self.args(request), self.messages[-1][1]),
            lambda: self.service.complete(*self.args(request), self.digest()),
            lambda: self.service.confirm_link(request['requestId'], params['token'][0]),
        ]:
            with self.assertRaises(RecoveryError):
                operation()

    def test_five_wrong_attempts_block_even_the_correct_otp(self):
        request = self.request()
        otp = self.messages[-1][1]
        wrong = '111111' if otp != '111111' else '222222'
        for _ in range(5):
            with self.assertRaises(RecoveryError):
                self.service.verify(*self.args(request), wrong)
        with self.assertRaises(RecoveryError):
            self.service.verify(*self.args(request), otp)

    def test_successful_resend_invalidates_old_code_and_link(self):
        old = self.request()
        old_code = self.messages[-1][1]
        old_link = parse_qs(urlparse(self.messages[-1][2]).fragment)
        self.now += 60
        new = self.service.resend(*self.args(old), 'test-ip')
        with self.assertRaises(RecoveryError):
            self.service.verify(*self.args(old), old_code)
        with self.assertRaises(RecoveryError):
            self.service.confirm_link(old['requestId'], old_link['token'][0])
        self.service.verify(*self.args(new), self.messages[-1][1])

    def test_failed_resend_preserves_the_previous_request(self):
        old = self.request()
        otp = self.messages[-1][1]
        self.now += 60
        self.fail_mail = True
        with self.assertRaises(RecoveryError) as error:
            self.service.resend(*self.args(old), 'test-ip')
        self.assertEqual(error.exception.status, 503)
        self.service.verify(*self.args(old), otp)

    def test_cooldown_and_hourly_limit(self):
        self.request()
        with self.assertRaises(RecoveryError) as error:
            self.request()
        self.assertEqual(error.exception.status, 429)
        for _ in range(4):
            self.now += 60
            self.request()
        self.now += 60
        with self.assertRaises(RecoveryError):
            self.request()

    def test_completion_invalidates_other_requests_for_same_email(self):
        first = self.request()
        first_otp = self.messages[-1][1]
        self.now += 60
        second = self.request()
        self.service.verify(*self.args(first), first_otp)
        self.service.complete(*self.args(first), self.digest())
        with self.assertRaises(RecoveryError):
            self.service.verify(*self.args(second), self.messages[-1][1])

    def test_server_does_not_store_or_return_plaintext_otp_tokens(self):
        request = self.request()
        with self.service.db() as db:
            row = dict(db.execute('SELECT * FROM requests').fetchone())
        self.assertNotIn(self.messages[-1][1], row.values())
        self.assertNotIn(request['sessionToken'], row.values())
        self.assertNotIn('otp', request)
        self.assertNotIn('link', request)

    def call(self, path, data=None, method='POST'):
        raw = json.dumps(data).encode() if data is not None else b''
        result = {}
        def start(status, headers):
            result.update(status=status, headers=dict(headers))
        body = b''.join(RecoveryApp(self.service)({
            'PATH_INFO': path, 'REQUEST_METHOD': method, 'REMOTE_ADDR': 'test-ip',
            'CONTENT_TYPE': 'application/json', 'CONTENT_LENGTH': str(len(raw)),
            'wsgi.input': io.BytesIO(raw),
        }, start))
        return result, body

    def test_http_contract_and_security_headers(self):
        response, body = self.call('/v1/recovery/request', {'email': 'rider@example.com'})
        self.assertTrue(response['status'].startswith('200'))
        request = json.loads(body)
        response, body = self.call('/v1/recovery/verify', {**request, 'otp': self.messages[-1][1]})
        # Only the documented string fields are accepted; numeric response metadata is not a request field.
        self.assertTrue(response['status'].startswith('400'))
        response, body = self.call('/v1/recovery/verify', {
            'requestId': request['requestId'], 'sessionToken': request['sessionToken'],
            'otp': self.messages[-1][1],
        })
        self.assertEqual(json.loads(body), {'verified': True})
        self.assertEqual(response['headers']['Cache-Control'], 'no-store')
        self.assertEqual(response['headers']['Referrer-Policy'], 'no-referrer')

    def test_link_get_never_confirms_email_automatically(self):
        request = self.request()
        response, body = self.call('/reset', method='GET')
        self.assertTrue(response['status'].startswith('200'))
        self.assertIn(b'Confirm Email', body)
        self.assertFalse(self.service.status(*self.args(request))['verified'])


if __name__ == '__main__':
    unittest.main()
