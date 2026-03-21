#!/bin/sh
# OpenClawMgr CLI Config Helper (for ttyd)

set -eu

export TERM="${TERM:-xterm-256color}"

ESC="$(printf '\033')"
RED="${ESC}[0;31m"; GREEN="${ESC}[0;32m"; YELLOW="${ESC}[1;33m"
CYAN="${ESC}[0;36m"; BOLD="${ESC}[1m"; DIM="${ESC}[2m"; NC="${ESC}[0m"

err() { printf '%s\n' "${RED}ERROR: $*${NC}"; }
warn() { printf '%s\n' "${YELLOW}$*${NC}"; }
info() { printf '%s\n' "${CYAN}$*${NC}"; }
ok() { printf '%s\n' "${GREEN}$*${NC}"; }

pause_enter() {
	printf "\n%s按回车继续...%s" "$DIM" "$NC"
	IFS= read -r _ || true
}

prompt_default() {
	local prompt="$1" def="${2:-}" v=""
	if [ -n "$def" ]; then
		printf "%s%s[%s]%s: " "$prompt" "$DIM" "$def" "$NC" >&2
	else
		printf "%s: " "$prompt" >&2
	fi
	IFS= read -r v || v=""
	[ -z "$v" ] && v="$def"
	printf "%s" "$v"
}

uci_get() { uci -q get "openclawmgr.main.$1" 2>/dev/null || true; }

init_paths() {
	BASE_DIR="${BASE_DIR:-$(uci_get base_dir)}"
	if [ -z "$BASE_DIR" ]; then
		err "base_dir 未配置。请先在 OpenClaw 启动器页面设置数据目录并保存应用。"
		exit 1
	fi

	NODE_DIR="${BASE_DIR}/node"
	GLOBAL_DIR="${BASE_DIR}/global"
	DATA_DIR="${BASE_DIR}/data"

	NODE_BIN="${NODE_DIR}/bin/node"
	OPENCLAW_BIN="${GLOBAL_DIR}/bin/openclaw"
	CONFIG_FILE="${DATA_DIR}/.openclaw/openclaw.json"
	BACKUP_DIR="${DATA_DIR}/.openclaw/backups"

	export HOME="$DATA_DIR"
	export OPENCLAW_HOME="$DATA_DIR"
	export OPENCLAW_STATE_DIR="${DATA_DIR}/.openclaw"
	export OPENCLAW_CONFIG_PATH="$CONFIG_FILE"
	export PATH="${NODE_DIR}/bin:${GLOBAL_DIR}/bin:/usr/sbin:/usr/bin:/sbin:/bin"
}

find_openclaw_entry() {
	local d="${GLOBAL_DIR}/lib/node_modules/openclaw"
	[ -f "${d}/openclaw.mjs" ] && { echo "${d}/openclaw.mjs"; return 0; }
	[ -f "${d}/dist/cli.js" ] && { echo "${d}/dist/cli.js"; return 0; }
	return 1
}

openclaw_cmd() {
	if [ -x "$OPENCLAW_BIN" ]; then
		"$OPENCLAW_BIN" "$@"
		return $?
	fi

	local entry=""
	entry="$(find_openclaw_entry 2>/dev/null || true)"
	if [ -x "$NODE_BIN" ] && [ -n "$entry" ]; then
		"$NODE_BIN" "$entry" "$@"
		return $?
	fi

	err "OpenClaw 未安装或运行时不完整。"
	printf '%s\n' "HINT: 在 OpenClaw 启动器页面执行安装/升级。"
	return 127
}

action_backup_config() {
	mkdir -p "$BACKUP_DIR" 2>/dev/null || true
	if [ ! -f "$CONFIG_FILE" ]; then
		warn "配置文件不存在，无法备份。"
		return 1
	fi
	local ts dst
	ts="$(date -u +%Y-%m-%dT%H-%M-%SZ 2>/dev/null || date +%s)"
	dst="${BACKUP_DIR}/${ts}-openclaw.json"
	cp -f "$CONFIG_FILE" "$dst"
	ok "已备份到: ${dst}"
}

action_restore_config() {
	mkdir -p "$BACKUP_DIR" 2>/dev/null || true
	printf '\n'
	info "=== 可用备份 ==="
	ls -lt "$BACKUP_DIR"/*.json 2>/dev/null | head -10 | awk '{print "  " $NF}' || warn "(无备份)"
	printf '\n'
	local fp=""
	fp="$(prompt_default "请输入要恢复的备份文件路径" "")"
	[ -n "$fp" ] || return 0
	if [ ! -f "$fp" ]; then
		warn "文件不存在：${fp}"
		return 1
	fi
	cp -f "$fp" "$CONFIG_FILE"
	ok "已恢复配置到: ${CONFIG_FILE}"
}

action_configure() {
	printf '\n'
	info "=== openclaw configure ==="
	openclaw_cmd configure || true
}

main_menu() {
	while true; do
		printf '\n'
		printf '%s\n' "${BOLD}OpenClaw AI Gateway — CLI 配置入口（OpenClawMgr）${NC}"
		printf '%s\n' "${DIM}base_dir: ${BASE_DIR}${NC}"
		printf '\n'
		printf '%s\n' "  ${CYAN}1)${NC} 🧭 官方配置向导  ${DIM}(openclaw configure)${NC}"
		printf '%s\n' "  ${CYAN}2)${NC} 💾 备份配置"
		printf '%s\n' "  ${CYAN}3)${NC} 📥 恢复配置"
		printf '\n'
		printf '%s\n' "  ${CYAN}0)${NC} 退出"
		printf '\n'

		local c=""
		c="$(prompt_default "请选择" "1")"
		case "$c" in
			1) action_configure; pause_enter ;;
			2) action_backup_config || true; pause_enter ;;
			3) action_restore_config || true; pause_enter ;;
			0) ok "再见！"; exit 0 ;;
			*) warn "无效选择" ;;
		esac
	done
}

init_paths

case "${1:-}" in
	--help|-h)
		echo "Usage: openclawmgr-cli.sh [configure|backup|restore]"
		;;
	*)
		case "${1:-menu}" in
			menu) main_menu ;;
			configure) action_configure; pause_enter ;;
			backup) action_backup_config || true; pause_enter ;;
			restore) action_restore_config || true; pause_enter ;;
			*) echo "Unknown command: ${1:-}" >&2; exit 2 ;;
		esac
		;;
esac
