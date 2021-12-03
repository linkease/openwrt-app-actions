#!/bin/sh

image_name=`uci get jellyfin.@jellyfin[0].image 2>/dev/null`

[ -z "$image_name" ] && image_name="default"

if [ "$image_name" == "default" ]; then
    image_name="jjm2473/jellyfin-rtk:latest"
    if uname -r | grep -q '^4\.9\.'; then
        image_name="jjm2473/jellyfin-rtk:4.9-latest"
    fi
fi

install(){
    local media=`uci get jellyfin.@jellyfin[0].media_path 2>/dev/null`
    local config=`uci get jellyfin.@jellyfin[0].config_path 2>/dev/null`
    local cache=`uci get jellyfin.@jellyfin[0].cache_path 2>/dev/null`
    local port=`uci get jellyfin.@jellyfin[0].port 2>/dev/null`

    if [ -z "$config" ]; then
        echo "config path is empty!" >&2
        exit 1
    fi

    [ -z "$port" ] && port=8096

    local cmd="docker run --restart=unless-stopped -d \
    --device /dev/rpc0:/dev/rpc0 \
    --device /dev/rpc1:/dev/rpc1 \
    --device /dev/rpc2:/dev/rpc2 \
    --device /dev/rpc3:/dev/rpc3 \
    --device /dev/rpc4:/dev/rpc4 \
    --device /dev/rpc5:/dev/rpc5 \
    --device /dev/rpc6:/dev/rpc6 \
    --device /dev/rpc7:/dev/rpc7 \
    --device /dev/rpc100:/dev/rpc100 \
    --device /dev/uio250:/dev/uio250 \
    --device /dev/uio251:/dev/uio251 \
    --device /dev/uio252:/dev/uio252 \
    --device /dev/uio253:/dev/uio253 \
    --device /dev/ion:/dev/ion \
    --device /dev/ve3:/dev/ve3 \
    --device /dev/vpu:/dev/vpu \
    --device /dev/memalloc:/dev/memalloc \
    -v /tmp/shm:/dev/shm \
    -v /sys/class/uio:/sys/class/uio \
    -v /var/tmp/vowb:/var/tmp/vowb \
    --pid=host \
    --dns=172.17.0.1 \
    -p $port:8096 -v \"$config:/config\""

    [ -z "$cache" ] || cmd="$cmd -v \"$cache:/config/transcodes\""
    [ -z "$media" ] || cmd="$cmd -v \"$media:/media\""

    cmd="$cmd -v /mnt:/mnt"
    mountpoint -q /mnt && cmd="$cmd:rslave"
    cmd="$cmd --name myjellyfin-rtk \"$image_name\""

    echo "$cmd" >&2
    eval "$cmd"
}


while getopts ":il" optname
do
    case "$optname" in
        "l")
        echo -n $image_name
        ;;
        "i")
        install
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
