module("luci.controller.picoclaw", package.seeall)

local jsonc = require("luci.jsonc")
local sys = require("luci.sys")
local http = require("luci.http")
local dispatcher = require("luci.dispatcher")

function index()
    entry({"admin", "services", "picoclaw"}, call("action_main"), _("PicoClaw"), 60)
    entry({"admin", "services", "picoclaw", "action"}, call("action_do"), nil)
end

-- Parse JSON using luci.jsonc instead of manual regex
function parse_json_file(filepath)
    local f = io.open(filepath, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    local ok, data = pcall(jsonc.parse, content)
    if ok then return data end
    return nil
end

function get_status()
    local pid = ""
    local running = false
    local memory_kb = 0
    local port_active = false
    local f = io.popen("ps | grep 'picoclaw gateway' | grep -v grep | head -1 2>/dev/null")
    if f then
        local line = f:read("*l") or ""
        f:close()
        local p = line:match("^%s*(%d+)")
        if p and p ~= "" then
            pid = p
            running = true
        end
    end
    if running and pid ~= "" then
        local mf = io.open("/proc/" .. pid .. "/status", "r")
        if mf then
            local c = mf:read("*a")
            mf:close()
            local vm = c:match("VmRSS:%s*(%d+)")
            if vm then memory_kb = tonumber(vm) or 0 end
        end
    end
    local nf = io.open("/proc/net/tcp6", "r")
    if not nf then nf = io.open("/proc/net/tcp", "r") end
    if nf then
        local c = nf:read("*a")
        nf:close()
        -- 4966 is hex for port 18790
        if c:find(":4966") then port_active = true end
    end
    return {running=running, pid=pid, memory_kb=memory_kb, port_active=port_active}
end

function get_config()
    local f = io.open("/root/.picoclaw/config.json", "r")
    if not f then return nil, "Config file not found" end
    local c = f:read("*a")
    f:close()
    return c, nil
end

function get_version_info()
    local cur_ver = "N/A"
    local build_time = ""
    local git_commit = ""
    local output = sys.exec("picoclaw version 2>/dev/null | sed 's/\\x1b\\[[0-9;]*m//g'")
    if output and output ~= "" then
        -- Match: "picoclaw 0.2.4 (git: 5f50ae5)"
        local v, g = output:match("picoclaw%s+([%d.]+)%s*%(%s*git:%s*([a-f0-9]+)%s*%)")
        if v then cur_ver = v end
        if g then git_commit = g end
        -- Match: "Build: 2026-03-25T09:09:15Z"
        local bt = output:match("Build:%s*([%dT:Z%d%-]+)")
        if bt then build_time = bt end
    end
    return cur_ver, build_time, git_commit
end

function check_latest_version()
    local latest_ver = ""
    local latest_url = ""
    local err_msg = ""
    local cache_file = "/tmp/picoclaw_latest_ver"
    local cf = io.open(cache_file, "r")
    if cf then
        local cached = cf:read("*a")
        cf:close()
        local v = cached:match("^([%d.]+)")
        local u = cached:match("\n(.+)$")
        local ts = 0
        local tf = io.open(cache_file .. ".ts", "r")
        if tf then
            ts = tonumber(tf:read("*l")) or 0
            tf:close()
        end
        if v and ts and (os.time() - ts < 3600) then
            return v, u or "", ""
        end
    end
    -- Detect current architecture for correct download URL
    local arch = "linux_arm64"
    local m = sys.exec("uname -m")
    if m:find("x86") then arch = "linux_amd64"
    elseif m:find("armv7") then arch = "linux_armv7" end
    local f = io.popen("curl -sL --max-time 5 'https://api.github.com/repos/sipeed/picoclaw/releases/latest' 2>/dev/null")
    if f then
        local body = f:read("*a")
        f:close()
        local ok, data = pcall(jsonc.parse, body)
        if ok and data then
            if data.tag_name then
                latest_ver = data.tag_name:gsub("^v", "")
            end
            if data.assets then
                for _, asset in ipairs(data.assets) do
                    if asset.browser_download_url and asset.browser_download_url:find(arch) then
                        latest_url = asset.browser_download_url
                        break
                    end
                end
            end
        end
    else
        err_msg = "curl failed"
    end
    if latest_ver ~= "" then
        local cf2 = io.open(cache_file, "w")
        if cf2 then
            cf2:write(latest_ver .. "\n" .. latest_url)
            cf2:close()
        end
        local tf = io.open(cache_file .. ".ts", "w")
        if tf then
            tf:write(tostring(os.time()))
            tf:close()
        end
    end
    if latest_ver == "" then err_msg = "checking" end
    return latest_ver, latest_url, err_msg
end

function get_logs()
    local l = sys.exec("logread 2>/dev/null | grep -i picoclaw | tail -50")
    if l == "" then
        l = sys.exec("logread 2>/dev/null | tail -30")
    end
    return l
end

function html_escape(s)
    if not s then return "" end
    s = tostring(s)
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    s = s:gsub('"', "&quot;")
    return s
end

function do_update()
    local arch = "linux_arm64"
    local m = sys.exec("uname -m")
    if m:find("x86") then arch = "linux_amd64" end
    local dl_url = "https://github.com/sipeed/picoclaw/releases/latest/download/picoclaw_" .. arch
    sys.exec("pkill -f 'picoclaw gateway' 2>/dev/null")
    sys.exec("sleep 1")
    sys.exec("curl -L -o /tmp/picoclaw_new '" .. dl_url .. "' --max-time 120 2>&1")
    sys.exec("chmod +x /tmp/picoclaw_new")
    sys.exec("cp /usr/bin/picoclaw /usr/bin/picoclaw.bak 2>/dev/null")
    sys.exec("mv /tmp/picoclaw_new /usr/bin/picoclaw")
    sys.exec("picoclaw gateway >/dev/null 2>&1 &")
    sys.exec("sleep 3")
end

-- Validate CSRF token for POST actions
function check_csrf()
    local token = http.formvalue("token")
    if not token or token ~= dispatcher.context.authtoken then
        http.status(403, "Forbidden")
        http.write("Invalid CSRF token")
        return false
    end
    return true
end

-- ============================================================
-- Hardware: System Info
-- ============================================================
function get_sysinfo()
    local info = {
        hostname = sys.exec("cat /proc/sys/kernel/hostname 2>/dev/null"):match("^%s*(.-)%s*$") or "",
        kernel = sys.exec("uname -r 2>/dev/null"):match("^%s*(.-)%s*$") or "",
        arch = sys.exec("uname -m 2>/dev/null"):match("^%s*(.-)%s*$") or "",
        uptime = "",
        cpu_model = "",
        cpu_cores = 0,
        load_avg = "",
        mem_total = 0,
        mem_free = 0,
        mem_available = 0,
        cpu_temp = {},
        disks = {}
    }
    -- Uptime
    local up = sys.exec("cat /proc/uptime 2>/dev/null")
    local secs = tonumber(up:match("^([%d.]+)")) or 0
    local days = math.floor(secs / 86400)
    local hours = math.floor((secs % 86400) / 3600)
    local mins = math.floor((secs % 3600) / 60)
    info.uptime = string.format("%dd %dh %dm", days, hours, mins)
    -- Load average
    info.load_avg = sys.exec("cat /proc/loadavg 2>/dev/null"):match("^([%d. ]+)")
    -- CPU
    local cpuinfo = sys.exec("cat /proc/cpuinfo 2>/dev/null")
    info.cpu_model = cpuinfo:match("Hardware[%s]*:[%s]*(.-)\n") or cpuinfo:match("model name[%s]*:[%s]*(.-)\n") or ""
    for _ in cpuinfo:gmatch("processor") do info.cpu_cores = info.cpu_cores + 1 end
    -- Memory
    local meminfo = sys.exec("cat /proc/meminfo 2>/dev/null")
    local mt = meminfo:match("MemTotal:[%s]*(%d+)")
    local mf = meminfo:match("MemFree:[%s]*(%d+)")
    local ma = meminfo:match("MemAvailable:[%s]*(%d+)")
    if mt then info.mem_total = math.floor(tonumber(mt) / 1024) end
    if mf then info.mem_free = math.floor(tonumber(mf) / 1024) end
    if ma then info.mem_available = math.floor(tonumber(ma) / 1024) end
    -- CPU Temperature
    local temps = sys.exec("cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null")
    local types = sys.exec("cat /sys/class/thermal/thermal_zone*/type 2>/dev/null")
    for temp, ttype in temps:gmatch("(%d+)\n") do
        local temp_c = math.floor(tonumber(temp) / 1000)
        table.insert(info.cpu_temp, temp_c)
    end
    -- Disks
    local df = sys.exec("df -h 2>/dev/null | grep -v '^Filesystem\\|^overlay\\|^tmpfs\\|^devtmpfs\\|^/dev\\|^none'")
    for line in df:gmatch("[^\n]+") do
        local parts = {}
        for p in line:gmatch("%S+") do table.insert(parts, p) end
        if #parts >= 6 then
            table.insert(info.disks, {
                filesystem = parts[1],
                size = parts[2],
                used = parts[3],
                avail = parts[4],
                use_pct = parts[5],
                mounted = parts[6]
            })
        end
    end
    return info
end

-- ============================================================
-- Hardware: GPIO
-- ============================================================
function get_gpio_info()
    local pins = {}
    local debug_out = sys.exec("cat /sys/kernel/debug/gpio 2>/dev/null")
    if debug_out == "" then return pins end
    for line in debug_out:gmatch("[^\n]+") do
        local name, dir, val, func, drive, pull = line:match("^%s*(gpio%d+)%s*:%s*(in|out)%s*(%w+)%s*func(%d+)%s*(%d+)mA%s*(.-)%s*$")
        if name then
            table.insert(pins, {
                name = name,
                direction = dir,
                value = val,
                function_num = func,
                drive = drive,
                pull = pull
            })
        end
    end
    return pins
end

function gpio_export(num)
    local f = io.open("/sys/class/gpio/export", "w")
    if f then f:write(tostring(num)); f:close() end
    sys.exec("sleep 0.1")
end

function gpio_unexport(num)
    local f = io.open("/sys/class/gpio/unexport", "w")
    if f then f:write(tostring(num)); f:close() end
end

function gpio_set(num, val)
    local base = "/sys/class/gpio/gpio" .. tostring(num)
    gpio_export(num)
    local f = io.open(base .. "/direction", "w")
    if f then f:write("out"); f:close() end
    f = io.open(base .. "/value", "w")
    if f then f:write(val == 1 and "1" or "0"); f:close() end
end

function gpio_read(num)
    local base = "/sys/class/gpio/gpio" .. tostring(num)
    local f = io.open(base .. "/value", "r")
    if f then
        local v = f:read("*l")
        f:close()
        return v
    end
    return nil
end

-- ============================================================
-- Hardware: LED
-- ============================================================
function get_leds()
    local leds = {}
    local led_dir = io.popen("ls /sys/class/leds/ 2>/dev/null")
    if not led_dir then return leds end
    for name in led_dir:lines() do
        local base = "/sys/class/leds/" .. name
        local f = io.open(base .. "/brightness", "r")
        local brightness = f and tonumber(f:read("*l")) or 0
        if f then f:close() end
        f = io.open(base .. "/max_brightness", "r")
        local max_b = f and tonumber(f:read("*l")) or 255
        if f then f:close() end
        f = io.open(base .. "/trigger", "r")
        local trigger_raw = f and f:read("*l") or "none"
        if f then f:close() end
        -- Extract current trigger (marked with [])
        local trigger = trigger_raw:match("%[(.-)%]") or "none"
        -- Extract all available triggers
        local triggers = {}
        for t in trigger_raw:gmatch("(%w+)") do
            table.insert(triggers, t)
        end
        table.insert(leds, {
            name = name,
            brightness = brightness,
            max_brightness = max_b,
            trigger = trigger,
            triggers = triggers
        })
    end
    led_dir:close()
    return leds
end

function led_set(name, brightness, trigger)
    local base = "/sys/class/leds/" .. name
    if trigger then
        local f = io.open(base .. "/trigger", "w")
        if f then f:write(trigger); f:close() end
    end
    if brightness then
        local f = io.open(base .. "/brightness", "w")
        if f then f:write(tostring(math.max(0, math.min(255, tonumber(brightness) or 0)))); f:close() end
    end
end

-- ============================================================
-- Hardware: USB
-- ============================================================
function get_usb_devices()
    local devices = {}
    local lsusb = sys.exec("lsusb 2>/dev/null")
    if lsusb == "" then
        -- Fallback: read from sysfs
        local product = sys.exec("for d in /sys/bus/usb/devices/*/; do name=$(basename $d); if [ -f $d/product ]; then prod=$(cat $d/product 2>/dev/null); vid=$(cat $d/idVendor 2>/dev/null); pid=$(cat $d/idProduct 2>/dev/null); echo \"$name|$prod|$vid|$pid\"; fi; done")
        for line in product:gmatch("[^\n]+") do
            local parts = {}
            for p in line:gmatch("[^|]+") do table.insert(parts, p) end
            if #parts >= 4 then
                table.insert(devices, {
                    bus_dev = parts[1],
                    product = parts[2],
                    vid = parts[3],
                    pid = parts[4]
                })
            end
        end
    else
        for line in lsusb:gmatch("[^\n]+") do
            local bus, dev, rest = line:match("Bus (%d+) Device (%d+): (.+)")
            if bus then
                table.insert(devices, {
                    bus_dev = "Bus " .. bus .. " Dev " .. dev,
                    product = rest
                })
            end
        end
    end
    return devices
end

-- ============================================================
-- Hardware: PicoClaw Tools (cron, skills)
-- ============================================================
function get_picoclaw_tools()
    local tools = {
        cron_jobs = {},
        skills = {}
    }
    -- Cron jobs
    local cron_out = sys.exec("picoclaw cron list 2>/dev/null | sed 's/\\x1b\\[[0-9;]*m//g' | grep -v 'PicoClaw\\|^$\\|████'")
    if cron_out and cron_out ~= "" and not cron_out:find("No scheduled") then
        for line in cron_out:gmatch("[^\n]+") do
            line = line:match("^%s*(.-)%s*$")
            if line and line ~= "" then
                table.insert(tools.cron_jobs, line)
            end
        end
    end
    -- Skills
    local skill_dir = io.popen("ls /root/.picoclaw/workspace/skills/ 2>/dev/null")
    if skill_dir then
        for name in skill_dir:lines() do
            local desc = ""
            local f = io.open("/root/.picoclaw/workspace/skills/" .. name .. "/SKILL.md", "r")
            if f then
                local content = f:read("*a")
                f:close()
                desc = content:match("description:%s*\"(.-)\"") or content:match("description:%s*(.-)\n") or ""
            end
            table.insert(tools.skills, { name = name, description = desc })
        end
        skill_dir:close()
    end
    return tools
end

function action_do()
    if not check_csrf() then return end

    local action = http.formvalue("action") or ""
    local msg = ""
    local ok = true

    if action == "start" then
        sys.exec("picoclaw gateway >/dev/null 2>&1 &")
        sys.exec("sleep 2")
        msg = "服务正在启动..."
    elseif action == "stop" then
        sys.exec("pkill -f 'picoclaw gateway' 2>/dev/null")
        sys.exec("sleep 1")
        msg = "服务已停止。"
    elseif action == "restart" then
        sys.exec("pkill -f 'picoclaw gateway' 2>/dev/null")
        sys.exec("sleep 1")
        sys.exec("picoclaw gateway >/dev/null 2>&1 &")
        sys.exec("sleep 2")
        msg = "服务已重启。"
    elseif action == "autostart_on" then
        sys.exec("/etc/init.d/picoclaw enable 2>/dev/null")
        msg = "已启用开机自动启动。"
    elseif action == "autostart_off" then
        sys.exec("/etc/init.d/picoclaw disable 2>/dev/null")
        msg = "已关闭开机自动启动。"
    elseif action == "save_config" or action == "save_form_config" then
        local config = http.formvalue("config") or ""
        if config ~= "" then
            -- Validate JSON before saving
            local valid, _ = pcall(jsonc.parse, config)
            if not valid then
                msg = "错误：JSON 格式无效"
                ok = false
            else
                local f = io.open("/root/.picoclaw/config.json", "w")
                if f then
                    f:write(config)
                    f:close()
                    sys.exec("pkill -f 'picoclaw gateway' 2>/dev/null; sleep 1; picoclaw gateway >/dev/null 2>&1 &")
                    msg = "配置已保存，服务已重启！"
                else
                    msg = "错误：无法写入配置文件"
                    ok = false
                end
            end
        else
            msg = "错误：配置内容为空"
            ok = false
        end
    elseif action == "update" then
        do_update()
        msg = "更新完成，服务已重启！"
    -- Hardware actions
    elseif action == "led_set" then
        local led_name = http.formvalue("led") or ""
        local brightness = http.formvalue("brightness") or ""
        local trigger = http.formvalue("trigger") or ""
        if led_name ~= "" then
            led_set(led_name, tonumber(brightness) or 0, trigger ~= "" and trigger or nil)
            msg = "LED 已更新: " .. led_name
        else
            msg = "错误：未指定 LED"; ok = false
        end
    elseif action == "gpio_set" then
        local gpio_num = http.formvalue("gpio") or ""
        local gpio_val = http.formvalue("value") or "0"
        if gpio_num ~= "" then
            gpio_set(tonumber(gpio_num) or 0, tonumber(gpio_val) or 0)
            msg = "GPIO " .. gpio_num .. " = " .. gpio_val
        else
            msg = "错误：未指定 GPIO"; ok = false
        end
    elseif action == "usb_power_toggle" then
        local f = io.open("/sys/class/gpio/usb_power/value", "r")
        if f then
            local cur = f:read("*l")
            f:close()
            local new_val = (cur == "1") and "0" or "1"
            local fw = io.open("/sys/class/gpio/usb_power/value", "w")
            if fw then fw:write(new_val); fw:close() end
            msg = "USB 电源已" .. (new_val == "1" and "开启" or "关闭")
        else
            msg = "错误：USB 电源 GPIO 不存在"; ok = false
        end
    elseif action == "delete_skill" then
        local skill_name = http.formvalue("skill_name") or ""
        if skill_name ~= "" then
            -- Sanitize: only allow alphanumeric, underscore, hyphen
            if skill_name:match("^[%w_%-]+$") then
                local skill_path = "/root/.picoclaw/workspace/skills/" .. skill_name
                os.remove(skill_path .. "/SKILL.md")  -- remove file only, not directory (in case user has extra files)
                local _, _, exit_code = sys.exec("rm -rf '" .. skill_path .. "' 2>/dev/null; echo $?")
                -- Verify deleted
                local check = io.open(skill_path .. "/SKILL.md", "r")
                if check then check:close() msg = "错误：删除失败"; ok = false
                else msg = "技能已删除: " .. skill_name end
            else
                msg = "错误：技能名称无效"; ok = false
            end
        else
            msg = "错误：未指定技能"; ok = false
        end
    elseif action == "import_skill" then
        local skill_name = http.formvalue("skill_name") or ""
        local skill_content = http.formvalue("skill_content") or ""
        if skill_name ~= "" and skill_content ~= "" then
            if skill_name:match("^[%w_%-]+$") then
                local skill_dir = "/root/.picoclaw/workspace/skills/" .. skill_name
                sys.exec("mkdir -p '" .. skill_dir .. "'")
                local f = io.open(skill_dir .. "/SKILL.md", "w")
                if f then
                    f:write(skill_content)
                    f:close()
                    msg = "技能已导入: " .. skill_name
                else
                    msg = "错误：无法写入文件"; ok = false
                end
            else
                msg = "错误：技能名称仅允许字母、数字、下划线和连字符"; ok = false
            end
        else
            msg = "错误：请填写技能名称和内容"; ok = false
        end
    end

    local url = dispatcher.build_url("admin", "services", "picoclaw")
    if msg ~= "" then
        url = url .. "?msg=" .. http.urlencode(msg) .. "&ok=" .. (ok and "1" or "0")
    end
    http.redirect(url)
end

function action_main()
    local status = get_status()
    local config_content, config_err = get_config()
    local logs = get_logs()

    local cur_ver, build_time, git_commit = get_version_info()
    local latest_ver, latest_url, check_err = check_latest_version()

    local has_update = false
    if latest_ver ~= "" and cur_ver ~= "N/A" then
        local function ver_parts(v)
            local t = {}
            for n in v:gmatch("%d+") do
                t[#t + 1] = tonumber(n)
            end
            return t
        end
        local cv = ver_parts(cur_ver)
        local lv = ver_parts(latest_ver)
        for i = 1, math.max(#cv, #lv) do
            local a = cv[i] or 0
            local b = lv[i] or 0
            if b > a then
                has_update = true
                break
            end
            if a > b then
                break
            end
        end
    end

    local memory_mb = "0.0"
    if status.memory_kb and tonumber(status.memory_kb) then
        memory_mb = string.format("%.1f", tonumber(status.memory_kb) / 1024)
    end
    local pid_str = "-"
    if status.pid and status.pid ~= "" then
        pid_str = tostring(status.pid)
    end

    -- Parse weixin status using proper JSON parser
    local weixin_status = "none"
    local weixin_configured = false
    local config = parse_json_file("/root/.picoclaw/config.json")
    if config then
        local weixin = config.weixin
        if weixin and type(weixin) == "table" then
            if weixin.enabled == true then
                weixin_status = "connected"
            end
            if weixin.base_url and weixin.base_url ~= "" then
                weixin_configured = true
                if weixin_status == "none" then
                    weixin_status = "configured"
                end
            end
        end
    end

    local flash_msg = http.formvalue("msg") or ""
    local flash_ok = http.formvalue("ok") or "1"

    local autostart = false
    local asf = io.open("/etc/rc.d/S99picoclaw", "r")
    if asf then asf:close() autostart = true end

    -- Hardware data
    local hw_sysinfo = get_sysinfo()
    local hw_gpio = get_gpio_info()
    local hw_leds = get_leds()
    local hw_usb = get_usb_devices()
    local hw_tools = get_picoclaw_tools()

    luci.template.render("picoclaw/main", {
        running = status.running,
        pid = pid_str,
        memory_mb = memory_mb,
        port_active = status.port_active or false,
        cur_ver = html_escape(cur_ver),
        latest_ver = html_escape(latest_ver),
        build_time = html_escape(build_time),
        git_commit = html_escape(git_commit),
        latest_url = html_escape(latest_url),
        has_update = has_update,
        check_err = check_err,
        config_content = html_escape(config_content or ""),
        config_json_safe = html_escape(config_content or "{}"),
        weixin_status = weixin_status,
        weixin_configured = weixin_configured,
        channels_html = "",
        logs = html_escape(logs),
        flash_msg = html_escape(flash_msg),
        flash_ok = flash_ok,
        action_url = dispatcher.build_url("admin", "services", "picoclaw", "action"),
        csrf_token = dispatcher.context.authtoken,
        autostart = autostart,
        hw_sysinfo = hw_sysinfo,
        hw_gpio = hw_gpio,
        hw_leds = hw_leds,
        hw_usb = hw_usb,
        hw_tools = hw_tools
    })
end
