-- Cloudreve LuCI 设置页（全中文）
local fs = require "nixio.fs"
local sys = require "luci.sys"
local ok, api = pcall(require, "luci.model.cbi.cloudreve.api")
-- 生态标准库：lsblk 探测 + quickstart 目录约定（缺失时不影响主流程）
local ok_model, cloudreve_model = pcall(require, "luci.model.cloudreve")

m = Map("cloudreve", translate('Cloudreve 云盘'),
	translate('自建网盘 / 文件分享系统。程序本体（二进制）存放在您所选磁盘的 Configs/cloudreve/ 目录里，不占用路由器自身闪存。'))

-- 关键：LuCI 的「保存并应用」默认只给 procd 发 reload，
-- 而服务从来没起来过时 reload 不会把它拉起来 —— 必须显式 restart。
m.on_after_commit = function(self)
	sys.call("/etc/init.d/cloudreve enable >/dev/null 2>&1")
	sys.call("(sleep 1; /etc/init.d/cloudreve restart) >/dev/null 2>&1 &")
end

-- 防御：模块缺失时只提示，不让整页 500
if not ok then
	local es = m:section(TypedSection, "cloudreve", translate('模块异常'))
	es.anonymous = true
	es.addremove = false
	es:option(DummyValue, "_err", translate('状态')).value =
		translate('未找到 luci.model.cbi.cloudreve.api 模块，请重新安装 luci-app-cloudreve 后重试。')
	return m
end

-- 只有模板文件真实存在时才挂载，避免「Failed to load template」
local function tpl(name)
	if fs.access("/usr/lib/lua/luci/view/cloudreve/" .. name .. ".htm") then
		m:append(Template("cloudreve/" .. name))
	end
end

-- ────────────── 使用指引 ──────────────
local gs = m:section(TypedSection, "cloudreve", translate('使用指引（首次使用请先看这里）'))
gs.anonymous = true
gs.addremove = false
gs:option(DummyValue, "_guide", translate('操作流程')).value =
	translate('① 选磁盘　② 建目录　③ 下程序　④ 启服务　⑤ 开网盘')
gs:option(DummyValue, "_guide2", translate('详细说明')).value =
	translate('先在「存储与磁盘」里挑一块外置硬盘；再点「创建 Configs 目录」；') ..
	translate('然后点「下载最新二进制」（会自动匹配本机 CPU 架构）；') ..
	translate('接着勾选「启用服务」并点页面右下角「保存并应用」；') ..
	translate('等上方状态栏出现「打开网盘页面」按钮后点击即可。')
gs:option(DummyValue, "_guide3", translate('账号提示')).value =
	translate('首次打开网盘页面时会引导你创建管理员账号；Cloudreve 的运行输出（含初始密码）会写进系统日志，') ..
	translate('可以在本页最下方的「运行日志」中查看。')
gs:option(DummyValue, "_guide4", translate('数据存放位置')).value =
	translate('程序本体和数据库放在所选硬盘的 Configs/cloudreve/ 下（数据库固定为 data/cloudreve.db，不能自定义）；') ..
	translate('配置文件单独放在 /etc/cloudreve/cloudreve.ini，与数据目录分开，换盘不影响配置。')

-- ────────────── 运行状态 ──────────────
tpl("status")

-- ────────────── 存储与磁盘 ──────────────
local s = m:section(TypedSection, "cloudreve", translate('存储与磁盘'))
s.anonymous = true
s.addremove = false

