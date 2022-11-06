--[[
LuCI - Lua Configuration Interface
]]--

local taskd = require "luci.model.tasks"
local m, s, o

m = taskd.docker_map("plex", "plex", "/usr/libexec/istorec/plex.sh",
	translate("Plex"),
	translate("Plex is an elegant solution to organise all your web applications.")
		.. translate("Official website:") .. ' <a href=\"https://www.plex.tv/\" target=\"_blank\">https://www.plex.tv/</a>')

s = m:section(SimpleSection, translate("Service Status"), translate("Plex status:"))
s:append(Template("plex/status"))

s = m:section(TypedSection, "plex", translate("Setup"), translate("The following parameters will only take effect during installation or upgrade:"))
s.addremove=false
s.anonymous=true

o = s:option(Flag, "hostnet", translate("Host network"), translate("Plex running in host network, for DLNA application, port is always 32400 if enabled"))
o.default = 0
o.rmempty = false

o = s:option(Value, "claim_token", translate("Plex Claim").."<b>*</b>")
o.rmempty = false
o.datatype = "string"

o = s:option(Value, "port", translate("Port").."<b>*</b>")
o.rmempty = false
o.default = "32400"
o.datatype = "port"
o:depends("hostnet", 0)

o = s:option(Value, "config_path", translate("Config path").."<b>*</b>")
o.rmempty = false
o.datatype = "string"

o = s:option(Value, "media_path", translate("Media path"))
o.datatype = "string"

o = s:option(Value, "cache_path", translate("Transcode cache path"), translate("Default use 'transcodes' in 'config path' if not set, please make sure there has enough space"))
o.datatype = "string"

return m
