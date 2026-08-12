#!/usr/bin/env node
'use strict';

const fs = require('fs');
const net = require('net');
const tls = require('tls');

const [host, portRaw, tlsName, username, passwordFile, sender, recipient] = process.argv.slice(2);
const port = Number(portRaw);
if (!host || !Number.isInteger(port) || !tlsName || !username || !passwordFile || !sender || !recipient) {
  console.error('Usage: smtp-format-matrix.js HOST PORT TLS_NAME USER PASSWORD_FILE SENDER RECIPIENT');
  process.exit(64);
}
const stat = fs.statSync(passwordFile);
if (!stat.isFile() || (stat.mode & 0o077) !== 0) throw new Error('password file permissions are unsafe');
const password = fs.readFileSync(passwordFile, 'utf8').replace(/[\r\n]+$/, '');
if (!password) throw new Error('password file is empty');

const cases = [
  ['plain-text', [`From: <${sender}>`, `To: <${recipient}>`, 'Subject: Task 6.1 plain text', 'Content-Type: text/plain; charset=utf-8', '', 'Synthetic plain-text format check.']],
  ['html-unicode', [`From: <${sender}>`, `To: <${recipient}>`, 'Subject: Task 6.1 HTML Unicode', 'Content-Type: text/html; charset=utf-8', '', '<p>SMTP2Graph format check — Привіт</p>']],
  ['recipient-headers', [`From: <${sender}>`, `To: <${recipient}>`, `Cc: <${recipient}>`, 'Subject: Task 6.1 recipient headers', 'Content-Type: text/plain; charset=utf-8', '', 'To and CC use the single approved recipient; BCC is envelope-only.']],
  ['reply-to', [`From: <${sender}>`, `To: <${recipient}>`, `Reply-To: <${sender}>`, 'Subject: Task 6.1 Reply-To', 'Content-Type: text/plain; charset=utf-8', '', 'Synthetic Reply-To format check.']],
  ['attachment', multipart('mixed', sender, recipient, 'Task 6.1 attachment', 'attachment; filename="format-check.txt"', 'aW50ZWdyYXRpb24gZm9ybWF0IGNoZWNrCg==')],
  ['inline-attachment', multipart('related', sender, recipient, 'Task 6.1 inline attachment', 'inline; filename="format-check.txt"', 'aW50ZWdyYXRpb24gZm9ybWF0IGNoZWNrCg==', true)],
];

function multipart(kind, from, to, subject, disposition, payload, inline = false) {
  const boundary = 'smtp2graph-task61-boundary';
  return [
    `From: <${from}>`, `To: <${to}>`, `Subject: ${subject}`, `Content-Type: multipart/${kind}; boundary="${boundary}"`, '',
    `--${boundary}`, 'Content-Type: text/plain; charset=utf-8', '', 'Synthetic multipart format check.',
    `--${boundary}`, 'Content-Type: text/plain; name="format-check.txt"', 'Content-Transfer-Encoding: base64', `Content-Disposition: ${disposition}`,
    ...(inline ? ['Content-ID: <format-check@task61.invalid>'] : []), '', payload,
    `--${boundary}--`, '',
  ];
}

function expect(response, code) {
  if (!response.startsWith(code)) throw new Error(`unexpected SMTP response: ${response.slice(0, 80)}`);
}

function connectAndSubmit(name, lines, extraRecipients = []) {
  return new Promise((resolve, reject) => {
    let socket = net.connect({host, port});
    let buffer = '';
    let waiter;
    const next = () => new Promise((resolveResponse, rejectResponse) => { waiter = {resolve: resolveResponse, reject: rejectResponse}; });
    const command = value => { socket.write(`${value}\r\n`); return next(); };
    const attach = target => {
      target.on('data', chunk => {
        buffer += chunk.toString('utf8');
        const messages = buffer.split('\r\n');
        buffer = messages.pop();
        for (const message of messages) {
          if (/^[0-9]{3} /.test(message) && waiter) {
            const current = waiter;
            waiter = undefined;
            current.resolve(message);
          }
        }
      });
      target.on('error', error => { if (waiter) waiter.reject(error); else reject(error); });
    };
    attach(socket);
    (async () => {
      expect(await next(), '220');
      expect(await command('EHLO smtp2graph-task61.invalid'), '250');
      expect(await command('STARTTLS'), '220');
      socket = tls.connect({socket, servername: tlsName, rejectUnauthorized: true});
      buffer = '';
      attach(socket);
      await new Promise((resolveSecure, rejectSecure) => socket.once('secureConnect', resolveSecure).once('error', rejectSecure));
      expect(await command('EHLO smtp2graph-task61.invalid'), '250');
      expect(await command(`AUTH PLAIN ${Buffer.from(`\u0000${username}\u0000${password}`).toString('base64')}`), '235');
      expect(await command(`MAIL FROM:<${sender}>`), '250');
      for (const target of [recipient, ...extraRecipients]) expect(await command(`RCPT TO:<${target}>`), '250');
      expect(await command('DATA'), '354');
      socket.write(`${lines.join('\r\n')}\r\n.\r\n`);
      expect(await next(), '250');
      await command('QUIT');
      socket.end();
      console.log(`PASS: ${name} accepted by gateway.`);
      resolve();
    })().catch(error => { socket.destroy(); reject(error); });
  });
}

(async () => {
  for (const [name, lines, extraRecipients] of cases) await connectAndSubmit(name, lines, extraRecipients);
})().catch(error => { console.error(`ERROR: ${error.message}`); process.exitCode = 1; });
