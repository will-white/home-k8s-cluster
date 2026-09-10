#!/bin/bash
# Validates that all required CLI tools are available and working.
# Run this after container creation to catch broken installs early.
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
FAILED=0

check_tool() {
    local name="$1"
    local cmd="${2:-$1 --version}"
    if eval "$cmd" >/dev/null 2>&1; then
        printf "${GREEN}✓${NC} %-15s %s\n" "$name" "$(eval "$cmd" 2>&1 | head -1)"
    else
        printf "${RED}✗${NC} %-15s NOT FOUND\n" "$name"
        FAILED=$((FAILED + 1))
    fi
}

echo "=== DevContainer Tool Validation ==="
echo ""

check_tool "kubectl"     "kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null"
check_tool "helm"        "helm version --short"
check_tool "flux"        "flux version --client"
check_tool "kustomize"   "kustomize version"
check_tool "kubeconform" "kubeconform -v"
check_tool "sops"        "sops --version"
check_tool "age"         "age --version"
check_tool "talosctl"    "talosctl version --client --nodes 127.0.0.1 2>&1 | grep -m1 'Tag:'"
check_tool "talhelper"   "talhelper --version"
check_tool "yq"          "yq --version"
check_tool "task"        "task --version"
check_tool "stern"       "stern --version"
check_tool "bws"         "bws --version"
check_tool "gh"          "gh --version"
check_tool "jq"          "jq --version"
check_tool "yamllint"    "yamllint --version"
check_tool "shellcheck"  "shellcheck --version | grep version:"
check_tool "gitleaks"    "gitleaks version"
check_tool "direnv"      "direnv version"
check_tool "fish"        "fish --version"
check_tool "claude"      "claude --version"

# Guard the fix for workspace-local .bin shadowing the image's pinned tools.
# Every tool below must resolve to the copy baked into the image, not to a stale
# binary left in ./.bin by `task workstation:generic-linux`.
echo ""
echo "=== PATH precedence ==="
SHADOWED=0
for tool in kubectl helm kustomize kubeconform sops age talosctl talhelper yq gh flux stern; do
    resolved="$(command -v "$tool" 2>/dev/null || true)"
    case "$resolved" in
        */.bin/*)
            printf "${RED}\u2717${NC} %-15s shadowed by %s\n" "$tool" "$resolved"
            SHADOWED=$((SHADOWED + 1))
            ;;
    esac
done
if [ "$SHADOWED" -gt 0 ]; then
    printf "${RED}%s tool(s) resolve to ./.bin instead of the image's pinned copies.${NC}\n" "$SHADOWED"
    FAILED=$((FAILED + SHADOWED))
else
    printf "${GREEN}\u2713${NC} no tools shadowed by ./.bin\n"
fi

echo ""
if [ "$FAILED" -gt 0 ]; then
    echo -e "${RED}${FAILED} tool(s) failed validation!${NC}"
    exit 1
else
    echo -e "${GREEN}All tools validated successfully.${NC}"
fi
