#!/usr/bin/env bash
# Generate application scaffolding for agents
# Usage: ./generate-app-scaffold.sh <app-name> <namespace> [chart-name] [chart-version] [repo-name]

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check arguments
if [ $# -lt 2 ]; then
    echo -e "${RED}Error: Missing required arguments${NC}"
    echo ""
    echo "Usage: $0 <app-name> <namespace> [chart-name] [chart-version] [repo-name]"
    echo ""
    echo "Arguments:"
    echo "  app-name      Name of the application (required)"
    echo "  namespace     Target namespace (required)"
    echo "  chart-name    Helm chart name (optional, defaults to app-template)"
    echo "  chart-version Helm chart version (optional, defaults to 3.7.3)"
    echo "  repo-name     Helm repo name (optional, defaults to bjw-s)"
    echo ""
    echo "Example:"
    echo "  $0 my-app media"
    echo "  $0 bazarr media app-template 3.7.3 bjw-s"
    exit 1
fi

APP_NAME="$1"
NAMESPACE="$2"
CHART_NAME="${3:-app-template}"
CHART_VERSION="${4:-3.7.3}"
REPO_NAME="${5:-bjw-s}"

TEMPLATE_DIR="kubernetes/templates/app-scaffold"
TARGET_DIR="kubernetes/apps/${NAMESPACE}/${APP_NAME}"

# Validate inputs
if [[ ! "$APP_NAME" =~ ^[a-z0-9-]+$ ]]; then
    echo -e "${RED}Error: App name must be lowercase with hyphens only${NC}"
    exit 1
fi

if [ ! -d "kubernetes/apps/${NAMESPACE}" ]; then
    echo -e "${RED}Error: Namespace directory does not exist: kubernetes/apps/${NAMESPACE}${NC}"
    echo "Available namespaces:"
    find kubernetes/apps -maxdepth 1 -type d -name "[!.]*" | sed 's|kubernetes/apps/||' | sort
    exit 1
fi

if [ -d "$TARGET_DIR" ]; then
    echo -e "${RED}Error: Application directory already exists: ${TARGET_DIR}${NC}"
    exit 1
fi

# Copy template
echo -e "${GREEN}Creating application scaffold...${NC}"
cp -r "$TEMPLATE_DIR" "$TARGET_DIR"

# Replace placeholders
echo -e "${YELLOW}Replacing placeholders...${NC}"
find "$TARGET_DIR" -type f -name "*.yaml" -exec sed -i \
    -e "s/<APP-NAME>/${APP_NAME}/g" \
    -e "s/<NAMESPACE>/${NAMESPACE}/g" \
    -e "s/<CHART-NAME>/${CHART_NAME}/g" \
    -e "s/<CHART-VERSION>/${CHART_VERSION}/g" \
    -e "s/<REPO-NAME>/${REPO_NAME}/g" \
    {} \;

# Remove README from app directory
rm -f "${TARGET_DIR}/README.md"

echo -e "${GREEN}✓ Application scaffold created at: ${TARGET_DIR}${NC}"
echo ""
echo "Next steps:"
echo "1. Edit ${TARGET_DIR}/app/helmrelease.yaml to configure your app"
echo "2. Remove unused files from ${TARGET_DIR}/app/"
echo "3. Update ${TARGET_DIR}/app/kustomization.yaml to reference only needed files"
echo "4. Add '- ./${APP_NAME}/ks.yaml' to kubernetes/apps/${NAMESPACE}/kustomization.yaml"
echo "5. Validate: task kubernetes:kubeconform"
echo ""
echo "Template files created:"
ls -1 "$TARGET_DIR"
echo "  app/"
ls -1 "${TARGET_DIR}/app/" | sed 's/^/    /'
