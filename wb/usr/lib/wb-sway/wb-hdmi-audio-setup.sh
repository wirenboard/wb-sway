#!/bin/sh
set -eu

# This helper applies the kiosk HDMI volume before Firefox starts.
# The value comes from /run/wb-sway-kiosk, with /etc/wb-hardware.conf as a
# fallback. If the ALSA softvol control is missing, short silent playback
# creates it before the volume is set.

RUNTIME_CONFIG_DIR=/run/wb-sway-kiosk
CONFIG_PATH=/etc/wb-hardware.conf

read_runtime_value() {
	name=$1
	path="${RUNTIME_CONFIG_DIR}/${name}"

	if [ -r "$path" ]; then
		head -n 1 "$path"
		return 0
	fi

	return 1
}

get_volume() {
	volume=$(read_runtime_value volume 2>/dev/null || true)
	if [ -z "$volume" ] || [ "$volume" = "null" ]; then
		volume=$(jq -r '.mod4.options.volume // 50' "$CONFIG_PATH" 2>/dev/null || true)
	fi
	if [ -z "$volume" ] || [ "$volume" = "null" ]; then
		volume=50
	fi
	printf '%s\n' "$volume"
}

main() {
	volume=$(get_volume)

	# Create the softvol control if the HDMI PCM is not initialized yet.
	if ! amixer -D default scontrols 2>/dev/null | grep -q "WB HDMI Softvol"; then
		timeout 0.1 aplay -D default -q -t raw -f S16_LE -c 2 -r 48000 /dev/zero \
			2>/dev/null || true
	fi

	amixer -D default -q sset 'WB HDMI Softvol' "${volume}%" >/dev/null 2>&1 || true
	alsactl --file /var/lib/alsa/asound.state store >/dev/null 2>&1 || true
}

main "$@"
