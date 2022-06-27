local util  = require "luci.util"
local http = require "luci.http"
local iform = require "luci.iform"
local jsonc = require "luci.jsonc"

module("luci.controller.kodexplorer", package.seeall)

function index()

  entry({"admin", "services", "kodexplorer"}, call("redirect_index"), _("KodExplorer"), 30).dependent = true
  entry({"admin", "services", "kodexplorer", "pages"}, call("kodexplorer_index")).leaf = true
  entry({"admin", "services", "kodexplorer", "form"}, call("kodexplorer_form"))
  entry({"admin", "services", "kodexplorer", "submit"}, call("kodexplorer_submit"))
  entry({"admin", "services", "kodexplorer", "log"}, call("kodexplorer_log"))

end

local const_log_end = "XU6J03M6"
local appname = "kodexplorer"
local page_index = {"admin", "services", "kodexplorer", "pages"}

function redirect_index()
    http.redirect(luci.dispatcher.build_url(unpack(page_index)))
end

function kodexplorer_index()
    luci.template.render("kodexplorer/main", {prefix=luci.dispatcher.build_url(unpack(page_index))})
end

function kodexplorer_form()
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
  local _ = luci.i18n.translate
  local access = _('access homepage: ')
  local homepage = '<a href=\"https://kodcloud.com/\" target=\"_blank\">https://kodcloud.com/</a>'
  local schema = {
    actions = actions,
    containers = get_containers(data),
    description = _("Open source home automation that puts local control and privacy first. Powered by a worldwide community of tinkerers and DIY enthusiasts.")..access..homepage,
    title = _("KodExplorer")
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
    status_value = "KodExplorer 运行中"
  else
    status_value = "KodExplorer 未运行"
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
      }

    },
    description = "KodExplorer 的状态信息如下：",
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
          name = "cache_path",
          required = true,
          title = "存储位置：",
          type = "string",
          enum = dup_array(data.blocks),
          enumNames = dup_array(data.blocks)
        },
      },
      description = "请选择合适的存储位置进行安装：",
      title = "服务操作"
    }
    return main_c2
end

function get_data() 
  local uci = require "luci.model.uci".cursor()
  local default_path = ""
  local blks = blocks()
  if #blks > 0 then
    default_path = blks[1] .. "/kodexplorer"
  end
  local blk1 = {}
  for _, val in pairs(blks) do
    table.insert(blk1, val .. "/kodexplorer")
  end
  local docker_path = util.exec("which docker")
  local docker_install = (string.len(docker_path) > 0)
  local container_id = util.trim(util.exec("docker ps -aqf 'name="..appname.."'"))
  local container_install = (string.len(container_id) > 0)
  local port = tonumber(uci:get_first(appname, appname, "port", "8081"))
  local data = {
    port = port,
    cache_path = uci:get_first(appname, appname, "cache_path", ""),
    blocks = blk1,
    container_install = container_install
  }
  return data
end

function kodexplorer_submit()
    local error = ""
    local scope = ""
    local success = 0
    local result
    
    local json_parse = jsonc.parse
    local content = http.content()
    local req = json_parse(content)
    if req["$apply"] == "upgrade" then
      result = install_upgrade_kodexplorer(req)
    elseif req["$apply"] == "install" then 
      result = install_upgrade_kodexplorer(req)
    elseif req["$apply"] == "restart" then 
      result = restart_kodexplorer(req)
    else
      result = delete_kodexplorer()
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

function kodexplorer_log()
  iform.response_log("/var/log/"..appname..".log")
end

function install_upgrade_kodexplorer(req)
  local port = req["port"]
  local cache_path = req["cache_path"]

  -- save config
  local uci = require "luci.model.uci".cursor()
  uci:tset(appname, "@"..appname.."[0]", {
    cache_path = cache_path,
    port = port or "8081",
  })
  uci:save(appname)
  uci:commit(appname)

  local exec_cmd = string.format("/usr/share/kodexplorer/install.sh %s", req["$apply"])
  iform.fork_exec(exec_cmd)

  local result = {
    async = true,
    exec = exec_cmd,
    async_state = req["$apply"]
  }
  return result
end

function delete_kodexplorer()
  local log = iform.exec_to_log("docker rm -f kodexplorer")
  local result = {
    async = false,
    log = log
  }
  return result
end

function restart_kodexplorer()
  local log = iform.exec_to_log("docker restart kodexplorer")
  local result = {
    async = false,
    log = log
  }
  return result
end

function blocks()
  local f = io.popen("lsblk -s -f -b -o NAME,FSSIZE,MOUNTPOINT --json", "r")
  local vals = {}
  if f then
    local ret = f:read("*all")
    f:close()
    local obj = jsonc.parse(ret)
    for _, val in pairs(obj["blockdevices"]) do
      local fsize = val["fssize"]
      if string.len(fsize) > 10 and val["mountpoint"] then
        -- fsize > 1G
        vals[#vals+1] = val["mountpoint"]
      end
    end
  end
  return vals
end

function dup_array(a)
  local a2 = {}
  for _, val in pairs(a) do
    table.insert(a2, val)
  end
  return a2
end
