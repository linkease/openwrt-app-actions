local m, s
local uci = luci.model.uci.cursor()
local sys = require 'luci.sys'

m = Map("jellyfin", translate("Jellyfin"), translate("Jellyfin is the volunteer-built media solution that puts you in control of your media. Stream to any device from your own server, with no strings attached. Your media, your server, your way. ")
.. translatef("For further information "
.. "<a href=\"%s\" target=\"_blank\">"
.. "访问官网</a>", "https://jellyfin.org/"))

-- s = m:section(TypedSection, 'MySection', translate('基本设置'))
-- s.anonymous = true
-- o = s:option(DummyValue, '', '')
-- o.rawhtml = true
-- o.version = sys.exec('uci get jd-dailybonus.@global[0].version')
-- o.template = 'jellyfin/service'

m:section(SimpleSection).template  = "jellyfin/jellyfin"

-- s=m:section(TypedSection, "linkease", translate("Global settings"))
-- s.anonymous=true

-- s:option(Flag, "enabled", translate("Enable")).rmempty=false

-- s:option(Value, "port", translate("Port")).rmempty=false
return m