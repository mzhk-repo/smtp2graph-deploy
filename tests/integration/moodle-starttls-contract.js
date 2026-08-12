#!/usr/bin/env node
'use strict';

const fs = require('fs');
const net = require('net');
const tls = require('tls');

const [host, portRaw, tlsName, username, passwordFile] = process.argv.slice(2);
const port = Number(portRaw);
if (!host || !Number.isInteger(port) || !tlsName || !username || !passwordFile) {
  console.error('Usage: moodle-starttls-contract.js HOST PORT TLS_NAME USER PASSWORD_FILE');
  process.exit(64);
}
const stat = fs.statSync(passwordFile);
if (!stat.isFile() || (stat.mode & 0o077) !== 0) throw new Error('password file permissions are unsafe');
const password = fs.readFileSync(passwordFile, 'utf8').replace(/[\r\n]+$/, '');
if (!password) throw new Error('password file is empty');

let socket = net.connect({host, port});
let buffer = '';
let waiter;
const next = () => new Promise((resolve, reject) => { waiter = {resolve, reject}; });
const command = value => { socket.write(`${value}\r\n`); return next(); };
function expect(response, code) {
  if (!response.startsWith(code)) throw new Error(`unexpected SMTP response: ${response.slice(0, 80)}`);
}
function attach(target) {
  target.on('data', chunk => {
    buffer += chunk.toString('utf8');
    const lines = buffer.split('\r\n');
    buffer = lines.pop();
    for (const line of lines) {
      if (/^[0-9]{3} /.test(line) && waiter) {
        const current = waiter;
        waiter = undefined;
        current.resolve(line);
      }
    }
  });
  target.on('error', error => { if (waiter) waiter.reject(error); });
}
attach(socket);

(async () => {
  expect(await next(), '220');
  expect(await command('EHLO moodle-task61.invalid'), '250');
  const auth = Buffer.from(`\u0000${username}\u0000${password}`).toString('base64');
  const beforeTls = await command(`AUTH PLAIN ${auth}`);
  if (beforeTls.startsWith('235')) throw new Error('SMTP AUTH was accepted before STARTTLS');
  expect(await command('STARTTLS'), '220');
  socket = tls.connect({socket, servername: tlsName, rejectUnauthorized: true});
  buffer = '';
  attach(socket);
  await new Promise((resolve, reject) => socket.once('secureConnect', resolve).once('error', reject));
  expect(await command('EHLO moodle-task61.invalid'), '250');
  expect(await command(`AUTH PLAIN ${auth}`), '235');
  await command('QUIT');
  socket.end();
  console.log('PASS: Moodle STARTTLS hostname validation and AUTH boundary are valid.');
})().catch(error => { console.error(`ERROR: ${error.message}`); socket.destroy(); process.exitCode = 1; });
