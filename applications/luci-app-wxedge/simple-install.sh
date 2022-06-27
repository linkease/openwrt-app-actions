#!/bin/sh

# run in router

mkdir -p /usr/lib/lua/luci/view/wxedge
cp ./luasrc/controller/wxedge.lua /usr/lib/lua/luci/controller/
cp ./luasrc/view/wxedge/* /usr/lib/lua/luci/view/wxedge/
cp -rf ./root/* /
rm -rf /tmp/luci-*

