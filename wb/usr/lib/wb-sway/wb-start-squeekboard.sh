#!/bin/sh
set -eu

# This helper keeps Squeekboard running in the kiosk session.
# It selects the WB keyboard layouts, writes Squeekboard's Wayland debug log,
# and restarts Squeekboard if it exits. The autovis watcher reads that log to
# show and hide the keyboard. A lock directory prevents duplicate launcher loops.

LOCK_DIR=/run/wb-sway-kiosk/wb-start-squeekboard.lock

mkdir -p /run/wb-sway-kiosk
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
	exit 0
fi

cleanup() {
	pkill -TERM -P "$$" 2>/dev/null || true
	rmdir "$LOCK_DIR" 2>/dev/null || true
}

trap cleanup EXIT
trap 'cleanup; exit 0' INT TERM

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
