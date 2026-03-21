#!/bin/sh
# ============================================================================
# OpenClawMgr CLI Config Helper (LAN ttyd)
# - Provides an interactive menu to run OpenClaw official configure wizard,
#   manage config file, and restart gateway.
# ============================================================================

set -e

# Ensure a sensible TERM for ttyd/xterm.js.
export TERM="${TERM:-xterm-256color}"

ESC="$(printf '\033')"
RED="${ESC}[0;31m"; GREEN="${ESC}[0;32m"; YELLOW="${ESC}[1;33m"
CYAN="${ESC}[0;36m"; BOLD="${ESC}[1m"; DIM="${ESC}[2m"; NC="${ESC}[0m"

prompt_with_default() {
	local prompt="$1" def="$2" var="$3" v=""
	if [ -n "$def" ]; then
		printf "%s%s[%s]%s: " "$prompt" "$DIM" "$def" "$NC"
	else
		printf "%s: " "$prompt"
	fi
	# shellcheck disable=SC2162
	read v
	[ -z "$v" ] && v="$def"
	eval "$var=\$v"
}

pause_enter() {
	printf "\n%s按回车继续...%s" "$DIM" "$NC"
	# shellcheck disable=SC2162
	read _
}

uci_get() { uci -q get "openclawmgr.main.$1" 2>/dev/null || true; }

BASE_DIR="${BASE_DIR:-$(uci_get base_dir)}"
if [ -z "$BASE_DIR" ]; then
	printf '%s\n' "${RED}ERROR: base_dir 未配置。请先在 OpenClaw 启动器页面设置数据目录并保存应用。${NC}"
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

find_entry() {
	local d="${GLOBAL_DIR}/lib/node_modules/openclaw"
	[ -f "${d}/openclaw.mjs" ] && { echo "${d}/openclaw.mjs"; return 0; }
	[ -f "${d}/dist/cli.js" ] && { echo "${d}/dist/cli.js"; return 0; }
	return 1
}

OPENCLAW_ENTRY="$(find_entry 2>/dev/null || true)"

oc_cmd() {
	if [ -x "$OPENCLAW_BIN" ]; then
		"$OPENCLAW_BIN" "$@"
		return $?
	fi
	if [ -x "$NODE_BIN" ] && [ -n "$OPENCLAW_ENTRY" ]; then
		"$NODE_BIN" "$OPENCLAW_ENTRY" "$@"
		return $?
	fi
	printf '%s\n' "${RED}ERROR: OpenClaw 未安装或运行时不完整。${NC}"
	printf '%s\n' "HINT: 在 OpenClaw 启动器页面执行安装/升级。"
	return 127
}

restart_gateway() {
	printf '\n'
	printf '%s\n' "${CYAN}=== 重启 Gateway ===${NC}"
	/usr/libexec/istorec/openclawmgr.sh restart 2>&1 || true
}

apply_config() {
	printf '\n'
	printf '%s\n' "${CYAN}=== 重新生成/应用配置（以 OpenClawMgr 配置为准）===${NC}"
	/usr/libexec/istorec/openclawmgr.sh apply_config 2>&1 || true
}

show_config() {
	printf '\n'
	printf '%s\n' "${CYAN}=== 配置文件 ===${NC}"
	printf '%s\n' "路径: ${DIM}${CONFIG_FILE}${NC}"
	printf '\n'
	if [ ! -f "$CONFIG_FILE" ]; then
		printf '%s\n' "${YELLOW}(配置文件不存在)${NC}"
		return 0
	fi
	if [ -x "$NODE_BIN" ]; then
		"$NODE_BIN" -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync(process.env.OPENCLAW_CONFIG_PATH,'utf8')),null,2))" 2>/dev/null \
			|| cat "$CONFIG_FILE"
	else
		cat "$CONFIG_FILE"
	fi
}

edit_config() {
	if [ ! -f "$CONFIG_FILE" ]; then
		printf '%s\n' "${YELLOW}配置文件不存在：${CONFIG_FILE}${NC}"
		return 1
	fi
	if command -v vi >/dev/null 2>&1; then
		vi "$CONFIG_FILE"
	elif command -v nano >/dev/null 2>&1; then
		nano "$CONFIG_FILE"
	else
		printf '%s\n' "${YELLOW}未找到编辑器（vi/nano）。${NC}"
		return 1
	fi
}

