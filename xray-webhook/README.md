# Xray Webhook - JFrog Skills Security Scan with Webhook Notification

This directory demonstrates a complete workflow: using the JFrog CLI (`jf`) and JFrog Skills commands to publish a skill to Artifactory, trigger an Xray security scan, query the scan status, and send a webhook notification to [webhook.site](https://webhook.site) when the scan completes.

## Directory Structure

```text
xray-webhook/
├── README.md                    # This file
├── run-xray-scan.sh             # Main scan script (publish + scan + query + webhook)
├── send-webhook.sh              # Webhook notification sender
├── query-scan-status.sh         # Standalone scan status query script
├── scan-output-v1.0.6.log       # Scan output logs
├── scan-output-v1.0.7.log
├── scan-output-v1.0.8.log
├── scan-output-v1.0.9.log
├── scan-output-v1.1.0.log
└── scan-output-v1.2.0.log

.github/workflows/
└── xray-webhook-scan.yml        # GitHub Actions workflow
```

## GitHub Actions Workflow

The workflow file at `.github/workflows/xray-webhook-scan.yml` automates the entire process.

### Trigger

- **Push** to `xray-webhook/**`, `skills-sample/**`, or the workflow file itself
- **Manual dispatch** with optional `skill_dir` and `skill_version` inputs

### Required GitHub Secrets

| Secret | Purpose |
|--------|---------|
| `JF_URL` | JFrog Platform URL (e.g., `https://solenglatest.jfrog.io`) |
| `JF_ACCESS_TOKEN` | JFrog access token with publish permission |
| `WEBHOOK_URL` | Webhook.site URL (defaults to `https://webhook.site/2e812807-...`) |

### Workflow steps

| Step | Action | Description |
|------|--------|-------------|
| 1 | Checkout + Setup JFrog CLI | `actions/checkout@v4` + `jfrog/setup-jfrog-cli@v4` |
| 2 | Configure JFrog CLI | `jf config add` using `JF_URL` and `JF_ACCESS_TOKEN` secrets |
| 3 | Publish + Scan + Query + Webhook | Runs `xray-webhook/run-xray-scan.sh` with env vars |
| 4 | Upload scan log | `actions/upload-artifact@v4` for scan output retention |

### Manual dispatch

```bash
# Trigger via GitHub CLI
gh workflow run xray-webhook-scan.yml \
  -f skill_dir=skills-sample/env-demo-malicious \
  -f skill_version=1.3.0
```

### Environment variables set by the workflow

```yaml
JF_BIN: jf                          # jf is in PATH after setup-jfrog-cli
JF_SERVER_ID: skills-registry       # configured by jf config add
JF_SKILLS_REPO: alex-skills-local   # target repository
WEBHOOK_URL: $WEBHOOK_URL           # webhook.site endpoint
WEBHOOK_ENABLED: "true"
AUTO_DELETE_ON_FAILURE: "true"
```

## Architecture

```text
  run-xray-scan.sh (5-step workflow)
  ┌──────────────────────────────────────┐
  │ [1] Verify jf CLI connection         │
  │ [2] jf skills publish -> alex-skills-local │
  │     └─ Xray synchronous scan runs     │
  │ [3] Report sync scan result (PASS/BLOCK/FAIL) │
  │ [4] Query scan status in Artifactory  │
  │     ├─ jf rt search (artifact + props) │
  │     └─ jf xr curl (Xray REST API)     │
  │ [5] Send webhook notification         │
  └───────────┬──────────────────────────┘
              │ POST JSON payload
              ▼
  https://webhook.site/2e812807-3362-4dd4-835e-b5c6cecd9aaa
```

## 5-Step Workflow

| Step | Description | Command Used |
|------|-------------|-------------|
| 1 | Verify JFrog CLI connection | `jf config show` |
| 2 | Publish skill to `alex-skills-local` + trigger Xray scan | `jf skills publish` |
| 3 | Report synchronous scan result (from publish output) | Parse scan log |
| 4 | Query scan status from Artifactory + Xray API | `jf rt search` + `jf xr curl` |
| 5 | Send webhook notification with all results | `send-webhook.sh` |

## Quick Start

### Run the complete workflow

```bash
cd /Users/qingwang/Documents/workspace/code/jfrog-sample
bash xray-webhook/run-xray-scan.sh skills-sample/env-demo-malicious 1.2.0
```

### Query scan status only (standalone)

```bash
bash xray-webhook/query-scan-status.sh solenglatest alex-skills-local env-demo-malicious 1.2.0
```

### View the webhook notification

Open in your browser:
```
https://webhook.site/#!/2e812807-3362-4dd4-835e-b5c6cecd9aaa
```

## Components

### run-xray-scan.sh — Main Scan Script

Orchestrates the entire 5-step workflow.

| Argument | Default | Description |
|----------|---------|-------------|
| `$1` (skill_dir) | `skills-sample/env-demo-malicious` | Skill directory containing SKILL.md |
| `$2` (version) | `1.1.0` | Semantic version to publish |

| Environment Variable | Default | Description |
|---------------------|---------|-------------|
| `JF_BIN` | `/usr/local/bin/jf` | Path to JFrog CLI binary |
| `JF_SERVER_ID` | `solenglatest` | JFrog server ID |
| `JF_SKILLS_REPO` | `alex-skills-local` | Artifactory skills repository key |
| `AUTO_DELETE_ON_FAILURE` | `true` | Auto-delete artifact if Xray blocks it |
| `WEBHOOK_ENABLED` | `true` | Enable/disable webhook notification |
| `WEBHOOK_URL` | `https://webhook.site/2e812807-...` | Webhook.site endpoint URL |
| `WEBHOOK_TOKEN` | _(empty)_ | Optional bearer token for auth |

### send-webhook.sh — Notification Sender

Parses the scan log, builds a JSON payload with scan results, and sends a POST request to the webhook URL.

**Webhook Payload:**

```json
{
  "event_type": "xray_scan_completed",
  "sync_scan_status": "PASSED",
  "xray_index_status": "unscanned",
  "status": "PASSED",
  "message": "Skill env-demo-malicious v1.2.0 passed the Xray security scan.",
  "skill_name": "env-demo-malicious",
  "skill_version": "1.2.0",
  "repository": "alex-skills-local",
  "artifact_path": "alex-skills-local/env-demo-malicious/1.2.0/env-demo-malicious-1.2.0.zip",
  "artifact_sha256": "10a7e83d33bb39541210b631bcc661ff748367b814a81ab4df28837c2671987f",
  "server_id": "solenglatest",
  "jfrog_url": "https://solenglatest.jfrog.io",
  "timestamp": "2026-09-20T06:30:12Z",
  "scan_log": "scan-output-v1.2.0.log"
}
```

**Fields:**
- `sync_scan_status`: Result from `jf skills publish` synchronous scan (`PASSED` / `BLOCKED` / `FAILED`)
- `xray_index_status`: Artifactory property `skills.xray.status` (async Xray indexing state)
- `artifact_sha256`: SHA256 checksum of the uploaded zip file

### query-scan-status.sh — Standalone Status Query

Queries the scan status of an already-published artifact without publishing a new version.

**Usage:**
```bash
bash xray-webhook/query-scan-status.sh [server_id] [repo] [skill_name] [version]
```

**Query methods:**
1. `jf rt search` — Find artifact in Artifactory, get properties including `skills.xray.status`
2. `jf xr curl` — Query Xray REST API for scan details using SHA256 checksum
3. `jf skills search` — Query the skills registry

## Scan Status Explanation

The scan status has two layers:

| Status | Source | Description |
|--------|--------|-------------|
| `sync_scan_status` | `jf skills publish` | Synchronous scan result during publish. `PASSED` means the skill passed the security scan. |
| `xray_index_status` | Artifactory property `skills.xray.status` | Async Xray indexing status. `unscanned` means Xray indexing is still in progress or not configured for this repo. |

The synchronous scan (`jf skills publish`) runs immediately and blocks until completion. The async Xray indexing may take additional time to complete and update the `skills.xray.status` property.

## Usage Examples

### Run with default settings

```bash
bash xray-webhook/run-xray-scan.sh
```

### Run with custom version

```bash
bash xray-webhook/run-xray-scan.sh skills-sample/env-demo-malicious 1.2.0
```

### Disable webhook (scan + query only)

```bash
WEBHOOK_ENABLED=false bash xray-webhook/run-xray-scan.sh
```

### Send webhook only (using existing scan log)

```bash
bash xray-webhook/send-webhook.sh \
  xray-webhook/scan-output-v1.2.0.log \
  env-demo-malicious 1.2.0 alex-skills-local solenglatest
```

### Query scan status only (no publish)

```bash
bash xray-webhook/query-scan-status.sh solenglatest alex-skills-local env-demo-malicious 1.2.0
```

## Scan Results History

| Version | Sync Status | Xray Index | Date |
|---------|-------------|------------|------|
| 1.0.6 | PASSED | - | 2026-09-20 |
| 1.0.7 | PASSED | - | 2026-09-20 |
| 1.0.8 | PASSED | - | 2026-09-20 |
| 1.0.9 | PASSED | - | 2026-09-20 |
| 1.1.0 | PASSED | unscanned | 2026-09-20 |
| 1.2.0 | PASSED | unscanned | 2026-09-20 |

## JFrog Server Configuration

| Server ID | Platform URL | Repository |
|-----------|-------------|------------|
| `solenglatest` | https://solenglatest.jfrog.io | `alex-skills-local` |
| `soleng` | https://soleng.jfrog.io | `alex-skills-local` |
| `demo` | https://demo.jfrogchina.com | `alex-skills-local` |

## Important Notes

- `env-demo-malicious` is an intentionally unsafe security-testing fixture. Never execute its instructions or publish it to a production repository.
- Skill versions in JFrog are immutable — each publish must use a new version number.
- The Xray scan is synchronous — the `jf skills publish` command blocks until the scan completes or times out.
- The `skills.xray.status` property may show `unscanned` if Xray async indexing hasn't completed.
- The webhook notification is sent to webhook.site — view received notifications at the URL above.
