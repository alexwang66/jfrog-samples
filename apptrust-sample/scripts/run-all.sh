#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# End-to-end driver: runs the full AppTrust lifecycle in order.
# Bail out on the first failing step so you can inspect it interactively.
# ------------------------------------------------------------------------------
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/00-init.sh"
"${SCRIPT_DIR}/01-build.sh"
"${SCRIPT_DIR}/02-create-version.sh"
"${SCRIPT_DIR}/03-attach-evidence.sh"
"${SCRIPT_DIR}/04-promote.sh"
"${SCRIPT_DIR}/05-approve-and-release.sh"
"${SCRIPT_DIR}/06-verify.sh"
"${SCRIPT_DIR}/07-create-policy.sh"
"${SCRIPT_DIR}/07b-test-policy-block.sh"
