local sys  = require "luci.sys"
local uci  = require "luci.model.uci".cursor()
local util  = require "luci.util"
local http = require "luci.http"

module("luci.controller.wxedge", package.seeall)

function index()

  entry({"admin", "services", "wxedge"}, call("redirect_index"), _("网心云"), 30).dependent = true
  entry({"admin", "services", "wxedge", "pages"}, call("wxedge_index")).leaf = true
  entry({"admin", "services", "wxedge", "form"}, call("wxedge_form"))
  entry({"admin", "services", "wxedge", "submit"}, call("wxedge_submit"))
  entry({"admin", "services", "wxedge", "log"}, call("wxedge_log"))

end

local const_log_end = "XU6J03M6"
local appname = "wxedge"
local page_index = {"admin", "services", "wxedge", "pages"}

function redirect_index()
    http.redirect(luci.dispatcher.build_url(unpack(page_index)))
end

function wxedge_index()
    luci.template.render("wxedge/main", {prefix=luci.dispatcher.build_url(unpack(page_index))})
end

function wxedge_form()
    local sys  = require "luci.sys"
    local error = ""
    local scope = ""
    local success = 0

    local data = get_data()
    local result = {
        data = data,
        schema = get_schema(data)
    } 
    local response = {
            error = error,
            scope = scope,
            success = success,
            result = result,
    }
    http.prepare_content("application/json")
    http.write_json(response)
end

function get_schema(data)
    local actions = {
        {
            name = "install",
            text = "安装",
            type = "apply",
        },
        {
            name = "upgrade",
            text = "更新",
            type = "apply",
        },
        {
            name = "remove",
            text = "删除",
            type = "apply",
        },
    } 
    local schema = {
        actions = actions,
        containers = get_containers(data),
        description = "本插件能让设备快速加入网心云共享计算生态网络，为网心科技星域云贡献设备的上行带宽和存储资源，用户根据每日的贡献量可获得相应的现金收益回报。 具体请访问它的<a href=\"https://www.onethingcloud.com/\">官网</a>",
        title = "网心云"
    }
    return schema
end

function get_containers(data) 
    local containers = {
        status_container(data),
        main_container(data)
    }
    return containers
end

function status_container(data)
  local status_c1 = {
    labels = {
      {
        key = "状态：",
        value = "The wxedge service is not installed"
      },
      {
        key = "访问：",
        value = ""
        -- value = "'<a href=\"https://' + location.host + ':6901\" target=\"_blank\">Ubuntu 桌面</a>'"
      }

    },
    description = "注意网心云会以超级权限运行！",
    title = "服务状态"
  }
  return status_c1
end

function main_container(data)
    local main_c2 = {
        properties = {
          {
            name = "instance1",
            required = true,
            title = "实例1的存储位置：",
            type = "string",
            enum = {"standard", "full"},
            enumNames = {"Standard Version", "Full Version"}
          },
        },
        description = "请选择合适的存储位置进行安装：",
        title = "服务操作"
      }
      return main_c2
end

function get_data()
    local data = {
        port = "6901",
        password = "password",
        version = "standard"
    }
    return data
end

function wxedge_submit()
    local error = ""
    local scope = ""
    local success = 0
    local result
    
    local jsonc = require "luci.jsonc"
    local json_parse = jsonc.parse
    local content = http.content()
    local req = json_parse(content)
    if req["$apply"] == "upgrade" then
      result = install_upgrade_wxedge(req)
    elseif req["$apply"] == "install" then 
      result = install_upgrade_wxedge(req)
    elseif req["$apply"] == "restart" then 
      result = restart_wxedge(req)
    else
      result = delete_wxedge()
    end
    http.prepare_content("application/json")
    local resp = {
        error = error,
        scope = scope,
        success = success,
        result = result,
    }
    http.write_json(resp)
end

function wxedge_log()
  local fs   = require "nixio.fs"
  local ltn12 = require "luci.ltn12"
  local logfd = io.open("/var/log/wxedge.log", "r")
  local curr = logfd:seek()
  local size = logfd:seek("end")
  if size > 8*1024 then
    logfd:seek("end", -8*1024)
  else
    logfd:seek("set", curr)
  end

  local write_log = function()
    local buffer = logfd:read(4096)
    if buffer and #buffer > 0 then
        return buffer
    else
        logfd:close()
        return nil
    end
  end

  http.prepare_content("text/plain;charset=utf-8")

  if logfd then
    ltn12.pump.all(write_log, http.write)
  else
    http.write("log not found" .. const_log_end)
  end
end

function install_upgrade_wxedge(req)
  local password = req["password"]
  local port = req["port"]
  local version = req["version"]

  -- save config
  local uci = require "luci.model.uci".cursor()
  uci:tset(appname, "@"..appname.."[0]", {
    password = password or "password",
    port = port or "6901",
    version = version or "standard",
  })
  uci:save(appname)
  uci:commit(appname)

  -- local exec_cmd = string.format("start-stop-daemon -q -S -b -x /usr/share/wxedge/install.sh -- %s", req["$apply"])
  -- os.execute(exec_cmd)
  local exec_cmd = string.format("/usr/share/wxedge/install.sh %s", req["$apply"])
  fork_exec(exec_cmd)

  local result = {
    async = true,
    exec = exec_cmd,
    async_state = req["$apply"]
  }
  return result
end

function delete_wxedge()
  local f = io.popen("docker rm -f wxedge", "r")
  local log = "docker rm -f wxedge\n"
  if f then
    local output = f:read('*all')
    f:close()
    log = log .. output .. const_log_end
  else
    log = log .. "Failed" .. const_log_end
  end
  local result = {
    async = false,
    log = log
  }
  return result
end

function restart_wxedge()
  local f = io.popen("docker restart wxedge", "r")
  local log = "docker restart wxedge\n"
  if f then
    local output = f:read('*all')
    f:close()
    log = log .. output .. const_log_end
  else
    log = log .. "Failed" .. const_log_end
  end
  local result = {
    async = false,
    log = log
  }
  return result
end

function fork_exec(command)
	local pid = nixio.fork()
	if pid > 0 then
		return
	elseif pid == 0 then
		-- change to root dir
		nixio.chdir("/")

		-- patch stdin, out, err to /dev/null
		local null = nixio.open("/dev/null", "w+")
		if null then
			nixio.dup(null, nixio.stderr)
			nixio.dup(null, nixio.stdout)
			nixio.dup(null, nixio.stdin)
			if null:fileno() > 2 then
				null:close()
			end
		end

		-- replace with target command
		nixio.exec("/bin/sh", "-c", command)
	end
end
