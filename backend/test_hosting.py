import unittest

from serve import hosting_options, public_origin


class HostingTests(unittest.TestCase):
    def test_render_origin_is_used_only_without_an_explicit_public_url(self):
        environment = {'RENDER_EXTERNAL_URL': 'https://recovery.onrender.com/',
                       'RECOVERY_DATABASE': '/var/data/recovery.db'}
        self.assertEqual(public_origin(environment), 'https://recovery.onrender.com')
        self.assertEqual(hosting_options(environment)['port'], 8787)
        environment['PUBLIC_URL'] = 'https://custom.example.com'
        self.assertEqual(public_origin(environment), 'https://custom.example.com')
        environment['PUBLIC_URL'] = 'http://localhost:8787'
        with self.assertRaises(ValueError):
            hosting_options(environment)

    def options(self, **changes):
        environment = {'PUBLIC_URL': 'https://recovery.example.com',
                       'RECOVERY_DATABASE': '/data/recovery.db'}
        environment.update(changes)
        return hosting_options(environment)

    def test_hosted_server_requires_https_and_a_database_path(self):
        for url in ('', 'http://example.com', 'http://localhost:8787',
                    'https://localhost', 'https://user:password@example.com',
                    'https://example.com/reset', 'https://example.com#secret'):
            with self.subTest(url=url), self.assertRaises(ValueError):
                self.options(PUBLIC_URL=url)
        with self.assertRaises(ValueError):
            self.options(RECOVERY_DATABASE='')

    def test_host_port_and_request_limits(self):
        options = self.options(PORT='8080')
        self.assertEqual(options['host'], '0.0.0.0')
        self.assertEqual(options['port'], 8080)
        self.assertEqual(options['max_request_body_size'], 4096)
        self.assertFalse(options['expose_tracebacks'])
        for port in ('0', '65536', 'not-a-port'):
            with self.subTest(port=port), self.assertRaises(ValueError):
                self.options(PORT=port)

    def test_proxy_headers_are_only_trusted_for_a_configured_proxy(self):
        self.assertNotIn('trusted_proxy', self.options())
        with self.assertRaises(ValueError):
            self.options(TRUSTED_PROXY='*')
        options = self.options(TRUSTED_PROXY='127.0.0.1')
        self.assertEqual(options['trusted_proxy'], '127.0.0.1')
        self.assertIn('x-forwarded-for', options['trusted_proxy_headers'])


if __name__ == '__main__':
    unittest.main()
