#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Xray Webhook - JFrog Skills Xray Scan Script
#
# Complete workflow:
#   1. Verify JFrog CLI connection
#   2. Publish skill to alex-skills-local (triggers Xray scan)
#   3. Report synchronous scan result
#   4. Query scan status from Artifactory + Xray API
#   5. Send webhook notification with all results
# ============================================================

# Configuration
JF_BIN="${JF_BIN:-/usr/local/bin/jf}"
SERVER_ID="${JF_SERVER_ID:-solenglatest}"
REPO="${JF_SKILLS_REPO:-alex-skills-local}"
SKILL_DIR="${1:-skills-sample/env-demo-malicious}"
VERSION="${2:-1.1.0}"
AUTO_DELETE="${AUTO_DELETE_ON_FAILURE:-true}"

# Webhook configuration
WEBHOOK_ENABLED="${WEBHOOK_ENABLED:-true}"
WEBHOOK_URL="${WEBHOOK_URL:-https://webhook.site/2e812807-3362-4dd4-835e-b5c6cecd9aaa}"
WEBHOOK_TOKEN="${WEBHOOK_TOKEN:-}"

# Resolve project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SKILL_NAME=$(basename "$SKILL_DIR")

# Validate inputs
JF_BIN_RESOLVED=""
if [ -n "$JF_BIN" ] && command -v "$JF_BIN" >/dev/null 2>&1; then
  JF_BIN_RESOLVED="$JF_BIN"
elif command -v jf >/dev/null 2>&1; then
  JF_BIN_RESOLVED="jf"
fi
[ -n "$JF_BIN_RESOLVED" ] || { echo "ERROR: jf binary not found. Set JF_BIN or ensure jf is in PATH."; exit 1; }
JF_BIN="$JF_BIN_RESOLVED"
[ -f "$PROJECT_ROOT/$SKILL_DIR/SKILL.md" ] || { echo "ERROR: SKILL.md not found in $SKILL_DIR"; exit 1; }

echo "============================================================"
echo "Xray Webhook - Skills Security Scan"
echo "============================================================"
echo "Skill directory : $SKILL_DIR"
echo "Skill version   : $VERSION"
echo "Server ID       : $SERVER_ID"
echo "Repository      : $REPO"
echo "Auto-delete     : $AUTO_DELETE"
echo "Webhook enabled : $WEBHOOK_ENABLED"
echo "Webhook URL     : $WEBHOOK_URL"
echo "============================================================"
echo ""

# Step 1: Verify JFrog CLI connection
echo "[1/5] Verifying JFrog CLI connection..."
$JF_BIN config show "$SERVER_ID" >/dev/null 2>&1 || {
  echo "ERROR: Server ID '$SERVER_ID' not configured. Run: jf config add $SERVER_ID"
  exit 1
}
echo "  -> Connection OK"
echo ""

# Step 2: Publish skill to Artifactory and trigger Xray scan
echo "[2/5] Publishing skill to $REPO and triggering Xray scan..."
echo ""

PUBLISH_ARGS=(
  "$PROJECT_ROOT/$SKILL_DIR"
  --server-id "$SERVER_ID"
  --repo "$REPO"
  --version "$VERSION"
  --quiet
)

if [ "$AUTO_DELETE" = "true" ]; then
  PUBLISH_ARGS+=(--auto-delete-on-failure)
fi

# Capture scan output
SCAN_LOG="$SCRIPT_DIR/scan-output-v${VERSION}.log"
$JF_BIN skills publish "${PUBLISH_ARGS[@]}" 2>&1 | tee "$SCAN_LOG"
PUBLISH_EXIT=$?

echo ""

# Step 3: Report synchronous scan result (from jf skills publish)
echo "[3/5] Synchronous scan result (jf skills publish)"
echo "------------------------------------------------------------"
if [ $PUBLISH_EXIT -eq 0 ]; then
  if grep -q "passed security scan" "$SCAN_LOG" 2>/dev/null; then
    SYNC_STATUS="PASSED"
    echo "STATUS: PASSED"
    echo "The skill passed the Xray security scan."
  elif grep -q "blocked\|malicious\|violation" "$SCAN_LOG" 2>/dev/null; then
    SYNC_STATUS="BLOCKED"
    echo "STATUS: BLOCKED"
    echo "The skill was blocked by Xray security scan."
  else
    SYNC_STATUS="COMPLETED"
    echo "STATUS: COMPLETED"
    echo "Publish completed. Check the scan log for details."
  fi
else
  SYNC_STATUS="FAILED"
  echo "STATUS: FAILED"
  echo "The publish or scan process encountered an error."
