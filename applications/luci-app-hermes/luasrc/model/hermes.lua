local util  = require "luci.util"
local jsonc = require "luci.jsonc"

local hermes = {}

hermes.blocks = function()
  local f = io.popen("lsblk -s -f -b -o NAME,FSSIZE,MOUNTPOINT --json", "r")
  local vals = {}
  if f then
    local ret = f:read("*all")
    f:close()
    local obj = jsonc.parse(ret)
    if obj and obj["blockdevices"] then
      for _, val in pairs(obj["blockdevices"]) do
        local fsize = val["fssize"]
        if fsize ~= nil and string.len(fsize) > 10 and val["mountpoint"] then
          -- fsize > 1G
          vals[#vals+1] = val["mountpoint"]
        end
      end
    end
  end
  return vals
end

hermes.find_paths = function(blocks, subdir)
  local configs = {}
  local default_path = ''
  for _, mountpoint in pairs(blocks) do
    table.insert(configs, mountpoint .. "/hermes/" .. subdir)
  end
  if #configs > 0 then
    default_path = configs[1]
  end
  return configs, default_path
end

return hermes
