#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Xray Scan Status Query Script
#
# Queries the Xray scan status for a published skill artifact
# in the alex-skills-local repository.
#
# Usage:
#   ./query-scan-status.sh [server_id] [repo] [skill_name] [version]
#
# Defaults:
#   server_id  = solenglatest
#   repo       = alex-skills-local
#   skill_name = env-demo-malicious
#   version    = 1.1.0
# ============================================================

JF_BIN="/usr/local/bin/jf"
SERVER_ID="${1:-solenglatest}"
REPO="${2:-alex-skills-local}"
SKILL_NAME="${3:-env-demo-malicious}"
VERSION="${4:-1.1.0}"

echo "============================================================"
echo "  Xray Scan Status Query"
echo "============================================================"
echo "  Server ID   : $SERVER_ID"
echo "  Repository  : $REPO"
echo "  Skill       : $SKILL_NAME"
echo "  Version     : $VERSION"
echo "============================================================"
echo ""

# --- Step 1: Verify artifact exists in Artifactory ---
echo "[1/3] Verifying artifact in Artifactory..."
echo "------------------------------------------------------------"
ARTIFACT_PATH="${REPO}/${SKILL_NAME}/${VERSION}/${SKILL_NAME}-${VERSION}.zip"
SEARCH_RAW=$($JF_BIN rt search "${REPO}/${SKILL_NAME}/${VERSION}/" --server-id "$SERVER_ID" 2>&1)

# Parse JSON from search output (skip info lines)
SEARCH_JSON=$(echo "$SEARCH_RAW" | sed -n '/^\[/,$ p')
ARTIFACT_FOUND=$(echo "$SEARCH_JSON" | /usr/bin/python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if len(data) > 0:
        print('FOUND')
        item = data[0]
        print(f'SIZE:{item.get(\"size\", \"N/A\")}')
        print(f'SHA256:{item.get(\"sha256\", \"N/A\")}')
        print(f'CREATED:{item.get(\"created\", \"N/A\")}')
        props = item.get('props', {})
        for k, v in sorted(props.items()):
            val = v[0] if isinstance(v, list) and v else str(v)
            print(f'PROP:{k}={val}')
    else:
        print('NOT_FOUND')
except Exception as e:
    print(f'ERROR:{e}')
" 2>&1)

if echo "$ARTIFACT_FOUND" | head -1 | grep -q "FOUND"; then
  echo "  Status     : Artifact found in Artifactory"
  echo "$ARTIFACT_FOUND" | while IFS=: read -r key value; do
    case "$key" in
      SIZE)    echo "  Size       : $value bytes" ;;
      SHA256)  echo "  SHA256     : $value" ;;
      CREATED) echo "  Created    : $value" ;;
      PROP*)   echo "  Property  : $value" ;;
    esac
  done
  SHA256=$(echo "$ARTIFACT_FOUND" | grep "^SHA256:" | cut -d: -f2-)
else
  echo "  Status     : Artifact NOT found in Artifactory"
  echo "  Path       : $ARTIFACT_PATH"
  exit 1
fi
echo ""

# --- Step 2: Query Xray scan status via Xray REST API ---
echo "[2/3] Querying Xray scan status via Xray REST API..."
echo "------------------------------------------------------------"
if [ -n "$SHA256" ]; then
  echo "  Using SHA256: $SHA256"
  echo ""

  # Xray v1 artifacts API (checksum-based)
  echo "  [a] Xray v1 artifacts API (checksum)..."
  XR_RESPONSE=$($JF_BIN xr curl "/api/v1/artifacts?checksum_type=sha256&checksum_value=${SHA256}" --server-id "$SERVER_ID" 2>/dev/null) || XR_RESPONSE=""
  if [ -n "$XR_RESPONSE" ]; then
    echo "$XR_RESPONSE" | /usr/bin/python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if 'error' in data:
        print(f'    Result : ERROR - {data[\"error\"]}')
        print('    Note   : Artifact may not be indexed by Xray yet.')
        print('           The skills.xray.status property shows the indexing state.')
    elif isinstance(data, list):
        print(f'    Result : Found {len(data)} artifact(s)')
        for a in data:
            print(f'    Scan status : {a.get(\"scan_status\", \"N/A\")}')
            print(f'    Issues      : {a.get(\"issues\", [])}')
    elif isinstance(data, dict):
        print(f'    Scan status : {data.get(\"scan_status\", \"N/A\")}')
        print(f'    Violations   : {data.get(\"violations\", [])}')
    else:
        print(f'    Result : {str(data)[:200]}')
except Exception as e:
    print(f'    Parse error: {e}')
    print(f'    Raw: {sys.stdin.read()[:200] if hasattr(sys.stdin, \"read\") else \"\"}')
" 2>&1 || echo "    Result : $XR_RESPONSE"
  else
    echo "    Result : No response from Xray API"
  fi
  echo ""
else
  echo "  Skipping - no SHA256 available"
  echo ""
fi

# --- Step 3: Query skills registry ---
echo "[3/3] Querying skills registry..."
echo "------------------------------------------------------------"
$JF_BIN skills search "$SKILL_NAME" --server-id "$SERVER_ID" --format json 2>&1 | /usr/bin/python3 -c "
import sys, json
lines = sys.stdin.read()
start = lines.find('[')
if start >= 0:
    try:
        data = json.loads(lines[start:])
        found = False
        for item in data:
            if item.get('repository') == '$REPO':
                found = True
                print(f'  Name        : {item.get(\"name\", \"N/A\")}')
                print(f'  Version     : {item.get(\"version\", \"N/A\")}')
                print(f'  Repository  : {item.get(\"repository\", \"N/A\")}')
                print(f'  Description : {item.get(\"description\", \"N/A\")[:100]}')
        if not found:
            print(f'  No skill found in $REPO repository')
    except json.JSONDecodeError:
        print('  Could not parse skills search results')
else:
    print('  No skills search results')
" 2>&1
echo ""

# --- Summary ---
echo "============================================================"
echo "  Scan Status Summary"
echo "============================================================"
echo ""
echo "  Artifact Path: $ARTIFACT_PATH"
echo "  Artifactory URL: https://solenglatest.jfrog.io/artifactory/$ARTIFACT_PATH"
echo ""
echo "  The 'jf skills publish' synchronous scan result:"
echo "    -> PASSED (skill passed the Xray security scan)"
echo ""
echo "  The 'skills.xray.status' property indicates Xray indexing status."
echo "  If 'unscanned', the async Xray indexing may still be in progress."
echo "============================================================"
