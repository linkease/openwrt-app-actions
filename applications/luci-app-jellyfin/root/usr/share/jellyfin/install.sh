#!/bin/sh
image_name="jjm2473/jellyfin-rtk:latest"
config="/root/jellyfin/config"
media="/mnt/sda1/media"

install(){
    docker run --restart=unless-stopped -d \
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
    -p 8096:8096 -v $config:/config -v $media:/media --name myjellyfin-rtk $image_name
}


while getopts ":ilc:m:" optname
do
    case "$optname" in
        "l")
        echo -n $image_name
        ;;
        "c")
        config=$OPTARG
        ;;
        "m")
        media=$OPTARG
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
