#!/usr/bin/env fish

# Apply Tide prompt defaults without overriding user-defined values
if not set -q tide_kubectl_enabled
	set -g tide_kubectl_enabled true
end

if not set -q tide_kubectl_icon
	set -g tide_kubectl_icon "☸"
end

if not set -q tide_git_enabled
	set -g tide_git_enabled true
end

if not set -q tide_git_icon
	set -g tide_git_icon ""
end

if not set -q tide_character_icon
	set -g tide_character_icon "❯"
end

if not set -q tide_character_vi_mode_icon
	set -g tide_character_vi_mode_icon "❮"
end

if not set -q tide_context_enabled
	set -g tide_context_enabled true
end

if not set -q tide_pwd_enabled
	set -g tide_pwd_enabled true
end

if not set -q tide_pwd_icon
	set -g tide_pwd_icon ""
end

if not set -q tide_pwd_markers
	set -g tide_pwd_markers .git package.json Taskfile.yaml
end

echo "Tide prompt defaults applied."
