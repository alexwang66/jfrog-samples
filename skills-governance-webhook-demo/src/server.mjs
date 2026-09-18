import http from 'node:http';
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promoteFromScan } from './core.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const port = Number(process.env.PORT ?? 3100);
const secret = process.env.WEBHOOK_SHARED_SECRET;

function isAuthorized(value) {
  if (!secret) return false;
  const actual = Buffer.from(value ?? '');
  const expected = Buffer.from(secret);
  return actual.length === expected.length && crypto.timingSafeEqual(actual, expected);
}

const server = http.createServer(async (request, response) => {
  if (request.method === 'GET' && request.url === '/health') {
    response.writeHead(200, { 'content-type': 'application/json' });
    return response.end('{"status":"ok"}\n');
  }
  if (request.method !== 'POST' || request.url !== '/webhooks/xray-scan-status') {
    response.writeHead(404).end();
    return;
  }
  // Configure this value as a JFrog Platform custom webhook header, e.g.
  // X-Skills-Webhook-Secret: <secret>. Do not expose it to business users.
  if (!isAuthorized(request.headers['x-skills-webhook-secret'])) {
    response.writeHead(401, { 'content-type': 'application/json' });
    return response.end('{"error":"unauthorized"}\n');
  }
  let body = '';
  for await (const chunk of request) body += chunk;
  try {
    const result = await promoteFromScan({ root, payload: JSON.parse(body) });
    response.writeHead(result.action === 'promoted' ? 201 : 202, { 'content-type': 'application/json' });
    response.end(`${JSON.stringify(result)}\n`);
  } catch (error) {
    console.error(error);
    response.writeHead(500, { 'content-type': 'application/json' });
    response.end('{"error":"promotion failed"}\n');
  }
});

server.listen(port, () => console.log(`Webhook receiver listening on http://localhost:${port}`));
