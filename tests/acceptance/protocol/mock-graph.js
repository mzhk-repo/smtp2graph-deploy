#!/usr/bin/env node
'use strict';

const fs = require('fs');
const https = require('https');
const path = require('path');

const port = Number(process.env.MOCK_GRAPH_PORT || '443');
const stateDir = process.env.MOCK_GRAPH_STATE_DIR || '/state';
const scenarioFile = process.env.MOCK_GRAPH_SCENARIO_FILE || path.join(stateDir, 'scenario');
const keyPath = process.env.MOCK_GRAPH_TLS_KEY_PATH || '/tls/mock.key';
const certPath = process.env.MOCK_GRAPH_TLS_CERT_PATH || '/tls/mock.crt';

fs.mkdirSync(stateDir, {recursive: true});

function scenario() {
  try {
    return fs.readFileSync(scenarioFile, 'utf8').trim() || 'success';
  } catch {
    return 'success';
  }
}

function record(event) {
  fs.appendFileSync(path.join(stateDir, 'events.jsonl'), `${JSON.stringify({...event, timestamp: Date.now()})}\n`);
}

function sendJson(response, status, body, headers = {}) {
  response.writeHead(status, {'content-type': 'application/json', ...headers});
  response.end(JSON.stringify(body));
}

function receiveBody(request) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    request.on('data', chunk => chunks.push(chunk));
    request.on('end', () => resolve(Buffer.concat(chunks)));
    request.on('error', reject);
  });
}

const server = https.createServer({
  key: fs.readFileSync(keyPath),
  cert: fs.readFileSync(certPath),
}, async (request, response) => {
  try {
    if (request.method === 'GET' && request.url.includes('.well-known/openid-configuration')) {
      record({kind: 'openid-configuration', path: request.url});
      return sendJson(response, 200, {
        token_endpoint: 'https://login.microsoftonline.com/mock-tenant/oauth2/v2.0/token',
        authorization_endpoint: 'https://login.microsoftonline.com/mock-tenant/oauth2/v2.0/authorize',
        issuer: 'https://login.microsoftonline.com/mock-tenant/v2.0',
        jwks_uri: 'https://login.microsoftonline.com/mock-tenant/discovery/v2.0/keys',
      });
    }

    if (request.method === 'GET' && request.url.startsWith('/common/discovery/instance')) {
      record({kind: 'instance-discovery', path: request.url});
      return sendJson(response, 200, {
        tenant_discovery_endpoint: 'https://login.microsoftonline.com/mock-tenant/v2.0/.well-known/openid-configuration',
        metadata: [],
      });
    }

    if (request.method === 'POST' && request.url.endsWith('/token')) {
      await receiveBody(request);
      record({kind: 'token', path: request.url});
      return sendJson(response, 200, {
        token_type: 'Bearer',
        expires_in: 3600,
        access_token: 'synthetic-access-token',
      });
    }

    if (request.method === 'POST' && request.url.includes('/sendMail')) {
      const encodedMessage = (await receiveBody(request)).toString('utf8');
      const decodedMessage = Buffer.from(encodedMessage, 'base64');
      const attempt = Number(fs.existsSync(path.join(stateDir, 'graph-attempts')) ? fs.readFileSync(path.join(stateDir, 'graph-attempts'), 'utf8') : '0') + 1;
      fs.writeFileSync(path.join(stateDir, 'graph-attempts'), String(attempt));
      fs.writeFileSync(path.join(stateDir, 'last-message.eml'), decodedMessage, {mode: 0o600});
      record({kind: 'graph', attempt, path: request.url, scenario: scenario(), bytes: decodedMessage.length});

      switch (scenario()) {
        case 'retry-after':
          if (attempt === 1) return sendJson(response, 429, {error: {code: 'TooManyRequests'}}, {'Retry-After': '2'});
          return response.writeHead(202).end();
        case 'server-error':
          return sendJson(response, 500, {error: {code: 'InternalServerError'}});
        case 'access-denied':
          return sendJson(response, 403, {error: {code: 'ErrorAccessDenied'}});
        case 'unauthorized':
          return sendJson(response, 401, {error: {code: 'InvalidAuthenticationToken'}});
        case 'timeout':
          return sendJson(response, 408, {error: {code: 'RequestTimeout'}});
        default:
          return response.writeHead(202).end();
      }
    }

    record({kind: 'unexpected', method: request.method, path: request.url});
    return sendJson(response, 404, {error: {code: 'NotFound'}});
  } catch (error) {
    record({kind: 'mock-error', message: String(error)});
    return sendJson(response, 500, {error: {code: 'MockFailure'}});
  }
});

server.listen(port, '0.0.0.0', () => {
  record({kind: 'ready', port});
});

process.on('SIGTERM', () => server.close(() => process.exit(0)));
