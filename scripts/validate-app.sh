#!/usr/bin/env bash
# Validate a single application
# Usage: ./validate-app.sh <namespace> <app-name>

set -euo pipefail

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

if [ $# -ne 2 ]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    echo ""
    echo "Usage: $0 <namespace> <app-name>"
    echo ""
    echo "Example:"
    echo "  $0 media bazarr"
    exit 1
fi

NAMESPACE="$1"
APP_NAME="$2"
APP_DIR="kubernetes/apps/${NAMESPACE}/${APP_NAME}"

# Validate app directory exists
if [ ! -d "$APP_DIR" ]; then
    echo -e "${RED}Error: Application directory does not exist: ${APP_DIR}${NC}"
    exit 1
fi

echo -e "${GREEN}Validating ${APP_NAME} in ${NAMESPACE} namespace...${NC}\n"

# Check for required files
echo -e "${YELLOW}▶ Checking required files...${NC}"
REQUIRED_FILES=(
    "${APP_DIR}/ks.yaml"
    "${APP_DIR}/app/helmrelease.yaml"
    "${APP_DIR}/app/kustomization.yaml"
)

for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}  ✓ ${file}${NC}"
    else
        echo -e "${RED}  ✗ Missing required file: ${file}${NC}"
        exit 1
    fi
done
echo ""

# Validate YAML syntax
echo -e "${YELLOW}▶ Validating YAML syntax...${NC}"
if command -v yamllint &> /dev/null; then
    if yamllint -s "$APP_DIR"; then
        echo -e "${GREEN}✓ YAML syntax is valid${NC}\n"
    else
        echo -e "${RED}✗ YAML syntax errors found${NC}\n"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠ yamllint not found, skipping YAML syntax check${NC}\n"
fi

# Build with kustomize
echo -e "${YELLOW}▶ Building with kustomize...${NC}"
if kustomize build "${APP_DIR}/app" > /tmp/kustomize-output.yaml; then
    echo -e "${GREEN}✓ Kustomize build successful${NC}\n"
else
    echo -e "${RED}✗ Kustomize build failed${NC}\n"
    exit 1
fi

# Validate with kubeconform
echo -e "${YELLOW}▶ Validating Kubernetes manifests...${NC}"
if kustomize build "${APP_DIR}/app" | kubeconform \
    -strict \
    -ignore-missing-schemas \
    -skip "Secret,ExternalSecret,ReplicationSource,ReplicationDestination,HTTPRoute" \
    -schema-location default \
    -schema-location "https://kubernetes-schemas.pages.dev/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
    -verbose -; then
    echo -e "${GREEN}✓ Kubernetes manifest validation passed${NC}\n"
else
    echo -e "${RED}✗ Kubernetes manifest validation failed${NC}\n"
    exit 1
fi

# Check for common issues
echo -e "${YELLOW}▶ Checking for common issues...${NC}"
ISSUES_FOUND=false

# Check for latest tag
if grep -q "tag: latest" "${APP_DIR}/app/helmrelease.yaml" 2>/dev/null; then
    echo -e "${YELLOW}⚠ Warning: Using 'latest' tag (should pin version)${NC}"
    ISSUES_FOUND=true
fi

# Check for resource limits
if ! grep -q "limits:" "${APP_DIR}/app/helmrelease.yaml" 2>/dev/null; then
    echo -e "${YELLOW}⚠ Warning: No resource limits defined${NC}"
    ISSUES_FOUND=true
fi

# Check for secrets
if grep -q "Secret" "${APP_DIR}/app/"*.yaml 2>/dev/null; then
    if ! grep -q "ExternalSecret" "${APP_DIR}/app/"*.yaml && ! grep -q "sops:" "${APP_DIR}/app/"*.yaml 2>/dev/null; then
        echo -e "${YELLOW}⚠ Warning: Using plain Secrets (consider ExternalSecret or SOPS)${NC}"
        ISSUES_FOUND=true
    fi
fi

if [ "$ISSUES_FOUND" = false ]; then
    echo -e "${GREEN}✓ No common issues found${NC}\n"
else
    echo ""
fi

# Summary
echo "=================================="
echo -e "${GREEN}✓ Validation complete for ${APP_NAME}${NC}"
echo ""
echo "Application structure:"
tree -L 2 "$APP_DIR" 2>/dev/null || find "$APP_DIR" -type f

# Test with Flux (if flux is available and cluster is accessible)
if command -v flux &> /dev/null && [ -n "${KUBECONFIG:-}" ] && [ -f "${KUBECONFIG}" ]; then
    echo ""
    echo -e "${YELLOW}▶ Testing with Flux (dry-run)...${NC}"
    if flux build ks "${APP_NAME}" \
        --kustomization-file "${APP_DIR}/ks.yaml" \
        --path "${APP_DIR}/app" \
        --dry-run > /tmp/flux-output.yaml 2>&1; then
        echo -e "${GREEN}✓ Flux dry-run successful${NC}"
        echo "  Output saved to /tmp/flux-output.yaml"
    else
        echo -e "${YELLOW}⚠ Flux dry-run not available or failed${NC}"
        echo "  (This is normal if cluster is not accessible)"
    fi
fi

echo ""
echo -e "${GREEN}All checks passed! Application is ready.${NC}"
