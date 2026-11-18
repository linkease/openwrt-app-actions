# 第三方仓库测试（仅 third 分支）

`third` 是长期保留的第三方测试分支，**不向 `main` 合并，也不向 `main` 发合并 PR**。第三方源码保留在作者仓库，本仓库只维护 feed 地址和测试说明。

## 构建 Codex iStore

复用现有的 **Build IPKs**，不用新增 workflow：

1. 打开本仓库的 Actions → **Build IPKs** → **Run workflow**。
2. **Branch 选择 `third`**。
3. `applications` 填 `luci-app-codex-istore`。
4. `target` 填 `x64`。
5. 运行结束后，在该次任务的 Artifacts 下载 `x64`，查看其中的 `ipk/` 和 `apk/`。

也可以在有仓库写权限、已登录 GitHub CLI 的终端中触发：

```sh
gh workflow run main.yml --repo linkease/openwrt-app-actions --ref third \
  -f applications='luci-app-codex-istore' -f target=x64
gh run list --repo linkease/openwrt-app-actions --branch third --workflow main.yml
```

同一架构下可以在 `applications` 中用空格分隔多个包名。不同架构支持范围的项目应分开触发。

### 当前测试范围

| Feed 名 | 仓库 / 版本 | 编译包 | target |
| --- | --- | --- | --- |
| `third_party` | [linkease/istore-packages](https://github.com/linkease/istore-packages)，跟随 `main` | 按仓库中的包名选择 | 按所选包支持范围选择 |
| `codex_istore` | [easepi/codex-istore](https://github.com/easepi/codex-istore)，跟随可维护 fork 的 `main` | `luci-app-codex-istore` | `x64` |

Codex 作者目前只验证了 OpenWrt 24.10.8 x86_64 / opkg；本仓库现有 `x64.env` 使用 **21.02.3 IPK SDK + 25.12.2 APK SDK**。这里接入的是这两套 SDK 的兼容性测试，不是复现作者的 24.10.8 构建。构建成功也不能代替在目标路由器上验证安装、页面和运行行为；APK 尤其需要单独验证。

此处只选择 LuCI 包，其中文语言包由 LuCI 构建系统生成。不要填 `app-meta-codex-istore`：它的 Makefile 包含 `../../meta.mk`，需要 iStore 元数据仓库的布局，并不是可以直接交给 SDK 构建的普通包。完整仓库的 feed 扫描可能出现该元数据包缺少 `meta.mk` 的提示，需要与所选 LuCI 包的实际构建结果区分。

**第三方测试请显式填写包名和 target，不使用 `all`。** 现有 workflow 的 `applications=all` 会安装本地 `applications/` 及所有自定义 feeds 中的包，`target=all` 会展开四个架构。它们不表示“只构建第三方项目支持的包和架构”。

## 接入后续仓库

1. 确认仓库中包含 SDK 可扫描的 OpenWrt 包目录和 Makefile，记录实际包名、依赖和支持架构。只有二进制或普通应用源码的仓库，需要作者先提供 OpenWrt 打包配方。
2. 只在 `feeds/third.conf` 增加一条 feed，使用唯一的名称（字母、数字、下划线）：

   ```text
   src-git example https://github.com/OWNER/REPO.git;main
   ```

   跟随分支时每次构建会更新到该分支最新代码。复现某个 PR 或版本时，改用完整 commit SHA：

   ```text
   src-git example https://github.com/OWNER/REPO.git^FULL_COMMIT_SHA
   ```

   两种写法二选一。仓库 URL 使用 clone 地址，不使用 GitHub 的 `/tree/main` 页面地址。当前 workflow 遍历 feed 文件的实现要求每行都是有效的 feed 条目，请把说明写在本文中，不在配置里放注释或空行。
3. 在上表记录仓库、版本、实际编译包名和支持 target，然后按前面的方式触发 **Build IPKs**，Branch 始终选 `third`。
4. 更新固定版本时，只修改该 feed 的 SHA 和上表。可以反复触发同一配置，无需复制源码或新增 workflow。

`feeds/third.conf` 是对默认自定义 feed 列表的**完整替换**，不是追加文件，所以保留了 `nas`、`nas_luci`、`istore` 作为依赖来源，以及此前 `third` 使用的 `third_party`。SDK 自带的 base / LuCI feed 和本地 `applications/` 仍由 workflow 加载。新项目有额外依赖 feed 时，也应在这里登记。包名应避免与本地应用及其他 feeds 重复；同名包需要先明确优先级，不能假设追加的 feed 会覆盖已有包。

## 与 main 的边界

- 第三方地址只写入 `feeds/third.conf`，默认 `feeds.conf` 与 `main` 保持一致。
- 第三方说明只放在 `third-party/`；复用 `.github/workflows/main.yml` 和现有 SDK 配置，不复制构建流程。
- 现有 workflow 在分支名为 `third` 时自动加载 `feeds/third.conf`，在 `main` 上继续使用默认 `feeds.conf`。产物仅通过该次 Actions 的 Artifact 提供，现有构建流程不发布到正式软件源。
- 需要更新构建基础设施时，允许从 `main` 单向同步到 `third`。同步后检查分支 feed 选择逻辑仍在，并比较默认配置；禁止反向合并。新增配置和文档独占路径，可以降低与 `main` 的文本冲突，但无法保证未来任何上游改动都无冲突。
- `third` 不向 `main` 合并是分支维护约定；本地文件无法阻止有权限的人发起或合入 PR。

现有 `main.yml` 已在默认分支上，因而可以在 Actions 界面选择 `third` 执行。不要为了第三方测试另建一个仅存在于 `third` 的手动 workflow：GitHub 要求 `workflow_dispatch` 的 workflow 存在于默认分支，届时会影响手动入口。

参考：[iStore PR #836](https://github.com/istoreos/istore-repo/pull/836)、[Codex 仓库构建说明](https://github.com/easepi/codex-istore/blob/main/README.md)、[GitHub 手动触发 workflow 说明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)、[OpenWrt feeds 实现](https://github.com/openwrt/openwrt/blob/v21.02.3/scripts/feeds)。
