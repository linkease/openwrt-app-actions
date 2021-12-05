module("luci.controller.wxedge", package.seeall)

function index()

	entry({'admin', 'services', 'wxedge'}, alias('admin', 'services', 'wxedge', 'client'), _('wxedge'), 10)
	entry({"admin", "services", "wxedge",'client'}, cbi("wxedge/status"), nil).leaf = true

	entry({"admin", "services", "wxedge","status"}, call("get_container_status"))
	entry({"admin", "services", "wxedge","stop"}, post("stop_container"))
	entry({"admin", "services", "wxedge","start"}, post("start_container"))
	entry({"admin", "services", "wxedge","install"}, post("install_container"))
	entry({"admin", "services", "wxedge","uninstall"}, post("uninstall_container"))

end

local sys  = require "luci.sys"
local uci  = require "luci.model.uci".cursor()
local keyword  = "wxedge"
local util  = require("luci.util")
local docker = require "luci.model.docker"

function container_status()
	local docker_path = util.exec("which docker")
	local docker_install = (string.len(docker_path) > 0)
	local docker_running = util.exec("ps | grep dockerd | grep -v 'grep' | wc -l")
	local container_id = util.trim(util.exec("docker ps -aqf 'name="..keyword.."'"))
	local container_install = (string.len(container_id) > 0)
	local container_running = container_install and (string.len(util.trim(util.exec("docker ps -qf 'id="..container_id.."'"))) > 0)

	local status = {
		docker_install = docker_install,
		docker_start = docker_running,
		container_id = container_id,
		container_port = (18888),
		container_install = container_install,
		container_running = container_running,
		cache_path = uci:get_first(keyword, keyword, "cache_path", "/wxedge"),
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

	local image = util.exec("sh /usr/share/wxedge/install.sh -l") 
	local cache_path = luci.http.formvalue("cache")

	uci:tset(keyword, "@"..keyword.."[0]", {
		cache_path = cache_path or "/wxedge",
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

	local install_wxedge = function()
		local os   = require "os"
		local fs   = require "nixio.fs"
		local c = ("sh /usr/share/wxedge/install.sh -i >/var/log/wxedge.stdout 2>/var/log/wxedge.stderr")
		-- docker:append_status(c)

		local r = os.execute(c)
		local e = fs.readfile("/var/log/wxedge.stderr")
		local o = fs.readfile("/var/log/wxedge.stdout")

		fs.unlink("/var/log/wxedge.stderr")
		fs.unlink("/var/log/wxedge.stdout")

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
		docker:write_status("wxedge installing\n")
		pull_image(image)
		install_wxedge()
	else
		docker:write_status("wxedge image not defined!\n")
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
-- 获取容器id docker ps -aqf'name=wxedge'
-- 启动容器 docker start 78a8455e6d38
-- 停止容器 docker stop 78a8455e6d38


--[[
todo
网络请求提示框
 --]]