#!/bin/sh

set -eu

agent="${1:-}"
node_version="22"

case "$agent" in
	codex)
		name="Codex"
		package="@openai/codex@latest"
		binary="codex"
		;;
	claude-code)
		name="Claude Code"
		package="@anthropic-ai/claude-code@latest"
		binary="claude"
		;;
	*)
		echo "Unsupported agent: $agent" >&2
		exit 2
		;;
esac

log() {
	printf '%s [agentflow] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

if [ ! -r /lib/functions/mise.sh ]; then
	log "Missing mise environment helper"
	exit 1
fi
. /lib/functions/mise.sh

if ! istore_runtime_env; then
	log "Failed to initialize the shared runtime environment"
	exit 1
fi
if [ ! -x /usr/bin/mise ]; then
	log "Missing mise executable"
	exit 1
fi

export MISE_YES=1

log "Installing $name into $HOME"
log "Preparing Node.js $node_version with mise"
/usr/bin/mise use --global "node@$node_version"

node_bin="$(/usr/bin/mise which node)"
npm_bin="${node_bin%/node}/npm"
if [ ! -x "$npm_bin" ]; then
	log "npm was not found next to $node_bin"
	exit 1
fi

log "Running npm install --global $package"
"$npm_bin" install --global "$package" --no-audit --no-fund
/usr/bin/mise reshim

agent_bin="${node_bin%/node}/$binary"
if [ ! -x "$agent_bin" ]; then
	log "$name executable was not created: $agent_bin"
	exit 1
fi

log "$name installed successfully"
"$agent_bin" --version
