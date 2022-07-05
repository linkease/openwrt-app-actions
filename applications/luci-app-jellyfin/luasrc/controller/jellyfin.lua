local util  = require "luci.util"
local http = require "luci.http"
local iform = require "luci.iform"
local jsonc = require "luci.jsonc"

module("luci.controller.jellyfin", package.seeall)

function index()

  entry({"admin", "services", "jellyfin"}, call("redirect_index"), _("Jellyfin"), 30).dependent = true
  entry({"admin", "services", "jellyfin", "pages"}, call("jellyfin_index")).leaf = true
  entry({"admin", "services", "jellyfin", "form"}, call("jellyfin_form"))
  entry({"admin", "services", "jellyfin", "submit"}, call("jellyfin_submit"))
  entry({"admin", "services", "jellyfin", "log"}, call("jellyfin_log"))

end

local const_log_end = "XU6J03M6"
local appname = "jellyfin"
local page_index = {"admin", "services", "jellyfin", "pages"}

function redirect_index()
    http.redirect(luci.dispatcher.build_url(unpack(page_index)))
end

function jellyfin_index()
    luci.template.render("jellyfin/main", {prefix=luci.dispatcher.build_url(unpack(page_index))})
end

function jellyfin_form()
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
  local homepage = '<a href=\"https://jellyfin.org/\" target=\"_blank\">https://jellyfin.org/</a>'
  local schema = {
    actions = actions,
    containers = get_containers(data),
    description = _("Jellyfin is the volunteer-built media solution that puts you in control of your media. Stream to any device from your own server, with no strings attached. Your media, your server, your way.")..access..homepage,
    title = _("Jellyfin")
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
    status_value = "Jellyfin 运行中"
  else
    status_value = "Jellyfin 未运行"
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
    description = "Jellyfin 的状态信息如下：",
    title = "服务状态"
  }
  return status_c1
end

function main_container(data)
  local _ = luci.i18n.translate
  local main_c2 = {
      properties = {
        {
          name = "hostnet",
          required = true,
          title = _("Host network"),
          type = "boolean",
          ["ui:options"] = {
            description = _("Jellyfin running in host network, for DLNA application, port is always 8096 if enabled")
          },
        },
        {
          name = "port",
          required = true,
          title = _("Port"),
          type = "string",
          ["ui:hidden"] = "{{rootValue.hostnet == '1'}}",
        },
        {
          name = "media_path",
          title = _("Media path"),
          type = "string",
        },
        {
          name = "config_path",
          required = true,
          title = _("Config path"),
          type = "string",
        },
        {
          name = "cache_path",
          title = _("Transcode cache path"),
          type = "string",
          ["ui:options"] = {
            description = _("Default use 'transcodes' in 'config path' if not set, please make sure there has enough space")
          },
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
    default_path = blks[1] .. "/jellyfin"
  end
  local blk1 = {}
  for _, val in pairs(blks) do
    table.insert(blk1, val .. "/jellyfin")
  end
  local docker_path = util.exec("which docker")
  local docker_install = (string.len(docker_path) > 0)
  local container_id = util.trim(util.exec("docker ps -qf 'name="..appname.."'"))
  local container_install = (string.len(container_id) > 0)
  local port = tonumber(uci:get_first(appname, appname, "port", "8096"))
  local data = {
    hostnet = uci:get_first(appname, appname, "hostnet", "0") == "1" and true or false,
    port = port,
    cache_path = uci:get_first(appname, appname, "cache_path", ""),
    media_path = uci:get_first(appname, appname, "media_path", ""),
    config_path = uci:get_first(appname, appname, "config_path", ""),
    blocks = blk1,
    container_install = container_install
  }
  return data
end

function jellyfin_submit()
    local error = ""
    local scope = ""
    local success = 0
    local result
    
    local json_parse = jsonc.parse
    local content = http.content()
    local req = json_parse(content)
    if req["$apply"] == "upgrade" then
      result = install_upgrade_jellyfin(req)
    elseif req["$apply"] == "install" then 
      result = install_upgrade_jellyfin(req)
    elseif req["$apply"] == "restart" then 
      result = restart_jellyfin(req)
    else
      result = delete_jellyfin()
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

function jellyfin_log()
  iform.response_log("/var/log/"..appname..".log")
end

function install_upgrade_jellyfin(req)
  local port = req["port"]

  -- save config
  local uci = require "luci.model.uci".cursor()
  uci:tset(appname, "@"..appname.."[0]", {
    hostnet = req["hostnet"] and 1 or 0,
    port = port or "",
    media_path = req["media_path"],
    config_path = req["config_path"],
    cache_path = req["cache_path"],
  })
  uci:save(appname)
  uci:commit(appname)

  local exec_cmd = string.format("/usr/share/jellyfin/install.sh %s", req["$apply"])
  iform.fork_exec(exec_cmd)

  local result = {
    async = true,
    exec = exec_cmd,
    async_state = req["$apply"]
  }
  return result
end

function delete_jellyfin()
  local log = iform.exec_to_log("docker rm -f jellyfin")
  local result = {
    async = false,
    log = log
  }
  return result
end

function restart_jellyfin()
  local log = iform.exec_to_log("docker restart jellyfin")
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
      if fsize ~= nil and string.len(fsize) > 10 and val["mountpoint"] then
        -- fsize > 1G
        vals[#vals+1] = val["mountpoint"]
      end
    end
  end
  return vals
end

