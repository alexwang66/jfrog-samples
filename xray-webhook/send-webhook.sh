#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Xray Webhook - Notification Sender
#
# Parses Xray scan output and sends a webhook notification
# with the scan results to a configured webhook URL.
#
# Usage:
#   ./send-webhook.sh <scan_log_file> <skill_name> <version> <repo> <server_id>
#
# Environment variables:
#   WEBHOOK_URL    - Target webhook URL (default: webhook.site endpoint)
#   WEBHOOK_TOKEN  - Optional bearer token for authentication
# ============================================================

# Resolve script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Arguments ---
SCAN_LOG="${1:-}"
SKILL_NAME="${2:-env-demo-malicious}"
VERSION="${3:-1.0.7}"
REPO="${4:-alex-skills-local}"
SERVER_ID="${5:-solenglatest}"

# --- Configuration ---
WEBHOOK_URL="${WEBHOOK_URL:-https://webhook.site/2e812807-3362-4dd4-835e-b5c6cecd9aaa}"
WEBHOOK_TOKEN="${WEBHOOK_TOKEN:-}"

# --- Scan status from Artifactory query (passed by run-xray-scan.sh) ---
XRAY_INDEX_STATUS="${XRAY_STATUS:-unknown}"
ARTIFACT_SHA256="${ARTIFACT_SHA256:-}"
SYNC_SCAN_STATUS="${SYNC_STATUS:-$SCAN_STATUS}"

# --- Validate scan log ---
if [ -z "$SCAN_LOG" ] || [ ! -f "$SCAN_LOG" ]; then
  echo "ERROR: Scan log file not provided or does not exist: $SCAN_LOG" >&2
  exit 1
fi

# --- Parse scan status from log ---
SCAN_STATUS="UNKNOWN"
SCAN_MESSAGE=""

if grep -q "passed security scan" "$SCAN_LOG" 2>/dev/null; then
  SCAN_STATUS="PASSED"
  SCAN_MESSAGE="Skill ${SKILL_NAME} v${VERSION} passed the Xray security scan."
elif grep -qi "blocked\|malicious.*detect\|violation.*found" "$SCAN_LOG" 2>/dev/null; then
  SCAN_STATUS="BLOCKED"
  SCAN_MESSAGE="Skill ${SKILL_NAME} v${VERSION} was BLOCKED by Xray security scan. Malicious content detected."
elif grep -qi "failed\|error" "$SCAN_LOG" 2>/dev/null; then
  SCAN_STATUS="FAILED"
  SCAN_MESSAGE="Skill ${SKILL_NAME} v${VERSION} publish or scan failed with an error."
else
  SCAN_STATUS="COMPLETED"
  SCAN_MESSAGE="Skill ${SKILL_NAME} v${VERSION} scan completed. Check log for details."
fi

# Determine JFrog platform URL based on server ID
case "$SERVER_ID" in
  solenglatest) JFROG_URL="https://solenglatest.jfrog.io" ;;
  soleng)       JFROG_URL="https://soleng.jfrog.io" ;;
  demo)         JFROG_URL="https://demo.jfrogchina.com" ;;
  *)            JFROG_URL="https://${SERVER_ID}.jfrog.io" ;;
esac

# Artifact path
ARTIFACT_PATH="${REPO}/${SKILL_NAME}/${VERSION}/${SKILL_NAME}-${VERSION}.zip"

# --- Build webhook payload ---
SCAN_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

PAYLOAD=$(cat <<ENDJSON
{
  "event_type": "xray_scan_completed",
  "sync_scan_status": "${SYNC_SCAN_STATUS}",
  "xray_index_status": "${XRAY_INDEX_STATUS}",
  "status": "${SCAN_STATUS}",
  "message": "${SCAN_MESSAGE}",
  "skill_name": "${SKILL_NAME}",
  "skill_version": "${VERSION}",
  "repository": "${REPO}",
  "artifact_path": "${ARTIFACT_PATH}",
  "artifact_sha256": "${ARTIFACT_SHA256}",
  "server_id": "${SERVER_ID}",
  "jfrog_url": "${JFROG_URL}",
  "timestamp": "${SCAN_TIME}",
  "scan_log": "$(basename "$SCAN_LOG")"
}
ENDJSON
)

echo ""
echo "============================================================"
echo "  Sending Webhook Notification"
echo "============================================================"
echo "  Webhook URL  : $WEBHOOK_URL"
echo "  Event Type   : xray_scan_completed"
echo "  Sync Status  : $SYNC_SCAN_STATUS"
echo "  Xray Index   : $XRAY_INDEX_STATUS"
echo "  SHA256       : $ARTIFACT_SHA256"
echo "  Status       : $SCAN_STATUS"
echo "  Skill        : $SKILL_NAME"
echo "  Version      : $VERSION"
echo "  Repository   : $REPO"
echo "  Artifact     : $ARTIFACT_PATH"
echo "  Timestamp    : $SCAN_TIME"
echo "============================================================"
echo ""

# --- Send webhook notification via curl ---
CURL_ARGS=(
  -s
  -X POST
  -H "Content-Type: application/json"
  -w "\nHTTP_STATUS:%{http_code}"
  --max-time 10
)

if [ -n "$WEBHOOK_TOKEN" ]; then
  CURL_ARGS+=(-H "Authorization: Bearer ${WEBHOOK_TOKEN}")
fi

CURL_ARGS+=(-d "$PAYLOAD" "$WEBHOOK_URL")

echo "Sending POST to $WEBHOOK_URL ..."
echo ""
echo "Payload:"
echo "$PAYLOAD" | /usr/bin/python3 -m json.tool 2>/dev/null || echo "$PAYLOAD"
echo ""

RESPONSE=$(curl "${CURL_ARGS[@]}" 2>&1) || true
HTTP_CODE=$(echo "$RESPONSE" | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)
RESPONSE_BODY=$(echo "$RESPONSE" | sed 's/HTTP_STATUS:[0-9]*//')

echo "Response:"
echo "  HTTP Status : ${HTTP_CODE:-N/A}"
echo "  Body        : ${RESPONSE_BODY:-N/A}"
echo ""

if [ "${HTTP_CODE:-000}" = "200" ]; then
  echo "  -> Webhook notification sent successfully."
  echo "     View at: https://webhook.site/#!/2e812807-3362-4dd4-835e-b5c6cecd9aaa"
else
  echo "  -> WARNING: Webhook delivery may have failed (HTTP ${HTTP_CODE:-000})."
  echo "     Check webhook URL: $WEBHOOK_URL"
fi
echo ""
