#!/usr/bin/env bash
set -euo pipefail

skill_dir="${1:-}"
root="${SKILLS_FLOW_ROOT:-skills-management-flow}"

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 1
}

[ -n "$skill_dir" ] || fail "skill directory argument is required"

case "$skill_dir" in
  "$root"/develop/*) ;;
  *) fail "skill must be under $root/develop/" ;;
esac

skill_file="$skill_dir/SKILL.md"
[ -f "$skill_file" ] || fail "missing SKILL.md at $skill_file"

first_line="$(sed -n '1p' "$skill_file")"
[ "$first_line" = "---" ] || fail "SKILL.md must start with YAML frontmatter"

frontmatter_end="$(awk 'NR > 1 && $0 == "---" { print NR; exit }' "$skill_file")"
[ -n "$frontmatter_end" ] || fail "SKILL.md frontmatter is not closed"

extract_value() {
  local key="$1"
  awk -v key="$key" '
    NR == 1 { next }
    $0 == "---" { exit }
    index($0, key ":") == 1 {
      sub("^[^:]+:[[:space:]]*", "", $0)
      gsub(/^"|"$/, "", $0)
      gsub(/^'\''|'\''$/, "", $0)
      print
      exit
    }
  ' "$skill_file"
}

skill_name="$(extract_value "name")"
description="$(extract_value "description")"
version="$(extract_value "version")"

[ -n "$skill_name" ] || fail "frontmatter field 'name' is required"
[ -n "$description" ] || fail "frontmatter field 'description' is required"
[ -n "$version" ] || fail "frontmatter field 'version' is required"

case "$skill_name" in
  *[!a-zA-Z0-9._-]* | "") fail "name must contain only letters, numbers, dot, underscore, or hyphen" ;;
esac

case "$version" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) fail "version must be semantic version format, for example 1.0.0" ;;
esac

printf 'SKILL_NAME=%s\n' "$skill_name"
printf 'SKILL_VERSION=%s\n' "$version"
printf 'SKILL_FILE=%s\n' "$skill_file"
