local m, s
local uci = luci.model.uci.cursor()
local sys = require 'luci.sys'
local docker = require "luci.model.docker"

m = SimpleForm("kodexplorer", translate("kodexplorer"), translate("KodExplorer是一款快捷高效的私有云和在线文档管理系统，为个人网站、企业私有云部署、网络存储、在线文档管理、在线办公等提供安全可控，简便易用、可高度定制的私有云产品。采用windows风格界面、操作习惯，无需适应即可快速上手，支持几百种常用文件格式的在线预览，可扩展易定制。")
.. translatef(" "
.. "<a href=\"%s\" target=\"_blank\">"
.. "访问官网</a>", "https://kodcloud.com"))
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
s.template  = "kodexplorer/kodexplorer"


return m