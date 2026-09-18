import { cp, mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';

const readJson = async (file) => JSON.parse(await readFile(file, 'utf8'));

export function artifactKey(resource) {
  return `${resource.repo}/${resource.path}/${resource.name}`;
}

export async function promoteFromScan({ root, payload }) {
  if (payload?.domain !== 'xray_scan_status') {
    return { action: 'ignored', reason: 'unsupported webhook domain' };
  }

  if (payload?.data?.overall?.status !== 'DONE' || payload?.event_type !== 'done') {
    return { action: 'ignored', reason: 'scan did not finish successfully' };
  }

  const resource = payload?.data?.resource;
  if (!resource?.repo || !resource?.path || !resource?.name) {
    return { action: 'ignored', reason: 'missing artifact coordinates' };
  }

  const config = await readJson(path.join(root, 'config', 'approved-skills.json'));
  const key = artifactKey(resource);
  const approved = config.artifacts.find((item) => artifactKey(item) === key);
  if (!approved || approved.approval !== 'approved') {
    return { action: 'ignored', reason: 'artifact is not explicitly approved', artifact: key };
  }

  // Xray can emit more than one terminal event for the same resource. Keep the
  // promotion idempotent, as required for webhook consumers.
  const eventId = `${key}@${payload.data.occurred_at ?? payload.data.overall.updated_at ?? 'unknown'}`
    .replaceAll('/', '__').replaceAll(':', '-');
  const stateDir = path.join(root, 'data', 'processed-events');
  const stateFile = path.join(stateDir, `${eventId}.json`);
  try {
    await readFile(stateFile, 'utf8');
    return { action: 'ignored', reason: 'duplicate terminal event', artifact: key };
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }

  // In production replace registry-mirror with an authenticated download from
  // Artifactory. Promotion intentionally never reads development-repo.
  const source = path.join(root, 'registry-mirror', approved.skillName, approved.version);
  const target = path.join(root, 'authorized-repo', approved.skillName, approved.version);
  await mkdir(path.dirname(target), { recursive: true });
  await cp(source, target, { recursive: true, force: true });
  await writeFile(path.join(target, 'APPROVAL.json'), JSON.stringify({
    skill: approved.skillName,
    version: approved.version,
    artifact: key,
    xrayScanStatus: payload.data.overall.status,
    scanCompletedAt: payload.data.occurred_at ?? null,
    promotedAt: new Date().toISOString()
  }, null, 2) + '\n');
  await mkdir(stateDir, { recursive: true });
  await writeFile(stateFile, JSON.stringify({ artifact: key, receivedAt: new Date().toISOString() }) + '\n');
  return { action: 'promoted', artifact: key, target };
}
