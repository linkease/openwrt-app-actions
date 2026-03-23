module("luci.controller.openclawmgr", package.seeall)

function index()
	local fs = require "nixio.fs"
	if not fs.access("/etc/config/openclawmgr") then
		return
	end

	entry({"admin", "services", "openclawmgr"}, alias("admin", "services", "openclawmgr", "config"), _("OpenClaw 启动器"), 90).dependent = true
	local page = entry({"admin", "services", "openclawmgr", "config"}, call("action_app"), _("Config"), 10)
	page.leaf = true

	entry({"admin", "services", "openclawmgr", "cli"}, form("openclawmgr/cli"), _("命令行"), 20).leaf = true
	entry({"admin", "services", "openclawmgr", "logs"}, template("openclawmgr/logs"), _("日志"), 30).leaf = true

	entry({"admin", "services", "openclawmgr", "status"}, call("action_status")).leaf = true
	entry({"admin", "services", "openclawmgr", "ready"}, call("action_ready")).leaf = true
	entry({"admin", "services", "openclawmgr", "op"}, call("action_op")).leaf = true
	entry({"admin", "services", "openclawmgr", "config_data"}, call("action_config_data")).leaf = true
	entry({"admin", "services", "openclawmgr", "apply_config"}, call("action_apply_config")).leaf = true

	entry({"admin", "services", "openclawmgr", "logs_api"}, call("action_logs")).leaf = true

	entry({"admin", "services", "openclawmgr", "diag_info"}, call("action_diag_info")).leaf = true
	entry({"admin", "services", "openclawmgr", "diag_run"}, call("action_diag_run")).leaf = true
	entry({"admin", "services", "openclawmgr", "diag_poll"}, call("action_diag_poll")).leaf = true
end

function action_app()
	local http = require "luci.http"
	local tmpl = require "luci.template"
	local disp = require "luci.dispatcher"
	local ctx = disp.context or {}

	tmpl.render("openclawmgr/app", {
		token = ctx.token or "",
	})
	http.close()
end

local function lan_ipv4()
	local sys = require "luci.sys"
	local jsonc = require "luci.jsonc"
	local raw = sys.exec("ubus call network.interface.lan status 2>/dev/null")
	local obj = jsonc.parse(raw)
	if obj and obj["ipv4-address"] then
		for _, addr in ipairs(obj["ipv4-address"]) do
			if addr.address and addr.address ~= "" then
				return addr.address
			end
		end
	end
	return ""
end

local function default_allowed_origin(port_val)
	local ip = lan_ipv4()
	if ip ~= "" then
		return "http://" .. ip .. ":" .. port_val
	end
	return ""
end

local function write_json(obj)
	local http = require "luci.http"
	http.prepare_content("application/json")
	http.write_json(obj)
end

local function read_json_body()
	local http = require "luci.http"
	local jsonc = require "luci.jsonc"
	local ctype = http.getenv("CONTENT_TYPE") or ""
	if not ctype:match("^application/json") then
		return nil
	end
	local raw = http.content() or ""
	if #raw == 0 then
		return nil
	end
	local obj = jsonc.parse(raw)
	if type(obj) ~= "table" then
		return nil
	end
	return obj
end

local function get_task_state(task_id)
	local fs = require "nixio.fs"
	local jsonc = require "luci.jsonc"
	local sys = require "luci.sys"

	if not fs.access("/etc/init.d/tasks") then
		return {
			running = false,
			op = "",
			command = "",
		}
	end

	local raw = sys.exec("/etc/init.d/tasks task_status " .. task_id .. " 2>/dev/null")
	local obj = jsonc.parse(raw) or {}
	local cmd = ""
	local cmd_parts = {}

	local function as_bool(v)
		return v == true or v == "true" or v == "1" or v == 1
	end

	if type(obj.command) == "table" then
		cmd_parts = obj.command
		cmd = table.concat(obj.command, " ")
	elseif type(obj.command) == "string" then
		cmd = obj.command
	elseif type(obj.data) == "table" and type(obj.data.command) == "string" then
		cmd = obj.data.command
	end

	local op = ""
	for _, candidate in ipairs({ "install", "upgrade", "uninstall_openclaw", "uninstall", "purge", "restart", "start", "stop" }) do
		if cmd:match("(^|[^%w_])" .. candidate .. "([^%w_]|$)") then
			op = candidate
			break
		end
		for _, part in ipairs(cmd_parts) do
			if type(part) == "string" and part:match("(^|[^%w_])" .. candidate .. "([^%w_]|$)") then
				op = candidate
				break
			end
		end
		if op ~= "" then
			break
		end
	end

	return {
		running = as_bool(obj.running),
		op = op,
		command = cmd,
		pid = obj.pid and tostring(obj.pid) or "",
	}
