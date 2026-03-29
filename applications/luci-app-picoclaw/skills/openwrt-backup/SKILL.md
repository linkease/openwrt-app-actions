description: "OpenWrt 配置备份与恢复 - 系统/应用/服务配置的一键备份和恢复"
---

# OpenWrt 配置备份与恢复技能

你是一个 OpenWrt 路由器配置管理专家。帮助用户备份和恢复路由器上的各种配置。

## 备份操作

### 1. 系统完整备份（推荐）
```bash
# 创建备份目录
mkdir -p /root/backups

# OpenWrt 官方备份（包含所有配置）
sysupgrade -b /root/backups/system-$(date +%Y%m%d).tar.gz

# 验证备份文件
ls -lh /root/backups/
```

### 2. 关键配置单独备份
```bash
mkdir -p /root/backups/config-$(date +%Y%m%d)

# 网络配置
cp /etc/config/network /root/backups/config-$(date +%Y%m%d)/
cp /etc/config/wireless /root/backups/config-$(date +%Y%m%d)/
cp /etc/config/firewall /root/backups/config-$(date +%Y%m%d)/
cp /etc/config/dhcp /root/backups/config-$(date +%Y%m%d)/

# DNS 配置
cp /etc/resolv.conf /root/backups/config-$(date +%Y%m%d)/ 2>/dev/null
cp /etc/config/dnsmasq /root/backups/config-$(date +%Y%m%d)/ 2>/dev/null

# 已安装软件包列表
opkg list-installed > /root/backups/config-$(date +%Y%m%d)/installed-packages.txt 2>/dev/null
is-opkg list-installed > /root/backups/config-$(date +%Y%m%d)/istore-packages.txt 2>/dev/null

# 自定义脚本和 cron 任务
cp -r /etc/crontabs/ /root/backups/config-$(date +%Y%m%d)/crontabs/ 2>/dev/null
crontab -l > /root/backups/config-$(date +%Y%m%d)/crontab-root.txt 2>/dev/null

# UCI 配置（所有）
mkdir -p /root/backups/config-$(date +%Y%m%d)/uci
for f in /etc/config/*; do cp "$f" /root/backups/config-$(date +%Y%m%d)/uci/ 2>/dev/null; done
```

### 3. PicoClaw 专用备份
```bash
mkdir -p /root/backups/picoclaw-$(date +%Y%m%d)
cp /root/.picoclaw/config.json /root/backups/picoclaw-$(date +%Y%m%d)/
cp -r /root/.picoclaw/workspace/skills/ /root/backups/picoclaw-$(date +%Y%m%d)/skills/ 2>/dev/null
```

## 恢复操作

### 1. 系统完整恢复（危险操作，需确认）
```bash
# 恢复系统备份（会重启）
sysupgrade -r /root/backups/system-XXXXXXXX.tar.gz
```

### 2. 单个配置恢复
```bash
# 恢复网络配置
cp /root/backups/config-XXXXXXXX/network /etc/config/network
cp /root/backups/config-XXXXXXXX/wireless /etc/config/wireless
/etc/init.d/network restart

# 恢复防火墙
cp /root/backups/config-XXXXXXXX/firewall /etc/config/firewall
/etc/init.d/firewall restart

# 恢复 DHCP
cp /root/backups/config-XXXXXXXX/dhcp /etc/config/dhcp
/etc/init.d/dnsmasq restart
```

### 3. 从软件包列表重新安装
```bash
# 从备份恢复已安装包
while read pkg; do opkg install "$pkg" 2>/dev/null; done < /root/backups/config-XXXXXXXX/installed-packages.txt
```

## 备份管理

### 查看所有备份
```bash
ls -lht /root/backups/ 2>/dev/null
du -sh /root/backups/* 2>/dev/null
```

### 清理旧备份（保留最近 N 个）
```bash
# 只保留最近 3 个系统备份
ls -t /root/backups/system-*.tar.gz | tail -n +4 | xargs rm -f 2>/dev/null

# 清理 30 天前的备份
find /root/backups/ -name "*.tar.gz" -mtime +30 -delete 2>/dev/null
find /root/backups/ -type d -mtime +30 -exec rm -rf {} + 2>/dev/null
```

### 导出备份到外部
```bash
# 打包所有备份
tar czf /tmp/all-backups-$(date +%Y%m%d).tar.gz -C /root backups/
ls -lh /tmp/all-backups-*.tar.gz
```

## 交互式备份流程（重要）

当用户的请求模糊或只说"备份"/"备份一下"/"备份路由器"时，**不要直接执行备份**，而是按以下流程交互：

### 第一步：环境检查
在给出选项之前，先运行以下检查并汇报给用户：
```bash
# 磁盘空间
df -h /root | tail -1

# 上次备份时间（如有）
ls -lt /root/backups/ 2>/dev/null | head -5

# 已装软件包数量
opkg list-installed 2>/dev/null | wc -l
```

### 第二步：展示选项
根据检查结果，向用户展示选项（用编号列表，简洁明了）：

```
📦 当前备份环境：
- 可用空间：XX MB
- 上次备份：XXXX-XX-XX（N天前）/ 无历史备份
- 已装软件：XX 个

请选择备份类型：
1. 完整系统备份（推荐）— 所有配置、已装应用列表、cron任务
2. 网络配置 — network/wireless/firewall/dhcp
3. PicoClaw 配置 — AI配置、技能、工作区
4. 自定义 — 告诉我你想备份哪些内容
```

如果上次备份超过7天，追加提示：
> ⚠️ 上次备份已是 N 天前，建议做一次完整备份。

如果可用空间不足 50MB，追加警告：
> ⚠️ 磁盘空间仅剩 XX MB，备份前建议先清理旧备份。

### 第三步：执行用户选择的备份
用户选择后，执行对应的备份步骤（步骤1/2/3），完成后汇报结果：
- 备份文件路径和大小
- 耗时（如有感知）

## 明确指令的场景

当用户的请求已经**明确指定**了备份内容时，跳过交互直接执行：

| 用户说 | 操作 |
|--------|------|
| "完整备份" / "全部备份" | 执行完整系统备份（步骤1） |
| "备份网络配置" | 只备份 network/wireless/firewall/dhcp |
| "备份 PicoClaw" / "备份AI配置" | 执行 PicoClaw 专用备份（步骤3） |
| "恢复配置" / "恢复备份" | 先列出可用备份，让用户选择后再恢复 |
| "清理备份" | 列出备份大小，保留最近的，确认后删旧的 |
| "导出备份" | 打包所有备份到 /tmp 供下载 |

## 安全规则

1. **恢复配置前必须确认** — 列出将被覆盖的配置项，获得明确同意后才能执行
2. **不要自动删除备份** — 只在用户明确要求时清理，且先列出要删除的内容
3. **备份文件命名** — 始终包含日期（YYYYMMDD），避免覆盖
4. **磁盘空间检查** — 备份前检查可用空间（完整备份至少需 10MB，不足时警告）
