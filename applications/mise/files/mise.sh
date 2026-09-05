#!/bin/sh

. /lib/functions.sh

istore_runtime_quickstart_conf_dir() {
	local main_dir conf_dir

	config_load quickstart >/dev/null 2>&1 || return 1
	config_get conf_dir main conf_dir ""
	if [ -z "$conf_dir" ]; then
		config_get main_dir main main_dir ""
		[ -n "$main_dir" ] || return 1
		conf_dir="$main_dir/Configs"
	fi

	printf '%s\n' "$conf_dir"
}

istore_runtime_dir() {
	local conf_dir="$1"

	[ -n "$conf_dir" ] || conf_dir="$(istore_runtime_quickstart_conf_dir)" || return 1
	conf_dir="${conf_dir%/}"
	[ -n "$conf_dir" ] || return 1

	printf '%s/Runtime/home\n' "$conf_dir"
}

istore_runtime_init() {
	local runtime_dir

	runtime_dir="$(istore_runtime_dir "$1")" || return 1
	mkdir -p \
		"$runtime_dir/.local/share/mise" \
		"$runtime_dir/.cache/mise" \
		"$runtime_dir/.config/mise" \
		"$runtime_dir/.local/state/mise" \
		"$runtime_dir/.local/bin" || return 1

	printf '%s\n' "$runtime_dir"
}

istore_runtime_env() {
	local runtime_dir

	runtime_dir="$(istore_runtime_init "$1")" || return 1

	export HOME="$runtime_dir"
	export XDG_DATA_HOME="$HOME/.local/share"
	export XDG_CACHE_HOME="$HOME/.cache"
	export XDG_CONFIG_HOME="$HOME/.config"
	export XDG_STATE_HOME="$HOME/.local/state"
	export MISE_DATA_DIR="$XDG_DATA_HOME/mise"
	export MISE_CACHE_DIR="$XDG_CACHE_HOME/mise"
	export MISE_CONFIG_DIR="$XDG_CONFIG_HOME/mise"
	export MISE_STATE_DIR="$XDG_STATE_HOME/mise"
	export PATH="$MISE_DATA_DIR/shims:$HOME/.local/bin:$PATH"
}
