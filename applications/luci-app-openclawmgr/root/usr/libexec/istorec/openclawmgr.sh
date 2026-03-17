#!/bin/sh

set -eu

APP="openclawmgr"
UCI_NS="openclawmgr"
LOCK_DIR="/tmp/openclawmgr-installer.lock"
DIAG_PREFIX="/tmp/openclawmgr-diag"

log_ts() { date "+%Y-%m-%d %H:%M:%S"; }

uci_get() { uci -q get "${UCI_NS}.main.$1" 2>/dev/null || true; }

uci_get_list() {
	local key="$1"
	uci -q show "${UCI_NS}.main.${key}" 2>/dev/null | \
		sed -n "s/^${UCI_NS}\\.main\\.${key}='\\(.*\\)'$/\\1/p"
}

fmt_elapsed() {
	local total="${1:-0}" h m s
	case "$total" in ''|*[!0-9]*) total=0 ;; esac
	h=$((total / 3600))
	m=$(((total % 3600) / 60))
	s=$((total % 60))
	if [ "$h" -gt 0 ]; then
		printf "%dh%dm%ds" "$h" "$m" "$s"
	elif [ "$m" -gt 0 ]; then
		printf "%dm%ds" "$m" "$s"
	else
		printf "%ds" "$s"
	fi
}

download_with_progress() {
	local url="$1" out="$2" err="$3" label="$4"
	local start_ts last_change_ts last_size last_report_ts

	write_installer_log "$label: $url"

	curl -fSL --retry 2 --retry-delay 1 --connect-timeout 15 --max-time 600 \
		-o "$out" "$url" 2>"$err" &
	local cpid="$!"

	start_ts="$(date +%s 2>/dev/null || echo 0)"
	last_change_ts="$start_ts"
	last_size=0
	last_report_ts="$start_ts"

	while kill -0 "$cpid" 2>/dev/null; do
		sleep 30
		kill -0 "$cpid" 2>/dev/null || break

		local now_ts size quiet_s elapsed_s elapsed_h size_mb
		now_ts="$(date +%s 2>/dev/null || echo 0)"
		size="$(wc -c <"$out" 2>/dev/null || echo 0)"
		case "$size" in ''|*[!0-9]*) size=0 ;; esac
		if [ "$size" -ne "$last_size" ]; then
			last_size="$size"
			last_change_ts="$now_ts"
		fi

		if [ $((now_ts - last_report_ts)) -ge 60 ]; then
			last_report_ts="$now_ts"
			quiet_s=$((now_ts - last_change_ts))
			elapsed_s=$((now_ts - start_ts))
			elapsed_h="$(fmt_elapsed "$elapsed_s")"
			size_mb=$((size / 1048576))

			if [ "$size" -gt 0 ]; then
				if [ "$quiet_s" -ge 60 ]; then
					write_installer_log "$label running (${elapsed_h} elapsed; no new data for ${quiet_s}s; downloaded ${size_mb}MB)"
				else
					write_installer_log "$label running (${elapsed_h} elapsed; downloaded ${size_mb}MB)"
				fi
			else
				write_installer_log "$label running (${elapsed_h} elapsed; no data yet)"
			fi
		fi
	done

	wait "$cpid"
	return $?
}

default_allowed_origins() {
	local port="$PORT" ip
	ip="$(uci -q get network.lan.ipaddr 2>/dev/null || true)"
	if [ -z "$ip" ]; then
		ip="$(ip -4 -o addr show br-lan 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1)"
	fi
	if [ -n "$ip" ]; then
		printf "http://%s:%s\n" "$ip" "$port"
	fi
}

build_allowed_origins_json() {
	local origins="${1:-}"
	printf "%s" "$origins" | awk '
		BEGIN { first=1; print "[" }
		{
			gsub(/^[ \t]+|[ \t]+$/, "", $0)
			if ($0 == "") next
			gsub(/\\/,"\\\\",$0); gsub(/"/,"\\\"",$0)
			if (first) { first=0; printf "      \"%s\"", $0 }
			else { printf ",\n      \"%s\"", $0 }
		}
		END {
			if (first) { print "]" } else { print "\n    ]" }
		}'
}

has_default_route() {
	ip route 2>/dev/null | grep -q '^default '
}

default_gateway() {
	ip route 2>/dev/null | awk '/^default/{print $3; exit}' 2>/dev/null || true
}

ensure_dirs() {
	mkdir -p "$BASE_DIR" "$BASE_DIR/log" "$NODE_DIR" "$GLOBAL_DIR" "$DATA_DIR/.openclaw" 2>/dev/null || true
}

check_space_mb() {
	local path="$1" need_mb="$2"
	local avail_kb
	avail_kb="$(df -kP "$path" 2>/dev/null | awk 'NR==2{print $4}' 2>/dev/null || echo 0)"
	[ -n "$avail_kb" ] || avail_kb=0
	if [ "$avail_kb" -lt $((need_mb * 1024)) ] 2>/dev/null; then
		write_installer_log "Insufficient disk space at $path: need ${need_mb}MB, available $((avail_kb / 1024))MB"
		return 1
	fi
	return 0
}

proc_ppid() {
	local pid="$1"
	[ -r "/proc/$pid/stat" ] || return 1
	awk '{print $4}' "/proc/$pid/stat" 2>/dev/null
}

pid_in_own_ancestry() {
	local target="$1" cur depth
	case "$target" in ''|*[!0-9]*) return 1 ;; esac

	cur="$$"
	depth=0
	while [ -n "$cur" ] && [ "$cur" -gt 1 ] 2>/dev/null && [ "$depth" -lt 64 ]; do
		[ "$cur" = "$target" ] && return 0
		cur="$(proc_ppid "$cur" 2>/dev/null || true)"
		depth=$((depth + 1))
	done

	return 1
}

