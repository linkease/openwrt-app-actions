#!/bin/sh

set -eu

agent="${1:-}"
installer_url="https://fw.koolcenter.com/binary/geili/agentflow/releases/installapp/installapp-mise.sh"
remote_installer="/tmp/agentflow-installapp-mise.$$"

case "$agent" in
	codexcli|claude-code|opencode|kimi|reasonix) ;;
	*)
		echo "Unsupported agent: $agent" >&2
		exit 2
		;;
esac

log() {
	printf '%s [agentflow] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

cleanup() {
	rm -f "$remote_installer"
}

download_installer() {
	if command -v wget >/dev/null 2>&1; then
		wget -O "$remote_installer" "$installer_url"
	elif command -v curl >/dev/null 2>&1; then
		curl -fL -o "$remote_installer" "$installer_url"
	elif command -v uclient-fetch >/dev/null 2>&1; then
		uclient-fetch -O "$remote_installer" "$installer_url"
	else
		log "No HTTPS download tool is available"
		return 1
	fi
}

trap cleanup 0 HUP INT TERM

if [ ! -r /lib/functions/mise.sh ]; then
	log "Missing mise environment helper"
	exit 1
fi
. /lib/functions/mise.sh

if ! istore_runtime_env; then
	log "Failed to initialize the shared runtime environment"
	exit 1
fi

export MISE_YES=1

log "Downloading installer: $installer_url"
if ! download_installer || [ ! -s "$remote_installer" ]; then
	log "Failed to download the agent installer"
	exit 1
fi
chmod 0700 "$remote_installer"

log "Running installapp-mise.sh for $agent in $HOME"
/bin/sh "$remote_installer" "$agent"
