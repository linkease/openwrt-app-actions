# Openwrt-actions

## 使用步骤
1. 选择actions标签，选择Build IPKs![image](https://user-images.githubusercontent.com/1214708/153843131-615197e2-4ff4-4c0b-b30a-372e1c513158.png)

2. 点击run workflow，输入要编译的插件名称，空格隔开，或者填“all”用来编译所有插件，然后开始编译![image](https://user-images.githubusercontent.com/1214708/153843217-0591a7e6-4758-461e-8b2b-9bb830b87fb2.png)

3. 等待编译完成，点击任务进入详情页
4. 在详情页下载插件压缩包![image](https://user-images.githubusercontent.com/1214708/153843272-81843b45-6dc8-4945-871f-a9a467f63c33.png)

## ForkApp

1. ./forkapp forkapp -from ../applications/luci-app-plex -to ../applications/luci-app-demo
2. ./forkapp upload -ip 192.168.100.1 -pwd "password" -from ../applications/luci-app-demo -to /root/
3. ./forkapp upload -ip 192.168.100.1 -pwd "password" -from ../applications/luci-app-demo -to /root/ -script ../tools/simple-install.sh -install

## 同步 AgentFlow

在 it-runner 中运行 `sync-agentflow`。任务会读取官方发布清单，下载并校验 amd64、arm64 二进制，然后更新 `applications/agentflow/Makefile`。同一版本的新构建会递增 `PKG_RELEASE`，新版本会将其重置为 1。