acquire_lock() {
	if mkdir "$LOCK_DIR" 2>/dev/null; then
		echo "$$" >"$LOCK_DIR/pid" 2>/dev/null || true
		trap 'rm -rf "$LOCK_DIR" 2>/dev/null || true' EXIT
		return 0
	fi

	# Lock exists: check if it's stale (e.g. previous task killed or power loss).
	if [ -d "$LOCK_DIR" ]; then
		local pid running
		pid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			write_installer_log "Another operation is running (lock: $LOCK_DIR, pid: $pid)"
			exit 2
		fi

		running="false"
		if [ -x /etc/init.d/tasks ] && command -v jsonfilter >/dev/null 2>&1; then
			local st tpid
			st="$(/etc/init.d/tasks task_status "$APP" 2>/dev/null || true)"
			running="$(printf "%s" "$st" | jsonfilter -e '@.running' 2>/dev/null || echo false)"
			tpid="$(printf "%s" "$st" | jsonfilter -e '@.pid' 2>/dev/null || true)"
			if [ "$running" = "true" ]; then
				if [ -n "${tpid:-}" ] && kill -0 "$tpid" 2>/dev/null; then
					if pid_in_own_ancestry "$tpid"; then
						write_installer_log "Stale lock detected for current task, recovering: $LOCK_DIR"
						running="false"
					else
						write_installer_log "Another operation is running (taskd: $APP, pid: $tpid)"
						exit 2
					fi
				fi
				if [ "$running" = "true" ]; then
					# task_status says running, but pid is gone -> stale task record
					write_installer_log "Stale task record detected, clearing: $APP"
					/etc/init.d/tasks task_del "$APP" >/dev/null 2>&1 || true
					running="false"
				fi
			fi
		fi
		if [ "$running" = "true" ]; then
			write_installer_log "Another operation is running (taskd: $APP)"
			exit 2
		fi

		write_installer_log "Stale lock detected, removing: $LOCK_DIR"
		rm -rf "$LOCK_DIR" 2>/dev/null || true
		if mkdir "$LOCK_DIR" 2>/dev/null; then
			echo "$$" >"$LOCK_DIR/pid" 2>/dev/null || true
			trap 'rm -rf "$LOCK_DIR" 2>/dev/null || true' EXIT
			return 0
		fi
	fi

	write_installer_log "Another operation is running (lock: $LOCK_DIR)"
	exit 2
}

gen_token() {
	(hexdump -n 24 -e '24/1 "%02x"' /dev/urandom 2>/dev/null) || \
	(openssl rand -hex 24 2>/dev/null) || \
	(date +%s | md5sum 2>/dev/null | awk '{print $1}')
}

is_musl() {
	ldd --version 2>&1 | grep -qi musl && return 0
	[ -e /lib/ld-musl-*.so.1 ] 2>/dev/null && return 0
	return 1
}

detect_arch() {
	case "$(uname -m 2>/dev/null || echo unknown)" in
		x86_64) echo "linux-x64" ;;
		aarch64) echo "linux-arm64" ;;
		*) echo "unsupported" ;;
	esac
}

ks_admin_port() {
	local en ap
	en="$(uci -q get istoreenhance.@istoreenhance[0].enabled 2>/dev/null || echo 0)"
	[ "$en" = "1" ] || return 1
	pidof iStoreEnhance >/dev/null 2>&1 || return 1
	ap="$(uci -q get istoreenhance.@istoreenhance[0].adminport 2>/dev/null || echo 5003)"
	echo "$ap"
}

download() {
	local url="$1" out="$2"
	local ap admin_path resp err tmp rc ks_enabled resp_file http_code

	tmp="/tmp/${APP}-curl.err"
	err="/tmp/${APP}-curl.err2"
	resp_file="/tmp/${APP}-ks-remap.json"
	rm -f "$tmp" "$err" "$resp_file" 2>/dev/null || true

	if [ "${INSTALL_ACCELERATED:-1}" != "1" ]; then
		write_installer_log "KSpeeder not used: accelerated install is disabled"
	else
		ks_enabled="$(uci -q get istoreenhance.@istoreenhance[0].enabled 2>/dev/null || echo 0)"
		if [ "$ks_enabled" != "1" ]; then
		write_installer_log "KSpeeder not used: istoreenhance is disabled"
		elif ! pidof iStoreEnhance >/dev/null 2>&1; then
		write_installer_log "KSpeeder not used: iStoreEnhance process is not running"
		else
			ap="$(uci -q get istoreenhance.@istoreenhance[0].adminport 2>/dev/null || echo 5003)"
			http_code="$(curl -sS --connect-timeout 2 --max-time 5 -G \
				--data-urlencode "url=${url}" \
				-o "$resp_file" -w "%{http_code}" \
				"http://127.0.0.1:${ap}/api/domainfold/remap" 2>"$tmp" || echo 000)"
			resp="$(cat "$resp_file" 2>/dev/null || true)"
			admin_path="$(printf "%s" "$resp" | jsonfilter -e '@.admin_path' 2>/dev/null || true)"
			if [ -n "$admin_path" ] && echo "$admin_path" | grep -q '^/'; then
				if download_with_progress "http://127.0.0.1:${ap}${admin_path}" "$out" "$err" "Downloading via KSpeeder"; then
					return 0
				fi
				rc=$?
				write_installer_log "Download via KSpeeder failed (rc=$rc): ${url}"
				tail -n 5 "$err" 2>/dev/null | while IFS= read -r ln; do write_installer_log "$ln"; done
			else
				local e brief
				e="$(printf "%s" "$resp" | jsonfilter -e '@.error' 2>/dev/null || true)"
				if [ -n "$e" ]; then
					write_installer_log "KSpeeder remap failed (http=${http_code}): $e"
				elif [ -n "$http_code" ] && [ "$http_code" != "000" ] && [ "$http_code" != "200" ]; then
					brief="$(printf "%s" "$resp" | tr '\n' ' ' | sed 's/[[:space:]]\\+/ /g' | cut -c1-200)"
					[ -n "$brief" ] || brief="(empty response)"
					write_installer_log "KSpeeder not used: remap http=${http_code}: ${brief}"
				elif [ -s "$tmp" ]; then
					write_installer_log "KSpeeder not used: remap request failed on 127.0.0.1:${ap}"
					tail -n 3 "$tmp" 2>/dev/null | while IFS= read -r ln; do write_installer_log "$ln"; done
				else
					write_installer_log "KSpeeder not used: remap response missing admin_path"
				fi
			fi
		fi
	fi

	if ! has_default_route; then
		write_installer_log "No default route (default gateway missing); internet is unreachable"
	fi

	if download_with_progress "$url" "$out" "$err" "Downloading"; then
		return 0
	fi
	rc=$?
	write_installer_log "Download failed (rc=$rc): ${url}"
	tail -n 5 "$err" 2>/dev/null | while IFS= read -r ln; do write_installer_log "$ln"; done
	return "$rc"
}

