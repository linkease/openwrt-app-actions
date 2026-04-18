#!/bin/sh

ACTION=${1}
shift 1

do_install() {
  local port=$(uci get hermes.@main[0].port 2>/dev/null | tr -d '\n\r')
  local data=$(uci get hermes.@main[0].data_path 2>/dev/null | tr -d '\n\r')
  local workspace=$(uci get hermes.@main[0].workspace_path 2>/dev/null | tr -d '\n\r')

  local image_name="linkease/hermes:latest"
  echo "docker pull ${image_name}"
  docker pull ${image_name}
  docker rm -f hermes

  [ -z "$port" ] && port=8787

  local cmd="docker run --restart=unless-stopped -d"

  [ -n "$data" ] && cmd="$cmd -v \"$data:/data/.hermes\""
  [ -n "$workspace" ] && cmd="$cmd -v \"$workspace:/workspace\""

  cmd="$cmd -p $port:8787"

  local tz=$(uci get system.@system[0].zonename 2>/dev/null | sed 's/ /_/g')
  [ -z "$tz" ] || cmd="$cmd -e TZ=$tz"

  cmd="$cmd --name hermes \"$image_name\""

  echo "$cmd"
  eval "$cmd"
}

usage() {
  echo "usage: $0 sub-command"
  echo "where sub-command is one of:"
  echo "      install                Install the hermes"
  echo "      upgrade                Upgrade the hermes"
  echo "      rm/start/stop/restart  Remove/Start/Stop/Restart the hermes"
  echo "      status                 Hermes status"
  echo "      port                   Hermes port"
}

case ${ACTION} in
  "install")
    do_install
  ;;
  "upgrade")
    do_install
  ;;
  "rm")
    docker rm -f hermes
  ;;
  "start" | "stop" | "restart")
    docker ${ACTION} hermes
  ;;
  "status")
    docker ps --all -f 'name=^/hermes$' --format '{{.State}}'
  ;;
  "port")
    docker ps --all -f 'name=^/hermes$' --format '{{.Ports}}' | grep -om1 '0.0.0.0:[0-9]*->8787/tcp' | sed 's/0.0.0.0:\([0-9]*\)->.*/\1/'
  ;;
  *)
    usage
    exit 1
  ;;
esac
