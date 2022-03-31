local m, s
local uci = luci.model.uci.cursor()
local sys = require 'luci.sys'
local docker = require "luci.model.docker"

m = Map("Ubuntu")
m.title = translate("Ubuntu")
m.description = translate("<a href=\"https://github.com/messense/aliyundrive-webdav\" target=\"_blank\">Project GitHub URL</a>")
m.submit=false
m.reset=false

m:section(SimpleSection).template = "ubuntu/ubuntu_status"

s=m:section(SimpleSection)
s.template  = "ubuntu/ubuntu"

return m
