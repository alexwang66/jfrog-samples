#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Step 7: Ensure a Unified Policy that blocks TEST entry unless the application
# version has security-scan/v1 evidence. Existing resources are updated/reused so
# the script can be demonstrated repeatedly without duplicate-name failures.
# ------------------------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

require jf
require jq

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

REGO_FILE="${REPO_ROOT}/policy/require-security-scan.rego"
[[ -f "${REGO_FILE}" ]] || die "Missing Rego at ${REGO_FILE}"
REGO_TEXT="$(cat "${REGO_FILE}")"

TEMPLATE_NAME="${TEMPLATE_NAME:-${APP_KEY}-require-security-scan-v2}"
RULE_NAME="${RULE_NAME:-${APP_KEY}-require-security-scan-rule-v5}"
POLICY_NAME="${POLICY_NAME:-${APP_KEY}-test-entry-must-have-scan}"
POLICY_GATE="${POLICY_GATE:-entry}"
POLICY_STAGE="${POLICY_STAGE:-${STAGE_TEST}}"

list_resources() {
  local resource="$1"
  jf api --server-id "${JF_SERVER_ID}" \
    "/unifiedpolicy/api/v1/${resource}?limit=1000" \
    > "${TMP_DIR}/${resource}.json"
}

find_id_by_name() {
  local resource="$1" name="$2"
  jq -r --arg name "${name}" \
    '(.items // .)[] | select(.name == $name) | .id' \
    "${TMP_DIR}/${resource}.json" | head -n 1
}

TMPL_BODY=$(jq -n --arg name "${TEMPLATE_NAME}" --arg rego "${REGO_TEXT}" '{
  name: $name,
  description: "AppTrust demo: require a security-scan/v1 evidence before promotion",
  category: "quality",
  data_source_type: "onemodel_evidence",
  version: "1.0.0",
  parameters: [],
  scanners: [],
  is_custom: true,
  rego: $rego
}')
printf '%s' "${TMPL_BODY}" > "${TMP_DIR}/template.json"

list_resources templates
TMPL_ID="$(find_id_by_name templates "${TEMPLATE_NAME}")"
if [[ -n "${TMPL_ID}" ]]; then
  say "Updating template '${TEMPLATE_NAME}'"
  jf api --server-id "${JF_SERVER_ID}" \
    "/unifiedpolicy/api/v1/templates/${TMPL_ID}" \
    -X PUT -H 'Content-Type: application/json' \
    --input "${TMP_DIR}/template.json" > "${TMP_DIR}/template-response.json"
else
  say "Creating template '${TEMPLATE_NAME}'"
  jf api --server-id "${JF_SERVER_ID}" /unifiedpolicy/api/v1/templates \
    -X POST -H 'Content-Type: application/json' \
    --input "${TMP_DIR}/template.json" > "${TMP_DIR}/template-response.json"
  TMPL_ID="$(jq -r '.id' "${TMP_DIR}/template-response.json")"
fi
[[ -n "${TMPL_ID}" && "${TMPL_ID}" != "null" ]] || die "Template setup failed"
ok "Template id: ${TMPL_ID}"

list_resources rules
RULE_ID="$(find_id_by_name rules "${RULE_NAME}")"
if [[ -n "${RULE_ID}" ]]; then
  EXISTING_TEMPLATE_ID="$(jq -r --arg id "${RULE_ID}" '(.items // .)[] | select(.id == $id) | .template_id' "${TMP_DIR}/rules.json")"
  [[ "${EXISTING_TEMPLATE_ID}" == "${TMPL_ID}" ]] \
    || die "Existing rule '${RULE_NAME}' references template ${EXISTING_TEMPLATE_ID}, expected ${TMPL_ID}"
  say "Reusing rule '${RULE_NAME}'"
else
  say "Creating rule '${RULE_NAME}'"
  jq -n --arg name "${RULE_NAME}" --arg tid "${TMPL_ID}" '{
    name: $name,
    description: "Require security-scan/v1 evidence for the target application",
    template_id: $tid,
    parameters: [],
    is_custom: true
  }' > "${TMP_DIR}/rule.json"
  jf api --server-id "${JF_SERVER_ID}" /unifiedpolicy/api/v1/rules \
    -X POST -H 'Content-Type: application/json' \
    --input "${TMP_DIR}/rule.json" > "${TMP_DIR}/rule-response.json"
  RULE_ID="$(jq -r '.id' "${TMP_DIR}/rule-response.json")"
fi
[[ -n "${RULE_ID}" && "${RULE_ID}" != "null" ]] || die "Rule setup failed"
ok "Rule id: ${RULE_ID}"

jq -n \
  --arg name "${POLICY_NAME}" \
  --arg app "${APP_KEY}" \
  --arg gate "${POLICY_GATE}" \
  --arg stage "${POLICY_STAGE}" \
  --arg rid "${RULE_ID}" '{
  name: $name,
  description: "Block TEST entry unless security-scan evidence exists",
  enabled: true,
  mode: "block",
  rule_ids: [$rid],
  scope: {type: "application", application_keys: [$app]},
  action: {type: "certify_to_gate", stage: {gate: $gate, key: $stage}}
}' > "${TMP_DIR}/policy.json"

list_resources policies
POLICY_ID="$(find_id_by_name policies "${POLICY_NAME}")"
if [[ -n "${POLICY_ID}" ]]; then
  say "Updating policy '${POLICY_NAME}'"
  jf api --server-id "${JF_SERVER_ID}" \
    "/unifiedpolicy/api/v1/policies/${POLICY_ID}" \
    -X PUT -H 'Content-Type: application/json' \
    --input "${TMP_DIR}/policy.json" > "${TMP_DIR}/policy-response.json"
else
  say "Creating policy '${POLICY_NAME}'"
  jf api --server-id "${JF_SERVER_ID}" /unifiedpolicy/api/v1/policies \
    -X POST -H 'Content-Type: application/json' \
    --input "${TMP_DIR}/policy.json" > "${TMP_DIR}/policy-response.json"
  POLICY_ID="$(jq -r '.id' "${TMP_DIR}/policy-response.json")"
fi
[[ -n "${POLICY_ID}" && "${POLICY_ID}" != "null" ]] || die "Policy setup failed"
ok "Policy id: ${POLICY_ID}"

cat <<SUMMARY

Summary
-------
Template : ${TEMPLATE_NAME} (${TMPL_ID})
Rule     : ${RULE_NAME} (${RULE_ID})
Policy   : ${POLICY_NAME} (${POLICY_ID})
Blocks   : promotion into stage '${POLICY_STAGE}' (${POLICY_GATE}_gate) for app '${APP_KEY}'
           unless security-scan/v1 evidence is attached.
SUMMARY
