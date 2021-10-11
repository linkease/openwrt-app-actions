module("luci.controller.jellyfin", package.seeall)

function index()
	
	entry({'admin', 'services', 'jellyfin'}, alias('admin', 'services', 'jellyfin', 'client'), _('Jellyfin'), 10).dependent = true -- 首页
	entry({"admin", "services", "jellyfin",'client'}, cbi("jellyfin/status", {hideresetbtn=true, hidesavebtn=true}), _("Jellyfin"), 20).leaf = true
    entry({'admin', 'services', 'jellyfin', 'script'}, form('jellyfin/script'), _('Script'), 20).leaf = true -- 直接配置脚本

	entry({"admin", "services", "jellyfin","status"}, call("container_status"))
	entry({"admin", "services", "jellyfin","stop"}, call("stop_container"))
	entry({"admin", "services", "jellyfin","start"}, call("start_container"))
	entry({"admin", "services", "jellyfin","install"}, call("install_container"))
	entry({"admin", "services", "jellyfin","uninstall"}, call("uninstall_container"))

end

local sys  = require "luci.sys"
local uci  = require "luci.model.uci".cursor()
local keyword  = "jellyfin"
local util  = require("luci.util")
local docker = require "luci.model.docker"

function container_status()
	local docker_path = util.exec("which docker")
	local docker_server_version = util.exec("docker info | grep 'Server Version'")
	local docker_install = (string.len(docker_path) > 0)
	local docker_start = (string.len(docker_server_version) > 0)
	local port = tonumber(uci:get_first(keyword, keyword, "port"))
	local container_id = util.trim(util.exec("docker ps -aqf'name='"..keyword.."''"))
	local container_install = (string.len(container_id) > 0)
	local container_running = (sys.call("pidof '"..keyword.."' >/dev/null") == 0)

	local status = {
		docker_install = docker_install,
		docker_start = docker_start,
		container_id = container_id,
		container_install = container_install,
		container_running = container_running,
		container_port = (port or 8096),
	}

	luci.http.prepare_content("application/json")
	luci.http.write_json(status)
	return status
end

function stop_container()
	local status = container_status()
	local container_id = status.container_id
	util.exec("docker stop '"..container_id.."'")
end

function start_container()
	local status = container_status()
	local container_id = status.container_id
	util.exec("docker start '"..container_id.."'")
end

function install_container()
	
	docker:write_status("jellyfin installing\n")
	local dk = docker.new()
	local images = dk.images:list().body
	local image = "jjm2473/jellyfin-rtk:v10.7"
	local pull_image = function(image)
		docker:append_status("Images: " .. "pulling" .. " " .. image .. "...\n")
		local res = dk.images:create({query = {fromImage=image}}, docker.pull_image_show_status_cb)
		if res and res.code and res.code == 200 and (res.body[#res.body] and not res.body[#res.body].error and res.body[#res.body].status and (res.body[#res.body].status == "Status: Downloaded newer image for ".. image or res.body[#res.body].status == "Status: Image is up to date for ".. image)) then
			docker:append_status("done\n")
		else
			res.code = (res.code == 200) and 500 or res.code
			docker:append_status("code:" .. res.code.." ".. (res.body[#res.body] and res.body[#res.body].error or (res.body.message or res.message)).. "\n")
		end
	end

	local install_jellyfin = function()
		local os   = require "os"
		local fs   = require "nixio.fs"
		local c = "sh /usr/share/jellyfin/install.sh >/tmp/log/jellyfin.stdout 2>/tmp/log/jellyfin.stderr"
		local r = os.execute(c)
		local e = fs.readfile("/tmp/log/jellyfin.stderr")
		local o = fs.readfile("/tmp/log/jellyfin.stdout")

		fs.unlink("/tmp/log/jellyfin.stderr")
		fs.unlink("/tmp/log/jellyfin.stdout")

		docker:append_status("r:\n" .. r .. "\n")
		if r == 0 then
			docker:write_status(o)
		else
			docker:write_status( e )
		end
	end

	local exist_image = false
	if image then
		for _, v in ipairs (images) do
			if v.RepoTags and v.RepoTags[1] == image then
				exist_image = true
				break
			end
		end
		if not exist_image then
			pull_image(image)
			install_jellyfin()
		else
			install_jellyfin()
		end
	end

end


function uninstall_container()
	local status = container_status()
	local container_id = status.container_id
	util.exec("docker container rm '"..container_id.."'")
end

-- 总结：
-- docker是否安装
-- 容器是否安装
-- 缺少在lua和htm中运行命令的方法
-- 获取容器id docker ps -aqf'name=jellyfin'
-- 启动容器 docker start 78a8455e6d38
-- 停止容器 docker stop 78a8455e6d38


--[[
todo
网络请求提示框
 --]]