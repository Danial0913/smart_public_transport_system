# Password recovery server

This server verifies email ownership for accounts stored in this app's local
SQLite database. It sends a six-digit OTP and a one-time confirmation link using
Gmail SMTP with TLS. The app writes the new password locally only after verified
server completion. It does not migrate accounts to a cloud identity service or
reset accounts on other devices.

## Local development

The local `backend/.env` contains the configured sender and is ignored by Git.
Never add that file to Flutter assets or version control. A redacted example is
provided as `.env.example`. Python 3.10+ is required; local mode uses only the
standard library.

From the project root:

```powershell
python backend/check_smtp.py
adb reverse tcp:8787 tcp:8787
python backend/app.py
flutter run
```

Keep the recovery server running while testing. Debug builds use
`http://127.0.0.1:8787`. Android phones and emulators connect through ADB reverse
port forwarding: `adb reverse tcp:8787 tcp:8787`. The Windows startup script
configures this for every connected, authorized Android device. HTTP is permitted
only on development loopback addresses and only in debug builds. Release builds
require an explicitly configured HTTPS recovery URL.

On this Windows computer, `./backend/start.ps1` connects Android devices and starts
the server using the Python runtime bundled with Codex, without relying on the
Windows Store Python alias. It reuses an already-running server. After reconnecting
your phone, run it again, or run `./backend/connect_android.ps1`. Enable USB
debugging and keep the phone connected while testing.

The local server handles requests concurrently, so browser preconnections cannot
block OTP verification. Only one server may listen on the recovery port. After
changing backend code, stop the running server with Ctrl+C before starting it
again. Email-link confirmation times out after 20 seconds and allows retrying.

Register an account on that emulator/device using an email you can receive.
Choose Forgot Password, request the email, and either enter its OTP or open the
link, press Confirm Email, return to the app, and select the link-confirmation
button. Enter and confirm a new password, then sign in normally. The previous
password will no longer match that device's account.

With the default `PUBLIC_URL`, links can be opened on this computer or the Android
device connected through ADB reverse. OTP entry still works when the email is read
on another device. For phones without a development connection and links that work
anywhere, deploy the server to a public HTTPS origin,
set `PUBLIC_URL` to that origin, and build with:

```text
flutter run --dart-define=PASSWORD_RECOVERY_URL=https://your-recovery-domain.example
```

The app does not claim an email was sent if SMTP rejects the request. SMTP
acceptance does not guarantee inbox placement; users should also check spam.

## Deployment

`app.py`'s built-in WSGI server is for local development. Use a production WSGI
server (for example Waitress) behind HTTPS and point it at `app:create_app` using
its application-factory mode from the `backend` directory. Keep the database on
persistent storage and back up the server secret with the deployment secrets.
Do not run multiple isolated database copies: rate limits and consumed tokens
must share the same persistent state. The app's new password stays on the device;
the server stores only an HMAC binding for completion retries.

The service limits each email to one request/minute and five/hour, and each
source IP to twenty/hour. Only five wrong OTP attempts are permitted per request.
Codes expire after ten minutes. Successful resends invalidate the previous
request; SMTP failure preserves it. Successful completion invalidates other
requests for that email. Retrying completion is allowed only for the same
session and identical password digest, to recover from connection/database
failures without authorizing a second password change.

The service does not trust client-provided proxy headers. If deployed behind a
proxy, configure trusted client-IP forwarding in the server/proxy layer and
protect the public sending endpoint with deployment-level abuse controls.
The server has no cloud account directory, so it cannot check cloud registration;
the app checks for the account in its local database before requesting email.

## Tests

```powershell
python -m unittest discover -s backend -p "test_*.py" -v
node --test backend/test_reset_page.cjs
flutter test
```

Tests stub SMTP and send no real email. `check_smtp.py` authenticates without
sending. The email-link page uses an explicit confirmation button so opening a
link in an email scanner does not consume it. Link secrets are in the URL
fragment, then removed from browser history; API bodies and tokens are not logged.
