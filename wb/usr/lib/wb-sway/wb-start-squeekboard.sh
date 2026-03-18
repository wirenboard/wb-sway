#!/bin/sh
set -eu

LOCK_DIR=/run/wb-kiosk/wb-start-squeekboard.lock

mkdir -p /run/wb-kiosk
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
	exit 0
fi
trap 'rmdir "$LOCK_DIR"' EXIT INT TERM

sleep 1

LOG_FILE=${XDG_RUNTIME_DIR:-/tmp}/squeekboard.log
XDG_DATA_HOME_DEFAULT=${HOME:-/root}/.local/share

if [ -d "$XDG_DATA_HOME_DEFAULT/squeekboard/keyboards" ]; then
	XDG_DATA_HOME=$XDG_DATA_HOME_DEFAULT
else
	XDG_DATA_HOME=/usr/share/wb-sway
fi

export XDG_DATA_HOME
export WAYLAND_DEBUG=1

while true; do
	stdbuf -oL -eL /usr/bin/squeekboard >"$LOG_FILE" 2>&1 || true
	sleep 1
done
