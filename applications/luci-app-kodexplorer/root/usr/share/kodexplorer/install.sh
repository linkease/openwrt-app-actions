#!/bin/sh

image_name=`uci get kodexplorer.@kodexplorer[0].image 2>/dev/null`

[ -z "$image_name" ] && image_name="kodcloud/kodexplorer:latest"

install(){
    local cache=`uci get kodexplorer.@kodexplorer[0].cache_path 2>/dev/null`
    local port=`uci get jellyfin.@jellyfin[0].port 2>/dev/null`
    if [ -z "$cache"]; then
        echo "cache path is empty!" >&2
        exit 1
    fi
    [ -z "$port" ] && port=8081

    docker run -d --name kodexplorer -p $port:80 -v $cache:/var/www/html $image_name
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
