#!/bin/bash
# This script is executed every time the dev container is started.

# -e: Exit immediately if a command exits with a non-zero status.
# -u: Treat unset variables as an error when substituting.
# -o pipefail: The return value of a pipeline is the status of the last command to exit with a non-zero status,
# or zero if no command exited with a non-zero status.
set -euo pipefail

echo "Starting post-start script..."

# Ensure git operations work from inside the container when the repo is volume-mounted
if ! git config --global --get-all safe.directory >/dev/null 2>&1; then
  echo "Adding ${PWD} to git safe.directory..."
  git config --global --add safe.directory "${PWD}"
elif ! git config --global --get-all safe.directory | grep -Fxq "${PWD}"; then
  echo "Adding ${PWD} to git safe.directory..."
  git config --global --add safe.directory "${PWD}"
fi

# Optionally disable docker-in-docker to save resources
if [ "${ENABLE_DIND:-true}" != "true" ]; then
  echo "Disabling Docker-in-Docker..."
  if command -v supervisorctl >/dev/null 2>&1; then
    sudo supervisorctl stop docker || true
    sudo supervisorctl stop dockerd || true
    sudo supervisorctl stop containerd || true
  fi
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl stop docker || true
    sudo systemctl stop dockerd || true
  fi
fi

echo "Post-start script finished."
