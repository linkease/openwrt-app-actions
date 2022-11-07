#!/bin/sh
# Author Xiaobao(xiaobao@linkease.com)

ACTION=${1}
shift 1

do_install() {
  local hostnet=`uci get plex.@plex[0].hostnet 2>/dev/null`
  local claim_token==`uci get plex.@plex[0].claim_token 2>/dev/null`
  local port=`uci get plex.@plex[0].port 2>/dev/null`
  local image_name=`uci get plex.@plex[0].image_name 2>/dev/null`
  local config=`uci get plex.@plex[0].config_path 2>/dev/null`
  local media=`uci get plex.@plex[0].media_path 2>/dev/null`
  local cache=`uci get plex.@plex[0].cache_path 2>/dev/null`

  [ -z "$image_name" ] && image_name="plexinc/pms-docker:latest"
  echo "docker pull ${image_name}"
  docker pull ${image_name}
  docker rm -f plex

  if [ -z "$config" ]; then
      echo "config path is empty!"
      exit 1
  fi

  [ -z "$port" ] && port=32400

  local cmd="docker run --restart=unless-stopped -d -e PLEX_CLAIM="$claim_token" -v \"$config:/config\" "

  if [ -d /dev/dri ]; then
    cmd="$cmd\
    --device /dev/dri:/dev/dri \
    --privileged "
  fi

  if [ "$hostnet" = 1 ]; then
    cmd="$cmd\
    --dns=127.0.0.1 \
    --network=host "
  else
    cmd="$cmd\
    --dns=172.17.0.1 \
    -p 3005:3005/tcp \
    -p 8324:8324/tcp \
    -p 32469:32469/tcp \
    -p 1900:1900/udp \
    -p 32410:32410/udp \
    -p 32412:32412/udp \
    -p 32413:32413/udp \
    -p 32414:32414/udp \
    -p $port:32400 "
  fi

  local tz="`cat /tmp/TZ`"
  [ -z "$tz" ] || cmd="$cmd -e TZ=$tz"

  [ -z "$cache" ] || cmd="$cmd -v \"$cache:/config/transcodes\""
  [ -z "$media" ] || cmd="$cmd -v \"$media:/media\""

  cmd="$cmd -v /mnt:/mnt"
  mountpoint -q /mnt && cmd="$cmd:rslave"
  cmd="$cmd --name plex \"$IMAGE_NAME\""

  echo "$cmd"
  eval "$cmd"
}

usage() {
  echo "usage: $0 sub-command"
  echo "where sub-command is one of:"
  echo "      install                Install the plex"
  echo "      upgrade                Upgrade the plex"
  echo "      rm/start/stop/restart  Remove/Start/Stop/Restart the plex"
  echo "      status                 Heimdall status"
  echo "      port                   Heimdall port"
}

case ${ACTION} in
  "install")
    do_install
  ;;
  "upgrade")
    do_install
  ;;
  "rm")
    docker rm -f plex
  ;;
  "start" | "stop" | "restart")
    docker ${ACTION} plex
  ;;
  "status")
    docker ps --all -f 'name=plex' --format '{{.State}}'
  ;;
  "port")
    docker ps --all -f 'name=plex' --format '{{.Ports}}' | grep -om1 '0.0.0.0:[0-9]*' | sed 's/0.0.0.0://'
  ;;
  *)
    usage
    exit 1
  ;;
esac
