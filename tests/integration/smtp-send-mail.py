#!/usr/bin/env python3
# Category 1a: Zero-dependency Python 3 helper for live E2E SMTP delivery testing.
import argparse
import email.utils
from email.message import EmailMessage
import os
import smtplib
import ssl
import sys
import uuid


def parse_args():
    parser = argparse.ArgumentParser(
        description='Send a test email through the SMTP2Graph gateway via STARTTLS.'
    )
    parser.add_argument('--host', default='127.0.0.1', help='SMTP server host (default: 127.0.0.1)')
    parser.add_argument('--port', type=int, default=2525, help='SMTP server port (default: 2525)')
    parser.add_argument('--tls-name', default='smtp-int.ldubgd.edu.ua', help='TLS servername for SNI')
    parser.add_argument('--user', required=True, help='SMTP username')
    parser.add_argument('--password-file', help='Path to file containing SMTP password (mode 0600)')
    parser.add_argument('--password', help='SMTP password string (prefer --password-file)')
    parser.add_argument('--sender', required=True, help='Sender address (MAIL FROM)')
    parser.add_argument('--recipient', required=True, help='Recipient address (RCPT TO)')
    parser.add_argument('--subject', default=None, help='Email subject')
    parser.add_argument('--body', default=None, help='Email body text')
    parser.add_argument('--insecure', action='store_true', help='Disable TLS certificate verification')
    return parser.parse_args()


def read_password(args):
    if args.password_file:
        path = os.path.abspath(args.password_file)
        if not os.path.isfile(path):
            sys.exit(f"ERROR: password file '{path}' does not exist.")
        mode = os.stat(path).st_mode
        if mode & 0o077 != 0:
            sys.exit(f"ERROR: password file '{path}' must be readable only by owner (mode 0600).")
        with open(path, 'r', encoding='utf-8') as f:
            return f.read().rstrip('\r\n')
    if args.password is not None:
        return args.password
    sys.exit("ERROR: either --password-file or --password is required.")


def main():
    args = parse_args()
    password = read_password(args)
    if not password:
        sys.exit("ERROR: password cannot be empty.")

    now = email.utils.formatdate(localtime=True)
    msg_id = f"<{uuid.uuid4()}@smtp2graph.test>"
    subject = args.subject or f"SMTP2Graph E2E Test - {now}"
    body = args.body or (
        f"This is an automated end-to-end delivery test sent via SMTP2Graph.\n"
        f"Timestamp: {now}\n"
        f"Host: {args.host}:{args.port}\n"
        f"Sender: {args.sender}\n"
        f"Recipient: {args.recipient}\n"
    )

    msg = EmailMessage()
    msg['From'] = args.sender
    msg['To'] = args.recipient
    msg['Date'] = now
    msg['Message-ID'] = msg_id
    msg['Subject'] = subject
    msg.set_content(body)

    print(f"[*] Connecting to SMTP gateway at {args.host}:{args.port}...")
    try:
        server = smtplib.SMTP(args.host, args.port, timeout=15)
    except Exception as e:
        sys.exit(f"ERROR: Failed to connect to {args.host}:{args.port}: {e}")

    try:
        server.ehlo()

        print(f"[*] Upgrading connection with STARTTLS (SNI: {args.tls_name})...")
        if args.insecure:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
        else:
            ctx = ssl.create_default_context()

        server.starttls(context=ctx)
        server.ehlo()

        print(f"[*] Authenticating as '{args.user}'...")
        server.login(args.user, password)
        print(f"[*] Authentication successful.")

        print(f"[*] Submitting email:")
        print(f"    From:       {args.sender}")
        print(f"    To:         {args.recipient}")
        print(f"    Subject:    {subject}")
        print(f"    Message-ID: {msg_id}")

        refused = server.send_message(msg)
        if refused:
            sys.exit(f"ERROR: Recipient refused: {refused}")

        print("[+] Message accepted by gateway.")
        print("PASS: E2E email delivery to SMTP2Graph gateway succeeded.")
    except smtplib.SMTPAuthenticationError as e:
        sys.exit(f"ERROR: SMTP Authentication failed: {e}")
    except smtplib.SMTPRecipientsRefused as e:
        sys.exit(f"ERROR: Recipient refused by gateway: {e}")
    except smtplib.SMTPSenderRefused as e:
        sys.exit(f"ERROR: Sender refused by gateway: {e}")
    except smtplib.SMTPDataError as e:
        sys.exit(f"ERROR: Data transfer rejected: {e}")
    except Exception as e:
        sys.exit(f"ERROR: SMTP transaction failed: {e}")
    finally:
        try:
            server.quit()
        except Exception:
            pass


if __name__ == '__main__':
    main()
