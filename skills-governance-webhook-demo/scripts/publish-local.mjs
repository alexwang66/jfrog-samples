import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.join(root, 'development-repo', 'customer-support');
const target = path.join(root, 'registry-mirror', 'customer-support', '1.0.0');
await rm(target, { recursive: true, force: true });
await mkdir(path.dirname(target), { recursive: true });
await cp(source, target, { recursive: true });
const skillContents = await readFile(path.join(source, 'SKILL.md'));
await writeFile(path.join(target, 'registry-artifact.json'), JSON.stringify({
  repository: 'acme-skills-local',
  path: 'customer-support/1.0.0',
  name: 'customer-support-1.0.0.zip',
  publishedAt: new Date().toISOString(),
  sourceSha256: crypto.createHash('sha256').update(skillContents).digest('hex')
}, null, 2) + '\n');
console.log('Published local fixture to registry-mirror/customer-support/1.0.0');
