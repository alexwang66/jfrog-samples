import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { promoteFromScan } from '../src/core.mjs';

async function fixtureRoot() {
  const root = await mkdtemp(path.join(os.tmpdir(), 'skill-webhook-'));
  await mkdir(path.join(root, 'config'), { recursive: true });
  await mkdir(path.join(root, 'registry-mirror', 'customer-support', '1.0.0'), { recursive: true });
  await writeFile(path.join(root, 'registry-mirror', 'customer-support', '1.0.0', 'SKILL.md'), '# Approved skill\n');
  await writeFile(path.join(root, 'config', 'approved-skills.json'), JSON.stringify({ artifacts: [{
    repo: 'acme-skills-local', path: 'customer-support/1.0.0', name: 'customer-support-1.0.0.zip',
    skillName: 'customer-support', version: '1.0.0', approval: 'approved'
  }] }));
  return root;
}

function payload(status = 'DONE') {
  return { domain: 'xray_scan_status', event_type: status.toLowerCase(), data: {
    resource: { repo: 'acme-skills-local', path: 'customer-support/1.0.0', name: 'customer-support-1.0.0.zip' },
    overall: { status, updated_at: '2026-09-18T08:30:00Z' }, occurred_at: '2026-09-18T08:30:00Z'
  } };
}

test('promotes only a DONE event for an explicitly approved artifact', async () => {
  const root = await fixtureRoot();
  const result = await promoteFromScan({ root, payload: payload() });
  assert.equal(result.action, 'promoted');
  assert.match(await readFile(path.join(root, 'authorized-repo', 'customer-support', '1.0.0', 'SKILL.md'), 'utf8'), /Approved/);
});

test('does not promote failed scans or duplicate terminal events', async () => {
  const root = await fixtureRoot();
  assert.equal((await promoteFromScan({ root, payload: payload('FAILED') })).action, 'ignored');
  assert.equal((await promoteFromScan({ root, payload: payload() })).action, 'promoted');
  assert.match((await promoteFromScan({ root, payload: payload() })).reason, /duplicate/);
});
