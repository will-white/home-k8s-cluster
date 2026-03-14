#!/usr/bin/env bash
# Pre-commit validation script for agents
# Runs all necessary checks before committing code changes

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Running pre-commit validation checks...${NC}\n"

# Track overall success
VALIDATION_PASSED=true

# Function to run a check
run_check() {
    local check_name="$1"
    local check_command="$2"
    
    echo -e "${YELLOW}▶ ${check_name}${NC}"
    if eval "$check_command"; then
        echo -e "${GREEN}✓ ${check_name} passed${NC}\n"
    else
        echo -e "${RED}✗ ${check_name} failed${NC}\n"
        VALIDATION_PASSED=false
    fi
}

# 1. Check for required tools
echo -e "${YELLOW}▶ Checking required tools...${NC}"
# Note: 'task' is project-specific but required for validation workflows
REQUIRED_TOOLS=("kustomize" "kubeconform")
OPTIONAL_TOOLS=("task" "yamllint")

for tool in "${REQUIRED_TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo -e "${RED}✗ Required tool not found: ${tool}${NC}"
        echo "  Install it before continuing."
        VALIDATION_PASSED=false
    else
        echo -e "${GREEN}  ✓ ${tool} found${NC}"
    fi
done

for tool in "${OPTIONAL_TOOLS[@]}"; do
    if ! command -v "$tool" &> /dev/null; then
        echo -e "${YELLOW}  ⚠ Optional tool not found: ${tool}${NC}"
    else
        echo -e "${GREEN}  ✓ ${tool} found${NC}"
    fi
done
echo ""

# 2. Check for unencrypted secrets
echo -e "${YELLOW}▶ Checking for unencrypted secrets...${NC}"
UNENCRYPTED_SECRETS=$(find kubernetes/apps -type f \( -name "secret.yaml" -o -name "*-secret.yaml" \) | while read -r file; do
    # Skip ExternalSecret and PushSecret files - they're not plain secrets
    if grep -q "kind: ExternalSecret\|kind: PushSecret" "$file" 2>/dev/null; then
        continue
    fi
    # Check if file has SOPS encryption
    if ! grep -q "sops:" "$file" 2>/dev/null; then
        echo "$file"
    fi
done)

if [ -n "$UNENCRYPTED_SECRETS" ]; then
    echo -e "${RED}✗ Found potentially unencrypted secrets:${NC}"
    echo "$UNENCRYPTED_SECRETS"
    echo -e "${YELLOW}  Ensure all secrets are encrypted with SOPS or use ExternalSecrets${NC}\n"
    VALIDATION_PASSED=false
else
    echo -e "${GREEN}✓ No unencrypted secrets found${NC}\n"
fi

# 3. YAML Linting
if command -v yamllint &> /dev/null; then
    run_check "YAML linting" "yamllint -s kubernetes/"
fi

# 4. Kubeconform validation
run_check "Kubernetes manifest validation" "task kubernetes:kubeconform"

# 5. Check for common issues
echo -e "${YELLOW}▶ Checking for common issues...${NC}"

# Check for latest tag usage (discouraged)
LATEST_TAGS=$(grep -r "tag: latest" kubernetes/apps --include="*.yaml" || true)
if [ -n "$LATEST_TAGS" ]; then
    echo -e "${YELLOW}⚠ Warning: Found usage of 'latest' tag (should pin versions):${NC}"
    echo "$LATEST_TAGS"
    echo ""
fi

# Check for missing namespace in kustomization
MISSING_NAMESPACE=$(find kubernetes/apps -name "kustomization.yaml" -type f -exec sh -c 'grep -L "^namespace:" "$1"' _ {} \; || true)
if [ -n "$MISSING_NAMESPACE" ]; then
    echo -e "${YELLOW}⚠ Warning: Kustomizations without namespace field:${NC}"
    echo "$MISSING_NAMESPACE"
    echo ""
fi

# Check for resources without limits
NO_LIMITS=$(grep -r "resources:" kubernetes/apps --include="*.yaml" -A 10 | grep -v "limits:" || true)
if [ -n "$NO_LIMITS" ]; then
    echo -e "${YELLOW}⚠ Warning: Some resources may be missing limits${NC}"
    echo "  Review resource configurations for proper limits"
    echo ""
fi

echo -e "${GREEN}✓ Common issue checks complete${NC}\n"

# 6. Check Git status
echo -e "${YELLOW}▶ Git status${NC}"
git status --short
echo ""

# Final result
echo "=================================="
if [ "$VALIDATION_PASSED" = true ]; then
    echo -e "${GREEN}✓ All validation checks passed!${NC}"
    echo -e "${GREEN}  Safe to commit changes.${NC}"
    exit 0
else
    echo -e "${RED}✗ Some validation checks failed${NC}"
    echo -e "${RED}  Fix the issues before committing.${NC}"
    exit 1
fi
