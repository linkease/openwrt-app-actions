local m, s
local uci = luci.model.uci.cursor()
local sys = require 'luci.sys'
local docker = require "luci.model.docker"

m = SimpleForm("wxedge", translate("网心云"), translate("「容器魔方」由网心云推出的一款docker容器镜像软件，通过简单安装后即可快速加入网心云共享计算生态网络，为网心科技星域云贡献带宽和存储资源，用户根据每日的贡献量可获得相应的现金收益回报")
.. translatef(" "
.. "<a href=\"%s\" target=\"_blank\">"
.. "访问官网</a>", "https://www.onethingcloud.com/"))
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
s.template  = "wxedge/wxedge"


return m