write_installer_log() {
	local msg="$1"
	mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
	local line
	line="$(printf "%s [%s] %s" "$(log_ts)" "$APP" "$msg")"
	printf "%s\n" "$line"
	printf "%s\n" "$line" >> "$LOG_FILE"
}

openclaw_bin() {
	local b="${GLOBAL_DIR}/bin/openclaw"
	[ -x "$b" ] && { echo "$b"; return 0; }
	return 1
}

openclaw_cmd() {
	local b
	b="$(openclaw_bin 2>/dev/null || true)"
	[ -n "$b" ] || return 127
	HOME="$DATA_DIR" \
	OPENCLAW_HOME="$DATA_DIR" \
	OPENCLAW_STATE_DIR="${DATA_DIR}/.openclaw" \
	OPENCLAW_CONFIG_PATH="${DATA_DIR}/.openclaw/openclaw.json" \
	PATH="${NODE_DIR}/bin:${GLOBAL_DIR}/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
	"$b" "$@"
}

find_entry() {
	local d="${GLOBAL_DIR}/lib/node_modules/openclaw"
	[ -f "${d}/openclaw.mjs" ] && { echo "${d}/openclaw.mjs"; return 0; }
	[ -f "${d}/dist/cli.js" ] && { echo "${d}/dist/cli.js"; return 0; }
	return 1
}

node_version() {
	[ -x "$NODE_BIN" ] || return 0
	"$NODE_BIN" --version 2>/dev/null || true
}

openclaw_version() {
	local pkg="${GLOBAL_DIR}/lib/node_modules/openclaw/package.json"
	[ -f "$pkg" ] || return 0
	sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$pkg" 2>/dev/null | head -n 1
}

have_openclaw_runtime() {
	[ -x "$NODE_BIN" ] || return 1
	find_entry >/dev/null 2>&1 || return 1
	return 0
}

agent_key_name() {
	case "${DEFAULT_AGENT:-anthropic}" in
		openai) echo "OPENAI_API_KEY" ;;
		anthropic) echo "ANTHROPIC_API_KEY" ;;
		minimax-cn) echo "MINIMAX_API_KEY" ;;
		moonshot) echo "MOONSHOT_API_KEY" ;;
		*) echo "ANTHROPIC_API_KEY" ;;
	esac
}

agent_default_model() {
	if [ -n "${DEFAULT_MODEL:-}" ]; then
		echo "$DEFAULT_MODEL"
		return 0
	fi
	case "${DEFAULT_AGENT:-anthropic}" in
		openai) echo "openai/gpt-5.2" ;;
		anthropic) echo "anthropic/claude-sonnet-4-6" ;;
		minimax-cn) echo "minimax-cn/MiniMax-M2.5" ;;
		moonshot) echo "moonshot/kimi-k2.5" ;;
		*) echo "anthropic/claude-sonnet-4-6" ;;
	esac
}

agent_default_base_url() {
	case "${DEFAULT_AGENT:-anthropic}" in
		openai) echo "https://api.openai.com/v1" ;;
		anthropic) echo "https://api.anthropic.com" ;;
		minimax-cn) echo "https://api.minimaxi.com/anthropic" ;;
		moonshot) echo "https://api.moonshot.cn/v1" ;;
		*) echo "https://api.anthropic.com" ;;
	esac
}

is_valid_http_url() {
	case "${1:-}" in
		http://*|https://*) return 0 ;;
		*) return 1 ;;
	esac
}

