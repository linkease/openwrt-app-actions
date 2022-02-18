local m, s
local uci = luci.model.uci.cursor()
local sys = require 'luci.sys'
local docker = require "luci.model.docker"

m = SimpleForm("ubuntu", translate("ubuntu"), translate("带Web远程桌面的Docker版Ubuntu。默认<用户名:kasm_user  密码:password>")
.. translatef(" "
.. "<a href=\"%s\" target=\"_blank\">"
.. "访问官网</a>", "https://www.kasmweb.com"))
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