local util  = require "luci.util"
local http = require "luci.http"
local docker = require "luci.model.docker"
local iform = require "luci.iform"

module("luci.controller.systools", package.seeall)

function index()

  entry({"admin", "services", "systools"}, call("redirect_index"), _("SysTools"), 30).dependent = true
  entry({"admin", "services", "systools", "pages"}, call("systools_index")).leaf = true
  entry({"admin", "services", "systools", "form"}, call("systools_form"))
  entry({"admin", "services", "systools", "submit"}, call("systools_submit"))
  entry({"admin", "services", "systools", "log"}, call("systools_log"))

end

local const_log_end = "XU6J03M6"
local appname = "systools"
local page_index = {"admin", "services", "systools", "pages"}

function redirect_index()
    http.redirect(luci.dispatcher.build_url(unpack(page_index)))
end

function systools_index()
    luci.template.render("systools/main", {prefix=luci.dispatcher.build_url(unpack(page_index))})
end

function systools_form()
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
  actions = {
    {
        name = "install",
        text = "安装",
        type = "apply",
    },
  }
  local schema = {
    actions = actions,
    containers = get_containers(data),
    description = "带 Web 远程桌面的 Docker 高性能版 SysTools。默认<用户名:kasm_user 密码:password> 访问官网 <a href=\"https://www.kasmweb.com/\" target=\"_blank\">https://www.kasmweb.com/</a>",
    title = "SysTools"
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
  status_value = "SysTools 未运行"
  local status_c1 = {
    labels = {
      {
        key = "状态：",
        value = status_value
      },
      {
        key = "访问：",
        value = ""
        -- value = "'<a href=\"https://' + location.host + ':6901\" target=\"_blank\">SysTools 桌面</a>'"
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
            name = "testName",
            required = true,
            title = "测试变化",
            type = "string",
            enum = {"test1", "test2"},
            enumNames = {"Test1", "Test2"}
          },
          {
            name = "tool",
            required = true,
            title = "安装版本",
            type = "string",
            enum = {"speedtest", "reset_rom"},
            enumNames = {"网络测速", "恢复系统软件包"}
          },
          {
            name = "server",
            title = "Servers",
            type = "string",
            ["ui:hidden"] = "{{rootValue.tool !== 'speedtest' }}",
            enum = {"server1", "server2"},
            enumNames = {"ServerTest1", "ServerTest2"}
          },
        },
        description = "请选择合适的版本进行安装：",
        title = "服务操作"
      }
      return main_c2
end

function get_data() 
  local data = {
    testName = 'test1',
    tool = "reset_rom",
  }
  return data
end

function systools_submit()
    local error = ""
    local scope = ""
    local success = 0
    local result
    
    local jsonc = require "luci.jsonc"
    local json_parse = jsonc.parse
    local content = http.content()
    local req = json_parse(content)
    if req["$apply"] == "upgrade" then
      result = install_upgrade_systools(req)
    elseif req["$apply"] == "install" then 
      result = install_upgrade_systools(req)
    elseif req["$apply"] == "restart" then 
      result = restart_systools(req)
    else
      result = delete_systools()
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

function systools_log()
  iform.response_log("/var/log/"..appname..".log")
end

function install_upgrade_systools(req)
  local password = req["tool"]
  local port = req["server"]

  local exec_cmd = string.format("/usr/share/systools/install.sh %s", req["$apply"])
  iform.fork_exec(exec_cmd)

  local result = {
    async = true,
    exec = exec_cmd,
    async_state = req["$apply"]
  }
  return result
end

function delete_systools()
  local log = iform.exec_to_log("docker rm -f systools")
  local result = {
    async = false,
    log = log
  }
  return result
end

function restart_systools()
  local log = iform.exec_to_log("docker restart systools")
  local result = {
    async = false,
    log = log
  }
  return result
end

