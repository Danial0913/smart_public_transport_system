"""Verify configured sender credentials without sending any email."""
from app import load_environment
from mailer import SmtpMailer

if __name__ == '__main__':
    load_environment()
    try:
        SmtpMailer().check_connection()
        print('SMTP authentication and TLS connection succeeded. No email sent.')
    except Exception as error:
        # Do not print credentials, server responses, or message content.
        print('SMTP connection failed: ' + type(error).__name__)
        raise SystemExit(1)
