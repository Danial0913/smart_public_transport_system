'use strict';
const params = new URLSearchParams(location.hash.slice(1));
const requestId = params.get('requestId');
const token = params.get('token');
history.replaceState(null, '', '/reset');
const button = document.getElementById('confirm');
const status = document.getElementById('status');
if (!requestId || !token) {
  button.disabled = true;
  status.textContent = 'This link is incomplete. Request a new email in the app.';
}
button.addEventListener('click', async () => {
  button.disabled = true;
  status.textContent = 'Confirming…';
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 20000);
  try {
    const response = await fetch('/v1/recovery/link', {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({requestId, token}), credentials: 'omit',
      signal: controller.signal,
    });
    if (!response.ok) throw new Error('Invalid link');
    const result = await response.json();
    if (result.verified !== true) throw new Error('Email not verified');
    status.textContent = 'Email confirmed. Return to the app and select “I’ve Confirmed the Email Link”.';
    button.textContent = 'Email Confirmed';
  } catch (error) {
    status.textContent = error.name === 'AbortError' || error instanceof TypeError
      ? 'Could not reach the recovery service. Check your connection and try again. For local testing, keep the server running and your phone connected by USB.'
      : 'Could not confirm this link. It may have expired or been used. Return to the app to check confirmation, enter the OTP, or request a new email.';
    button.disabled = false;
  } finally {
    clearTimeout(timeout);
  }
});
