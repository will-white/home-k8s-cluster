#!/usr/bin/env bash
# PostToolUse hook (Edit|Write): lint the YAML file that was just changed with
# the repo's yamllint config, so a long line or a bad indent is caught at
# edit time instead of by the YAML Lint workflow after the push. Exit 2
# returns the findings to Claude as feedback; anything else is silent.
set -euo pipefail

file="$(python3 -c 'import json,sys; print((json.load(sys.stdin).get("tool_input") or {}).get("file_path",""))' 2>/dev/null || true)"
[ -n "${file}" ] || exit 0
case "${file}" in
  *.yaml|*.yml) ;;
  *) exit 0 ;;
esac
[ -f "${file}" ] || exit 0
command -v yamllint >/dev/null 2>&1 || exit 0

cd "${CLAUDE_PROJECT_DIR:-.}"
if ! out="$(yamllint -c .yamllint.yaml -f parsable "${file}" 2>&1)"; then
  printf 'yamllint findings in %s:\n%s\n' "${file}" "${out}" >&2
  exit 2
fi
