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

istore_runtime_set_runtime_dir() {
	local conf_dir runtime_dir

	config_load mise >/dev/null 2>&1 || return 1
	config_get runtime_dir main runtime_dir ""
	[ -z "$runtime_dir" ] || return 0

	conf_dir="$(istore_runtime_quickstart_conf_dir)" || return 1
	runtime_dir="$conf_dir/Runtime/home"

	uci -q set "mise.main.runtime_dir=$runtime_dir" >/dev/null 2>&1 || return 1
	uci -q commit mise >/dev/null 2>&1
}

istore_runtime_init() {
	local runtime_dir

	config_load mise >/dev/null 2>&1 || return 1
	config_get runtime_dir main runtime_dir ""
	[ -n "$runtime_dir" ] || istore_runtime_set_runtime_dir
}

istore_runtime_env() {
	local runtime_dir

	config_load mise >/dev/null 2>&1 || return 1
	config_get runtime_dir main runtime_dir ""
	[ -n "$runtime_dir" ] || runtime_dir="${HOME:-}"
	[ -n "$runtime_dir" ] || return 1
	mkdir -p "$runtime_dir" || return 1

	export HOME="$runtime_dir"
	export PATH="$HOME/.local/share/mise/shims${PATH:+:$PATH}"
}
