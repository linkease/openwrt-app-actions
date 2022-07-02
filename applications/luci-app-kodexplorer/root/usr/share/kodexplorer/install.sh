#!/bin/sh
# Author Xiaobao(xiaobao@linkease.com)

ACTION=${1}
WRLOCK=/var/lock/kodexplorer.lock
LOGFILE=/var/log/kodexplorer.log
LOGEND="XU6J03M6"
shift 1

IMAGE_NAME='kodcloud/kodbox:latest'

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

do_install() {
  local CACHE=`uci get kodexplorer.@kodexplorer[0].cache_path 2>/dev/null`
  local PORT=`uci get kodexplorer.@kodexplorer[0].port 2>/dev/null`
  if [ -z "${CACHE}" ]; then
      echo "cache path is empty!" >${LOGFILE}
      exit 1
  fi
  echo "docker pull ${IMAGE_NAME}" >${LOGFILE}
  docker pull ${IMAGE_NAME} >>${LOGFILE} 2>&1
  docker rm -f kodexplorer
  local mntv="/mnt:/mnt"
  mountpoint -q /mnt && mntv="$mntv:rslave"
  docker run -d --name kodexplorer \
    --dns=172.17.0.1 \
    -p ${PORT}:80 \
    -v ${CACHE}:/var/www/html -v ${mntv} \
    $IMAGE_NAME >>${LOGFILE} 2>&1

  RET=$?
  if [ "${RET}" = "0" ]; then
    # mark END, remove the log file
    echo ${LOGEND} >> ${LOGFILE}
    sleep 5
    rm -f ${LOGFILE}
  else
    # reserve the log
    echo "docker run ${IMAGE_NAME} failed" >>${LOGFILE}
    echo ${LOGEND} >> ${LOGFILE}
  fi
  exit ${RET}
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
  echo "      install                Install the kodexplorer"
  echo "      upgrade                Upgrade the kodexplorer"
  echo "      remove                 Remove the kodexplorer"
}

case ${ACTION} in
  "install")
    run_action
  ;;
  "upgrade")
    run_action
  ;;
  "remove")
    docker rm -f kodexplorer
  ;;
  *)
    usage
  ;;
esac

