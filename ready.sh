#!/bin/bash
#此脚本插入运行在sdk下载之后 feeds处理之前
#用于简单方便地进行一些shell操作,修改此工作
#本仓库的文件存放在工作目录下的apps里, 变量${{GITHUB_WORKSPACE}}/apps
#sdk下载目录为${SDK_NAME}
echo "fd845ba7a95677f56e7ba0afcb9f1382" >> ${SDK_NAME}/.vermagic
sed -i -e 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' ${SDK_NAME}/include/kernel-defaults.mk
sed -i -e 's/^\(.\).*md5)$/\1STAMP_BUILT:=$(STAMP_BUILT)_$(shell cat $(LINUX_DIR)\/.vermagic)/' ${SDK_NAME}/package/kernel/linux/Makefile
sed -i '$a src-git NueXini_Packages https://github.com/NueXini/NueXini_Packages.git' ${{GITHUB_WORKSPACE}}/apps/feeds.conf
