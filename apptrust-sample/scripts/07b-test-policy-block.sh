#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Step 7b: Prove the policy blocks a promotion. Creates a NEW version
# (the next available patch version) from the current build WITHOUT attaching the
# required security-scan evidence, attempts to promote it, expects failure,
# then attaches the evidence and promotes successfully.
#
# Pre-requisite: 07-create-policy.sh has been run.
# ------------------------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

require jf
require jq

BUILD_INFO_REPO="${BUILD_INFO_REPO:-${JF_PROJECT}-build-info}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT

if [[ -z "${TEST_VERSION:-}" ]]; then
  [[ "${APP_VERSION}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] \
    || die "APP_VERSION must use numeric SemVer to derive TEST_VERSION"
  TEST_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"
fi
[[ "${TEST_VERSION}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] \
  || die "TEST_VERSION must use numeric SemVer (for example, 2.3.1)"

jf api --server-id "${JF_SERVER_ID}" \
  "/apptrust/api/v1/applications/${APP_KEY}/versions?limit=1000" \
  > "${WORK_DIR}/versions.json"
while jq -e --arg version "${TEST_VERSION}" \
  'any(.versions[]; .version == $version)' "${WORK_DIR}/versions.json" >/dev/null; do
  IFS=. read -r VERSION_MAJOR VERSION_MINOR VERSION_PATCH <<< "${TEST_VERSION}"
  TEST_VERSION="${VERSION_MAJOR}.${VERSION_MINOR}.$((VERSION_PATCH + 1))"
  warn "Application version already exists; trying ${TEST_VERSION}"
done
export TEST_VERSION
ok "Using policy test version ${TEST_VERSION}"

say "Creating version ${APP_KEY}@${TEST_VERSION} (no evidence attached)"
jf apptrust version-create "${APP_KEY}" "${TEST_VERSION}" \
  --server-id "${JF_SERVER_ID}" \
  --source-type-builds "name=${BUILD_NAME}, id=${BUILD_NUMBER}, repo-key=${BUILD_INFO_REPO}" \
  --tag "policy-test-${TEST_VERSION}" \
  --sync

say "Attempting promotion to ${STAGE_TEST} — expected: BLOCKED"
PROMOTE_LOG="$(mktemp /tmp/apptrust-promote.XXXXXX)"
if jf apptrust version-promote "${APP_KEY}" "${TEST_VERSION}" "${STAGE_TEST}" \
     --server-id "${JF_SERVER_ID}" --promotion-type copy --sync 2>&1 | tee "${PROMOTE_LOG}"; then
  rm -f "${PROMOTE_LOG}"
  die "Promotion should have been blocked but was not!"
else
  if grep -q "policy violations" "${PROMOTE_LOG}"; then
    ok "Promotion correctly blocked by policy"
  else
    warn "Promotion failed for a different reason (see ${PROMOTE_LOG})"
    exit 1
  fi
fi
rm -f "${PROMOTE_LOG}"

say "Attaching security-scan evidence to unblock"
sed -e "s|REPLACE_WITH_TAG|${TEST_VERSION}|g" \
    -e "s|REPLACE_WITH_PLATFORM|${REGISTRY_HOST}|g" \
    -e "s|REPLACE_WITH_REPO|${DOCKER_REPO_DEV}|g" \
    "${REPO_ROOT}/evidence/security-scan.json" > "${WORK_DIR}/scan.json"

jf evd create-evidence \
  --server-id "${JF_SERVER_ID}" \
  --application-key "${APP_KEY}" \
  --application-version "${TEST_VERSION}" \
  --predicate "${WORK_DIR}/scan.json" \
  --predicate-type "https://jfrog.com/evidence/security-scan/v1" \
  --key "${PRIVATE_KEY}" \
  --key-alias "${KEY_ALIAS}"

say "Retrying promotion to ${STAGE_TEST} — expected: SUCCESS"
jf apptrust version-promote "${APP_KEY}" "${TEST_VERSION}" "${STAGE_TEST}" \
  --server-id "${JF_SERVER_ID}" --promotion-type copy --sync
ok "Promotion succeeded after evidence attached"
