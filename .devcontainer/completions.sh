#!/bin/bash
set -euo pipefail

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

echo "Shell completions installed successfully"
