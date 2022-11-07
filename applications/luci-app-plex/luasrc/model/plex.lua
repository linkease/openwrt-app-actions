local util  = require "luci.util"
local jsonc = require "luci.jsonc"

local plex = {}

plex.blocks = function()
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

plex.home = function()
  local uci = require "luci.model.uci".cursor()
  local data = uci:get_first("linkease", "linkease", "local_home", "/root")
  return data
end

plex.find_paths = function(blocks, home, path_name)
  local default_path = ''
  local configs = {}
  if #blocks == 0 then
    default_path = home .. "/Programs/plex/" .. path_name
    table.insert(configs, default_path)
  else
    for _, val in pairs(blocks) do 
      table.insert(configs, val .. "/Programs/plex/" .. path_name)
    end
    default_path = configs[1]
  end

  return configs, default_path
end

plex.media_path = function(home)
  if home == "/root" then
    return ""
  else
    return home .. "/Downloads"
  end
end

return plex
