#!/bin/sh
set -eu

RUNTIME_CONFIG_DIR=/run/wb-kiosk

mkdir -p "$RUNTIME_CONFIG_DIR"
chmod 0755 "$RUNTIME_CONFIG_DIR"

url=$(jq -r '.mod4.options.url // "http://localhost"' /etc/wb-hardware.conf 2>/dev/null || true)
if [ -z "$url" ] || [ "$url" = "null" ]; then
	url="http://localhost"
fi

ff_mode=$(jq -r '.mod4.options.ff_mode // "kiosk"' /etc/wb-hardware.conf 2>/dev/null || true)
if [ -z "$ff_mode" ] || [ "$ff_mode" = "null" ]; then
	ff_mode="kiosk"
fi

printf '%s\n' "$url" > "${RUNTIME_CONFIG_DIR}/url"
printf '%s\n' "$ff_mode" > "${RUNTIME_CONFIG_DIR}/ff_mode"
chmod 0644 "${RUNTIME_CONFIG_DIR}/url" "${RUNTIME_CONFIG_DIR}/ff_mode"
