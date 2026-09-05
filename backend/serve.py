"""Hosted entry point. Place behind your hosting provider's HTTPS proxy."""
import os
from pathlib import Path
from urllib.parse import urlparse

from app import create_app, load_environment


def public_origin(environment):
    public_url = environment.get('PUBLIC_URL', environment.get('RENDER_EXTERNAL_URL', ''))
    parsed = urlparse(public_url)
    if (parsed.scheme != 'https' or not parsed.hostname
            or parsed.hostname in ('localhost', '127.0.0.1', '::1')
            or parsed.username or parsed.password or parsed.query or parsed.fragment
            or parsed.path not in ('', '/')):
        raise ValueError('Set PUBLIC_URL to the public HTTPS origin of this recovery server.')
    return public_url.rstrip('/')


def hosting_options(environment):
    public_origin(environment)
    if not environment.get('RECOVERY_DATABASE'):
        raise ValueError('Set RECOVERY_DATABASE to a file on persistent storage.')
    port = int(environment.get('PORT', '8787'))
    if not 1 <= port <= 65535:
        raise ValueError('PORT must be between 1 and 65535.')
    options = dict(host='0.0.0.0', port=port, threads=8, channel_timeout=30,
                   max_request_body_size=4096, max_request_header_size=16384,
                   expose_tracebacks=False, clear_untrusted_proxy_headers=True)
    # Only a known upstream proxy may supply the real client IP for rate limits.
    # Never enable wildcard trust on an internet-accessible backend port.
    proxy = environment.get('TRUSTED_PROXY')
    if proxy:
        if proxy == '*':
            raise ValueError('TRUSTED_PROXY must name a specific trusted proxy, not *.')
        options.update(trusted_proxy=proxy, trusted_proxy_count=1,
                       trusted_proxy_headers={'x-forwarded-for', 'x-forwarded-proto'})
    return options


def main():
    load_environment()
    options = hosting_options(os.environ)
    os.environ['PUBLIC_URL'] = public_origin(os.environ)
    database = Path(os.environ['RECOVERY_DATABASE']).expanduser().resolve()
    database.parent.mkdir(parents=True, exist_ok=True)
    os.environ['RECOVERY_DATABASE'] = str(database)
    from waitress import serve
    serve(create_app(), **options)


if __name__ == '__main__':
    main()
