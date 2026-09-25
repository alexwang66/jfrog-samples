#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Step 6: Verify the trusted signing key and final application-version state.
# Evidence creation already performs server-side signature verification. The
# current JFrog CLI does not support verify-evidence for application versions,
# so this step confirms the key remains trusted and the version reached PROD.
# ------------------------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

require jf
require jq

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

say "Checking trusted evidence key ${KEY_ALIAS}"
jf api --server-id "${JF_SERVER_ID}" \
  /artifactory/api/security/keys/trusted > "${TMP_DIR}/trusted-keys.json"

jq -e --arg alias "${KEY_ALIAS}" \
  'any(.keys[]; .alias == $alias)' \
  "${TMP_DIR}/trusted-keys.json" >/dev/null \
  || die "Trusted key alias not found: ${KEY_ALIAS}"
ok "Trusted evidence key is registered"

say "Fetching final application-version state via OneModel GraphQL"
QUERY=$(cat <<GQL
{
  applications {
    getApplicationVersion(applicationKey: "${APP_KEY}", version: "${APP_VERSION}") {
      version
      status
      releaseStatus
      currentStageName
    }
  }
}
GQL
)

jq -n --arg q "${QUERY}" '{query: $q}' > "${TMP_DIR}/query.json"
jf api --server-id "${JF_SERVER_ID}" \
  /onemodel/api/v1/graphql \
  -X POST \
  -H 'Content-Type: application/json' \
  --input "${TMP_DIR}/query.json" > "${TMP_DIR}/response.json"

jq -e '.errors == null' "${TMP_DIR}/response.json" >/dev/null \
  || die "OneModel returned GraphQL errors"
jq -e --arg stage "${STAGE_PROD}" \
  '.data.applications.getApplicationVersion
   | .status == "COMPLETED"
     and .releaseStatus == "RELEASED"
     and .currentStageName == $stage' \
  "${TMP_DIR}/response.json" >/dev/null \
  || die "Application version is not completed and released in ${STAGE_PROD}"

jq '.data.applications.getApplicationVersion' "${TMP_DIR}/response.json"
ok "Verified ${APP_KEY}@${APP_VERSION}: COMPLETED, RELEASED, ${STAGE_PROD}"