tail_logs() {
	printf '\n'
	printf '%s\n' "${CYAN}=== 最近日志（logread -e openclaw）===${NC}"
	printf '\n'
	logread -e openclaw 2>/dev/null | tail -200 || printf '%s\n' "${YELLOW}(无法读取日志)${NC}"
}

backup_config() {
	mkdir -p "$BACKUP_DIR" 2>/dev/null || true
	if [ ! -f "$CONFIG_FILE" ]; then
		printf '%s\n' "${YELLOW}配置文件不存在，无法备份。${NC}"
		return 1
	fi
	local ts dst
	ts="$(date -u +%Y-%m-%dT%H-%M-%SZ 2>/dev/null || date +%s)"
	dst="${BACKUP_DIR}/${ts}-openclaw.json"
	cp -f "$CONFIG_FILE" "$dst"
	printf '%s\n' "${GREEN}✅ 已备份到: ${dst}${NC}"
}

restore_config() {
	mkdir -p "$BACKUP_DIR" 2>/dev/null || true
	printf '\n'
	printf '%s\n' "${CYAN}=== 可用备份 ===${NC}"
	ls -lt "$BACKUP_DIR"/*.json 2>/dev/null | head -10 | awk '{print "  " $NF}' || printf '%s\n' "${YELLOW}(无备份)${NC}"
	printf '\n'
	local fp=""
	prompt_with_default "请输入要恢复的备份文件路径" "" fp
	[ -n "$fp" ] || return 0
	if [ ! -f "$fp" ]; then
		printf '%s\n' "${YELLOW}文件不存在：${fp}${NC}"
		return 1
	fi
	cp -f "$fp" "$CONFIG_FILE"
	printf '%s\n' "${GREEN}✅ 已恢复配置到: ${CONFIG_FILE}${NC}"
}

main_menu() {
	while true; do
		printf '\n'
		printf '%s\n' "${BOLD}OpenClaw AI Gateway — CLI 配置入口（OpenClawMgr）${NC}"
		printf '%s\n' "${DIM}base_dir: ${BASE_DIR}${NC}"
		printf '\n'
		printf '%s\n' "  ${CYAN}1)${NC} 🧭 官方配置向导  ${DIM}(openclaw configure)${NC}"
		printf '%s\n' "  ${CYAN}2)${NC} ℹ️  OpenClaw 版本/帮助  ${DIM}(openclaw --version / --help)${NC}"
		printf '%s\n' "  ${CYAN}3)${NC} 📄 查看配置文件  ${DIM}(openclaw.json)${NC}"
		printf '%s\n' "  ${CYAN}4)${NC} ✍️  编辑配置文件  ${DIM}(vi/nano)${NC}"
		printf '%s\n' "  ${CYAN}5)${NC} ♻️  应用/重建配置  ${DIM}(openclawmgr.sh apply_config)${NC}"
		printf '%s\n' "  ${CYAN}6)${NC} 🔄 重启 Gateway  ${DIM}(openclawmgr.sh restart)${NC}"
		printf '%s\n' "  ${CYAN}7)${NC} 📋 查看日志  ${DIM}(logread -e openclaw)${NC}"
		printf '%s\n' "  ${CYAN}8)${NC} 💾 备份配置"
		printf '%s\n' "  ${CYAN}9)${NC} 📥 恢复配置"
		printf '\n'
		printf '%s\n' "  ${CYAN}0)${NC} 退出"
		printf '\n'
		local c=""
		prompt_with_default "请选择" "1" c
		case "$c" in
			1)
				printf '\n'
				printf '%s\n' "${CYAN}=== openclaw configure ===${NC}"
				oc_cmd configure || true
				pause_enter
				;;
			2)
				printf '\n'
				oc_cmd --version 2>/dev/null || true
				printf '\n'
				oc_cmd --help 2>/dev/null | sed -n '1,120p' || true
				pause_enter
				;;
			3) show_config; pause_enter ;;
			4) edit_config || true; pause_enter ;;
			5) apply_config; pause_enter ;;
			6) restart_gateway; pause_enter ;;
			7) tail_logs; pause_enter ;;
			8) backup_config || true; pause_enter ;;
			9) restore_config || true; pause_enter ;;
			0) printf '%s\n' "${GREEN}再见！${NC}"; exit 0 ;;
			*) printf '%s\n' "${YELLOW}无效选择${NC}" ;;
		esac
	done
}

case "${1:-}" in
	--help|-h)
		echo "Usage: oc-config.sh [--help]"
		;;
	*)
		main_menu
		;;
esac