end

local function safe_int(v, def, minv, maxv)
	v = tostring(v or "")
	local n = tonumber(v)
	if not n then
		return def
	end
	n = math.floor(n)
	if minv and n < minv then
		return minv
	end
	if maxv and n > maxv then
		return maxv
	end
	return n
end

local function require_csrf()
	local http = require "luci.http"
	local disp = require "luci.dispatcher"

	local method = http.getenv("REQUEST_METHOD") or ""
	if method ~= "POST" then
		return true
	end

	local ctx = disp.context
	if not (ctx and ctx.authsession) then
		write_json({ ok = false, error = "auth session missing" })
		return false
	end

	local expected = ctx.token
	local header_token = http.getenv("HTTP_X_LUCI_TOKEN")
	local form_token = http.formvalue("token")
	local body = read_json_body()
	local body_token = (type(body) == "table") and body["token"] or nil
	local provided = header_token or form_token or body_token

	if expected and provided ~= expected then
		write_json({ ok = false, error = "bad csrf token" })
		return false
	end
	if not expected and (not provided or #provided == 0) then
		write_json({ ok = false, error = "csrf token missing" })
		return false
	end
	return true
end

local function get_host()
	local http = require "luci.http"
	local host = http.getenv("HTTP_HOST") or http.getenv("SERVER_NAME") or ""
	host = host:gsub(":%d+$", "")
	if host == "_redirect2ssl" or host == "redirect2ssl" or host == "" then
		host = http.getenv("SERVER_ADDR") or "localhost"
	end
	return host
end

function action_logs()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local fs = require "nixio.fs"
	local util = require "luci.util"

	local limit = safe_int(http.formvalue("limit"), 200, 50, 2000)
	local kind = (http.formvalue("kind") or "openclaw"):lower()

	local cmd = ""
	if kind == "tasks" then
		local f = "/var/log/tasks/openclawmgr.log"
		if fs.access(f) then
			cmd = "tail -n " .. limit .. " " .. util.shellquote(f) .. " 2>/dev/null"
		else
			cmd = "echo '(task log not found: " .. f .. ")'"
		end
	elseif kind == "openclawmgr" then
		cmd = "logread 2>/dev/null | grep -i openclawmgr | tail -n " .. limit
	elseif kind == "all" then
		cmd = "logread 2>/dev/null | tail -n " .. limit
	else
		-- default: openclaw gateway logs
		cmd = "logread 2>/dev/null | grep -i openclaw | tail -n " .. limit
	end

	local log = sys.exec(cmd) or ""
	write_json({ ok = true, kind = kind, limit = limit, server_time = os.time(), log = log })
end

local function configured_base_path(base_dir)
	local jsonc = require "luci.jsonc"
	if type(base_dir) ~= "string" or base_dir == "" then
		return "/"
	end
	local path = base_dir .. "/data/.openclaw/openclaw.json"
	local f = io.open(path, "r")
	if not f then
		return "/"
	end

	local raw = f:read("*a") or ""
	f:close()

	local obj = jsonc.parse(raw)
	local base_path = obj
		and obj.gateway
		and obj.gateway.controlUi
		and obj.gateway.controlUi.basePath
	if type(base_path) ~= "string" or base_path == "" or base_path == "/" then
		return "/"
	end
	if base_path:sub(1, 1) ~= "/" then
		base_path = "/" .. base_path
	end
	return base_path:gsub("/+$", "") .. "/"
end

local function fmt_elapsed(seconds)
	seconds = tonumber(seconds) or 0
	if seconds < 60 then
		return string.format("%ds", seconds)
	elseif seconds < 3600 then
		return string.format("%dm%02ds", math.floor(seconds / 60), seconds % 60)
	elseif seconds < 86400 then
		return string.format("%dh%02dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
	end
	return string.format("%dd%02dh", math.floor(seconds / 86400), math.floor((seconds % 86400) / 3600))
end

local function get_running_pid()
	local sys = require "luci.sys"
	local jsonc = require "luci.jsonc"
	local raw = sys.exec("ubus call service list '{\"name\":\"openclawmgr\"}' 2>/dev/null")
	local obj = jsonc.parse(raw) or {}
	local svc = obj.openclawmgr
	if type(svc) ~= "table" or type(svc.instances) ~= "table" then
		return ""
	end
	local inst = svc.instances.gateway
	if type(inst) == "table" and inst.pid then
		return tostring(inst.pid)
	end
	return ""
end

local function installer_lock_pid()
	local f = io.open("/tmp/openclawmgr-installer.lock/pid", "r")
	if not f then
		return ""
	end
	local pid = (f:read("*l") or ""):gsub("%s+$", "")
	f:close()
	return pid
end

local function installer_lock_running()
	local sys = require "luci.sys"
	local pid = installer_lock_pid()
	if pid ~= "" and sys.call("kill -0 " .. pid .. " >/dev/null 2>&1") == 0 then
		local f = io.open("/proc/" .. pid .. "/cmdline", "r")
		local cmdline = ""
		if f then
			cmdline = (f:read("*a") or ""):gsub("%z", " ")
			f:close()
		end
		if cmdline:match("openclawmgr%.sh") and (cmdline:match(" install([%s]|$)") or cmdline:match(" upgrade([%s]|$)")) then
			return true, pid
		end
	end
	return false, pid
end

local function get_pid_uptime_human(pid)
	if not pid or pid == "" then
		return ""
	end
	local f = io.open("/proc/" .. pid .. "/stat", "r")
	if not f then
		return ""
	end
	local stat_line = f:read("*l") or ""
	f:close()

	local uf = io.open("/proc/uptime", "r")
	if not uf then
		return ""
	end
	local uptime_line = uf:read("*l") or ""
	uf:close()

	local after = stat_line:match("%) (.+)$")
	if not after then
		return ""
	end
	local fields = {}
	for part in after:gmatch("%S+") do
		fields[#fields + 1] = part
	end
	local start_ticks = tonumber(fields[20] or "")
	local system_uptime = tonumber((uptime_line:match("^(%S+)"))) or 0
	if not start_ticks or system_uptime <= 0 then
		return ""
	end

	local ticks_per_sec = 100
	local elapsed = math.floor(system_uptime - (start_ticks / ticks_per_sec))
	if elapsed < 0 then
		elapsed = 0
	end
	return fmt_elapsed(elapsed)
end

local function probe_gateway_ready(port, base_dir, bind)
	local sys = require "luci.sys"
	local util = require "luci.util"

	if not port or not tostring(port):match("^%d+$") then
		return false, "", ""
	end
	if not base_dir or base_dir == "" then
		return false, "", ""
	end

	local base_path = configured_base_path(base_dir)
	local candidates = {}

	if bind == "lan" or bind == "auto" then
		local ip = lan_ipv4()
		if ip ~= "" then
			candidates[#candidates + 1] = ip
		end
	end
	candidates[#candidates + 1] = "127.0.0.1"

	local last_code, last_url = "", ""
	for _, host in ipairs(candidates) do
		local url = "http://" .. host .. ":" .. port .. base_path
		last_url = url
		local cmd = string.format(
			"curl -fsS -o /dev/null --connect-timeout 1 --max-time 2 -w '%%{http_code}' %s 2>/dev/null",
			util.shellquote(url)
		)
		local code = sys.exec(cmd):gsub("%s+$", "")
		last_code = code
		local n = tonumber(code) or 0
		if n >= 200 and n < 400 then
			return true, code, url
		end
	end
	return false, last_code, last_url
end

function action_status()
	local sys = require "luci.sys"
	local uci = require "luci.model.uci".cursor()
	local task = get_task_state("openclawmgr")

	local enabled = uci:get("openclawmgr", "main", "enabled") or "0"
	local port = uci:get("openclawmgr", "main", "port") or "18789"
	local bind = uci:get("openclawmgr", "main", "bind") or "lan"
	local base_dir = uci:get("openclawmgr", "main", "base_dir") or ""
	local token = uci:get("openclawmgr", "main", "token") or ""

	if not port:match("^%d+$") then port = "18789" end

	local running = false
	local installed = false
	if base_dir ~= "" then
		local st = sys.exec("/usr/libexec/istorec/openclawmgr.sh status 2>/dev/null"):gsub("%s+$", "")
		running = (st == "running")
		installed = (st == "running" or st == "stopped")
	end

	local reachable, reachable_code, reachable_url = false, "", ""
	if installed and not running then
		reachable, reachable_code, reachable_url = probe_gateway_ready(port, base_dir, bind)
	end
	local lock_running, lock_pid = installer_lock_running()
	local installing = (task.running and (task.op == "install" or task.op == "upgrade")) or lock_running
	if not installing and task.running and not installed and not running then
		installing = true
	end

	local node_ver = ""
	local oc_ver = ""
	if base_dir ~= "" then
		node_ver = sys.exec("/usr/libexec/istorec/openclawmgr.sh node_version 2>/dev/null"):gsub("%s+$", "")
		oc_ver = sys.exec("/usr/libexec/istorec/openclawmgr.sh openclaw_version 2>/dev/null"):gsub("%s+$", "")
	end
	local pid = running and get_running_pid() or ""
	if pid == "" and installing and lock_pid ~= "" then
		pid = lock_pid
	end
	local uptime_human = running and get_pid_uptime_human(pid) or ""

	local base_url = ""
	if base_dir ~= "" then
		base_url = "http://" .. get_host() .. ":" .. port .. configured_base_path(base_dir)
	end
	local token_url = base_url
	if token ~= "" then
		token_url = token_url .. "#token=" .. token
	end

	write_json({
		ok = true,
		enabled = enabled,
		installed = installed,
		running = running,
		reachable = reachable,
		reachable_http_code = reachable_code,
		reachable_url = reachable_url,
		task_running = task.running,
		task_op = task.op,
		installing = installing,
		port = port,
		bind = bind,
		base_dir = base_dir,
		token = token,
		node_version = node_ver,
		openclaw_version = oc_ver,
		pid = pid,
		uptime_human = uptime_human,
		base_url = base_url,
		token_url = token_url,
		url = token_url,
	})
end

function action_ready()
	local uci = require "luci.model.uci".cursor()

	local port = uci:get("openclawmgr", "main", "port") or "18789"
	local bind = uci:get("openclawmgr", "main", "bind") or "lan"
	local base_dir = uci:get("openclawmgr", "main", "base_dir") or ""

	if not port:match("^%d+$") then port = "18789" end

	if base_dir == "" then
		write_json({ ok = true, ready = false, reason = "base_dir missing" })
		return
	end

	local ready, code, url = probe_gateway_ready(port, base_dir, bind)

	write_json({
		ok = true,
		ready = ready,
		http_code = code,
		url = url,
	})
end

function action_apply_config()
	local sys = require "luci.sys"

	if not require_csrf() then
		return
	end

	local rc = sys.call("/usr/libexec/istorec/openclawmgr.sh apply_config >/dev/null 2>&1")
	if rc ~= 0 then
		write_json({ ok = false, error = "apply config failed" })
		return
	end

	write_json({
		ok = true,
		applied_at = os.date("%Y-%m-%d %H:%M:%S"),
	})
end

function action_config_data()
	local http = require "luci.http"
	local jsonc = require "luci.jsonc"
	local uci = require "luci.model.uci".cursor()
	local model = require "luci.model.openclawmgr"

	if (http.getenv("REQUEST_METHOD") or "GET") == "POST" then
		if not require_csrf() then
			return
		end

	local body = read_json_body() or {}
	local section = "main"

		local function bool_to_uci(value)
			return value and "1" or "0"
		end

		local function has(key)
			return body[key] ~= nil
		end

		if has("enabled") then
			uci:set("openclawmgr", section, "enabled", bool_to_uci(body.enabled == true or body.enabled == "1"))
		end

		if has("port") then
			local port = tostring(body.port or "")
			if not port:match("^%d+$") then
				write_json({ ok = false, error = "invalid port" })
				return
			end
			local port_num = tonumber(port) or 0
			if port_num < 1025 or port_num > 65535 then
				write_json({ ok = false, error = "invalid port (must be 1025-65535)" })
				return
			end
			uci:set("openclawmgr", section, "port", port)
		end

		if has("bind") then
			local bind = tostring(body.bind or "")
			if bind ~= "loopback" and bind ~= "lan" and bind ~= "auto" and bind ~= "tailnet" and bind ~= "custom" then
				write_json({ ok = false, error = "invalid bind" })
				return
			end
			uci:set("openclawmgr", section, "bind", bind)
		end

		if has("base_dir") then
			local base_dir = tostring(body.base_dir or "")
			if base_dir == "" then
				write_json({ ok = false, error = "base_dir required" })
				return
			end
			uci:set("openclawmgr", section, "base_dir", base_dir)
		end

		if has("default_agent") then
			local agent = tostring(body.default_agent or "")
			if agent ~= "openai" and agent ~= "anthropic" and agent ~= "minimax-cn" and agent ~= "moonshot" then
				write_json({ ok = false, error = "invalid default_agent" })
				return
			end
			uci:set("openclawmgr", section, "default_agent", agent)
		end

		if has("default_model") then
			uci:set("openclawmgr", section, "default_model", tostring(body.default_model or ""))
		end

		if has("install_accelerated") then
			uci:set("openclawmgr", section, "install_accelerated", bool_to_uci(body.install_accelerated == true or body.install_accelerated == "1"))
		end

		if has("provider_api_key") then
			uci:set("openclawmgr", section, "provider_api_key", tostring(body.provider_api_key or ""))
		end

		if has("provider_base_url") then
			local value = tostring(body.provider_base_url or "")
			if value ~= "" and not value:match("^https?://") then
				write_json({ ok = false, error = "invalid provider_base_url" })
				return
			end
			uci:set("openclawmgr", section, "provider_base_url", value)
		end

		if has("token") then
			uci:set("openclawmgr", section, "token", tostring(body.token or ""))
		end

		if has("allowed_origins") then
			local origins = {}
			if type(body.allowed_origins) == "table" then
				for _, item in ipairs(body.allowed_origins) do
					item = tostring(item or ""):match("^%s*(.-)%s*$")
					if item and item ~= "" then
						table.insert(origins, item)
					end
				end
			end
			if #origins > 0 then
				uci:set_list("openclawmgr", section, "allowed_origins", origins)
			else
				uci:delete("openclawmgr", section, "allowed_origins")
			end
		end

		if has("allow_insecure_auth") then
			uci:set("openclawmgr", section, "allow_insecure_auth", bool_to_uci(body.allow_insecure_auth == true or body.allow_insecure_auth == "1"))
		end

		if has("disable_device_auth") then
			uci:set("openclawmgr", section, "disable_device_auth", bool_to_uci(body.disable_device_auth == true or body.disable_device_auth == "1"))
		end

		uci:commit("openclawmgr")
		write_json({ ok = true })
		return
	end

	local base_dir = uci:get("openclawmgr", "main", "base_dir") or ""
	local port = uci:get("openclawmgr", "main", "port") or "18789"
	local blocks = model.blocks()
	local home = model.home()
	local paths, default_path = model.find_paths(blocks, home, "Configs")
	local choices = {}
	local seen = {}

	local function add_choice(path)
		if path and path ~= "" and not seen[path] then
			table.insert(choices, path)
			seen[path] = true
		end
	end

	if base_dir ~= "" then
		add_choice(base_dir)
	end
	for _, path in ipairs(paths or {}) do
		add_choice(path)
	end
	add_choice(default_path or "/root/Configs/OpenClawMgr")

	local allowed_origins = {}
	for _, item in ipairs(uci:get_list("openclawmgr", "main", "allowed_origins") or {}) do
		allowed_origins[#allowed_origins + 1] = item
	end

	write_json({
		ok = true,
		config = {
			enabled = (uci:get("openclawmgr", "main", "enabled") or "0") == "1",
			port = port,
			bind = uci:get("openclawmgr", "main", "bind") or "lan",
			base_dir = base_dir,
			token = uci:get("openclawmgr", "main", "token") or "",
			allowed_origins = allowed_origins,
			allow_insecure_auth = (uci:get("openclawmgr", "main", "allow_insecure_auth") or "0") == "1",
			disable_device_auth = (uci:get("openclawmgr", "main", "disable_device_auth") or "0") == "1",
			default_agent = uci:get("openclawmgr", "main", "default_agent") or "anthropic",
			default_model = uci:get("openclawmgr", "main", "default_model") or "",
			install_accelerated = (uci:get("openclawmgr", "main", "install_accelerated") or "1") == "1",
			provider_api_key = uci:get("openclawmgr", "main", "provider_api_key") or "",
			provider_base_url = uci:get("openclawmgr", "main", "provider_base_url") or "",
		},
		options = {
			base_dir_choices = choices,
			suggested_base_dir = default_path or "",
			default_origin = default_allowed_origin(port),
		}
	})
end

function action_op()
	local http = require "luci.http"
	local i18n = require "luci.i18n"
	local sys = require "luci.sys"
	local util = require "luci.util"
	local fs = require "nixio.fs"
	local tasks = nil
	do
		local ok, mod = pcall(require, "luci.model.tasks")
		if ok then tasks = mod end
	end

	if not require_csrf() then
		return
	end

	local op = http.formvalue("op") or ""
	local ok_ops = { install = true, upgrade = true, start = true, stop = true, restart = true, apply_config = true, uninstall = true, uninstall_openclaw = true, purge = true, cancel_install = true }
	if not ok_ops[op] then
		write_json({ ok = false, error = "unknown op" })
		return
	end

	local task_id = "openclawmgr"
	local script_path = "/usr/libexec/istorec/openclawmgr.sh"

	if op == "cancel_install" then
		if not fs.access("/etc/init.d/tasks") then
			write_json({ ok = false, error = i18n.translate("taskd is not available") })
			return
		end

		local task = get_task_state(task_id)
		local st = sys.exec("/usr/libexec/istorec/openclawmgr.sh status 2>/dev/null"):gsub("%s+$", "")
		local installed = (st == "running" or st == "stopped")
		local install_like = task.running and (task.op == "install" or task.op == "upgrade" or not installed)
		if not install_like then
			write_json({ ok = false, error = i18n.translate("No install task is running") })
			return
		end

		local rc = sys.call("/etc/init.d/tasks task_del " .. task_id .. " >/dev/null 2>&1")
		if rc ~= 0 and task.pid ~= "" then
			sys.call("kill -TERM " .. util.shellquote(task.pid) .. " >/dev/null 2>&1")
			sys.call("sleep 1")
			sys.call("kill -KILL " .. util.shellquote(task.pid) .. " >/dev/null 2>&1")
			rc = sys.call("/etc/init.d/tasks task_del " .. task_id .. " >/dev/null 2>&1")
		end

		if rc == 0 or not get_task_state(task_id).running then
			sys.call("rm -rf /tmp/openclawmgr-installer.lock >/dev/null 2>&1")
			write_json({ ok = true, canceled = true, task_id = task_id })
			return
		end

		write_json({ ok = false, error = i18n.translate("Failed to stop installation"), task_id = task_id, pid = task.pid })
		return
	end

	if not fs.access("/etc/init.d/tasks") then
		-- fallback (shouldn't happen on iStoreOS with luci-lib-taskd installed)
		local cmd = script_path .. " " .. util.shellquote(op)
		sys.exec("( " .. cmd .. " ) >/dev/null 2>&1 &")
		write_json({ ok = true, queued = true, task_id = task_id, warning = "taskd missing; fallback to background exec" })
		return
	end

	local cmd = string.format("\"%s\" %s", script_path, op)
	local rc = sys.call("/etc/init.d/tasks task_add " .. task_id .. " " .. util.shellquote(cmd) .. " >/dev/null 2>&1")
	if rc == 0 then
		write_json({ ok = true, task_id = task_id })
		return
	end

	-- busy: try to report which task is running
	local running_task = ""
	if tasks and tasks.status then
		local all = tasks.status("") or {}
		for id, st in pairs(all) do
			if type(st) == "table" and st.running then
				running_task = id
				break
			end
		end
	end

	write_json({ ok = false, busy = true, task_id = task_id, running_task_id = running_task })
end

local function file_read(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local c = f:read("*a")
	f:close()
	return c
end

function action_diag_info()
	local sys = require "luci.sys"
	local util = require "luci.util"
	local uci = require "luci.model.uci".cursor()

	local base_dir = uci:get("openclawmgr", "main", "base_dir") or ""
	local port = uci:get("openclawmgr", "main", "port") or "18789"
	local bind = uci:get("openclawmgr", "main", "bind") or "lan"
	local enabled = uci:get("openclawmgr", "main", "enabled") or "0"

	if not port:match("^%d+$") then port = "18789" end

	local avail_mb = 0
	if base_dir ~= "" then
		local df_kb = sys.exec("df -kP " .. util.shellquote(base_dir) .. " 2>/dev/null | awk 'NR==2{print $4}'"):gsub("%s+", "")
		avail_mb = math.floor((tonumber(df_kb) or 0) / 1024)
	end

	local node_ver = ""
	local oc_ver = ""
	if base_dir ~= "" then
		node_ver = sys.exec("/usr/libexec/istorec/openclawmgr.sh node_version 2>/dev/null"):gsub("%s+$", "")
		oc_ver = sys.exec("/usr/libexec/istorec/openclawmgr.sh openclaw_version 2>/dev/null"):gsub("%s+$", "")
	end

	local has_node = false
	local has_openclaw = false
	local has_config = false
	if base_dir ~= "" then
		has_node = sys.call("[ -x " .. util.shellquote(base_dir .. "/node/bin/node") .. " ] >/dev/null 2>&1") == 0
		has_openclaw = sys.call("[ -x " .. util.shellquote(base_dir .. "/global/bin/openclaw") .. " ] >/dev/null 2>&1") == 0
		has_config = sys.call("[ -f " .. util.shellquote(base_dir .. "/data/.openclaw/openclaw.json") .. " ] >/dev/null 2>&1") == 0
	end

	local default_gw = sys.exec("ip route 2>/dev/null | awk '/^default/{print $3; exit}' 2>/dev/null"):gsub("%s+", "")

	local svc = util.ubus("service", "list", { name = "openclawmgr" })
	local pid = ""
	if type(svc) == "table" and type(svc.openclawmgr) == "table" and type(svc.openclawmgr.instances) == "table" then
		local inst = svc.openclawmgr.instances.gateway
		if type(inst) == "table" and inst.pid then
			pid = tostring(inst.pid)
		end
	end
	local running = pid ~= ""

	write_json({
		ok = true,
		base_dir = base_dir,
		available_mb = avail_mb,
		enabled = enabled,
		port = port,
		bind = bind,
		default_gw = default_gw,
		node_version = node_ver,
		openclaw_version = oc_ver,
		has_node = has_node,
		has_openclaw = has_openclaw,
		has_config = has_config,
		procd_pid = pid,
		running = running,
			url = (base_dir ~= "" and ("http://" .. get_host() .. ":" .. port .. configured_base_path(base_dir)) or ""),
		})
	end

function action_diag_run()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local util = require "luci.util"

	if not require_csrf() then
		return
	end

	local op = http.formvalue("op") or ""
	local limit = http.formvalue("limit") or ""
	local ok_ops = {
		doctor = true,
		gateway_status = true,
		gateway_health = true,
		logs = true,
		channels_status = true,
	}
	if not ok_ops[op] then
		write_json({ ok = false, error = "unknown op" })
		return
	end

	local cmd = "/usr/libexec/istorec/openclawmgr.sh diag " .. util.shellquote(op)
	if op == "logs" and limit:match("^%d+$") then
		cmd = cmd .. " " .. util.shellquote(limit)
	end

	sys.exec("( " .. cmd .. " ) >/dev/null 2>&1 &")
	write_json({ ok = true, queued = true })
end

function action_diag_poll()
	local http = require "luci.http"
	local sys = require "luci.sys"
	local util = require "luci.util"

	local op = http.formvalue("op") or ""
	local ok_ops = {
		doctor = true,
		gateway_status = true,
		gateway_health = true,
		logs = true,
		channels_status = true,
	}
	if not ok_ops[op] then
		write_json({ ok = false, error = "unknown op" })
		return
	end

	local st = sys.exec("/usr/libexec/istorec/openclawmgr.sh diag_poll " .. util.shellquote(op) .. " 2>/dev/null"):gsub("%s+$", "")

	local log = file_read("/tmp/openclawmgr-diag-" .. op .. ".log") or ""
	local exit_code = nil
	local state = "idle"
	if st == "running" then
		state = "running"
	elseif st:match("^done:") then
		state = "done"
		exit_code = tonumber(st:gsub("^done:", "")) or -1
	end

	write_json({
		ok = true,
		state = state,
		exit_code = exit_code,
		log = log,
	})
end
