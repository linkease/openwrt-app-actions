module("luci.controller.hermes", package.seeall)

function index()
  entry({"admin", "services", "hermes"}, alias("admin", "services", "hermes", "config"), _("Hermes"), 30).dependent = true
  entry({"admin", "services", "hermes", "config"}, cbi("hermes"))
end
