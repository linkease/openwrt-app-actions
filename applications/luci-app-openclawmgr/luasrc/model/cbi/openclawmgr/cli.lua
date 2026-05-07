--[[
LuCI - Lua Configuration Interface
]]--

require "luci.util"

local uci = require "luci.model.uci".cursor()

local m, s, o

local cmd_ttyd = luci.util.exec("command -v ttyd"):match("^.+ttyd") or nil
local base_dir = uci:get("openclawmgr", "main", "base_dir") or ""

m = SimpleForm("OpenClawCLI", "", translate("Only works in LAN"))
m.submit = false
m.reset = false

if not cmd_ttyd or cmd_ttyd:match("^%s*$") then
	s = m:section(SimpleSection, nil, translate("ttyd not found"))
	return m
end

if base_dir == "" then
	s = m:section(SimpleSection, nil, translate("base_dir is not configured"))
	return m
end

local node_dir = base_dir .. "/node"
local global_dir = base_dir .. "/global"
local data_dir = base_dir .. "/data"

s = m:section(SimpleSection)

o = s:option(Value, "mode", translate("Mode"))
o:value("cli-env", translate("CLI终端 (仅注入环境)"))
o:value("configure", translate("官方配置向导 (openclaw configure)"))
o:value("backup", translate("备份配置"))
o:value("restore", translate("恢复配置"))
o.default = "cli-env"
o.forcewrite = true

o = s:option(DummyValue, "_tip", translate("CLI终端"))
o.rawhtml = true
o.cfgvalue = function()
	return translate("Starts a web terminal (LAN only) for common OpenClaw maintenance tasks.")
end

local function start_ttyd(action)
	local cmd_ttyd = luci.util.exec("command -v ttyd"):match("^.+ttyd") or nil
	if not cmd_ttyd or cmd_ttyd:match("^%s*$") then
		return
	end

	local pid = luci.util.trim(luci.util.exec("netstat -lnpt | grep :7682 | grep ttyd | tr -s ' ' | cut -d ' ' -f7 | cut -d'/' -f1"))
	if pid and pid:match("^%d+$") then
		luci.util.exec("kill -9 " .. pid)
	end

	local current_path = os.getenv("PATH") or "/usr/sbin:/usr/bin:/sbin:/bin"
	local env_path = node_dir .. "/bin:" .. global_dir .. "/bin:" .. current_path
	local env_prefix = table.concat({
		"BASE_DIR=" .. luci.util.shellquote(base_dir),
		"NODE_DIR=" .. luci.util.shellquote(node_dir),
		"GLOBAL_DIR=" .. luci.util.shellquote(global_dir),
		"DATA_DIR=" .. luci.util.shellquote(data_dir),
		"HOME=" .. luci.util.shellquote(data_dir),
		"OPENCLAW_HOME=" .. luci.util.shellquote(data_dir),
		"OPENCLAW_STATE_DIR=" .. luci.util.shellquote(data_dir .. "/.openclaw"),
		"OPENCLAW_CONFIG_PATH=" .. luci.util.shellquote(data_dir .. "/.openclaw/openclaw.json"),
		"PATH=" .. luci.util.shellquote(env_path),
	}, " ")

	local cmdline = "sh /usr/share/openclawmgr/openclawmgr-cli.sh " .. luci.util.shellquote(action)
	local start_cmd = string.format(
		"%s %s -d 2 --once -p 7682 sh -lc %s &",
		env_prefix,
		cmd_ttyd,
		luci.util.shellquote(cmdline)
	)
	os.execute(start_cmd)

	m.children[#m.children] = nil
	s = m:section(SimpleSection)
	o = s:option(DummyValue, "console")
	o.template = "openclawmgr/cli"
end

o = s:option(Button, "connect")
o.render = function(self, section, scope)
	self.inputstyle = "add"
	self.title = " "
	self.inputtitle = translate("Connect")
	Button.render(self, section, scope)
end
o.write = function(self, section)
	local mode = m:formvalue("mode") or m:formvalue("cbid.OpenClawCLI.1.mode") or "configure"
	if mode ~= "configure" and mode ~= "cli-env" and mode ~= "backup" and mode ~= "restore" then
		mode = "configure"
	end
	start_ttyd(mode)
end

return m