ensure_gateway_config() {
	local cfg="${DATA_DIR}/.openclaw/openclaw.json"
	[ -n "${TOKEN:-}" ] || return 1

	if [ -f "$cfg" ]; then
		# Only overwrite configs that look managed by OpenClawMgr (backward compatible).
		if ! grep -Eq '"controlUi"[[:space:]]*:' "$cfg" 2>/dev/null && \
		   ! grep -Eq '"basePath"[[:space:]]*:[[:space:]]*"\\?/openclawmgr"' "$cfg" 2>/dev/null; then
			write_installer_log "Skipping config update because ${cfg} does not look managed by OpenClawMgr"
			return 0
		fi
	fi

	local host_header_fallback="false"
	if [ "$BIND" != "loopback" ]; then
		host_header_fallback="true"
	fi

	local allow_insecure="false"
	if [ "${ALLOW_INSECURE_AUTH:-0}" = "1" ]; then
		allow_insecure="true"
	fi

	local disable_device_auth="false"
	if [ "${DISABLE_DEVICE_AUTH:-0}" = "1" ]; then
		disable_device_auth="true"
	fi

	local allowed_origins="$ALLOWED_ORIGINS"
	if [ -z "$allowed_origins" ]; then
		allowed_origins="$(default_allowed_origins)"
	fi
	local selected_key selected_model selected_base_url override_base_url base_url_mode
	selected_key="$(agent_key_name)"
	selected_model="$(agent_default_model)"
	selected_base_url="$(agent_default_base_url)"
	override_base_url=""
	base_url_mode="default"
	if [ -n "${PROVIDER_BASE_URL:-}" ]; then
		if is_valid_http_url "$PROVIDER_BASE_URL"; then
			override_base_url="$PROVIDER_BASE_URL"
			base_url_mode="override"
		else
			write_installer_log "Ignoring invalid relay URL for ${DEFAULT_AGENT:-anthropic}: ${PROVIDER_BASE_URL}"
			base_url_mode="preserve"
		fi
	fi

	mkdir -p "$(dirname "$cfg")" 2>/dev/null || true
	CFG_PATH="$cfg" \
	ALLOWED_ORIGINS_RAW="$allowed_origins" \
	GATEWAY_PORT="$PORT" \
	GATEWAY_BIND="$BIND" \
	GATEWAY_TOKEN="$TOKEN" \
	GATEWAY_ALLOW_INSECURE="$allow_insecure" \
	GATEWAY_DISABLE_DEVICE_AUTH="$disable_device_auth" \
	GATEWAY_HOST_HEADER_FALLBACK="$host_header_fallback" \
	DEFAULT_AGENT_NAME="${DEFAULT_AGENT:-anthropic}" \
	DEFAULT_AGENT_KEY="$selected_key" \
	DEFAULT_AGENT_MODEL="$selected_model" \
	DEFAULT_AGENT_BASE_URL="$selected_base_url" \
	DEFAULT_AGENT_OVERRIDE_BASE_URL="$override_base_url" \
	DEFAULT_AGENT_BASE_URL_MODE="$base_url_mode" \
	DEFAULT_AGENT_API_KEY="${PROVIDER_API_KEY:-}" \
	lua - <<'EOF'
local json = require "luci.jsonc"

local cfg_path = os.getenv("CFG_PATH")
local function slurp(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local data = f:read("*a")
	f:close()
	return data
end

local function bool_env(name)
	return os.getenv(name) == "true"
end

local function split_lines(raw)
	local out = {}
	raw = raw or ""
	for line in raw:gmatch("([^\n]+)") do
		line = line:gsub("^%s+", ""):gsub("%s+$", "")
		if line ~= "" then
			table.insert(out, line)
		end
	end
	return out
end

local function ensure_table(parent, key)
	if type(parent[key]) ~= "table" then
		parent[key] = {}
	end
	return parent[key]
end

local function read_config(path)
	local raw = slurp(path)
	if not raw or raw == "" then
		return {}
	end
	return json.parse(raw) or {}
end

local cfg = read_config(cfg_path)

local gateway = ensure_table(cfg, "gateway")
gateway.mode = "local"
gateway.port = tonumber(os.getenv("GATEWAY_PORT")) or 18789
gateway.bind = os.getenv("GATEWAY_BIND") or "lan"
gateway.auth = { mode = "token", token = os.getenv("GATEWAY_TOKEN") or "" }

local control = ensure_table(gateway, "controlUi")
control.enabled = true
control.basePath = nil
control.allowedOrigins = split_lines(os.getenv("ALLOWED_ORIGINS_RAW"))
control.allowInsecureAuth = bool_env("GATEWAY_ALLOW_INSECURE")
control.dangerouslyDisableDeviceAuth = bool_env("GATEWAY_DISABLE_DEVICE_AUTH")
control.dangerouslyAllowHostHeaderOriginFallback = bool_env("GATEWAY_HOST_HEADER_FALLBACK")

local env = {}
local selected_env_key = os.getenv("DEFAULT_AGENT_KEY")
local selected_api_key = os.getenv("DEFAULT_AGENT_API_KEY") or ""
if selected_env_key and selected_api_key ~= "" then
	env[selected_env_key] = selected_api_key
end
cfg.env = next(env) and env or nil

local models = {}
models.mode = "merge"
local providers = {}
models.providers = providers
cfg.models = models

local current_provider_id = os.getenv("DEFAULT_AGENT_NAME") or "anthropic"
local current_provider = {}
providers[current_provider_id] = current_provider

if current_provider_id == "openai" then
	current_provider.api = "openai-completions"
	current_provider.baseUrl = "https://api.openai.com/v1"
	current_provider.apiKey = selected_api_key
	current_provider.models = {
		{ id = "gpt-5.2", name = "GPT-5.2" },
	}
elseif current_provider_id == "anthropic" then
	current_provider.api = "anthropic-messages"
	current_provider.baseUrl = "https://api.anthropic.com"
	current_provider.apiKey = selected_api_key
	current_provider.models = {
		{ id = "claude-sonnet-4-6", name = "Claude Sonnet 4.6" },
	}
elseif current_provider_id == "minimax-cn" then
	current_provider.api = "anthropic-messages"
	current_provider.baseUrl = "https://api.minimaxi.com/anthropic"
	current_provider.apiKey = selected_api_key
	current_provider.authHeader = true
	current_provider.models = {
		{ id = "MiniMax-M2.5", name = "MiniMax M2.5" },
	}
elseif current_provider_id == "moonshot" then
	current_provider.api = "openai-completions"
	current_provider.baseUrl = "https://api.moonshot.cn/v1"
	current_provider.apiKey = selected_api_key
	current_provider.models = {
		{ id = "kimi-k2.5", name = "Kimi K2.5" },
	}
end

local override_base = os.getenv("DEFAULT_AGENT_OVERRIDE_BASE_URL") or ""
local base_url_mode = os.getenv("DEFAULT_AGENT_BASE_URL_MODE") or "default"
if base_url_mode == "override" and override_base ~= "" then
	current_provider.baseUrl = override_base
elseif base_url_mode == "default" then
	current_provider.baseUrl = os.getenv("DEFAULT_AGENT_BASE_URL") or current_provider.baseUrl
end

local agents = ensure_table(cfg, "agents")
local defaults = ensure_table(agents, "defaults")
local model = ensure_table(defaults, "model")
model.primary = os.getenv("DEFAULT_AGENT_MODEL") or "anthropic/claude-sonnet-4-6"

local encoded = json.stringify(cfg, true)
if encoded then
	encoded = encoded:gsub("\\/", "/")
end
local f = assert(io.open(cfg_path, "w"))
	f:write(encoded or "{}")
	f:write("\n")
f:close()

local env_path = cfg_path:gsub("openclaw%.json$", "openclaw.env")
local envf = assert(io.open(env_path, "w"))
if selected_env_key and selected_api_key ~= "" then
	local val = tostring(selected_api_key)
	val = val:gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub('"', '\\"')
	envf:write(selected_env_key .. '="' .. val .. '"\n')
end
envf:close()
EOF
}

have_local_node_runtime() {
	[ -x "$NODE_BIN" ] && [ -x "$NPM_BIN" ]
}

cached_node_archive_ok() {
	local archive="$1"
	[ -s "$archive" ] || return 1

	if command -v xz >/dev/null 2>&1; then
		xz -t "$archive" >/dev/null 2>&1
		return $?
	fi

	tar -tJf "$archive" >/dev/null 2>&1
}

	install_node() {
		local arch libc url tmp
		arch="$(detect_arch)"
		[ "$arch" != "unsupported" ] || { write_installer_log "Unsupported arch"; return 1; }

		if is_musl; then
			libc="musl"
		else
			libc="glibc"
		fi

		# OpenWrt/iStoreOS runs on musl; use musl builds by default.
		url="https://unofficial-builds.nodejs.org/download/release/v${NODE_VERSION}/node-v${NODE_VERSION}-${arch}-musl.tar.xz"

		if have_local_node_runtime; then
			write_installer_log "Using existing Node.js runtime: $($NODE_BIN --version 2>/dev/null || echo unknown)"
			return 0
		fi

	if [ -x "$NODE_BIN" ] || [ -x "$NPM_BIN" ]; then
		write_installer_log "Node.js runtime under $NODE_DIR is incomplete; reinstalling bundled Node.js"
	fi

	# Fallback: use system node/npm (e.g. from opkg) and symlink into BASE_DIR.
	local sys_node sys_npm
	sys_node="$(command -v node 2>/dev/null || true)"
	sys_npm="$(command -v npm 2>/dev/null || true)"
	if [ -n "$sys_node" ] && [ -n "$sys_npm" ]; then
		mkdir -p "${NODE_DIR}/bin" 2>/dev/null || true
		ln -sf "$sys_node" "${NODE_DIR}/bin/node" 2>/dev/null || true
		ln -sf "$sys_npm" "${NODE_DIR}/bin/npm" 2>/dev/null || true
		if have_local_node_runtime; then
			write_installer_log "Using system Node.js: $($NODE_BIN --version 2>/dev/null || echo unknown)"
			return 0
		fi
	fi

	write_installer_log "Downloading Node.js v${NODE_VERSION} (${arch}, ${libc})"
	tmp="/tmp/${APP}-node-${NODE_VERSION}.tar.xz"
	if cached_node_archive_ok "$tmp"; then
		write_installer_log "Reusing cached Node.js archive: $tmp"
	else
		if [ -e "$tmp" ]; then
			write_installer_log "Cached Node.js archive is invalid, re-downloading: $tmp"
			rm -f "$tmp" 2>/dev/null || true
		fi
		if ! download "$url" "$tmp"; then
			write_installer_log "Node.js download failed"
			return 1
		fi
	fi

	rm -rf "$NODE_DIR" 2>/dev/null || true
	mkdir -p "$NODE_DIR"
	if command -v xz >/dev/null 2>&1; then
		xz -dc "$tmp" | tar -xf - -C "$NODE_DIR" --strip-components=1
	else
		tar -xJf "$tmp" -C "$NODE_DIR" --strip-components=1
	fi
	rm -f "$tmp" 2>/dev/null || true

	[ -x "$NODE_BIN" ] || return 1
	write_installer_log "Node.js installed: $($NODE_BIN --version 2>/dev/null || echo unknown)"
	return 0
}

install_openclaw() {
	local flags="" npm_registry="" effective_registry=""
	[ -x "$NPM_BIN" ] || return 1

	if is_musl; then
		flags="--ignore-scripts"
	fi

	if [ "${INSTALL_ACCELERATED:-1}" = "1" ]; then
		npm_registry="https://registry.npmmirror.com"
	fi

	write_installer_log "Installing OpenClaw from npm"
	write_installer_log "Node.js: $($NODE_BIN --version 2>/dev/null || echo unknown), npm: $($NPM_BIN --version 2>/dev/null || echo unknown)"
	write_installer_log "npm prefix: $GLOBAL_DIR, cache: ${BASE_DIR}/npm-cache, musl: $(is_musl && echo yes || echo no) ${flags:+($flags)}"
	write_installer_log "npm registry: ${npm_registry:-default}"
	if [ -n "$npm_registry" ]; then
		effective_registry="$(HOME="$DATA_DIR" npm_config_cache="${BASE_DIR}/npm-cache" npm_config_registry="$npm_registry" \
			PATH="${NODE_DIR}/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
			"$NPM_BIN" config get registry 2>/dev/null | tr -d '\r' | head -n 1)"
	else
		effective_registry="$(HOME="$DATA_DIR" npm_config_cache="${BASE_DIR}/npm-cache" \
			PATH="${NODE_DIR}/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
			"$NPM_BIN" config get registry 2>/dev/null | tr -d '\r' | head -n 1)"
	fi
	write_installer_log "npm effective registry: ${effective_registry:-unknown}"
	rm -rf "${GLOBAL_DIR}/lib/node_modules/openclaw" 2>/dev/null || true
	local tmp="/tmp/${APP}-npm-install.log"
	rm -f "$tmp" 2>/dev/null || true

	# Some npm dependencies may be referenced as git+ssh (e.g. git@github.com:...),
	# which fails on routers without SSH keys. Force git to use HTTPS by writing a
	# scoped gitconfig under DATA_DIR and setting HOME for this invocation.
	if command -v git >/dev/null 2>&1; then
		mkdir -p "$DATA_DIR" 2>/dev/null || true
		# Use --add because url.*.insteadOf is multi-valued (git config without --add overwrites).
		git config --file "$DATA_DIR/.gitconfig" --add url."https://github.com/".insteadOf "ssh://git@github.com/" 2>/dev/null || true
		git config --file "$DATA_DIR/.gitconfig" --add url."https://github.com/".insteadOf "git@github.com:" 2>/dev/null || true
	fi

	# Stream npm output to taskd log while keeping a local copy for post-mortem.
	: >"$tmp"
	tail -n 0 -f "$tmp" &
	local tailpid="$!"
	write_installer_log "npm install started (may be quiet for a while); streaming npm output as it arrives"

	# npm from Node tarball uses `#!/usr/bin/env node`, ensure PATH contains our node.
	if [ -n "$npm_registry" ]; then
		HOME="$DATA_DIR" npm_config_cache="${BASE_DIR}/npm-cache" npm_config_registry="$npm_registry" \
			PATH="${NODE_DIR}/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
			"$NPM_BIN" install -g "openclaw@latest" --prefix="$GLOBAL_DIR" \
			$flags --no-audit --no-fund --no-progress >"$tmp" 2>&1 &
	else
		HOME="$DATA_DIR" npm_config_cache="${BASE_DIR}/npm-cache" \
			PATH="${NODE_DIR}/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
			"$NPM_BIN" install -g "openclaw@latest" --prefix="$GLOBAL_DIR" \
			$flags --no-audit --no-fund --no-progress >"$tmp" 2>&1 &
	fi
	local npmpid="$!"

	local start_ts last_change_ts last_size last_lines
	start_ts="$(date +%s 2>/dev/null || echo 0)"
	last_change_ts="$start_ts"
	last_size=0
	last_lines=0

	# Heartbeat: emit periodic logs so the UI doesn't appear stuck.
	while kill -0 "$npmpid" 2>/dev/null; do
		sleep 30
		kill -0 "$npmpid" 2>/dev/null || break

		local now_ts size lines quiet_s elapsed_s elapsed_h
		now_ts="$(date +%s 2>/dev/null || echo 0)"
		size="$(wc -c <"$tmp" 2>/dev/null || echo 0)"
		lines="$(wc -l <"$tmp" 2>/dev/null || echo 0)"
		case "$size" in ''|*[!0-9]*) size=0 ;; esac
		case "$lines" in ''|*[!0-9]*) lines=0 ;; esac

		if [ "$size" -ne "$last_size" ] || [ "$lines" -ne "$last_lines" ]; then
			last_size="$size"
			last_lines="$lines"
			last_change_ts="$now_ts"
		fi

		quiet_s=$((now_ts - last_change_ts))
		elapsed_s=$((now_ts - start_ts))
		elapsed_h="$(fmt_elapsed "$elapsed_s")"

		if [ "$quiet_s" -ge 60 ]; then
			local last
			last="$(tail -n 1 "$tmp" 2>/dev/null | tr -d '\r' || true)"
			if [ -n "$last" ]; then
				write_installer_log "npm install running (${elapsed_h} elapsed; no new output for ${quiet_s}s; last: ${last})"
			else
				write_installer_log "npm install running (${elapsed_h} elapsed; no output yet)"
			fi
		fi
	done

	local npm_rc=0
	wait "$npmpid" || npm_rc=$?
	if [ "$npm_rc" -ne 0 ]; then
		write_installer_log "npm install failed (rc=$npm_rc); dumping recent output"
		kill "$tailpid" 2>/dev/null || true
		wait "$tailpid" 2>/dev/null || true
		tail -n 200 "$tmp" >> "$LOG_FILE" 2>/dev/null || true
		rm -f "$tmp" 2>/dev/null || true
		return 1
	fi

	local end_ts elapsed_s elapsed_h
	end_ts="$(date +%s 2>/dev/null || echo 0)"
	elapsed_s=$((end_ts - start_ts))
	elapsed_h="$(fmt_elapsed "$elapsed_s")"
	write_installer_log "npm install finished (${elapsed_h} elapsed)"
	kill "$tailpid" 2>/dev/null || true
	wait "$tailpid" 2>/dev/null || true
	tail -n 200 "$tmp" >> "$LOG_FILE" 2>/dev/null || true
	rm -f "$tmp" 2>/dev/null || true
	find_entry >/dev/null 2>&1 || return 1
	write_installer_log "OpenClaw installed: $(openclaw_version || echo unknown)"
	return 0
}

	do_install() {
		acquire_lock
		write_installer_log "== install begin =="
		ensure_dirs
		# Node version is bundled/managed by installer code; do not allow UCI override.
		uci -q delete "${UCI_NS}.main.node_version" >/dev/null 2>&1 || true
		uci -q commit "$UCI_NS" >/dev/null 2>&1 || true
		if have_openclaw_runtime; then
			write_installer_log "OpenClaw is already installed: $(openclaw_version || echo unknown)"
			write_installer_log "Skip install. Use restart/apply config if you only need to refresh configuration."
			return 0
		fi
	if ! has_default_route; then
		write_installer_log "Install requires internet access, but no default gateway is configured."
		write_installer_log "Fix: configure WAN or add a default route, then retry Install."
		return 1
	fi
	check_space_mb "$BASE_DIR" 2048 || return 1

	TOKEN="$(uci_get token)"
	if [ -z "$TOKEN" ]; then
		TOKEN="$(gen_token)"
		uci -q set "${UCI_NS}.main.token=$TOKEN" && uci -q commit "$UCI_NS" || true
	fi

	install_node
	install_openclaw
	ensure_gateway_config || true

	/etc/init.d/openclawmgr enable >/dev/null 2>&1 || true
	uci -q set "${UCI_NS}.main.enabled=1" && uci -q commit "$UCI_NS" || true
	/etc/init.d/openclawmgr restart >/dev/null 2>&1 || true

	write_installer_log "== install done =="
}

