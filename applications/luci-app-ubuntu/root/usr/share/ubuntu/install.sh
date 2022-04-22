#!/bin/sh

image_name=`uci get ubuntu.@ubuntu[0].image 2>/dev/null`
# TODO auto detech platform
# TODO option for full and standard
# linkease/desktop-ubuntu-full-arm64:latest
# linkease/desktop-ubuntu-standard-arm64:latest
# linkease/desktop-ubuntu-full-amd64:latest
# linkease/desktop-ubuntu-standard-amd64:latest

[ -z "$image_name" ] && image_name="linkease/desktop-ubuntu-standard-arm64:latest"

get_image(){
    local version=`uci get ubuntu.@ubuntu[0].version 2>/dev/null`
    
    ARCH="arm64"
    if echo `uname -m` | grep -Eqi 'x86_64'; then
        ARCH='amd64'
    elif  echo `uname -m` | grep -Eqi 'aarch64'; then
        ARCH='arm64'
    else
        ARCH='arm64'
    fi

    #if [ "${version}" == "full" ];then
    #    image_name="linkease/desktop-ubuntu-full-arm64:latest"
    #fi

    #if [ "${version}" == "standard" ];then
    #    image_name="linkease/desktop-ubuntu-standard-arm64:latest"
    #fi
    
    image_name=linkease/desktop-ubuntu-${version}-${ARCH}:latest
}

install(){
    local password=`uci get ubuntu.@ubuntu[0].password 2>/dev/null`
    local port=`uci get ubuntu.@ubuntu[0].port 2>/dev/null`
    [ -z "$password" ] && password="password"
    [ -z "$port" ] && port=6901
    get_image
    docker network ls -f "name=docker-pcnet" | grep -q docker-pcnet || \
    docker network create -d bridge --subnet=10.10.100.0/24 --ip-range=10.10.100.0/24 --gateway=10.10.100.1 docker-pcnet

    docker run -d --name ubuntu \
    --dns=223.5.5.5 -u=0:0 \
    -v=/mnt:/mnt:rslave \
    --net="docker-pcnet" \
    --ip=10.10.100.9 \
    --shm-size=512m \
    -p $port:6901 \
    -e VNC_PW=$password \
    -e VNC_USE_HTTP=0 \
    --restart unless-stopped \
    $image_name
}

check_root(){
  local result=0
  #ignore the disk check in x86
  if echo `uname -m` | grep -Eqi 'x86_64'; then
    result=1
  else
    local DOCKERPATH=`docker info 2>/dev/null | grep ' Docker Root Dir:' | tail -c +19 -q`
    [ -n "$DOCKERPATH" ] && result=`findmnt -T $DOCKERPATH 2>/dev/null | grep -c /dev/sd`
  fi
  echo -n $result
}

while getopts ":ilc" optname
do
    case "$optname" in
        "l")
        get_image
        echo -n $image_name
        ;;
        "i")
        install
        ;;
        "c")
        check_root
        ;;
        ":")
        echo "No argument value for option $OPTARG"
        ;;
        "?")
        echo "未知选项 $OPTARG"
        ;;
        *)
        echo "Unknown error while processing options"
        ;;
    esac
done
