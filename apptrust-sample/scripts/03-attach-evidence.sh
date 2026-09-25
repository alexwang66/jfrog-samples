#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Step 3: Attach three evidence records before lifecycle promotion:
#   1. SLSA provenance   - who built it, from what source, with what tools
#   2. Unit-test results - test framework attestation
#   3. Security scan     - Xray results summary
# QA sign-off is attached later before release.
# All records are signed with the ECDSA key generated in step 0.
# ------------------------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
EVD_DIR="${REPO_ROOT}/evidence"

require jf
require jq

[[ -f "${PRIVATE_KEY}" ]] || die "Missing signing key at ${PRIVATE_KEY}. Run 00-init.sh first."

# Fill in template placeholders with real values from the environment.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

GIT_SHA="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || echo 'unknown')"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

render() {
  local src="$1" dst="$2"
  sed -e "s|REPLACE_WITH_GIT_SHA|${GIT_SHA}|g" \
      -e "s|REPLACE_WITH_START_TIME|${NOW}|g" \
      -e "s|REPLACE_WITH_END_TIME|${NOW}|g" \
      -e "s|REPLACE_WITH_RUN_ID|local-${NOW}|g" \
      -e "s|REPLACE_WITH_TAG|${IMAGE_TAG}|g" \
      -e "s|REPLACE_WITH_PLATFORM|${REGISTRY_HOST}|g" \
      -e "s|REPLACE_WITH_REPO|${DOCKER_REPO_DEV}|g" \
      -e "s|REPLACE_WITH_APPROVER|${USER:-ci}|g" \
      -e "s|REPLACE_WITH_ISO_TIMESTAMP|${NOW}|g" \
      -e "s|REPLACE_WITH_BASE_IMAGE_DIGEST|sha256:0000000000000000000000000000000000000000000000000000000000000000|g" \
      "${src}" > "${dst}"
  jq . "${dst}" >/dev/null || die "Rendered predicate is not valid JSON: ${dst}"
}

render "${EVD_DIR}/slsa-provenance.json" "${TMP_DIR}/slsa.json"
render "${EVD_DIR}/unit-tests.json"      "${TMP_DIR}/tests.json"
render "${EVD_DIR}/security-scan.json"   "${TMP_DIR}/scan.json"

attach_evidence() {
  local predicate="$1" predicate_type="$2" label="$3"
  say "Attaching evidence: ${label}"
  # NOTE: --project is inferred from the application; passing it explicitly is
  # rejected by the AppTrust evidence API in this mode.
  jf evd create-evidence \
    --server-id "${JF_SERVER_ID}" \
    --application-key "${APP_KEY}" \
    --application-version "${APP_VERSION}" \
    --predicate "${predicate}" \
    --predicate-type "${predicate_type}" \
    --key "${PRIVATE_KEY}" \
    --key-alias "${KEY_ALIAS}"
  ok "Attached ${label}"
}

attach_evidence "${TMP_DIR}/slsa.json"  "https://slsa.dev/provenance/v1"                       "SLSA provenance v1"
attach_evidence "${TMP_DIR}/tests.json" "https://jfrog.com/evidence/test-results/v1"           "unit-test results"
attach_evidence "${TMP_DIR}/scan.json"  "https://jfrog.com/evidence/security-scan/v1"          "Xray security scan"

ok "Pre-promotion evidence attached. Next: scripts/04-promote.sh"
