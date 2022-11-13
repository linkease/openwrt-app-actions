local util  = require "luci.util"
local http = require "luci.http"
local lng = require "luci.i18n"
local iform = require "luci.iform"

module("luci.controller.systools", package.seeall)

function index()

  entry({"admin", "services", "systools"}, call("redirect_index"), _("SysTools"), 30).dependent = true
  entry({"admin", "services", "systools", "pages"}, call("systools_index")).leaf = true
  entry({"admin", "services", "systools", "form"}, call("systools_form"))
  entry({"admin", "services", "systools", "submit"}, call("systools_submit"))

end

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
        text = lng.translate("Execute"),
        type = "apply",
    },
  }
  local schema = {
    actions = actions,
    containers = get_containers(data),
    description = lng.translate("SysTools can fix some errors when your system is broken."),
    title = lng.translate("SysTools")
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
        key = "访问：",                                                                                               
        value = "" 
      }
    },
    description = lng.translate("The running status"),
    title = lng.translate("Status")
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
            title = "可执行操作",
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
        description = lng.translate("Select the action to run:"),
        title = lng.translate("Actions")
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
    if req["$apply"] == "install" then
      result = install_execute_systools(req)
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

function install_execute_systools(req)
  local password = req["tool"]
  local port = req["server"]

  cmd = "/etc/init.d/tasks task_add systools " .. luci.util.shellquote(string.format("/usr/libexec/istorec/systools.sh %s", req["$apply"]))
  os.execute(cmd .. " >/dev/null 2>&1")

  local result = {
    async = true,
    async_state = "systools"
  }
  return result
end

