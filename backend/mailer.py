import os
import smtplib
import ssl
from email.message import EmailMessage


class SmtpMailer:
    def __init__(self):
        self.host = os.environ.get('SMTP_HOST', 'smtp.gmail.com')
        self.port = int(os.environ.get('SMTP_PORT', '587'))
        self.username = os.environ['SMTP_USERNAME']
        self.password = os.environ['SMTP_PASSWORD'].replace(' ', '')
        self.sender = os.environ.get('SMTP_FROM', self.username)

    def connection(self):
        smtp = smtplib.SMTP(self.host, self.port, timeout=20)
        try:
            smtp.ehlo()
            smtp.starttls(context=ssl.create_default_context())
            smtp.ehlo()
            smtp.login(self.username, self.password)
            return smtp
        except Exception:
            smtp.close()
            raise

    def check_connection(self):
        with self.connection() as smtp:
            smtp.noop()

    def __call__(self, recipient, otp, link):
        message = EmailMessage()
        message['From'] = self.sender
        message['To'] = recipient
        message['Subject'] = 'Smart Public Transport: password reset OTP and link'
        message.set_content(
            f'Your password reset OTP is: {otp}\n\n'
            f'Or open this link and press Confirm Email:\n{link}\n\n'
            'Both expire after 10 minutes. Return to the reset screen in the app '
            'to choose your new password. This resets the account on that device.\n\n'
            'If you did not request this, ignore this email. Do not share your OTP or link.'
        )
        with self.connection() as smtp:
            refused = smtp.send_message(message)
            if refused:
                raise RuntimeError('Recipient was rejected by the mail server')