do_uninstall() {
	acquire_lock
	write_installer_log "== uninstall begin =="
	/etc/init.d/openclawmgr stop >/dev/null 2>&1 || true
	/etc/init.d/openclawmgr disable >/dev/null 2>&1 || true
	uci -q set "${UCI_NS}.main.enabled=0" && uci -q commit "$UCI_NS" || true

	rm -rf "$NODE_DIR" "$GLOBAL_DIR" 2>/dev/null || true
	write_installer_log "Runtime removed (node/global)"
	write_installer_log "== uninstall done =="
}

do_uninstall_openclaw() {
	acquire_lock
	write_installer_log "== uninstall openclaw begin =="
	/etc/init.d/openclawmgr stop >/dev/null 2>&1 || true
	/etc/init.d/openclawmgr disable >/dev/null 2>&1 || true
	uci -q set "${UCI_NS}.main.enabled=0" && uci -q commit "$UCI_NS" || true

	rm -rf "${GLOBAL_DIR}/lib/node_modules/openclaw" \
		"${GLOBAL_DIR}/bin/openclaw" 2>/dev/null || true
	write_installer_log "OpenClaw removed (node kept)"
	write_installer_log "== uninstall openclaw done =="
}

do_purge() {
	acquire_lock
	write_installer_log "== purge begin =="
	/etc/init.d/openclawmgr stop >/dev/null 2>&1 || true
	/etc/init.d/openclawmgr disable >/dev/null 2>&1 || true
	uci -q set "${UCI_NS}.main.enabled=0" && uci -q commit "$UCI_NS" || true
	rm -rf "$BASE_DIR" 2>/dev/null || true
	write_installer_log "Base dir removed: $BASE_DIR"
	write_installer_log "== purge done =="
}

