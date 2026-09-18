import assert from 'node:assert/strict';
import { access, readFile, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { promoteFromScan } from '../src/core.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
await rm(path.join(root, 'data'), { recursive: true, force: true });
await rm(path.join(root, 'authorized-repo'), { recursive: true, force: true });

const payload = JSON.parse(await readFile(path.join(root, 'fixtures', 'xray-scan-done.json'), 'utf8'));
const result = await promoteFromScan({ root, payload });
assert.equal(result.action, 'promoted', JSON.stringify(result));

const authorizedSkill = path.join(root, 'authorized-repo', 'customer-support', '1.0.0', 'SKILL.md');
const approval = path.join(root, 'authorized-repo', 'customer-support', '1.0.0', 'APPROVAL.json');
await access(authorizedSkill);
await access(approval);
assert.match(await readFile(approval, 'utf8'), /"xrayScanStatus": "DONE"/);
console.log(`Pipeline passed: ${result.artifact} promoted to ${result.target}`);
