
module("luci.controller.codeserver", package.seeall)

function index()
  entry({"admin", "services", "codeserver"}, alias("admin", "services", "codeserver", "config"), _("CodeServer"), 30).dependent = true
  entry({"admin", "services", "codeserver", "config"}, cbi("codeserver"))
end
