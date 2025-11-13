#!/bin/bash
# This script is executed when the dev container is created.

# -e: Exit immediately if a command exits with a non-zero status.
# -u: Treat unset variables as an error when substituting.
# -o pipefail: The return value of a pipeline is the status of the last command to exit with a non-zero status,
# or zero if no command exited with a non-zero status.
set -euo pipefail

# Get the workspace directory
WORKSPACE_DIR="${PWD}"

# Create a .bin directory for local binaries
echo "Creating .bin directory..."
mkdir -p "${WORKSPACE_DIR}/.bin"

# Allow direnv to load the .envrc file if it exists
if command -v direnv >/dev/null 2>&1 && [ -f "${WORKSPACE_DIR}/.envrc" ]; then
  echo "Allowing direnv to load .envrc..."
  direnv allow "${WORKSPACE_DIR}" || true
fi

echo "Post-create script finished."
