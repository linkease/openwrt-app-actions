local m, s
local uci = luci.model.uci.cursor()
local sys = require 'luci.sys'
local docker = require "luci.model.docker"

m = SimpleForm("ubuntu", translate("ubuntu"), translate("Linkease-PC是为EasePi定制的一套Ubuntu系统。纯英文系统，欢迎各位极客玩家享用。默认<用户名:kasm_user  密码:password>")
.. translatef(" "
.. "<a href=\"%s\" target=\"_blank\">"
.. "访问官网</a>", "https://easepi.linkease.com/"))
m.submit=false
m.reset=false

s = m:section(SimpleSection)
s.template = "dockerman/apply_widget"
s.err = docker:read_status()
s.err = s.err and s.err:gsub("\n","<br>"):gsub(" ","&nbsp;")
if s.err then
	docker:clear_status()
end


s=m:section(SimpleSection)
s.template  = "ubuntu/ubuntu"


return m