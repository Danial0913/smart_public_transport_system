# Password recovery server

This server verifies email ownership for accounts stored in this app's local
SQLite database. It sends a six-digit OTP and a one-time confirmation link using
Gmail SMTP with TLS. The app writes the new password locally only after verified
server completion. It does not migrate accounts to a cloud identity service or
reset accounts on other devices.

## Sharing the project with a friend

Pushing or cloning the Flutter project does **not** start or publish the recovery
server. The default debug address, `127.0.0.1:8787`, refers to the phone itself.
ADB reverse connects that address to the computer currently connected to that
phone. It does not connect a friend's phone to the original developer's computer.
The private SMTP configuration in `.env` is intentionally excluded from Git.

For a shared app, deploy this backend to an HTTPS host, set its `PUBLIC_URL` to
that public origin, and run/build Flutter with the same origin:

```powershell
flutter run --dart-define=PASSWORD_RECOVERY_URL=https://your-real-recovery-host
flutter build apk --release --dart-define=PASSWORD_RECOVERY_URL=https://your-real-recovery-host
```

Replace the example with an actual deployed address. A public URL by itself does
not start a server. Friends using this build do not need Python, USB forwarding,
or SMTP credentials. They register an account on their own device before using
password recovery. Passwords and account records still belong to that device.

Alternatively, a developer can run a separate local recovery server on their own
computer with their own private `.env` based on `.env.example`, Python 3.10+,
and ADB reverse to their phone/emulator. Do not commit or distribute the sender's
app password with the Flutter project or APK.

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

On Windows, `./backend/start.ps1` connects Android devices and starts the server
using the Python launcher, a normal Python installation, or the Codex bundled
runtime if available. It skips the Windows Store alias. It reuses an already-running server. After reconnecting
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

### Optional Render setup

`backend/render.yaml` prepares one paid Python web service in Singapore with a
1 GB persistent disk. No service is created by adding this file to the repository.
The estimated base cost is US$7.25/month ($7 compute + $0.25 disk), before taxes
and additional usage. Check the current estimate in Render before approving it.
See Render's [compute pricing](https://render.com/articles/render-vs-railway)
and [storage pricing](https://render.com/articles/how-much-does-cloud-application-hosting-cost-for-small-businesses).
The [free service](https://render.com/docs/free) blocks Gmail SMTP ports and does
not support persistent disks, so it cannot use this configuration.

1. After choosing this paid setup, push these deployment files to your repository.
2. In Render, create a Blueprint connected to that repository. Set **Blueprint
   Path** to `backend/render.yaml` and review the service and disk charges.
3. Enter `SMTP_USERNAME` and `SMTP_PASSWORD` privately in Render's prompted
   environment fields. Use the Gmail sender and its app password; never put them
   in Git or Flutter. `SMTP_FROM` defaults to `SMTP_USERNAME`.
4. Deploy. The secret is generated by Render and the database is stored under
   `/var/data`. Keep the service to one instance. The server uses Render's
   automatic `RENDER_EXTERNAL_URL` for email links unless you explicitly set
   `PUBLIC_URL` for a custom HTTPS domain.
5. Check `/health` at the assigned HTTPS address, then build Flutter with that
   exact address using `--dart-define=PASSWORD_RECOVERY_URL=...` as shown above.
6. Install the new build on the friend's phone. Register locally, disconnect USB,
   and request a fresh OTP/link. Test OTP verification and email-link confirmation
   separately with fresh requests, then finish a password change and sign in.

Automatic code deployments are disabled; deploy later code changes manually in
Render. If the host does not provide a specific trusted proxy address, leave
`TRUSTED_PROXY` unset: users behind its proxy share the 20 requests/hour IP limit.

### Other Python or Docker hosts

`app.py` is the local development entry point. `serve.py` runs
[Waitress](https://docs.pylonsproject.org/projects/waitress/en/stable/) behind the
hosting provider's HTTPS proxy. For a Python host, use these commands from the
project root:

```text
python -m pip install -r backend/requirements.txt
python backend/serve.py
```

Or use `backend/Dockerfile` with `backend` as its Docker build context:

```text
docker build -t transport-recovery backend
```

Set the following as **server environment variables**, never Flutter values:

- `PUBLIC_URL`: the server's public HTTPS origin (no `/reset` suffix).
- `RECOVERY_SECRET`: a stable randomly generated secret of at least 32 characters.
- `RECOVERY_DATABASE`: a file on persistent storage, such as `/data/recovery.db`.
- `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM`: private
  sender configuration; Gmail uses `smtp.gmail.com`, port `587`, and an app password.
- `PORT`: the host's assigned HTTP port; defaults to `8787`.
- `TRUSTED_PROXY`: only if the host provides a known proxy address. Requests must
  arrive through that proxy to trust its client-IP headers. Without it, callers
  behind the same proxy share the existing IP send limit.

The host must support outbound SMTP and writable persistent storage. Some hosting
plans restrict SMTP or have temporary disks; check those capabilities before
choosing a host. For Docker, mount persistent storage at `/data`, writable by the
container's `recovery` user. The image contains no `.env` or recovery database.
HTTPS is supplied by the host/proxy, not by the container itself.

After deployment, open `https://your-real-recovery-host/health`; it should return
`{"status":"ok"}`. Then configure Flutter with that same origin and test a newly
requested OTP and link on a phone without USB forwarding.

Keep the database on persistent storage and back up the server secret with the deployment secrets.
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
