#!/usr/bin/env bash
# Verify every Kubernetes Secret manifest in the repo is SOPS-encrypted.
#
# Rules:
#   1. Any tracked YAML under kubernetes/ that contains a `kind: Secret`
#      document MUST also contain a top-level `sops:` metadata block.
#   2. Files explicitly marked as templates / examples are skipped via
#      the SKIP_PATTERNS list below.
#
# Exits non-zero on the first offender so CI fails the PR.

set -o errexit
set -o pipefail
set -o nounset

ROOT_DIR="${1:-kubernetes}"

# Files to ignore (regex, matched against the relative path).
SKIP_PATTERNS=(
    # Bjw-s app-template values often render Secret CRDs at runtime; the
    # source YAML in templates/ is not itself a Secret manifest.
    "^kubernetes/templates/"
)

skip() {
    local path="$1"
    for pattern in "${SKIP_PATTERNS[@]}"; do
        if [[ "$path" =~ $pattern ]]; then
            return 0
        fi
    done
    return 1
}

errors=0
checked=0

# Use git ls-files so untracked / ignored files are not scanned.
while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if skip "$file"; then
        continue
    fi

    # Quick filter: only consider files that declare a Secret kind.
    if ! grep -qE '^kind:[[:space:]]+Secret[[:space:]]*$' "$file"; then
        continue
    fi

    checked=$((checked + 1))

    # ExternalSecret / SealedSecret / etc. are NOT plain Secrets.
    # We already filtered to `kind: Secret` above; ensure the file has SOPS metadata.
    if ! grep -qE '^sops:' "$file"; then
        echo "::error file=${file}::Secret manifest is not SOPS-encrypted (no top-level 'sops:' block found)"
        errors=$((errors + 1))
    fi
done < <(git ls-files -- "${ROOT_DIR}/**/*.yaml" "${ROOT_DIR}/**/*.yml")

echo "Scanned ${checked} Secret manifest(s); ${errors} unencrypted."

if (( errors > 0 )); then
    exit 1
fi