fi
echo "------------------------------------------------------------"
echo "Scan log: $SCAN_LOG"
ARTIFACT_PATH="${REPO}/${SKILL_NAME}/${VERSION}/${SKILL_NAME}-${VERSION}.zip"
echo "Artifact: $ARTIFACT_PATH"
echo ""

# Step 4: Query scan status from Artifactory + Xray API
echo "[4/5] Querying scan status in Artifactory..."
echo "------------------------------------------------------------"

# Query artifact properties via jf rt search
SEARCH_RAW=$($JF_BIN rt search "${REPO}/${SKILL_NAME}/${VERSION}/" --server-id "$SERVER_ID" 2>&1)
SEARCH_JSON=$(echo "$SEARCH_RAW" | sed -n '/^\[/,$ p')

# Parse properties
XRAY_STATUS="unknown"
ARTIFACT_SHA256=""
ARTIFACT_SIZE=""

PARSED=$(echo "$SEARCH_JSON" | /usr/bin/python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if len(data) > 0:
        item = data[0]
        print(item.get('sha256', ''))
        print(str(item.get('size', '')))
        props = item.get('props', {})
        xray_status = props.get('skills.xray.status', ['unknown'])
        print(xray_status[0] if isinstance(xray_status, list) else str(xray_status))
    else:
        print('NOT_FOUND')
except Exception as e:
    print(f'ERROR:{e}')
" 2>&1)

if [ "$(echo "$PARSED" | head -1)" != "NOT_FOUND" ] && [ "$(echo "$PARSED" | head -1)" != "ERROR"* ]; then
  ARTIFACT_SHA256=$(echo "$PARSED" | head -1)
  ARTIFACT_SIZE=$(echo "$PARSED" | sed -n '2p')
  XRAY_STATUS=$(echo "$PARSED" | sed -n '3p')
fi

echo "  Artifact in Artifactory : $( [ -n "$ARTIFACT_SHA256" ] && echo 'Found' || echo 'Not found' )"
echo "  SHA256                  : $ARTIFACT_SHA256"
echo "  Size                    : ${ARTIFACT_SIZE:-N/A} bytes"
echo "  skills.xray.status      : $XRAY_STATUS"
echo ""

# Query Xray REST API for scan details (if SHA256 available)
if [ -n "$ARTIFACT_SHA256" ]; then
  echo "  Querying Xray REST API (checksum)..."
  XR_RESPONSE=$($JF_BIN xr curl "/api/v1/artifacts?checksum_type=sha256&checksum_value=${ARTIFACT_SHA256}" --server-id "$SERVER_ID" 2>/dev/null) || XR_RESPONSE=""
  if [ -n "$XR_RESPONSE" ]; then
    echo "$XR_RESPONSE" | /usr/bin/python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'error' in data:
        print(f'    Xray API response      : {data[\"error\"]}')
        print('    (artifact may not be indexed by Xray yet)')
    elif isinstance(data, list) and len(data) > 0:
        a = data[0]
        print(f'    Xray scan status       : {a.get(\"scan_status\", \"N/A\")}')
    elif isinstance(data, dict):
        print(f'    Xray scan status       : {data.get(\"scan_status\", \"N/A\")}')
    else:
        print(f'    Xray API response      : {str(data)[:200]}')
except:
    print(f'    Xray API response      : {sys.stdin.read()[:200]}')
" 2>&1 || true
  else
    echo "    Xray API response      : No response"
  fi
fi
echo "------------------------------------------------------------"
echo ""

# Step 5: Send webhook notification
echo "[5/5] Sending webhook notification..."
echo "------------------------------------------------------------"
if [ "$WEBHOOK_ENABLED" = "true" ]; then
  if [ -x "$SCRIPT_DIR/send-webhook.sh" ]; then
    WEBHOOK_URL="$WEBHOOK_URL" WEBHOOK_TOKEN="$WEBHOOK_TOKEN" \
      XRAY_STATUS="$XRAY_STATUS" \
      ARTIFACT_SHA256="$ARTIFACT_SHA256" \
      SYNC_STATUS="$SYNC_STATUS" \
      bash "$SCRIPT_DIR/send-webhook.sh" "$SCAN_LOG" "$SKILL_NAME" "$VERSION" "$REPO" "$SERVER_ID"
  else
    echo "  send-webhook.sh not found or not executable. Skipping webhook."
  fi
else
  echo "  Webhook disabled (WEBHOOK_ENABLED=false). Skipping."
fi
echo "------------------------------------------------------------"
echo ""
