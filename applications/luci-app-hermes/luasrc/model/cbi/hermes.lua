--[[
LuCI - Lua Configuration Interface
]]--

local taskd = require "luci.model.tasks"
local hermes_model = require "luci.model.hermes"
local m, s, o

m = taskd.docker_map("hermes", "hermes", "/usr/libexec/istorec/hermes.sh",
	translate("Hermes"),
	translate("The self-improving AI agent that runs on your server. Layered memory that accumulates across sessions, a cron scheduler that fires while you're offline, and a skills system that saves reusable procedures automatically.")
		.. translate("Official website:") .. ' <a href=\"https://get-hermes.ai/\" target=\"_blank\">https://get-hermes.ai/</a>')

s = m:section(SimpleSection, translate("Service Status"), translate("Hermes status:"))
s:append(Template("hermes/status"))

s = m:section(TypedSection, "main", translate("Setup"), translate("The following parameters will only take effect during installation or upgrade:"))
s.addremove = false
s.anonymous = true

o = s:option(Value, "port", translate("Port") .. "<b>*</b>")
o.default = "8787"
o.datatype = "port"

local blocks = hermes_model.blocks()

o = s:option(Value, "data_path", translate("Data path") .. "<b>*</b>")
o.rmempty = false
o.datatype = "string"
local data_paths, data_default = hermes_model.find_paths(blocks, "data")
for _, val in pairs(data_paths) do
  o:value(val, val)
end
o.default = data_default

o = s:option(Value, "workspace_path", translate("Workspace path") .. "<b>*</b>")
o.rmempty = false
o.datatype = "string"
local ws_paths, ws_default = hermes_model.find_paths(blocks, "workspace")
for _, val in pairs(ws_paths) do
  o:value(val, val)
end
o.default = ws_default

return m
