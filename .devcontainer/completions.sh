#!/bin/bash
set -euo pipefail

# NOTE: run this from post-create.sh, not from the Docker build. Devcontainer
# features (flux, go-task) install *after* the image is built, so a build-time
# run silently skips them - which is how flux ended up with no completions.
COMPLETIONS_DIR="${HOME}/.config/fish/completions"
mkdir -p "${COMPLETIONS_DIR}"

generate_completion() {
	local tool="$1"
	local file="$2"
	if command -v "${tool}" >/dev/null 2>&1; then
		"${tool}" completion fish > "${COMPLETIONS_DIR}/${file}" 2>/dev/null || true
	fi
}

generate_completion kubectl kubectl.fish
generate_completion flux flux.fish
generate_completion helm helm.fish
generate_completion talosctl talosctl.fish
generate_completion talhelper talhelper.fish
generate_completion stern stern.fish
generate_completion kustomize kustomize.fish
generate_completion task task.fish
generate_completion yq yq.fish
generate_completion helmfile helmfile.fish
generate_completion claude claude.fish
generate_completion gitleaks gitleaks.fish

# gh uses a different completion subcommand signature
if command -v gh >/dev/null 2>&1; then
	gh completion -s fish > "${COMPLETIONS_DIR}/gh.fish" 2>/dev/null || true
fi

echo "Shell completions installed successfully"
