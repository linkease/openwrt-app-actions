module("luci.controller.qiyougamebooster", package.seeall)

function index()
	local page = entry(
		{"admin", "services", "qiyougamebooster"},
		cbi("qiyougamebooster"),
		("Qiyou Game Booster"), 99)
	page.dependent = false
	page.acl_depends = {"luci-app-qiyougamebooster"}
end