-- 自动检测磁盘下拉
local storage_opts = {}
local disks = api.get_disks()
if disks and #disks > 0 then
	for _, d in ipairs(disks) do
		local label = d.mount
		local extra = {}
		if d.fstype and d.fstype ~= "" then
			extra[#extra + 1] = d.fstype
		end
		if d.avail and d.avail ~= "" then
			extra[#extra + 1] = translate('可用 ') .. d.avail
		end
		if #extra > 0 then
			label = label .. "（" .. table.concat(extra, "，") .. "）"
		end
		storage_opts[#storage_opts + 1] = { d.mount, label }
	end
end

-- 没有检测到外置硬盘时给出明确指引（系统闪存不是合法的数据落点，不给兜底选项）
if #storage_opts == 0 then
	s:option(DummyValue, "_nodisk", translate('未检测到外置硬盘')).value =
		translate('没有找到符合要求的挂载点（需位于 /mnt 或 /media 下、剩余空间 ≥ 1GiB、并且可写）。') ..
		translate('数据不会放到路由器闪存里，请先把硬盘插好、在「系统 → 挂载点」里挂载成功后再回来操作。')
end

-- 自动推荐磁盘（iStoreOS 官方策略：空间最大且可写的外置挂载点）
local auto_base = api.get_auto_base()
if auto_base then
	s:option(DummyValue, "_autobase", translate('自动推荐磁盘')).value =
		auto_base .. translate('（按 iStoreOS 规则自动挑选：可写且剩余空间最大的外置挂载点）')
end

local storage = s:option(ListValue, "storage_path", translate('存储磁盘'),
	translate('程序本体与数据都放在这块盘的 Configs/cloudreve/ 目录里（配置文件另放 /etc/cloudreve/）。') ..
	translate('留空则每次启动自动挑一块可写、剩余空间最大的外置盘。') ..
	translate('如果之后换了磁盘，需要重新点一次「下载最新二进制」。'))
-- 用生态标准的 lsblk 探测结果补充候选（去重，不覆盖 detect_base.sh 的结果）
if ok_model and cloudreve_model then
	local blocks = cloudreve_model.blocks()
	local home = cloudreve_model.home()
	local paths, _ = cloudreve_model.find_paths(blocks, home, "Configs")
	local known = {}
	for _, opt in ipairs(storage_opts) do
		known[opt[1]] = true
	end
	for _, p in ipairs(paths) do
		-- 候选必须过一遍官方校验（可写 + 剩余空间 ≥ 1GiB + 非系统目录），
		-- 否则可能把 /root 下的系统盘路径也当成可选项摆出来
		local path_ok = api.check_path(p)
		if path_ok and not known[p] then
			known[p] = true
			storage_opts[#storage_opts + 1] = { p, p }
		end
	end
end

for _, opt in ipairs(storage_opts) do
	storage:value(opt[1], opt[2])
end
storage.default = api.get_storage_root()
storage.rmempty = true

local app_dir = api.get_app_dir()
local dir_state
if fs.access(app_dir) then
	dir_state = translate('已存在')
else
	dir_state = translate('尚未创建（保存后会自动创建，也可点下方按钮立即创建）')
end
s:option(DummyValue, "_appdir", translate('程序存放目录')).value =
	app_dir .. "　【" .. dir_state .. "】"

-- ────────────── 服务设置 ──────────────
local s2 = m:section(TypedSection, "cloudreve", translate('服务设置'))
s2.anonymous = true
s2.addremove = false

local o = s2:option(Flag, "enabled", translate('启用服务'),
	translate('勾选后必须点本页右下角「保存并应用」才会生效。') ..
	translate('如果程序本体还没下载，勾选了也启动不起来，请先完成上面的下载步骤。'))
o.rmempty = false

o = s2:option(Value, "listen_address", translate('监听地址'),
	translate('默认 0.0.0.0，表示局域网里所有设备都能访问。') ..
	translate('如果只想让路由器本机访问，可以填 127.0.0.1。'))
o.default = "0.0.0.0"
o.rmempty = false

o = s2:option(Value, "listen_port", translate('监听端口'),
	translate('默认 5212。如果提示端口被占用，改成别的空闲端口即可（例如 5213）。') ..
	translate('改完端口后，用「http://路由器IP:端口」访问网盘。'))
o.datatype = "port"
o.default = "5212"
o.rmempty = false

-- V4 不支持自定义网盘根目录和数据库路径，一律用只读说明，避免用户以为能配
s2:option(DummyValue, "_dbinfo", translate('数据库位置')).value =
	translate('固定为「程序存放目录/data/cloudreve.db」，随所选磁盘走，不需要也不能手动指定。')

s2:option(DummyValue, "_fileinfo", translate('上传文件位置')).value =
	translate('在 Cloudreve 管理面板 → 存储策略里设置，配置文件管不了，所以本页没有这一项。')

s2:option(DummyValue, "_confinfo", translate('配置文件')).value =
	api.get_conf_path() .. translate('（放在路由器系统盘上，与磁盘里的数据分开）')

-- ────────────── 操作按钮 ──────────────
o = s2:option(Button, "_svcctl", translate('服务控制'),
	translate('不改配置，直接启动 / 停止 / 重启 Cloudreve。') ..
	translate('如果「保存并应用」之后服务没起来，点「启动服务」或「重启服务」即可。'))
o.inputstyle = "apply"
if fs.access("/usr/lib/lua/luci/view/cloudreve/svcctl.htm") then
	o.template = "cloudreve/svcctl"
end

o = s2:option(Button, "_initdir", translate('创建 Configs 目录'),
	translate('立即在所选磁盘上创建 Configs/cloudreve/ 目录。') ..
	translate('正常情况下保存配置时会自动创建，这个按钮用于你想提前手动创建。'))
o.inputstyle = "apply"
-- 必须绑定点击事件，否则按钮点了没反应（1.2.x 遗漏）
o.btnclick = "initDirClick(this);"
o.id = "initdir_btn"
if fs.access("/usr/lib/lua/luci/view/cloudreve/initdir.htm") then
	o.template = "cloudreve/initdir"
end

o = s2:option(Button, "_download", translate('下载最新二进制'),
	translate('自动识别本机 CPU 架构，从 GitHub 拉取对应版本的 Cloudreve 并安装到 Configs/cloudreve/。') ..
	translate('第一次点击是检测架构和版本，检测完成后再点一次才真正开始下载。'))
o.inputstyle = "apply"
o.btnclick = "downloadClick(this);"
o.id = "download_btn"
if fs.access("/usr/lib/lua/luci/view/cloudreve/download.htm") then
	o.template = "cloudreve/download"
end

-- ────────────── 运行日志 ──────────────
tpl("log")

return m
