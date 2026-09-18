#!/usr/bin/env bash
set -euo pipefail

skill_dir="${1:-}"
repo_key="${JFROG_SKILLS_REPO:-alex-skills-local}"
root="${SKILLS_FLOW_ROOT:-skills-management-flow}"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

[ -n "$skill_dir" ] || fail "skill directory argument is required"

validation_output="$(bash "$root/scripts/validate-skill.sh" "$skill_dir")"
skill_name="$(printf '%s\n' "$validation_output" | awk -F= '/^SKILL_NAME=/{print $2}')"
skill_version="$(printf '%s\n' "$validation_output" | awk -F= '/^SKILL_VERSION=/{print $2}')"
skill_file="$skill_dir/SKILL.md"
authorized_dir="$root/authorized/$skill_name"
approval_file="$authorized_dir/APPROVAL.json"
approved_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
source_sha="$(shasum -a 256 "$skill_file" | awk '{print $1}')"

mkdir -p "$authorized_dir"
cp "$skill_file" "$authorized_dir/SKILL.md"

{
  printf '{\n'
  printf '  "skill": "%s",\n' "$skill_name"
  printf '  "version": "%s",\n' "$skill_version"
  printf '  "sourcePath": "%s",\n' "$skill_file"
  printf '  "authorizedPath": "%s",\n' "$authorized_dir/SKILL.md"
  printf '  "sourceSha256": "%s",\n' "$source_sha"
  printf '  "jfrogRepository": "%s",\n' "$repo_key"
  printf '  "approvedBy": "github-actions",\n'
  printf '  "githubRunId": "%s",\n' "${GITHUB_RUN_ID:-local}"
  printf '  "githubSha": "%s",\n' "${GITHUB_SHA:-local}"
  printf '  "approvedAt": "%s"\n' "$approved_at"
  printf '}\n'
} > "$approval_file"

printf 'Promoted %s@%s to %s\n' "$skill_name" "$skill_version" "$authorized_dir"
