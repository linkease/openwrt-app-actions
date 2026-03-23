#!/bin/sh
# Backward-compatible wrapper. New entry: openclawmgr-cli.sh

set -eu

exec /usr/share/openclawmgr/openclawmgr-cli.sh "$@"
