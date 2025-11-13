#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USERNAME="${USER:-vscode}"
USER_HOME="$(eval echo "~${USERNAME}")"
FISH_CONFIG_DIR="${USER_HOME}/.config/fish"
FISH_CONFIG_FILE="${FISH_CONFIG_DIR}/config.fish"

mkdir -p "${FISH_CONFIG_DIR}"
touch "${FISH_CONFIG_FILE}"

DIR_ENV_HOOK='eval "$(direnv hook fish)"'
if ! grep -Fxq "${DIR_ENV_HOOK}" "${FISH_CONFIG_FILE}"; then
	printf '%s\n' "${DIR_ENV_HOOK}" >> "${FISH_CONFIG_FILE}"
fi

FISHER_CMD="if not functions -q fisher; curl -sL https://git.io/fisher | source; and fisher install jorgebucaran/fisher; end; set -l plugins decors/fish-colored-man edc/bass jorgebucaran/autopair.fish nickeb96/puffer-fish PatrickF1/fzf.fish IlanCosman/tide@v6; fisher install \$plugins; fisher update"
fish -c "${FISHER_CMD}"

fish -c 'tide configure --auto --style=Lean --prompt_colors="True color" --show_time="24-hour format" --lean_prompt_height="Two lines" --prompt_connection=Disconnected --prompt_spacing=Compact --icons="Many icons" --transient=No'

fish "${SCRIPT_DIR}/fish-config.fish"

bash "${SCRIPT_DIR}/completions.sh"
