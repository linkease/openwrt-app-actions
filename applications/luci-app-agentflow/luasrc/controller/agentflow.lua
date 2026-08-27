local http = require "luci.http"

module("luci.controller.agentflow", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/agentflow") then
		return
	end
	local page
	page = entry({"admin", "services", "agentflow"}, cbi("agentflow"), _("AgentFlow"), 100)
	page.dependent = true
	entry({"admin", "services", "agentflow_status"}, call("agentflow_status"))
end

function agentflow_status()
	local sys = require "luci.sys"
	local uci = require "luci.model.uci".cursor()
	local port = tonumber(uci:get_first("agentflow", "agentflow", "port")) or 3333
	if port < 1 or port > 65535 then
		port = 3333
	end
	local running = (sys.call("pidof agentflow >/dev/null") == 0)
	local status = {
		running = running,
		port = port
	}
	http.prepare_content("application/json")
	http.write_json(status)
end
