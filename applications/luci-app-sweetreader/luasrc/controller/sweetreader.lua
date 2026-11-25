-- SweetReader LuCI 控制器：在「服务」菜单下提供一个入口，跳转至书库 Web 界面。
module("luci.controller.sweetreader", package.seeall)

function index()
    entry({"admin", "services", "sweetreader"},
        template("sweetreader/main"),
        _("SweetReader 书库"), 60).dependent = false
    entry({"admin", "services", "sweetreader", "open"},
        call("action_open"), nil).dependent = false
end

function action_open()
    local uci = require("luci.model.uci").cursor()
    local port = uci:get("sweetreader", "main", "port") or "5000"
    local host = luci.http.getenv("HTTP_HOST") or "192.168.1.1"
    local ip = host:match("(%d+%.%d+%.%d+%.%d+)") or "192.168.1.1"
    luci.http.redirect("http://" .. ip .. ":" .. port .. "/")
end
