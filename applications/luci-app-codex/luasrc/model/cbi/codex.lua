local m = Map("codex", translate("Codex"), translate("Run the OpenAI Codex CLI with a fixed mise runtime and a protected browser terminal."))
m:section(SimpleSection).template = "codex/status"

local s = m:section(NamedSection, "main", "codex", translate("Settings"))
s.addremove = false

local enabled = s:option(Flag, "enabled", translate("Enable browser terminal"))
enabled.rmempty = false

local model = require "luci.model.codex"
local paths, default_path = model.find_paths()
local data_dir = s:option(Value, "data_dir", translate("Data directory"))
data_dir.rmempty = false
data_dir.default = default_path
data_dir.description = translate("Stores the pinned Codex release, credentials and default workspace. Use a persistent disk; the package can require more than 500 MB.")
for _, path in ipairs(paths) do data_dir:value(path, path) end
function data_dir.validate(self, value)
	value = (value or ""):match("^%s*(.-)%s*$"):gsub("/+$", "")
	if not value:match("^/mnt/[^/]+/.+") or value:find("[%c:]") or value:find("//", 1, true) then
		return nil, translate("Select a normalized directory on a persistent disk.")
	end
	return value
end

local workspace = s:option(Value, "workspace_dir", translate("Workspace directory"))
workspace.rmempty = true
workspace.description = translate("Optional. Defaults to <data directory>/workspace. For another directory, assign it to the dedicated codex user first.")
function workspace.validate(self, value)
	value = (value or ""):match("^%s*(.-)%s*$"):gsub("/+$", "")
	if value == "" then return value end
	if not value:match("^/mnt/[^/]+/.+") or value:find("[%c:]") or value:find("//", 1, true) then
		return nil, translate("Workspace must be a normalized /mnt path.")
	end
	return value
end

local port = s:option(Value, "terminal_port", translate("Internal terminal port"))
port.default = "7683"
port.rmempty = false
port.datatype = "portrange(1025,65535)"
port.description = translate("ttyd listens on loopback only. Browser access goes through the authenticated application gateway.")

function m.on_after_commit()
	require("luci.sys").call("/etc/init.d/codex restart >/dev/null 2>&1")
end

return m
