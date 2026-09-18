import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const response = await fetch(`http://localhost:${process.env.PORT ?? 3100}/webhooks/xray-scan-status`, {
  method: 'POST',
  headers: {
    'content-type': 'application/json',
    'x-skills-webhook-secret': process.env.WEBHOOK_SHARED_SECRET ?? ''
  },
  body: await readFile(path.join(root, 'fixtures', 'xray-scan-done.json'))
});
console.log(response.status, await response.text());
