module("luci.controller.ubuntu", package.seeall)

function index()

	entry({'admin', 'services', 'ubuntu'}, alias('admin', 'services', 'ubuntu', 'client'), _('Ubuntu'), 10)
	entry({"admin", "services", "ubuntu",'client'}, cbi("ubuntu/status"), nil).leaf = true

	entry({"admin", "services", "ubuntu","status"}, call("get_container_status"))
	entry({"admin", "services", "ubuntu","stop"}, post("stop_container"))
	entry({"admin", "services", "ubuntu","start"}, post("start_container"))
	entry({"admin", "services", "ubuntu","install"}, post("install_container"))
	entry({"admin", "services", "ubuntu","uninstall"}, post("uninstall_container"))

end

local sys  = require "luci.sys"
local uci  = require "luci.model.uci".cursor()
local keyword  = "ubuntu"
local util  = require("luci.util")
local docker = require "luci.model.docker"

function container_status()
	local docker_path = util.exec("which docker")
	local docker_install = (string.len(docker_path) > 0)
	local docker_running = util.exec("ps | grep dockerd | grep -v 'grep' | wc -l")
	local container_id = util.trim(util.exec("docker ps -aqf 'name="..keyword.."'"))
	local container_install = (string.len(container_id) > 0)
	local container_running = container_install and (string.len(util.trim(util.exec("docker ps -qf 'id="..container_id.."'"))) > 0)
	local port = tonumber(uci:get_first(keyword, keyword, "port", "6901"))
	local wan_status = util.ubus("network.interface.wan", "status", { })
	local public_address = ""
	if wan_status["ipv4-address"] and wan_status["ipv4-address"][1] and wan_status["ipv4-address"][1]["address"] then
		public_address = wan_status["ipv4-address"][1]["address"]
	end
	-- local nxfs      = require "nixio.fs"
	-- nxfs.writefile("/tmp/test.log", dump["ipv4-address"][1]["address"])
	local status = {
		docker_install = docker_install,
		docker_start = docker_running,
		container_id = container_id,
		container_port = (port),
		container_install = container_install,
		container_running = container_running,
		password = uci:get_first(keyword, keyword, "password", ""),
		user_name = "kasm_user",
		local_address = "https://10.10.100.9:"..port.."",
		public_address = "https://"..public_address..":"..port..""
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

	local docker_on_disk = tonumber(util.exec("sh /usr/share/ubuntu/install.sh -c")) 
	local password = luci.http.formvalue("password")
	local port = luci.http.formvalue("port")
	local version = luci.http.formvalue("version")
	
	uci:tset(keyword, "@"..keyword.."[0]", {
		password = password or "password",
		port = port or "6901",
		version = version or "stanard",
	})
	uci:save(keyword)
	uci:commit(keyword)
	local image = util.exec("sh /usr/share/ubuntu/install.sh -l") 

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

	local install_ubuntu = function()
		local os   = require "os"
		local fs   = require "nixio.fs"
		local c = ("sh /usr/share/ubuntu/install.sh -i >/tmp/log/ubuntu.stdout 2>/tmp/log/ubuntu.stderr")
		-- docker:append_status(c)

		local r = os.execute(c)
		local e = fs.readfile("/tmp/log/ubuntu.stderr")
		local o = fs.readfile("/tmp/log/ubuntu.stdout")

		fs.unlink("/tmp/log/ubuntu.stderr")
		fs.unlink("/tmp/log/ubuntu.stdout")

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
	-- docker:append_status("docker not in disk" .. docker_on_disk .."")

	if docker_on_disk == 0 then
		docker:write_status("docker not in disk\n")
	else
		if image then
			docker:write_status("ubuntu installing\n")
			pull_image(image)
			install_ubuntu()
		else
			docker:write_status("ubuntu image not defined!\n")
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
-- 获取容器id docker ps -aqf'name=ubuntu'
-- 启动容器 docker start 78a8455e6d38
-- 停止容器 docker stop 78a8455e6d38


--[[
todo
网络请求提示框
 --]]