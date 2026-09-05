"""Email ownership verification for the app's device-local accounts.

No passwords or SMTP credentials are sent to the Flutter application. OTP/link
verification and completion are enforced here, independently of UI state.
"""
import hashlib
import hmac
import re
import secrets
import sqlite3
import time
from contextlib import contextmanager
from urllib.parse import urlencode, urlparse


class RecoveryError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status


class RecoveryService:
    TTL = 600
    COOLDOWN = 60
    MAX_ATTEMPTS = 5

    def __init__(self, database, secret, public_url, send_email, clock=time.time):
        if len(secret) < 32:
            raise ValueError('RECOVERY_SECRET must contain at least 32 characters')
        parsed = urlparse(public_url)
        local = parsed.scheme == 'http' and parsed.hostname in ('localhost', '127.0.0.1')
        if (parsed.scheme != 'https' and not local) or not parsed.hostname or parsed.username or parsed.query or parsed.fragment or parsed.path not in ('', '/'):
            raise ValueError('PUBLIC_URL must be an HTTPS origin (HTTP loopback is allowed for local testing)')
        self.database = database
        self.secret = secret.encode()
        self.public_url = public_url.rstrip('/')
        self.send_email = send_email
        self.clock = clock
        with self.db() as db:
            db.executescript('''
                CREATE TABLE IF NOT EXISTS requests (
                    id TEXT PRIMARY KEY, email TEXT NOT NULL,
                    session_hash TEXT NOT NULL, otp_hash TEXT NOT NULL,
                    link_hash TEXT NOT NULL, created INTEGER NOT NULL,
                    expires INTEGER NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
                    delivered INTEGER NOT NULL DEFAULT 0,
                    verified INTEGER NOT NULL DEFAULT 0,
                    completion_hash TEXT, invalidated INTEGER NOT NULL DEFAULT 0
                );
                CREATE TABLE IF NOT EXISTS send_limits (
                    email_hash TEXT NOT NULL, ip_hash TEXT NOT NULL,
                    created INTEGER NOT NULL
                );
                CREATE INDEX IF NOT EXISTS email_limits ON send_limits(email_hash, created);
                CREATE INDEX IF NOT EXISTS ip_limits ON send_limits(ip_hash, created);
            ''')

    @contextmanager
    def db(self):
        db = sqlite3.connect(self.database, timeout=10)
        db.row_factory = sqlite3.Row
        try:
            db.execute('BEGIN IMMEDIATE')
            yield db
            db.commit()
        except BaseException:
            db.rollback()
            raise
        finally:
            db.close()

    def digest(self, value):
        return hmac.new(self.secret, value.encode(), hashlib.sha256).hexdigest()

    def same(self, value, expected):
        return isinstance(value, str) and len(value) <= 512 and hmac.compare_digest(self.digest(value), expected)

    def session(self, db, request_id, session_token, allow_expired=False):
        row = db.execute('SELECT * FROM requests WHERE id = ?', (request_id,)).fetchone()
        if row is None or not self.same(session_token, row['session_hash']) or not row['delivered'] or row['invalidated']:
            raise RecoveryError(400, 'Invalid recovery request')
        if not allow_expired and self.clock() >= row['expires']:
            raise RecoveryError(400, 'Recovery request expired')
        return row

    def request(self, email, ip, previous=None):
        if not isinstance(email, str) or len(email) > 254 or not re.fullmatch(r'[^@\s]+@[^@\s]+\.[^@\s]+', email):
            raise RecoveryError(400, 'Invalid email')
        email = email.strip().lower()
        now = int(self.clock())
        request_id, session_token, link_token = (secrets.token_urlsafe(32) for _ in range(3))
        otp = f'{secrets.randbelow(1_000_000):06d}'
        email_hash, ip_hash = self.digest(email), self.digest(ip)
        with self.db() as db:
            db.execute('DELETE FROM send_limits WHERE created < ?', (now - 86400,))
            db.execute('DELETE FROM requests WHERE expires < ?', (now - 86400,))
            recent = db.execute('SELECT created FROM send_limits WHERE email_hash = ? ORDER BY created DESC LIMIT 1', (email_hash,)).fetchone()
            email_count = db.execute('SELECT count(*) FROM send_limits WHERE email_hash = ? AND created > ?', (email_hash, now - 3600)).fetchone()[0]
            ip_count = db.execute('SELECT count(*) FROM send_limits WHERE ip_hash = ? AND created > ?', (ip_hash, now - 3600)).fetchone()[0]
            if (recent and now - recent['created'] < self.COOLDOWN) or email_count >= 5 or ip_count >= 20:
                raise RecoveryError(429, 'Please wait before requesting another email')
            db.execute('INSERT INTO send_limits VALUES (?, ?, ?)', (email_hash, ip_hash, now))
            db.execute('INSERT INTO requests(id,email,session_hash,otp_hash,link_hash,created,expires) VALUES(?,?,?,?,?,?,?)',
                       (request_id, email, self.digest(session_token), self.digest(otp), self.digest(link_token), now, now + self.TTL))
        link = self.public_url + '/reset#' + urlencode({'requestId': request_id, 'token': link_token})
        try:
            self.send_email(email, otp, link)
        except Exception:
            with self.db() as db:
                db.execute('DELETE FROM requests WHERE id = ?', (request_id,))
            raise RecoveryError(503, 'Email delivery failed') from None
        with self.db() as db:
            db.execute('UPDATE requests SET delivered = 1 WHERE id = ?', (request_id,))
            if previous is not None:
                db.execute('UPDATE requests SET invalidated = 1 WHERE id = ?', (previous,))
        return {'requestId': request_id, 'sessionToken': session_token,
                'expiresIn': max(0, now + self.TTL - int(self.clock())),
                'resendAfter': max(0, now + self.COOLDOWN - int(self.clock()))}

    def resend(self, request_id, session_token, ip):
        with self.db() as db:
            row = self.session(db, request_id, session_token, allow_expired=True)
            if row['completion_hash']:
                raise RecoveryError(400, 'Recovery already completed')
            email = row['email']
        return self.request(email, ip, previous=request_id)

    def verify(self, request_id, session_token, otp):
        error = None
        with self.db() as db:
            row = self.session(db, request_id, session_token)
            if row['completion_hash'] or row['attempts'] >= self.MAX_ATTEMPTS:
                raise RecoveryError(400, 'Request used or attempt limit reached')
            if not isinstance(otp, str) or not re.fullmatch(r'\d{6}', otp) or not self.same(otp, row['otp_hash']):
                db.execute('UPDATE requests SET attempts = attempts + 1 WHERE id = ?', (request_id,))
                error = RecoveryError(400, 'Invalid OTP')
            else:
                db.execute('UPDATE requests SET verified = 1 WHERE id = ?', (request_id,))
        # Commit failed attempts before reporting failure.
        if error:
            raise error
        return {'verified': True}

    def confirm_link(self, request_id, token):
        with self.db() as db:
            row = db.execute('SELECT * FROM requests WHERE id = ?', (request_id,)).fetchone()
            if row is None or not self.same(token, row['link_hash']) or not row['delivered'] or row['invalidated'] or row['completion_hash'] or self.clock() >= row['expires']:
                raise RecoveryError(400, 'Invalid or expired link')
            db.execute('UPDATE requests SET verified = 1, link_hash = ? WHERE id = ?', (self.digest(secrets.token_urlsafe(32)), request_id))
        return {'verified': True}

    def status(self, request_id, session_token):
        with self.db() as db:
            row = self.session(db, request_id, session_token)
            if row['completion_hash']:
                raise RecoveryError(400, 'Recovery already completed')
            return {'verified': bool(row['verified'])}

    def complete(self, request_id, session_token, password_digest):
        if not isinstance(password_digest, str) or not re.fullmatch(r'[0-9a-f]{64}', password_digest):
            raise RecoveryError(400, 'Invalid password digest')
        binding = self.digest('completion:' + password_digest)
        with self.db() as db:
            row = self.session(db, request_id, session_token)
            if not row['verified']:
                raise RecoveryError(400, 'Email verification required')
            if row['completion_hash'] and not hmac.compare_digest(row['completion_hash'], binding):
                raise RecoveryError(400, 'Recovery already used for a different password')
            db.execute('UPDATE requests SET completion_hash = ? WHERE id = ?', (binding, request_id))
            db.execute('UPDATE requests SET invalidated = 1 WHERE email = ? AND id != ?', (row['email'], request_id))
        # Same request/password may retry after a network or local database error.
        # A consumed request can never authorize a different password.
        return {'completed': True, 'email': row['email'], 'passwordDigest': password_digest}
