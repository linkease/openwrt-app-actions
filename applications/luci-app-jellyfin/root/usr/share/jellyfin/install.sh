#!/bin/sh
# Author Xiaobao(xiaobao@linkease.com)

ACTION=${1}
WRLOCK=/var/lock/jellyfin.lock
LOGFILE=/var/log/jellyfin.log
LOGEND="XU6J03M6"
shift 1

ARCH=''
IMAGE_NAME='default'

check_params() {

  if [ -z "${WRLOCK}" ]; then
    echo "lock file not found"
    exit 1
  fi

  if [ -z "${LOGFILE}" ]; then
    echo "logger file not found"
    exit 1
  fi

}

lock_run() {
  local lock="$WRLOCK"
  exec 300>$lock
  flock -n 300 || return
  do_run
  flock -u 300
  return
}

run_action() {
  if check_params; then
    lock_run
  fi
}

get_image() {
  ARCH="arm64"
  if echo `uname -m` | grep -Eqi 'x86_64'; then
    ARCH="amd64"
  elif  echo `uname -m` | grep -Eqi 'aarch64'; then
    ARCH="arm64"
  else
    ARCH="arm64"
  fi

  if [ "${ARCH}" = "amd64" ]; then
    IMAGE_NAME="jellyfin/jellyfin"
  else
    if [ "$IMAGE_NAME" == "default" ]; then
        IMAGE_NAME="jjm2473/jellyfin-rtk:latest"
        if uname -r | grep -q '^4\.9\.'; then
          IMAGE_NAME="jjm2473/jellyfin-rtk:4.9-latest"
        fi
    fi
  fi
}

do_install() {
  get_image
  echo "docker pull ${IMAGE_NAME}" >${LOGFILE}
  docker pull ${IMAGE_NAME} >>${LOGFILE} 2>&1
  docker rm -f jellyfin

  do_install_detail
}

do_install_detail() {
  local media=`uci get jellyfin.@jellyfin[0].media_path 2>/dev/null`
  local config=`uci get jellyfin.@jellyfin[0].config_path 2>/dev/null`
  local cache=`uci get jellyfin.@jellyfin[0].cache_path 2>/dev/null`
  local port=`uci get jellyfin.@jellyfin[0].port 2>/dev/null`

  if [ -z "$config" ]; then
      echo "config path is empty!" >>${LOGFILE}
      exit 1
  fi

  [ -z "$port" ] && port=8096

  local cmd=""

  if [ "${ARCH}" = "amd64" ]; then
    cmd="docker run --restart=unless-stopped -d \
    --dns=172.17.0.1 \
    -p $port:8096 -v \"$config:/config\""
  else
    cmd="docker run --restart=unless-stopped -d \
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
  fi

  [ -z "$cache" ] || cmd="$cmd -v \"$cache:/config/transcodes\""
  [ -z "$media" ] || cmd="$cmd -v \"$media:/media\""

  cmd="$cmd -v /mnt:/mnt"
  mountpoint -q /mnt && cmd="$cmd:rslave"
  cmd="$cmd --name jellyfin \"$IMAGE_NAME\" >>\"${LOGFILE}\" 2>&1"

  echo "$cmd" >>${LOGFILE}
  eval "$cmd"

  echo ${LOGEND} >> ${LOGFILE}
  sleep 5
  rm -f ${LOGFILE}
}

# run in lock
do_run() {
  case ${ACTION} in
    "install")
      do_install
    ;;
    "upgrade")
      do_install
    ;;
  esac
}

usage() {
  echo "usage: wxedge sub-command"
  echo "where sub-command is one of:"
  echo "      install                Install the jellyfin"
  echo "      upgrade                Upgrade the jellyfin"
  echo "      remove                 Remove the jellyfin"
}

case ${ACTION} in
  "install")
    run_action
  ;;
  "upgrade")
    run_action
  ;;
  "remove")
    docker rm -f jellyfin
  ;;
  *)
    usage
  ;;
esac
