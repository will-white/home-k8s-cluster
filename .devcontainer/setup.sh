#!/bin/bash
set -e

# This script is run as root by the dev container postCreateCommand.

# Install direnv
# The install script will place the binary in /usr/local/bin
curl -sfL https://direnv.net/install.sh | bash

# The dev container user is 'vscode'
USERNAME=vscode

# Create fish config directory for the user
mkdir -p /home/${USERNAME}/.config/fish

# Add direnv hook to fish config
echo 'eval "$(direnv hook fish)"' >> /home/${USERNAME}/.config/fish/config.fish

# Allow the .envrc file in the workspace.
# This needs to run as the container user, from the workspace directory.
# The devcontainer `postCreateCommand` runs from the workspace root, so `.` is correct.
su - ${USERNAME} -c "cd $(pwd) && direnv allow ."

# Change ownership of the user's config files to the user.
# This is important because the script runs as root.
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config
