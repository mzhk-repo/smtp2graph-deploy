#!/usr/bin/env node
'use strict';

const fs = require('fs');
const tls = require('tls');

const [host, port, scenario, fixture] = process.argv.slice(2);
const username = process.env.SMTP_TEST_USER;
const password = process.env.SMTP_TEST_PASSWORD;
if (!host || !port || !scenario || !fixture || !username || !password) {
  console.error('Usage: SMTP_TEST_USER=... SMTP_TEST_PASSWORD=... smtp-scenario.js HOST PORT SCENARIO FIXTURE');
  process.exit(64);
}

const socket = tls.connect({host, port: Number(port), rejectUnauthorized: false});
let buffer = '';
let waiting;

function nextResponse() {
  return new Promise((resolve, reject) => {
    waiting = {resolve, reject};
  });
}

function command(value) {
  socket.write(`${value}\r\n`);
  return nextResponse();
}

function expectCode(response, expected) {
  if (!response.startsWith(expected)) throw new Error(`Expected ${expected}, got ${response}`);
}

function authLine() {
  return Buffer.from(`\u0000${username}\u0000${password}`).toString('base64');
}

function messageForScenario() {
  if (scenario !== 'oversize') {
    return fs.readFileSync(fixture, 'utf8').replace(/\r?\n/g, '\r\n').replace(/^\./gm, '..');
  }
  return `Subject: Oversize synthetic test\r\n\r\n${'A'.repeat(26 * 1024 * 1024)}`;
}

socket.on('data', chunk => {
  buffer += chunk.toString('utf8');
  const lines = buffer.split('\r\n');
  buffer = lines.pop();
  for (const line of lines) {
    if (line.length && waiting && /^[0-9]{3} /.test(line)) {
      const current = waiting;
      waiting = undefined;
      current.resolve(line);
    }
  }
});

socket.on('error', error => {
  if (waiting) waiting.reject(error);
  else process.exitCode = 1;
});

(async () => {
  try {
    expectCode(await nextResponse(), '220');
    expectCode(await command('EHLO local-mvp-test.invalid'), '250');

    if (scenario === 'unauthenticated') {
      const response = await command('MAIL FROM:<noreply@example.invalid>');
      if (response.startsWith('250')) throw new Error(`Unauthenticated sender was accepted: ${response}`);
      console.log(JSON.stringify({scenario, rejected: true, response}));
      socket.end();
      return;
    }

    expectCode(await command(`AUTH PLAIN ${authLine()}`), '235');
    const sender = scenario === 'denied-sender' ? 'outside@example.invalid' : 'noreply@example.invalid';
    const mailResponse = await command(`MAIL FROM:<${sender}>`);
    if (scenario === 'denied-sender') {
      if (mailResponse.startsWith('250')) throw new Error(`Denied sender was accepted: ${mailResponse}`);
      console.log(JSON.stringify({scenario, rejected: true, response: mailResponse}));
      socket.end();
      return;
    }
    expectCode(mailResponse, '250');
    expectCode(await command('RCPT TO:<recipient@example.invalid>'), '250');
    expectCode(await command('DATA'), '354');
    socket.write(`${messageForScenario()}\r\n.\r\n`);
    const dataResponse = await nextResponse();
    if (scenario === 'oversize') {
      if (dataResponse.startsWith('250')) throw new Error(`Oversize message was accepted: ${dataResponse}`);
      console.log(JSON.stringify({scenario, rejected: true, response: dataResponse}));
    } else {
      expectCode(dataResponse, '250');
      console.log(JSON.stringify({scenario, accepted: true, response: dataResponse}));
    }
    await command('QUIT');
    socket.end();
  } catch (error) {
    console.error(String(error));
    socket.destroy();
    process.exitCode = 1;
  }
})();
