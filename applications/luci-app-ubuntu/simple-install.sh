#!/bin/sh

# run in router

mkdir -p /usr/lib/lua/luci/view/ubuntu/cbi
cp ./luasrc/controller/ubuntu.lua /usr/lib/lua/luci/controller/
cp ./luasrc/model/cbi/ubuntu/ubuntu.lua /usr/lib/lua/luci/model/cbi/ubuntu/
cp ./luasrc/view/ubuntu/* /usr/lib/lua/luci/view/ubuntu/
cp -rf ./root /
