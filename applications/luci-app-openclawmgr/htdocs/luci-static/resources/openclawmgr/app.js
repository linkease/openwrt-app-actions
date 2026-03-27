(function() {
  var config = window.openclawmgrConfig || {};
  var container = document.getElementById("openclawmgr-app");
  if (!container) {
    return;
  }

  function parseRgb(value) {
    var m = value && value.match(/\d+/g);
    if (m && m.length >= 3) {
      return { r: parseInt(m[0], 10), g: parseInt(m[1], 10), b: parseInt(m[2], 10) };
    }
    return null;
  }

  function detectDarkMode() {
    try {
      var bg = window.getComputedStyle(document.body).backgroundColor;
      var rgb = parseRgb(bg);
      if (rgb) {
        var luminance = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b;
        return luminance < 128;
      }
    } catch (e) {}
    return false;
  }

  var root = container.attachShadow ? (container.shadowRoot || container.attachShadow({ mode: "open" })) : container;
  var state = {
    status: null,
    form: null,
    options: null,
    newOrigin: "",
    activeTab: "basic",
    savingSection: "",
    lastAppliedAt: "",
    statusTimer: null,
    installWatchTimer: null,
    lastTaskRunning: false,
    taskLogOpenTs: 0,
    consoleReady: false,
    consoleCheckTimer: null,
    updateCheck: {
      checking: false,
      checked: false,
      hasUpdate: false,
      upgrading: false,
      localVersion: "",
      remoteVersion: "",
      error: ""
    }
  };
  var styleText = "";

  function request(url, options) {
    options = options || {};
    options.credentials = "same-origin";
    options.headers = options.headers || {};
    if (config.token) {
      options.headers["X-LuCI-Token"] = config.token;
    }
    return fetch(url, options).then(function(r) { return r.json(); });
  }

  function postJson(url, payload) {
    payload = payload || {};
    if (config.token && payload.token == null) {
      payload.token = config.token;
    }
    return request(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(payload)
    });
  }

  function postForm(url, payload) {
    var body = new URLSearchParams();
    payload = payload || {};
    if (config.token && payload.token == null) {
      payload.token = config.token;
    }
    Object.keys(payload || {}).forEach(function(key) {
      body.append(key, payload[key]);
    });
    return request(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8"
      },
      body: body.toString()
    });
  }

  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function modelForAgent(agent) {
    return {
      openai: "openai/gpt-5.2",
      anthropic: "anthropic/claude-sonnet-4-6",
      "minimax-cn": "minimax-cn/MiniMax-M2.5",
      moonshot: "moonshot/kimi-k2.5"
    }[agent] || "anthropic/claude-sonnet-4-6";
  }

  function modelMatchesAgent(agent, model) {
    model = String(model || "");
    return {
      openai: /^openai\//,
      anthropic: /^anthropic\//,
      "minimax-cn": /^minimax-cn\//,
      moonshot: /^moonshot\//
    }[agent] ? ({
      openai: /^openai\//,
      anthropic: /^anthropic\//,
      "minimax-cn": /^minimax-cn\//,
      moonshot: /^moonshot\//
    }[agent]).test(model) : false;
  }

  function resolveModelValue(form) {
    var agent = form && form.default_agent ? form.default_agent : "anthropic";
    var value = form && form.default_model ? String(form.default_model) : "";
    if (!value || !modelMatchesAgent(agent, value)) {
      return modelForAgent(agent);
    }
    return value;
  }

  function statusText(status) {
    if (status.installing) return status.task_op === "upgrade" ? "更新中" : "安装中";
    if (!status || !status.installed) return "未安装";
    if (status.running) return "运行中";
    if (status.reachable) return "运行中（未托管）";
    return "已停止";
  }

  function statusDotClass(status) {
    if (status && status.installing) return "";
    if (status && status.running) return "is-success";
    if (status && status.reachable) return "";
    return "is-danger";
  }

  function statusSpinSeconds(status) {
    return (backgroundStatusDelay(status) / 1000).toFixed(1);
  }

  function escapeAttr(value) {
    return escapeHtml(value).replace(/'/g, "&#39;");
  }

  function maskedTokenUrl(url) {
    var value = String(url || "");
    if (!value) {
      return "-";
    }
    return value.replace(/(#token=)([^&#]+)/, function(_, prefix, token) {
      if (!token) {
        return prefix;
      }
      var head = token.slice(0, 6);
      var tail = token.length > 10 ? token.slice(-4) : "";
      return prefix + head + "****" + tail;
    });
  }

  function getUpdateCheck() {
    state.updateCheck = state.updateCheck || {
      checking: false,
      checked: false,
      hasUpdate: false,
      upgrading: false,
      localVersion: "",
      remoteVersion: "",
      error: ""
    };
    return state.updateCheck;
  }

  function updateActionLabel(status) {
    var updateCheck = getUpdateCheck();
    if (updateCheck.upgrading || (status && status.installing && status.task_op === "upgrade")) return "更新中";
    if (updateCheck.checking) return "检测中…";
    if (updateCheck.hasUpdate) return "更新 OpenClaw";
    return "检测更新";
  }

  function statusNoteText(status) {
    var updateCheck = getUpdateCheck();
    if (status && status.installing) {
      return status.task_op === "upgrade"
        ? "更新任务正在后台运行，可打开任务日志查看进度。"
        : "安装任务正在后台运行，可打开任务日志查看进度。";
    }
    if (updateCheck.checking) {
      return "正在检测远程版本，请稍候…";
    }
    if (updateCheck.upgrading) {
      return "更新任务已提交，请稍候查看版本变化。";
    }
    if (updateCheck.error) {
      return updateCheck.error;
    }
    if (updateCheck.checked && updateCheck.localVersion && updateCheck.remoteVersion) {
      if (updateCheck.hasUpdate) {
        return "发现新版本：本地 " + updateCheck.localVersion + "，远程 " + updateCheck.remoteVersion;
      }
      return "当前已是最新版：本地 " + updateCheck.localVersion + "，远程 " + updateCheck.remoteVersion;
    }
    return "";
  }

  function copyIcon(className) {
    return '' +
      '<svg class="' + escapeAttr(className || "") + '" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">' +
      '<rect x="9" y="9" width="10" height="10" rx="2" stroke="currentColor" stroke-width="1.8"></rect>' +
      '<path d="M6 15H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v1" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"></path>' +
      '</svg>';
  }

  function copiedIcon(className) {
    return '' +
      '<svg class="' + escapeAttr(className || "") + '" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">' +
      '<path d="M5 12.5l4 4L19 7" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"></path>' +
      '</svg>';
  }

  function fallbackCopyText(value) {
    var el = document.createElement("textarea");
    el.value = String(value || "");
    el.setAttribute("readonly", "readonly");
    el.style.position = "fixed";
    el.style.top = "-9999px";
    el.style.left = "-9999px";
    document.body.appendChild(el);
    el.focus();
    el.select();
    var ok = false;
    try {
      ok = document.execCommand("copy");
    } catch (e) {}
    document.body.removeChild(el);
    return ok;
  }

  function copyText(value) {
    value = String(value || "");
    if (!value) {
      return Promise.resolve(false);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(value).then(function() {
        return true;
      }).catch(function() {
        return fallbackCopyText(value);
      });
    }
    return Promise.resolve(fallbackCopyText(value));
  }

  function flashCopied(el) {
    if (!el) {
      return;
    }
    if (el._oclmCopyTimer) {
      window.clearTimeout(el._oclmCopyTimer);
      el._oclmCopyTimer = null;
    }
    el.classList.add("is-copied");
    el.innerHTML = copiedIcon("oclm-copy-icon");
    el._oclmCopyTimer = window.setTimeout(function() {
      el.classList.remove("is-copied");
      el.innerHTML = copyIcon("oclm-copy-icon");
      el._oclmCopyTimer = null;
    }, 1100);
  }

  function openclawIcon(className) {
    return '' +
      '<svg class="' + escapeAttr(className || "") + '" viewBox="0 0 120 120" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">' +
      '<defs>' +
      '<linearGradient id="oclm-lobster-gradient" x1="0%" y1="0%" x2="100%" y2="100%">' +
      '<stop offset="0%" stop-color="#ff4d4d"/>' +
      '<stop offset="100%" stop-color="#991b1b"/>' +
      '</linearGradient>' +
      '</defs>' +
      '<path d="M60 10 C30 10 15 35 15 55 C15 75 30 95 45 100 L45 110 L55 110 L55 100 C55 100 60 102 65 100 L65 110 L75 110 L75 100 C90 95 105 75 105 55 C105 35 90 10 60 10Z" fill="url(#oclm-lobster-gradient)"/>' +
      '<path d="M20 45 C5 40 0 50 5 60 C10 70 20 65 25 55 C28 48 25 45 20 45Z" fill="url(#oclm-lobster-gradient)"/>' +
      '<path d="M100 45 C115 40 120 50 115 60 C110 70 100 65 95 55 C92 48 95 45 100 45Z" fill="url(#oclm-lobster-gradient)"/>' +
      '<path d="M45 15 Q35 5 30 8" stroke="#ff4d4d" stroke-width="3" stroke-linecap="round"/>' +
      '<path d="M75 15 Q85 5 90 8" stroke="#ff4d4d" stroke-width="3" stroke-linecap="round"/>' +
      '<circle cx="45" cy="35" r="6" fill="#050810"/>' +
      '<circle cx="75" cy="35" r="6" fill="#050810"/>' +
      '<circle cx="46" cy="34" r="2.5" fill="#00e5cc"/>' +
      '<circle cx="76" cy="34" r="2.5" fill="#00e5cc"/>' +
      '</svg>';
  }

  function communityIcon(className) {
    return '' +
      '<svg class="' + escapeAttr(className || "") + '" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">' +
      '<path d="M8 10h8M8 14h5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"></path>' +
      '<path d="M7 19l-3 2V7a3 3 0 0 1 3-3h10a3 3 0 0 1 3 3v8a3 3 0 0 1-3 3H7Z" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round"></path>' +
      '</svg>';
  }

  function taskWindowAvailable() {
    return !!(window.taskd && window.taskd.show_log);
  }

  function showTaskLog(taskId) {
    taskId = taskId || "openclawmgr";
    if (!taskWindowAvailable()) {
      window.alert("任务窗口不可用（未加载 taskd/xterm）。请安装 luci-lib-taskd 和 luci-lib-xterm，然后强制刷新页面。");
      return;
    }
    var now = Date.now ? Date.now() : (+new Date());
    if (state.taskLogOpenTs && now - state.taskLogOpenTs < 1500) {
      return;
    }
    state.taskLogOpenTs = now;
    window.taskd.show_log(taskId);
  }

  function stopStatusPolling() {
    if (state.statusTimer) {
      window.clearTimeout(state.statusTimer);
      state.statusTimer = null;
    }
  }

  function stopInstallWatch() {
    if (state.installWatchTimer) {
      window.clearTimeout(state.installWatchTimer);
      state.installWatchTimer = null;
    }
  }

  function stopConsoleCheck() {
    if (state.consoleCheckTimer) {
      window.clearTimeout(state.consoleCheckTimer);
      state.consoleCheckTimer = null;
    }
  }

  function pollConsoleReady(rounds) {
    rounds = typeof rounds === "number" ? rounds : 20;
    stopConsoleCheck();
    state.consoleReady = false;

    function tick(remaining) {
      request(config.readyUrl).then(function(rv) {
        state.consoleReady = !!(rv && rv.ok && rv.ready);
        updateStatusDom(state.status);
        if (!state.consoleReady && remaining > 1) {
          state.consoleCheckTimer = window.setTimeout(function() { tick(remaining - 1); }, 1000);
        } else {
          state.consoleCheckTimer = null;
        }
      }).catch(function() {
        state.consoleReady = false;
        updateStatusDom(state.status);
        if (remaining > 1) {
          state.consoleCheckTimer = window.setTimeout(function() { tick(remaining - 1); }, 1500);
        } else {
          state.consoleCheckTimer = null;
        }
      });
    }

    tick(rounds);
  }

  function backgroundStatusDelay(status) {
    if (status && status.installing) {
      return 3000;
    }
    if (!status || !status.installed) {
      return 30000;
    }
    if (status.running) {
      return 15000;
    }
    return 20000;
  }

  function ensureInstallWatch() {
    stopInstallWatch();
    state.installWatchTimer = window.setTimeout(function() {
      refreshStatus(function() {
        ensureInstallWatch();
      });
    }, backgroundStatusDelay(state.status));
  }

  function scheduleStatusRefresh(rounds, delay) {
    rounds = typeof rounds === "number" ? rounds : 6;
    delay = typeof delay === "number" ? delay : 1000;
    stopStatusPolling();

    function tick(remaining) {
      refreshStatus(function() {
        if (remaining > 1) {
          state.statusTimer = window.setTimeout(function() {
            tick(remaining - 1);
          }, delay);
        } else {
          state.statusTimer = null;
        }
      });
    }

    tick(rounds);
  }

  function render() {
    var status = state.status || {};
    var form = state.form || {};
    var options = state.options || { base_dir_choices: [] };
    var allowedOrigins = Array.isArray(form.allowed_origins) ? form.allowed_origins : [];
    var baseDirOptions = (options.base_dir_choices || []).map(function(path) {
      return '<option value="' + escapeHtml(path) + '"></option>';
    }).join("");
    var origins = allowedOrigins.map(function(item, index) {
      return '' +
        '<div class="oclm-origin-item">' +
        '<input class="oclm-control" type="text" value="' + escapeHtml(item) + '" data-origin-index="' + index + '" />' +
        '<button class="oclm-button oclm-button-danger" type="button" data-remove-origin="' + index + '">删除</button>' +
        '</div>';
    }).join("");

    var updateCheck = getUpdateCheck();
    var installLabel = status.installing ? (status.task_op === "upgrade" ? "更新中" : "安装中") : "立即安装";
    var installAcceleratedChecked = form.install_accelerated == null ? true : form.install_accelerated === true;
    var showInstallAction = !status.installed;
    var showUpdateAction = status.installed && !status.installing;
    var showServiceActions = status.installed && !status.installing;
    var activeTab = state.activeTab || "basic";
    var savingBasic = state.savingSection === "basic";
    var savingAi = state.savingSection === "ai";
    var savingAccess = state.savingSection === "access";
    var noteText = statusNoteText(status);

    var canStartService = !status.running && !status.reachable;
    var canStopService = !!status.running;

    root.innerHTML =
      '<style>' + styleText + '</style>' +
      '<div class="oclm-app"' + (detectDarkMode() ? ' data-darkmode="true"' : '') + '>' +
      '<div class="oclm-root">' +
      '<div class="oclm-shell">' +
      '<div class="oclm-header">' +
      '<h1>' + openclawIcon("oclm-title-icon") + 'OpenClaw 启动器</h1>' +
      '<p>在 OpenWrt 上原生安装、启动并管理官方 OpenClaw</p>' +
      '</div>' +

      '<section class="oclm-card">' +
      '<h2>服务状态</h2>' +
      '<div class="oclm-status-grid">' +
      '<div class="oclm-status-row"><span class="oclm-status-label">状态</span><span id="oclm-status-pill" class="oclm-status-pill" style="--oclm-spin-duration:' + escapeAttr(statusSpinSeconds(status)) + 's"><span id="oclm-status-dot" class="oclm-dot ' + statusDotClass(status) + '"></span><span class="oclm-status-spinner" aria-hidden="true"></span><span id="oclm-status-text">' + escapeHtml(statusText(status)) + '</span></span>' +
      '<span id="oclm-uptime" class="oclm-tag' + (status.running && status.uptime_human ? '' : ' oclm-hidden') + '">运行时间 <strong id="oclm-uptime-text">' + escapeHtml(status.uptime_human || "") + '</strong></span>' +
      '</div>' +
      '<div><div id="oclm-pid-row"' + ((status.running && status.pid) ? '' : ' class="oclm-hidden"') + '><div class="oclm-inline-row"><span class="oclm-tag">PID <strong id="oclm-pid">' + escapeHtml(status.pid || "") + '</strong></span></div></div></div>' +
      '<div><div class="oclm-meta-label">地址</div><div class="oclm-address-row"><span id="oclm-address-text" class="oclm-address-text">' + escapeHtml(maskedTokenUrl(status.token_url || status.base_url || "")) + '</span><button id="oclm-copy-token-url" class="oclm-icon-button' + ((status.token_url || status.base_url) ? '' : ' oclm-hidden') + '" type="button" data-copy-token-url="1" aria-label="复制地址">' + copyIcon("oclm-copy-icon") + '</button></div></div>' +
      '<div><div class="oclm-meta-label">目录</div><div id="oclm-status-base-dir">' + escapeHtml(status.base_dir || "-") + '</div></div>' +
      '<div><div class="oclm-meta-label">版本</div><div class="oclm-version-tags"><a class="oclm-tag oclm-tag-link" href="https://github.com/openclaw/openclaw/releases" target="_blank" rel="noreferrer">OpenClaw <strong id="oclm-openclaw-version">' + escapeHtml(status.openclaw_version || "-") + '</strong></a><span class="oclm-tag">Node <strong id="oclm-node-version">' + escapeHtml(status.node_version || "-") + '</strong></span></div></div>' +
      '<div></div>' +
      '</div>' +
      '<div id="oclm-status-actions" class="oclm-status-actions">' +
      '<div id="oclm-install-inline" class="oclm-install-inline' + (showInstallAction ? '' : ' oclm-hidden') + '">' +
      '<button id="oclm-install-btn" class="oclm-button oclm-button-primary" type="button" data-install-action="1"' + (status.installing ? ' disabled' : '') + '>' + installLabel + '</button>' +
      '<label class="oclm-check"><input type="checkbox" id="oclm-install-accelerated"' + (installAcceleratedChecked ? ' checked' : '') + ' />Kspeeder 加速安装</label>' +
      '</div>' +
      '<button id="oclm-open-console" class="oclm-button oclm-button-primary' + ((status.running || status.reachable) ? '' : ' oclm-hidden') + '" type="button" data-open-console="1"' + (state.consoleReady ? '' : ' disabled') + '>' + openclawIcon("oclm-button-icon") + (state.consoleReady ? '打开控制台' : '控制台准备中…') + '</button>' +
      '<button id="oclm-update-btn" class="oclm-button oclm-button-primary' + (showUpdateAction ? '' : ' oclm-hidden') + '" type="button" data-update-action="1"' + ((updateCheck.checking || updateCheck.upgrading) ? ' disabled' : '') + '>' + updateActionLabel(status) + '</button>' +
      '<a id="oclm-open-community" class="oclm-button oclm-button-community" href="https://www.koolcenter.com/t/topic/19042" target="_blank" rel="noreferrer noopener">' + communityIcon("oclm-button-icon") + '玩家交流</a>' +
      '<button id="oclm-cancel-install" class="oclm-button oclm-button-danger' + (status.installing ? '' : ' oclm-hidden') + '" type="button" data-op="cancel_install">停止安装</button>' +
      '</div>' +
      '<div id="oclm-status-note" class="oclm-status-note' + (noteText ? '' : ' oclm-hidden') + '">' + escapeHtml(noteText) + '</div>' +
      '</section>' +

      '<section class="oclm-card">' +
      '<div class="oclm-tabs">' +
      '<button class="oclm-tab' + (activeTab === "basic" ? ' is-active' : '') + '" type="button" data-tab="basic">基础配置</button>' +
      '<button class="oclm-tab' + (activeTab === "ai" ? ' is-active' : '') + '" type="button" data-tab="ai">AI配置</button>' +
      '<button class="oclm-tab' + (activeTab === "access" ? ' is-active' : '') + '" type="button" data-tab="access">访问控制</button>' +
      '<button class="oclm-tab' + (activeTab === "cleanup" ? ' is-active' : '') + '" type="button" data-tab="cleanup">卸载清理</button>' +
      '</div>' +
      '<div class="' + (activeTab === "basic" ? '' : 'oclm-hidden') + '">' +
      '<h2>基础配置</h2>' +
      '<div class="oclm-form-grid oclm-form-grid-ai" style="margin-top: 26px;">' +
      fieldInput("监听端口", '<input class="oclm-control" type="number" min="1025" max="65535" id="oclm-port" value="' + escapeHtml(form.port || "18789") + '" />') +
      fieldInput("监听范围", selectHtml("oclm-bind", form.bind, [
        ["lan", "所有地址"],
        ["loopback", "仅本机"],
        ["auto", "自动"]
      ])) +
      fieldInput("数据目录", '<input class="oclm-control" type="text" id="oclm-base-dir" list="oclm-base-dir-options" value="' + escapeAttr(form.base_dir || "") + '" /><datalist id="oclm-base-dir-options">' + baseDirOptions + '</datalist>') +
      '<div class="oclm-section-submit">' +
      '<button class="oclm-button oclm-button-primary" type="button" id="oclm-save-basic"' + (savingBasic ? ' disabled' : '') + '>' + (savingBasic ? '应用中…' : '保存并应用') + '</button>' +
      '<span id="oclm-service-actions" class="oclm-inline-buttons' + (showServiceActions ? '' : ' oclm-hidden') + '">' +
      '<button id="oclm-btn-start" class="oclm-button' + (canStartService ? '' : ' oclm-hidden') + '" type="button" data-op="start">启动服务</button>' +
      '<button id="oclm-btn-stop" class="oclm-button' + (canStopService ? '' : ' oclm-hidden') + '" type="button" data-op="stop">停止服务</button>' +
      '<button id="oclm-btn-restart" class="oclm-button" type="button" data-op="restart">重启服务</button>' +
      '</span>' +
      (state.lastAppliedAt ? '<span class="oclm-applied-hint">已于 ' + escapeHtml(state.lastAppliedAt) + ' 更新配置</span>' : '') +
      '</div>' +
      '</div></div>' +

      '<div class="' + (activeTab === "ai" ? '' : 'oclm-hidden') + '">' +
      '<div class="oclm-section-heading"><h2>AI配置</h2><div class="oclm-hint">先配好一个能马上聊起来的默认 AI，再让openclaw协助你设置更多的AGENT、加角色等操作</div></div>' +
      '<div class="oclm-form-grid oclm-form-grid-ai">' +
      fieldInput("默认服务提供商", selectHtml("oclm-agent", form.default_agent, [
        ["openai", "OpenAI"],
        ["anthropic", "Anthropic"],
        ["minimax-cn", "MiniMax CN"],
        ["moonshot", "Moonshot CN"]
      ]) + '<div class="oclm-hint">如果你的供应商是兼容 OpenAI 等协议，可在下方填写中转地址</div>') +
      fieldInput("API 密钥", passwordHtml("oclm-api-key", form.provider_api_key || "", "sk-...")) +
      fieldInput("中转地址（可选）", '<input class="oclm-control" type="text" id="oclm-base-url" value="' + escapeHtml(form.provider_base_url || "") + '" placeholder="https://api.example.com" />') +
      fieldInput("默认模型", '<input class="oclm-control" type="text" id="oclm-model" value="' + escapeAttr(resolveModelValue(form)) + '" placeholder="请按照&lt;provider&gt;/&lt;model-id&gt;格式填写" />') +
      '<div class="oclm-section-submit"><button class="oclm-button oclm-button-primary" type="button" id="oclm-save-ai"' + (savingAi ? ' disabled' : '') + '>' + (savingAi ? '应用中…' : '保存 AI配置') + '</button>' + (state.lastAppliedAt ? '<span class="oclm-applied-hint">已于 ' + escapeHtml(state.lastAppliedAt) + ' 更新配置</span>' : '') + '</div>' +
      '</div></div>' +

      '<div class="' + (activeTab === "access" ? '' : 'oclm-hidden') + '">' +
      '<h2>访问控制</h2>' +
      '<div class="oclm-form-grid">' +
      fieldInput("访问令牌", passwordHtml("oclm-token", form.token || "", "")) +
      fieldInput("允许访问来源", '<div class="oclm-origin-list">' + origins +
        '<div class="oclm-origin-new"><input class="oclm-control" type="text" id="oclm-new-origin" value="' + escapeHtml(state.newOrigin || "") + '" placeholder="' + escapeHtml((options.default_origin || "http://192.168.1.1:18789")) + '" /><button class="oclm-button" type="button" id="oclm-add-origin">添加</button></div>' +
        '<div class="oclm-hint">展示：仅允许来源于该地址访问控制台的控制功能</div></div>') +
      fieldToggle("允许通过 HTTP 访问时认证", "allow_insecure_auth", form.allow_insecure_auth, "仅控制 HTTP 下的控制台认证，不影响端口监听") +
      fieldToggle("关闭设备身份校验", "disable_device_auth", form.disable_device_auth, "警告：仅建议在可信环境中开启，在内网生效") +
      '<div class="oclm-section-submit"><button class="oclm-button oclm-button-primary" type="button" id="oclm-save-access"' + (savingAccess ? ' disabled' : '') + '>' + (savingAccess ? '应用中…' : '保存访问控制设置') + '</button>' + (state.lastAppliedAt ? '<span class="oclm-applied-hint">已于 ' + escapeHtml(state.lastAppliedAt) + ' 更新配置</span>' : '') + '</div>' +
      '</div></div>' +

      '<div class="' + (activeTab === "cleanup" ? '' : 'oclm-hidden') + '">' +
      '<h2>卸载清理</h2>' +
      '<div class="oclm-banner">以下操作会影响当前安装环境，请在确认后执行。</div>' +
      '<div class="oclm-danger-actions">' +
      '<button class="oclm-button" type="button" data-op="uninstall_openclaw">卸载 OpenClaw（保留 Node）</button>' +
      '<button class="oclm-button oclm-button-danger" type="button" data-op="uninstall">卸载</button>' +
      '<button class="oclm-button oclm-button-danger" type="button" data-op="purge">彻底清理</button>' +
      '</div>' +
      '</div>' +
      '</section>' +
      '</div></div></div>';

    bindEvents();
  }

  function updateStatusDom(status) {
    status = status || {};
    var gatewayActive = !!(status.running || status.reachable);

    function byId(id) {
      if (root.getElementById) return root.getElementById(id);
      return root.querySelector("#" + id);
    }

    var pill = byId("oclm-status-pill");
    var dot = byId("oclm-status-dot");
    var textEl = byId("oclm-status-text");
    if (!pill || !dot || !textEl) {
      render();
      return;
    }

    pill.style.setProperty("--oclm-spin-duration", statusSpinSeconds(status) + "s");
    dot.classList.remove("is-success");
    dot.classList.remove("is-danger");
    var cls = statusDotClass(status);
    if (cls) dot.classList.add(cls);
    textEl.textContent = statusText(status);

    var uptimeWrap = byId("oclm-uptime");
    var uptimeText = byId("oclm-uptime-text");
    if (uptimeWrap && uptimeText) {
      if (status.running && status.uptime_human) {
        uptimeText.textContent = String(status.uptime_human);
        uptimeWrap.classList.remove("oclm-hidden");
      } else {
        uptimeText.textContent = "";
        uptimeWrap.classList.add("oclm-hidden");
      }
    }

    var pidRow = byId("oclm-pid-row");
    var pidText = byId("oclm-pid");
    if (pidRow && pidText) {
      if (status.running && status.pid) {
        pidText.textContent = String(status.pid);
        pidRow.classList.remove("oclm-hidden");
      } else {
        pidText.textContent = "";
        pidRow.classList.add("oclm-hidden");
      }
    }

    var addrText = byId("oclm-address-text");
    if (addrText) addrText.textContent = maskedTokenUrl(status.token_url || status.base_url || "");
    var copyBtn = byId("oclm-copy-token-url");
    if (copyBtn) {
      if (status.token_url || status.base_url) copyBtn.classList.remove("oclm-hidden");
      else copyBtn.classList.add("oclm-hidden");
    }

    var baseDirEl = byId("oclm-status-base-dir");
    if (baseDirEl) baseDirEl.textContent = String(status.base_dir || "-");
    var openclawVerEl = byId("oclm-openclaw-version");
    if (openclawVerEl) openclawVerEl.textContent = String(status.openclaw_version || "-");
    var nodeVerEl = byId("oclm-node-version");
    if (nodeVerEl) nodeVerEl.textContent = String(status.node_version || "-");

    var installInline = byId("oclm-install-inline");
    var installBtn = byId("oclm-install-btn");
    var updateBtn = byId("oclm-update-btn");
    var cancelInstallBtn = byId("oclm-cancel-install");
    var openConsoleBtn = byId("oclm-open-console");
    var noteEl = byId("oclm-status-note");
    var updateCheck = getUpdateCheck();

    var showInstallAction = !status.installed;
    var showUpdateAction = !!(status.installed && !status.installing);
    if (installInline) {
      if (showInstallAction) installInline.classList.remove("oclm-hidden");
      else installInline.classList.add("oclm-hidden");
    }
    if (installBtn) {
      installBtn.textContent = status.installing ? (status.task_op === "upgrade" ? "更新中" : "安装中") : "立即安装";
      installBtn.disabled = !!status.installing;
    }
    if (updateBtn) {
      updateBtn.textContent = updateActionLabel(status);
      updateBtn.disabled = !!(updateCheck.checking || updateCheck.upgrading);
      if (showUpdateAction) updateBtn.classList.remove("oclm-hidden");
      else updateBtn.classList.add("oclm-hidden");
    }
    if (cancelInstallBtn) {
      if (status.installing) cancelInstallBtn.classList.remove("oclm-hidden");
      else cancelInstallBtn.classList.add("oclm-hidden");
    }
    if (openConsoleBtn) {
      if (gatewayActive) openConsoleBtn.classList.remove("oclm-hidden");
      else openConsoleBtn.classList.add("oclm-hidden");
      openConsoleBtn.disabled = !state.consoleReady;
      openConsoleBtn.innerHTML = openclawIcon("oclm-button-icon") + (state.consoleReady ? "打开控制台" : "控制台准备中…");
    }
    if (noteEl) {
      var noteText = statusNoteText(status);
      noteEl.textContent = noteText;
      if (noteText) noteEl.classList.remove("oclm-hidden");
      else noteEl.classList.add("oclm-hidden");
    }

    var svcWrap = byId("oclm-service-actions");
    var btnStart = byId("oclm-btn-start");
    var btnStop = byId("oclm-btn-stop");
    var btnRestart = byId("oclm-btn-restart");
    var showServiceActions = !!(status.installed && !status.installing);
    var canStartService = !!(!status.running && !status.reachable);
    var canStopService = !!status.running;

    if (svcWrap) {
      if (showServiceActions) svcWrap.classList.remove("oclm-hidden");
      else svcWrap.classList.add("oclm-hidden");
    }
    if (btnStart) {
      if (showServiceActions && canStartService) btnStart.classList.remove("oclm-hidden");
      else btnStart.classList.add("oclm-hidden");
    }
    if (btnStop) {
      if (showServiceActions && canStopService) btnStop.classList.remove("oclm-hidden");
      else btnStop.classList.add("oclm-hidden");
    }
    if (btnRestart) {
      if (showServiceActions) btnRestart.classList.remove("oclm-hidden");
      else btnRestart.classList.add("oclm-hidden");
    }
  }

  function fieldInput(label, control) {
    return '<div class="oclm-field"><div class="oclm-label">' + label + '</div><div>' + control + '</div></div>';
  }

  function fieldToggle(label, key, checked, hint) {
    return '' +
      '<div class="oclm-field">' +
      '<div class="oclm-label">' + label + '</div>' +
      '<div><label class="oclm-toggle"><input type="checkbox" id="oclm-' + key + '"' + (checked ? ' checked' : '') + ' /><span class="oclm-toggle-track"></span></label>' +
      (hint ? '<div class="oclm-hint">' + hint + '</div>' : '') +
      '</div></div>';
  }

  function selectHtml(id, value, items) {
    return '<select class="oclm-select" id="' + id + '">' + items.map(function(item) {
      return '<option value="' + escapeHtml(item[0]) + '"' + (value === item[0] ? ' selected' : '') + '>' + escapeHtml(item[1]) + '</option>';
    }).join("") + '</select>';
  }

  function passwordHtml(id, value, placeholder) {
    return '' +
      '<div class="oclm-password-wrap">' +
      '<input class="oclm-control" type="password" id="' + id + '" value="' + escapeAttr(value || "") + '" placeholder="' + escapeAttr(placeholder || "") + '" />' +
      '<button class="oclm-button oclm-eye-button" type="button" data-toggle-password="' + id + '" aria-label="显示密钥">' + eyeIcon(false) + '</button>' +
      '</div>';
  }

  function eyeIcon(off) {
    if (off) {
      return '' +
        '<svg viewBox="0 0 24 24" aria-hidden="true">' +
        '<path d="M3 3l18 18"></path>' +
        '<path d="M10.6 10.7a3 3 0 0 0 4.2 4.2"></path>' +
        '<path d="M9.9 5.1A10.9 10.9 0 0 1 12 5c5.2 0 9.3 4.1 10 7-0.3 1.1-1.1 2.6-2.4 3.9"></path>' +
        '<path d="M6.2 6.2C4.3 7.6 3.2 9.6 2 12c0.7 2.9 4.8 7 10 7 1 0 2-.2 2.9-.5"></path>' +
      '</svg>';
    }
    return '' +
      '<svg viewBox="0 0 24 24" aria-hidden="true">' +
      '<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7z"></path>' +
      '<circle cx="12" cy="12" r="3"></circle>' +
      '</svg>';
  }

  function syncDraftFromDom() {
    if (!state.form) {
      state.form = {};
    }

    function getEl(id) {
      return root.getElementById ? root.getElementById(id) : root.querySelector("#" + id);
    }

    var portEl = getEl("oclm-port");
    if (portEl) state.form.port = portEl.value;

    var bindEl = getEl("oclm-bind");
    if (bindEl) state.form.bind = bindEl.value;

    var baseDirEl = getEl("oclm-base-dir");
    if (baseDirEl) state.form.base_dir = baseDirEl.value;

    var installAccelEl = getEl("oclm-install-accelerated");
    if (installAccelEl) state.form.install_accelerated = !!installAccelEl.checked;

    var agentEl = getEl("oclm-agent");
    if (agentEl) state.form.default_agent = agentEl.value;

    var apiKeyEl = getEl("oclm-api-key");
    if (apiKeyEl) state.form.provider_api_key = apiKeyEl.value;

    var baseUrlEl = getEl("oclm-base-url");
    if (baseUrlEl) state.form.provider_base_url = baseUrlEl.value;

    var modelEl = getEl("oclm-model");
    if (modelEl) state.form.default_model = modelEl.value;

    var tokenEl = getEl("oclm-token");
    if (tokenEl) state.form.token = tokenEl.value;

    var allowInsecureEl = getEl("oclm-allow_insecure_auth");
    if (allowInsecureEl) state.form.allow_insecure_auth = !!allowInsecureEl.checked;

    var disableDeviceEl = getEl("oclm-disable_device_auth");
    if (disableDeviceEl) state.form.disable_device_auth = !!disableDeviceEl.checked;

    var newOriginEl = getEl("oclm-new-origin");
    if (newOriginEl) state.newOrigin = newOriginEl.value;
  }

  function bindEvents() {
    Array.prototype.forEach.call(root.querySelectorAll("[data-tab]"), function(el) {
      el.onclick = function() {
        syncDraftFromDom();
        state.activeTab = el.getAttribute("data-tab") || "basic";
        render();
      };
    });

    Array.prototype.forEach.call(root.querySelectorAll("[data-op]"), function(el) {
      el.onclick = function() {
        var op = el.getAttribute("data-op");
        if (!op) return;
        if (op === "uninstall_openclaw" && !window.confirm("卸载 OpenClaw 运行时但保留 Node.js，确认继续？")) return;
        if (op === "uninstall" && !window.confirm("卸载将删除运行时，但保留数据目录。确认继续？")) return;
        if (op === "purge" && !window.confirm("彻底清理会删除运行时和数据目录。确认继续？")) return;
        postForm(config.opUrl, { op: op }).then(function(rv) {
          if (!rv || !rv.ok) {
            if (rv && rv.busy && rv.running_task_id) {
              showTaskLog(rv.running_task_id);
              return;
            }
            window.alert((rv && rv.error) || "操作失败");
            return;
          }
          state.lastTaskRunning = true;
          showTaskLog((rv && (rv.running_task_id || rv.task_id)) || "openclawmgr");
          scheduleStatusRefresh(op === "restart" ? 8 : 6, 1000);
        });
      };
    });

    Array.prototype.forEach.call(root.querySelectorAll("[data-open-console]"), function(el) {
      el.onclick = function() {
        if (!state.consoleReady) {
          window.alert("控制台正在启动，请稍候再试。");
          return;
        }
        var url = (state.status && state.status.token_url) || "";
        if (!url) {
          window.alert("控制台地址不可用");
          return;
        }
        window.open(url, "_blank", "noreferrer");
      };
    });

    Array.prototype.forEach.call(root.querySelectorAll("[data-install-action]"), function(el) {
      el.onclick = function() {
        var accelerated = !!(root.getElementById("oclm-install-accelerated") && root.getElementById("oclm-install-accelerated").checked);
        var baseDirEl = root.getElementById("oclm-base-dir");
        var baseDir = baseDirEl && baseDirEl.value ? baseDirEl.value.trim() : "";
        if (!baseDir) {
          window.alert("请先选择数据目录并保存应用，再执行安装。");
          if (baseDirEl) baseDirEl.focus();
          return;
        }
        if (!state.status || state.status.installing) {
          return;
        }
        state.status.installing = true;
        state.status.task_running = true;
        state.status.task_op = "install";
        render();
        postJson(config.configUrl, { base_dir: baseDir, install_accelerated: accelerated }).then(function(cfgRv) {
          if (!cfgRv || !cfgRv.ok) {
            state.status.installing = false;
            render();
            window.alert((cfgRv && cfgRv.error) || "保存安装选项失败");
            return;
          }
          state.form.install_accelerated = accelerated;
          state.form.base_dir = baseDir;
          return postForm(config.opUrl, { op: "install" });
        }).then(function(rv) {
          if (!rv) return;
          if (!rv || !rv.ok) {
            if (rv && rv.busy && rv.running_task_id) {
              showTaskLog(rv.running_task_id);
              return;
            }
            state.status.installing = false;
            render();
            window.alert((rv && rv.error) || "启动安装失败");
            return;
          }
          state.lastTaskRunning = true;
          showTaskLog((rv && (rv.running_task_id || rv.task_id)) || "openclawmgr");
          scheduleStatusRefresh(10, 1000);
        }).catch(function() {
          state.status.installing = false;
          render();
          window.alert("启动安装失败");
        });
      };
    });

    Array.prototype.forEach.call(root.querySelectorAll("[data-update-action]"), function(el) {
      el.onclick = function() {
        var updateCheck = getUpdateCheck();
        if (!state.status || !state.status.installed || state.status.installing) {
          return;
        }

        if (updateCheck.hasUpdate) {
          updateCheck.upgrading = true;
          updateCheck.error = "";
          state.status.installing = true;
          state.status.task_running = true;
          state.status.task_op = "upgrade";
          render();
          postForm(config.opUrl, { op: "upgrade" }).then(function(rv) {
            if (!rv || !rv.ok) {
              updateCheck.upgrading = false;
              state.status.installing = false;
              state.status.task_running = false;
              state.status.task_op = "";
              render();
              if (rv && rv.busy && rv.running_task_id) {
                showTaskLog(rv.running_task_id);
                return;
              }
              window.alert((rv && rv.error) || "启动更新失败");
              return;
            }
            state.lastTaskRunning = true;
            showTaskLog((rv && (rv.running_task_id || rv.task_id)) || "openclawmgr");
            scheduleStatusRefresh(10, 1000);
          }).catch(function() {
            updateCheck.upgrading = false;
            state.status.installing = false;
            state.status.task_running = false;
            state.status.task_op = "";
            render();
            window.alert("启动更新失败");
          });
          return;
        }

        updateCheck.checking = true;
        updateCheck.error = "";
        render();
        postForm(config.checkUpdateUrl, {}).then(function(rv) {
          updateCheck.checking = false;
          if (!rv || !rv.ok) {
            updateCheck.checked = false;
            updateCheck.hasUpdate = false;
            updateCheck.error = (rv && rv.error) || "检测更新失败";
            updateCheck.localVersion = String((rv && rv.local_version) || (state.status && state.status.openclaw_version) || "");
            updateCheck.remoteVersion = String((rv && rv.remote_version) || "");
            render();
            window.alert(updateCheck.error);
            return;
          }
          updateCheck.checked = true;
          updateCheck.hasUpdate = !!rv.has_update;
          updateCheck.upgrading = false;
          updateCheck.error = "";
          updateCheck.localVersion = String(rv.local_version || (state.status && state.status.openclaw_version) || "");
          updateCheck.remoteVersion = String(rv.remote_version || "");
          render();
        }).catch(function() {
          updateCheck.checking = false;
          updateCheck.checked = false;
          updateCheck.hasUpdate = false;
          updateCheck.error = "检测更新失败";
          render();
          window.alert("检测更新失败");
        });
      };
    });

    Array.prototype.forEach.call(root.querySelectorAll("[data-toggle-password]"), function(el) {
      el.onclick = function() {
        var id = el.getAttribute("data-toggle-password");
        var input = id ? root.getElementById(id) : null;
        if (!input) return;
        input.type = input.type === "password" ? "text" : "password";
        el.innerHTML = eyeIcon(input.type !== "password");
        el.setAttribute("aria-label", input.type === "password" ? "显示密钥" : "隐藏密钥");
      };
    });

    var installAccelerated = root.getElementById("oclm-install-accelerated");
    if (installAccelerated) {
      installAccelerated.onchange = function() {
        state.form.install_accelerated = !!installAccelerated.checked;
      };
    }

    Array.prototype.forEach.call(root.querySelectorAll("[data-copy-token-url]"), function(el) {
      el.onclick = function() {
        var value = (state.status && (state.status.token_url || state.status.base_url)) || "";
        copyText(value).then(function(ok) {
          if (ok) {
            flashCopied(el);
          }
        });
      };
    });

    var agent = root.getElementById("oclm-agent");
    if (agent) {
      agent.onchange = function() {
        state.form.default_agent = agent.value;
        var model = root.getElementById("oclm-model");
        if (model) {
          var nextModel = modelForAgent(agent.value);
          model.value = nextModel;
          state.form.default_model = nextModel;
        }
      };
    }

    var apiKey = root.getElementById("oclm-api-key");
    if (apiKey) {
      apiKey.oninput = function() {
        state.form.provider_api_key = apiKey.value;
      };
    }

    var baseUrl = root.getElementById("oclm-base-url");
    if (baseUrl) {
      baseUrl.oninput = function() {
        state.form.provider_base_url = baseUrl.value;
      };
    }

    var modelInput = root.getElementById("oclm-model");
    if (modelInput) {
      modelInput.oninput = function() {
        state.form.default_model = modelInput.value;
      };
    }

    var addOrigin = root.getElementById("oclm-add-origin");
    if (addOrigin) {
      addOrigin.onclick = function() {
        var input = root.getElementById("oclm-new-origin");
        var value = input && input.value ? input.value.trim() : "";
        if (!value) return;
        state.form.allowed_origins = Array.isArray(state.form.allowed_origins) ? state.form.allowed_origins : [];
        state.form.allowed_origins.push(value);
        state.newOrigin = "";
        render();
      };
    }

    var newOrigin = root.getElementById("oclm-new-origin");
    if (newOrigin) {
      newOrigin.oninput = function() {
        state.newOrigin = newOrigin.value;
      };
    }

    Array.prototype.forEach.call(root.querySelectorAll("[data-remove-origin]"), function(el) {
      el.onclick = function() {
        var index = parseInt(el.getAttribute("data-remove-origin"), 10);
        if (isNaN(index)) return;
        state.form.allowed_origins.splice(index, 1);
        render();
      };
    });

    Array.prototype.forEach.call(root.querySelectorAll("[data-origin-index]"), function(el) {
      el.oninput = function() {
        var index = parseInt(el.getAttribute("data-origin-index"), 10);
        if (!isNaN(index)) {
          state.form.allowed_origins[index] = el.value;
        }
      };
    });

    var saveBasic = root.getElementById("oclm-save-basic");
    if (saveBasic) {
      saveBasic.onclick = function() {
        var payload = {
          port: root.getElementById("oclm-port").value,
          bind: root.getElementById("oclm-bind").value,
          base_dir: root.getElementById("oclm-base-dir").value,
          install_accelerated: !!(root.getElementById("oclm-install-accelerated") && root.getElementById("oclm-install-accelerated").checked),
        };
        state.savingSection = "basic";
        render();
        postJson(config.configUrl, payload).then(function(rv) { handleSaveResult(rv, "basic"); }).catch(function() {
          state.savingSection = "";
          render();
          window.alert("保存失败");
        });
      };
    }

    var saveAi = root.getElementById("oclm-save-ai");
    if (saveAi) {
      saveAi.onclick = function() {
        var payload = {
          default_agent: root.getElementById("oclm-agent").value,
          default_model: root.getElementById("oclm-model").value,
          provider_api_key: root.getElementById("oclm-api-key").value,
          provider_base_url: root.getElementById("oclm-base-url").value
        };
        state.savingSection = "ai";
        render();
        postJson(config.configUrl, payload).then(function(rv) { handleSaveResult(rv, "ai"); }).catch(function() {
          state.savingSection = "";
          render();
          window.alert("保存失败");
        });
      };
    }

    var saveAccess = root.getElementById("oclm-save-access");
    if (saveAccess) {
      saveAccess.onclick = function() {
        var payload = {
          token: root.getElementById("oclm-token").value,
          allowed_origins: (Array.isArray(state.form.allowed_origins) ? state.form.allowed_origins : []).map(function(item) { return item.trim(); }).filter(Boolean),
          allow_insecure_auth: !!root.getElementById("oclm-allow_insecure_auth").checked,
          disable_device_auth: !!root.getElementById("oclm-disable_device_auth").checked
        };
        state.savingSection = "access";
        render();
        postJson(config.configUrl, payload).then(function(rv) { handleSaveResult(rv, "access"); }).catch(function() {
          state.savingSection = "";
          render();
          window.alert("保存失败");
        });
      };
    }
  }

  function handleSaveResult(rv, section) {
    if (!rv || !rv.ok) {
      state.savingSection = "";
      render();
      window.alert((rv && rv.error) || "保存失败");
      return;
    }
    postForm(config.applyUrl, {}).then(function(applyRv) {
      state.savingSection = "";
      if (!applyRv || !applyRv.ok) {
        render();
        window.alert((applyRv && applyRv.error) || "应用配置失败");
        loadConfig();
        scheduleStatusRefresh(3, 600);
        return;
      }
      state.lastAppliedAt = applyRv.applied_at || "";
      render();
      loadConfig();
      scheduleStatusRefresh(6, 800);
    }).catch(function() {
      state.savingSection = "";
      render();
      window.alert("应用配置失败");
      loadConfig();
      scheduleStatusRefresh(3, 600);
    });
  }

  function refreshStatus(done) {
    request(config.statusUrl).then(function(data) {
      state.status = data || {};
      var updateCheck = getUpdateCheck();
      if (state.status && state.status.openclaw_version) {
        updateCheck.localVersion = String(state.status.openclaw_version || "");
      }
      if (!state.status || !state.status.installed) {
        updateCheck.upgrading = false;
        updateCheck.hasUpdate = false;
        updateCheck.checked = false;
      } else if (state.status.installing && state.status.task_op === "upgrade") {
        updateCheck.upgrading = true;
      } else if (!state.status.installing) {
        updateCheck.upgrading = false;
        if (updateCheck.remoteVersion && updateCheck.localVersion && updateCheck.remoteVersion === updateCheck.localVersion) {
          updateCheck.hasUpdate = false;
          updateCheck.checked = true;
          updateCheck.error = "";
        }
      }
      if (state.status && (state.status.running || state.status.reachable)) {
        if (!state.consoleReady) {
          pollConsoleReady(20);
        }
      } else {
        stopConsoleCheck();
        state.consoleReady = false;
      }
      if (state.status && state.status.task_running && !state.lastTaskRunning) {
        showTaskLog("openclawmgr");
      }
      state.lastTaskRunning = !!(state.status && state.status.task_running);
      updateStatusDom(state.status);
      ensureInstallWatch();
      if (typeof done === "function") {
        done();
      }
    }).catch(function() {
      state.status = state.status || {};
      updateStatusDom(state.status);
      ensureInstallWatch();
      if (typeof done === "function") {
        done();
      }
    });
  }

  function loadConfig() {
    request(config.configUrl).then(function(data) {
      if (!data || !data.ok) {
        return;
      }
      state.form = data.config || {};
      state.form.default_model = resolveModelValue(state.form);
      state.options = data.options || {};
      if (!state.form.base_dir) {
        var suggested = state.options && state.options.suggested_base_dir ? String(state.options.suggested_base_dir) : "";
        if (suggested) {
          state.form.base_dir = suggested;
        }
      }
      render();
      refreshStatus();
    }).catch(function() {
      state.form = state.form || {};
      state.options = state.options || { base_dir_choices: [] };
      render();
    });
  }

  fetch(config.staticBase + "/app.css").then(function(r) { return r.text(); }).then(function(css) {
    styleText = css || "";
    loadConfig();
  });
})();