do_start() {
	acquire_lock
	write_installer_log "== start begin =="
	ensure_dirs
	/etc/init.d/openclawmgr enable >/dev/null 2>&1 || true
	uci -q set "${UCI_NS}.main.enabled=1" && uci -q commit "$UCI_NS" || true
	ensure_gateway_config || true
	/etc/init.d/openclawmgr restart >/dev/null 2>&1 || /etc/init.d/openclawmgr start >/dev/null 2>&1 || true
	write_installer_log "== start done =="
}

do_stop() {
	acquire_lock
	write_installer_log "== stop begin =="
	/etc/init.d/openclawmgr stop >/dev/null 2>&1 || true
	/etc/init.d/openclawmgr disable >/dev/null 2>&1 || true
	uci -q set "${UCI_NS}.main.enabled=0" && uci -q commit "$UCI_NS" || true
	write_installer_log "== stop done =="
}

do_restart() {
	acquire_lock
	write_installer_log "== restart begin =="
	ensure_dirs
	ensure_gateway_config || true
	/etc/init.d/openclawmgr restart >/dev/null 2>&1 || true
	write_installer_log "== restart done =="
}

do_apply_config() {
	acquire_lock
	write_installer_log "== apply_config begin =="
	ensure_dirs
	ensure_gateway_config || true

	local pid=""
	pid="$(ubus call service list "{\"name\":\"openclawmgr\"}" 2>/dev/null | jsonfilter -e '$.openclawmgr.instances.gateway.pid' 2>/dev/null || true)"
	if [ "${ENABLED:-0}" = "1" ]; then
		/etc/init.d/openclawmgr enable >/dev/null 2>&1 || true
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			/etc/init.d/openclawmgr restart >/dev/null 2>&1 || true
		fi
	else
		/etc/init.d/openclawmgr stop >/dev/null 2>&1 || true
		/etc/init.d/openclawmgr disable >/dev/null 2>&1 || true
	fi

	write_installer_log "== apply_config done =="
}

