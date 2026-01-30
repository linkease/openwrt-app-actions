local sys = require("luci.sys")

local m = Map("qiyougamebooster",
	translate("Qiyou Game Booster"),
		translate("Play console games online with less lag and more stability.")
		 .. "<br />"
		 .. translate("— now supporting PS, Switch, Xbox, PC, and mobile."))

local s = m:section(TypedSection, "qiyougamebooster")
s.anonymous = true
s.addremove = false

local sts = sys.exec("qiyougamebooster.sh status 2> /dev/null")
local ver = sys.exec("qiyougamebooster.sh version 2> /dev/null")
local status = s:option(DummyValue, "status")
status.rawhtml = true
status.value = "<p style='color:green'><strong>"
	.. translate("Status") .. ": " .. ver .. " " .. translate(sts)
	.. "</strong></p>"

local switch = s:option(Flag, "enable", translate("Enable"))
switch.default = 0

local instructions = s:option(DummyValue, "instructions")
instructions.rawhtml = true
instructions.value = "<p><img src='/qiyougamebooster.png' height='300'/></p>"

return m
