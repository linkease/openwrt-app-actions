module("luci.controller.jellyfin", package.seeall)

function index()

	entry({'admin', 'services', 'jellyfin'}, alias('admin', 'services', 'jellyfin', 'client'), _('Jellyfin'), 10)
	entry({"admin", "services", "jellyfin",'client'}, cbi("jellyfin/status"), nil).leaf = true

	entry({"admin", "services", "jellyfin","status"}, call("get_container_status"))
	entry({"admin", "services", "jellyfin","stop"}, post("stop_container"))
	entry({"admin", "services", "jellyfin","start"}, post("start_container"))
	entry({"admin", "services", "jellyfin","install"}, post("install_container"))
	entry({"admin", "services", "jellyfin","uninstall"}, post("uninstall_container"))

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
	local port = tonumber(uci:get_first(keyword, keyword, "port", "8096"))
	local container_id = util.trim(util.exec("docker ps -aqf 'name="..keyword.."'"))
	local container_install = (string.len(container_id) > 0)
	local container_running = container_install and (string.len(util.trim(util.exec("docker ps -qf 'id="..container_id.."'"))) > 0)

	local status = {
		docker_install = docker_install,
		docker_start = docker_start,
		container_id = container_id,
		container_install = container_install,
		container_running = container_running,
		container_port = (port or 8096),
		media_path = uci:get_first(keyword, keyword, "media_path", ""),
		config_path = uci:get_first(keyword, keyword, "config_path", "/root/jellyfin/config"),
		cache_path = uci:get_first(keyword, keyword, "cache_path", ""),
	}

	return status
end

function get_container_status()
	local status = container_status()
	luci.http.prepare_content("application/json")
	luci.http.write_json(status)
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

	local image = util.exec("sh /usr/share/jellyfin/install.sh -l") 
	local media_path = luci.http.formvalue("media")
	local config_path = luci.http.formvalue("config")
	local cache_path = luci.http.formvalue("cache")
	local port = luci.http.formvalue("port")

	uci:tset(keyword, "@"..keyword.."[0]", {
		media_path = media_path or "",
		config_path = config_path or "/root/jellyfin/config",
		cache_path = cache_path or "",
		port = port or "8096",
	})
	uci:save(keyword)
	uci:commit(keyword)

	local pull_image = function(image)
		docker:append_status("Images: " .. "pulling" .. " " .. image .. "...\n")
		local dk = docker.new()
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
		local c = ("sh /usr/share/jellyfin/install.sh -i >/var/log/jellyfin.stdout 2>/var/log/jellyfin.stderr")
		-- docker:append_status(c)

		local r = os.execute(c)
		local e = fs.readfile("/var/log/jellyfin.stderr")
		local o = fs.readfile("/var/log/jellyfin.stdout")

		fs.unlink("/var/log/jellyfin.stderr")
		fs.unlink("/var/log/jellyfin.stdout")

		if r == 0 then
			docker:append_status(o)
		else
			docker:append_status( e )
		end
	end

	-- local status = {
	-- 	shell = shell,
	-- 	image_name = image,
	-- }
	-- luci.http.prepare_content("application/json")
	-- luci.http.write_json(status)

	if image then
		docker:write_status("jellyfin installing\n")
		pull_image(image)
		install_jellyfin()
	else
		docker:write_status("jellyfin image not defined!\n")
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
