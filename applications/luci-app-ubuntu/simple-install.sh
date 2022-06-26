#!/bin/sh

# run in router

mkdir -p /usr/lib/lua/luci/view/ubuntu
cp ./luasrc/controller/ubuntu.lua /usr/lib/lua/luci/controller/
cp ./luasrc/view/ubuntu/* /usr/lib/lua/luci/view/ubuntu/
cp -rf ./root/* /
rm -rf /tmp/luci-*

