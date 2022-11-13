#!/bin/sh
# Author Xiaobao(xiaobao@linkease.com)

ACTION=${1}
shift 1

do_install() {
  echo "starting"
  sleep  120
  echo "started"
}

usage() {
  echo "usage: $0 sub-command"
  echo "where sub-command is one of:"
  echo "      install                Install the emby"
  echo "      upgrade                Upgrade the emby"
  echo "      rm/start/stop/restart  Remove/Start/Stop/Restart the emby"
  echo "      status                 Emby status"
  echo "      port                   Emby port"
}

case ${ACTION} in
  "install")
    do_install
  ;;
  "upgrade")
    do_install
  ;;
  "rm")
    docker rm -f emby
  ;;
  "start" | "stop" | "restart")
    docker ${ACTION} emby
  ;;
  "status")
    docker ps --all -f 'name=emby' --format '{{.State}}'
  ;;
  "port")
    docker ps --all -f 'name=emby' --format '{{.Ports}}' | grep -om1 '0.0.0.0:[0-9]*' | sed 's/0.0.0.0://'
  ;;
  *)
    usage
    exit 1
  ;;
esac
