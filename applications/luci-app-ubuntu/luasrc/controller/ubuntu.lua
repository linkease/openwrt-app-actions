local sys  = require "luci.sys"
local util  = require "luci.util"
local http = require "luci.http"
local docker = require "luci.model.docker"

module("luci.controller.ubuntu", package.seeall)

function index()

  entry({"admin", "services", "ubuntu"}, call("redirect_index"), _("Ubuntu"), 30).dependent = true
  entry({"admin", "services", "ubuntu", "pages"}, call("ubuntu_index")).leaf = true
  if nixio.fs.access("/usr/lib/lua/luci/view/ubuntu/main_dev.htm") then 
    entry({"admin","services", "ubuntu", "dev"}, call("ubuntu_dev")).leaf = true 
  end 
  
  entry({"admin", "services", "ubuntu", "form"}, call("ubuntu_form"))
  entry({"admin", "services", "ubuntu", "submit"}, call("ubuntu_submit"))
  entry({"admin", "services", "ubuntu", "log"}, call("ubuntu_log"))

end

local const_log_end = "XU6J03M6"
local appname = "ubuntu"
local page_index = {"admin", "services", "ubuntu", "pages"}

function redirect_index()
    http.redirect(luci.dispatcher.build_url(unpack(page_index)))
end

function ubuntu_index()
    luci.template.render("ubuntu/main", {prefix=luci.dispatcher.build_url(unpack(page_index))})
end

function ubuntu_dev()
    luci.template.render("ubuntu/main_dev", {prefix=luci.dispatcher.build_url(unpack({"admin", "services", "ubuntu", "dev"}))})
end

function ubuntu_form()
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
  local actions
  if data.container_install then
    actions = {
      {
          name = "restart",
          text = "重启",
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
  else
    actions = {
      {
          name = "install",
          text = "安装",
          type = "apply",
      },
    }
  end
    local schema = {
      actions = actions,
      containers = get_containers(data),
      description = "带 Web 远程桌面的 Docker 高性能版 Ubuntu。默认<用户名:kasm_user 密码:password> 访问官网 <a href=\"https://www.kasmweb.com/\" target=\"_blank\">https://www.kasmweb.com/</a>",
      title = "Ubuntu"
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
  local status_value

  if data.container_install then
    status_value = "Ubuntu 运行中"
  else
    status_value = "Ubuntu 未运行"
  end

  local status_c1 = {
    labels = {
      {
        key = "状态：",
        value = status_value
      },
      {
        key = "访问：",
        value = ""
        -- value = "'<a href=\"https://' + location.host + ':6901\" target=\"_blank\">Ubuntu 桌面</a>'"
      }

    },
    description = "访问链接是一个自签名的 https，需要浏览器同意才能访问！",
    title = "服务状态"
  }
  return status_c1
end

function main_container(data)
    local main_c2 = {
        properties = {
          {
            name = "port",
            required = true,
            title = "端口",
            type = "string"
          },
          {
            name = "password",
            required = true,
            title = "密码",
            type = "string"
          },
          {
            name = "version",
            required = true,
            title = "安装版本",
            type = "string",
            enum = {"standard", "full"},
            enumNames = {"Standard Version", "Full Version"}
          },
        },
        description = "请选择合适的版本进行安装：",
        title = "服务操作"
      }
      return main_c2
end

function get_data() 
  local uci = require "luci.model.uci".cursor()
  local docker_path = util.exec("which docker")
  local docker_install = (string.len(docker_path) > 0)
  local container_id = util.trim(util.exec("docker ps -aqf 'name="..appname.."'"))
  local container_install = (string.len(container_id) > 0)
  local port = tonumber(uci:get_first(appname, appname, "port", "6901"))
  local data = {
    port = port,
    user_name = "kasm_user",
    password = uci:get_first(appname, appname, "password", ""),
    version = uci:get_first(appname, appname, "version", "standard"),
    container_install = container_install
  }
  return data
end

function ubuntu_submit()
    local error = ""
    local scope = ""
    local success = 0
    local result
    
    local jsonc = require "luci.jsonc"
    local json_parse = jsonc.parse
    local content = http.content()
    local req = json_parse(content)
    if req["$apply"] == "upgrade" then
      result = install_upgrade_ubuntu(req)
    elseif req["$apply"] == "install" then 
      result = install_upgrade_ubuntu(req)
    elseif req["$apply"] == "restart" then 
      result = restart_ubuntu(req)
    else
      result = delete_ubuntu()
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

function ubuntu_log()
  local fs   = require "nixio.fs"
  local ltn12 = require "luci.ltn12"
  local logfd = io.open("/var/log/ubuntu.log", "r")
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

function install_upgrade_ubuntu(req)
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

  -- local exec_cmd = string.format("start-stop-daemon -q -S -b -x /usr/share/ubuntu/install.sh -- %s", req["$apply"])
  -- os.execute(exec_cmd)
  local exec_cmd = string.format("/usr/share/ubuntu/install.sh %s", req["$apply"])
  fork_exec(exec_cmd)

  local result = {
    async = true,
    exec = exec_cmd,
    async_state = req["$apply"]
  }
  return result
end

function delete_ubuntu()
  local f = io.popen("docker rm -f ubuntu", "r")
  local log = "docker rm -f ubuntu\n"
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

function restart_ubuntu()
  local f = io.popen("docker restart ubuntu", "r")
  local log = "docker restart ubuntu\n"
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