do_status() {
	local entry
	entry="$(find_entry 2>/dev/null || true)"
	[ -n "$entry" ] || return 0
	local pid=""
	pid="$(ubus call service list "{\"name\":\"openclawmgr\"}" 2>/dev/null | jsonfilter -e '$.openclawmgr.instances.gateway.pid' 2>/dev/null || true)"
	if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
		echo "running"
		return 0
	fi
	echo "stopped"
}

do_port() { echo "$PORT"; }
do_token() { echo "${TOKEN:-}"; }

diag_paths() {
	local name="$1"
	DIAG_LOG="${DIAG_PREFIX}-${name}.log"
	DIAG_PID="${DIAG_PREFIX}-${name}.pid"
	DIAG_EXIT="${DIAG_PREFIX}-${name}.exit"
	DIAG_LOCK="${DIAG_PREFIX}-${name}.lock"
}

diag_busy() {
	local name="$1"
	diag_paths "$name"
	[ -d "$DIAG_LOCK" ] && return 0
	return 1
}

diag_run() {
	local name="$1" limit="${2:-200}"
	case "$name" in
		doctor|gateway_status|gateway_health|logs|channels_status) ;;
		*) echo "unknown diag: $name" >&2; exit 1 ;;
	esac

	diag_paths "$name"
	if ! mkdir "$DIAG_LOCK" 2>/dev/null; then
		echo "busy" >&2
		exit 2
	fi

	rm -f "$DIAG_EXIT" 2>/dev/null || true
	: >"$DIAG_LOG"
	echo "$$" >"$DIAG_PID"

	(
		set +e
		echo "== $APP diag: $name ==" 
		echo "time: $(log_ts)"
		echo "base_dir: $BASE_DIR"
		echo "config: ${DATA_DIR}/.openclaw/openclaw.json"
		echo ""

		case "$name" in
			doctor)
				openclaw_cmd doctor --no-color
				;;
			gateway_status)
				openclaw_cmd gateway status --no-color --url "ws://127.0.0.1:${PORT}" --token "${TOKEN}"
				;;
			gateway_health)
				openclaw_cmd gateway health --no-color --url "ws://127.0.0.1:${PORT}" --token "${TOKEN}"
				;;
			logs)
				case "$limit" in ''|*[!0-9]*) limit=200 ;; esac
				[ "$limit" -gt 2000 ] && limit=2000
				[ "$limit" -lt 10 ] && limit=10
				openclaw_cmd logs --plain --no-color --limit "$limit"
				;;
			channels_status)
				openclaw_cmd channels status --no-color
				;;
		esac
		rc=$?
		echo ""
		echo "exit_code: $rc"
		exit "$rc"
	) >>"$DIAG_LOG" 2>&1

	rc=$?
	echo "$rc" >"$DIAG_EXIT"
	rm -f "$DIAG_PID" 2>/dev/null || true
	rmdir "$DIAG_LOCK" 2>/dev/null || true
	exit "$rc"
}

