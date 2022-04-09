#!/bin/sh

image_name=`uci get wxedge.@wxedge[0].image 2>/dev/null`

[ -z "$image_name" ] && image_name="onething1/wxedge:latest"

install(){
    local cache=`uci get wxedge.@wxedge[0].cache_path 2>/dev/null`

    if [ "x$cache" = "x" ]; then
        echo "cache path is empty!" >&2
        exit 1
    fi

    docker run -d --name wxedge -e PLACE=CTKS --privileged --network=host --tmpfs /run --tmpfs /tmp -v $cache:/storage:rw --restart=always $image_name
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
