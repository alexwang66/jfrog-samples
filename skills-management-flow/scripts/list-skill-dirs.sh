#!/usr/bin/env bash
set -euo pipefail

root="${SKILLS_FLOW_ROOT:-skills-management-flow}"
develop_root="$root/develop"
manual_skill_path="${SKILL_PATH:-}"
before_sha="${BEFORE_SHA:-}"
head_sha="${HEAD_SHA:-}"

if [ -n "$manual_skill_path" ]; then
  printf '%s\n' "${manual_skill_path%/}"
  exit 0
fi

if [ -n "$before_sha" ] && [ -n "$head_sha" ] && [ "$before_sha" != "0000000000000000000000000000000000000000" ]; then
  git diff --name-only "$before_sha" "$head_sha" -- "$develop_root" \
    | awk '/\/SKILL.md$/ { sub(/\/SKILL.md$/, ""); print }' \
    | sort -u
  exit 0
fi

find "$develop_root" -mindepth 2 -maxdepth 2 -name SKILL.md -print \
  | sed 's#/SKILL.md$##' \
  | sort -u