diag_poll() {
	local name="$1"
	case "$name" in
		doctor|gateway_status|gateway_health|logs|channels_status) ;;
		*) echo "unknown diag: $name" >&2; exit 1 ;;
	esac

	diag_paths "$name"

	local running=0
	if [ -f "$DIAG_PID" ]; then
		local pid
		pid="$(cat "$DIAG_PID" 2>/dev/null || true)"
		if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
			running=1
		fi
	fi

	if [ "$running" -eq 1 ]; then
		echo "running"
		exit 0
	fi
	if [ -f "$DIAG_EXIT" ]; then
		echo "done:$(cat "$DIAG_EXIT" 2>/dev/null || echo -1)"
		exit 0
	fi
	echo "idle"
}

ACTION="${1:-help}"
shift 1 || true

	BASE_DIR="$(uci_get base_dir)"
	PORT="$(uci_get port)"
	BIND="$(uci_get bind)"
	TOKEN="$(uci_get token)"
	ALLOW_INSECURE_AUTH="$(uci_get allow_insecure_auth)"
	DISABLE_DEVICE_AUTH="$(uci_get disable_device_auth)"
ALLOWED_ORIGINS="$(uci_get_list allowed_origins)"
DEFAULT_AGENT="$(uci_get default_agent)"
DEFAULT_MODEL="$(uci_get default_model)"
INSTALL_ACCELERATED="$(uci_get install_accelerated)"
PROVIDER_API_KEY="$(uci_get provider_api_key)"
PROVIDER_BASE_URL="$(uci_get provider_base_url)"

	[ -n "$BASE_DIR" ] || BASE_DIR="/opt/openclawmgr"
	[ -n "$PORT" ] || PORT="18789"
	[ -n "$BIND" ] || BIND="lan"
	NODE_VERSION="24.14.0"
[ -n "$ALLOW_INSECURE_AUTH" ] || ALLOW_INSECURE_AUTH="0"
[ -n "$DISABLE_DEVICE_AUTH" ] || DISABLE_DEVICE_AUTH="0"
[ -n "$DEFAULT_AGENT" ] || DEFAULT_AGENT="anthropic"
[ -n "$DEFAULT_MODEL" ] || DEFAULT_MODEL=""
[ -n "$INSTALL_ACCELERATED" ] || INSTALL_ACCELERATED="1"
[ -n "$PROVIDER_API_KEY" ] || PROVIDER_API_KEY=""
[ -n "$PROVIDER_BASE_URL" ] || PROVIDER_BASE_URL=""

case "$PORT" in
	''|*[!0-9]*) PORT="18789" ;;
esac
case "$BIND" in
	loopback|lan|auto|tailnet|custom) ;;
	*) BIND="lan" ;;
esac
case "$ALLOW_INSECURE_AUTH" in
	1|true|yes|on) ALLOW_INSECURE_AUTH="1" ;;
	*) ALLOW_INSECURE_AUTH="0" ;;
esac
case "$DISABLE_DEVICE_AUTH" in
	1|true|yes|on) DISABLE_DEVICE_AUTH="1" ;;
	*) DISABLE_DEVICE_AUTH="0" ;;
esac
case "$DEFAULT_AGENT" in
	openai|anthropic|minimax-cn|moonshot) ;;
	*) DEFAULT_AGENT="anthropic" ;;
esac
case "$INSTALL_ACCELERATED" in
	1|true|yes|on) INSTALL_ACCELERATED="1" ;;
	*) INSTALL_ACCELERATED="0" ;;
esac

NODE_DIR="${BASE_DIR}/node"
GLOBAL_DIR="${BASE_DIR}/global"
DATA_DIR="${BASE_DIR}/data"
LOG_FILE="${BASE_DIR}/log/installer.log"

NODE_BIN="${NODE_DIR}/bin/node"
NPM_BIN="${NODE_DIR}/bin/npm"

case "$ACTION" in
	install|upgrade)
		do_install
		;;
	uninstall)
		do_uninstall
		;;
	uninstall_openclaw)
		do_uninstall_openclaw
		;;
	purge)
		do_purge
		;;
	rm)
		do_uninstall
		;;
	start)
		do_start
		;;
	stop)
		do_stop
		;;
	restart)
		do_restart
		;;
	apply_config)
		do_apply_config
		;;
	status)
		do_status
		;;
	port)
		do_port
		;;
	token)
		do_token
		;;
	node_version)
		node_version
		;;
	openclaw_version)
		openclaw_version
		;;
	diag)
		diag_run "${1:-}" "${2:-}"
		;;
	diag_poll)
		diag_poll "${1:-}"
		;;
	*)
		echo "Usage: $0 {install|upgrade|uninstall|uninstall_openclaw|purge|rm|start|stop|restart|status|port|token|node_version|openclaw_version|diag|diag_poll}" >&2
		exit 1
		;;
esac
