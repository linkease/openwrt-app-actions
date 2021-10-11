local m, s
local uci = luci.model.uci.cursor()
local sys = require 'luci.sys'
local docker = require "luci.model.docker"

m = SimpleForm("jellyfin", translate("Jellyfin"), translate("Jellyfin is the volunteer-built media solution that puts you in control of your media. Stream to any device from your own server, with no strings attached. Your media, your server, your way. ")
.. translatef("For further information "
.. "<a href=\"%s\" target=\"_blank\">"
.. "访问官网</a>", "https://jellyfin.org/"))
m.submit=false
m.reset=false

s = m:section(SimpleSection)
s.template = "dockerman/apply_widget"
s.err = docker:read_status()
s.err = s.err and s.err:gsub("\n","<br>"):gsub(" ","&nbsp;")
if s.err then
	docker:clear_status()
end

-- s = m:section(TypedSection, 'MySection', translate('基本设置'))
-- s.anonymous = true
-- o = s:option(DummyValue, '', '')
-- o.rawhtml = true
-- o.version = sys.exec('uci get jd-dailybonus.@global[0].version')
-- o.template = 'jellyfin/service'

s=m:section(SimpleSection)
s.template  = "jellyfin/jellyfin"

-- s=m:section(TypedSection, "linkease", translate("Global settings"))
-- s.anonymous=true

-- s:option(Flag, "enabled", translate("Enable")).rmempty=false

-- s:option(Value, "port", translate("Port")).rmempty=false



--下面学会怎么控制弹窗事件，如何判断提交按钮点击，在hml中如何调用model的方法。最后把命令输出显示到弹框上

-- 依次获取命令输出，结果太长无法显示完整，不能滚动
-- m.handle = function(self, state, data)
--     if state ~= FORM_VALID then
-- 		return
-- 	end
--     docker:clear_status()
--     docker:append_status(state .. "\n")
--     docker:append_status("done\n")
--     docker:append_status("done\n")
--     docker:append_status("done\n")
--     docker:append_status("done\n")
--     luci.http.redirect(luci.dispatcher.build_url("admin/services/jellyfin"))
-- end

return m