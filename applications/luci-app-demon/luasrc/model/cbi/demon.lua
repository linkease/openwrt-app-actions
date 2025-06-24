--[[
LuCI - Lua Configuration Interface
]]--

local taskd = require "luci.model.tasks"
local demon_model = require "luci.model.demon"
local m, s, o

m = taskd.docker_map("demon", "demon", "/usr/libexec/istorec/demon.sh",
	translate("Onething Demon"),
	"「容器魔王」由网心云推出的一款 docker 容器镜像软件，通过在简单安装后即可快速加入网心云共享计算生态网络，用户可根据每日的贡献量获得相应的现金收益回报。了解更多，请登录「<a href=\"https://www.onethingcloud.com/\" target=\"_blank\" >网心云官网</a>」并查看<a href=\"https://doc.linkease.com/zh/guide/istoreos/software/demon.html\" target=\"_blank\">「教程」</a>")

s = m:section(SimpleSection, translate("Service Status"), translate("Onething Demon status:"), "注意容器魔王会以超级权限运行！")
s:append(Template("demon/status"))

s = m:section(TypedSection, "demon", translate("Setup"), translate("The following parameters will only take effect during installation or upgrade:"))
s.addremove=false
s.anonymous=true

o = s:option(Value, "port", translate("Port").."<b>*</b>")
o.default = "18888"
o.datatype = "port"

o = s:option(Value, "image_name", translate("Image").."<b>*</b>")
o.rmempty = false
o.datatype = "string"
o:value("images-cluster.xycloud.com/wxedge/amd64-wxedge:3.5.1-CTWXKS1748570956", "images-cluster.xycloud.com/wxedge/amd64-wxedge:3.5.1-CTWXKS1748570956")
o.default = "images-cluster.xycloud.com/wxedge/amd64-wxedge:3.5.1-CTWXKS1748570956"

local blks = demon_model.caches()
local dir
o = s:option(Value, "cache_path", translate("Cache path").."<b>*</b>", "请选择合适的存储位置进行安装，安装位置容量越大，收益越高。安装后请勿轻易改动")
o.rmempty = false
o.datatype = "string"
for _, dir in pairs(blks) do
	dir = dir
	o:value(dir, dir)
end
if #blks > 0 then
    o.default = blks[1]
end

return m
