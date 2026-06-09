#!/bin/sh
set -eu

# This helper applies display and input settings to the running Sway session.
# It reads /etc/wb-hardware.conf, waits briefly for an active output, and then
# updates cursor visibility, output rotation, touch output mapping, output mode,
# and keyboard layout.
# It is safe to run after startup and after Sway config reloads.

CONFIG_PATH=/etc/wb-hardware.conf

get_option() {
    key=$1
    jq -r ".mod4.options.${key} // empty" "$CONFIG_PATH" 2>/dev/null || true
}

find_output() {
    for _ in $(seq 1 20); do
        output=$(swaymsg -t get_outputs -r 2>/dev/null | \
            jq -r '.[] | select(.active and (.name | startswith("HDMI-A-"))) | .name' | \
            head -n1)
        if [ -n "$output" ]; then
            printf '%s\n' "$output"
            return 0
        fi

        output=$(swaymsg -t get_outputs -r 2>/dev/null | \
            jq -r '.[] | select(.active) | .name' | \
            head -n1)
        if [ -n "$output" ]; then
            printf '%s\n' "$output"
            return 0
        fi

        sleep 0.5
    done

    return 1
}

config_mode_to_sway() {
    mode=$1

    if [ -z "$mode" ] || [ "$mode" = "auto" ] || [ "$mode" = "null" ]; then
        return 0
    fi

    base=${mode%%|*}
    if [ "${base#*-}" != "$base" ]; then
        res=${base%-*}
        rate=${base##*-}
        printf '%s@%sHz\n' "$res" "$rate"
        return 0
    fi

    printf '%s\n' "$base"
}

config_rotate_to_sway() {
    case "$1" in
        90|180|270)
            printf '%s\n' "$1"
            ;;
        *)
            printf 'normal\n'
            ;;
    esac
}

main() {
    mouse=$(get_option mouse)
    mode=$(get_option mode)
    rotate=$(get_option rotate)
    output=$(find_output || true)

    swaymsg input type:keyboard xkb_switch_layout 0 >/dev/null 2>&1 || true

    if [ -z "$mouse" ] || [ "$mouse" = "hide" ] || [ "$mouse" = "null" ]; then
        swaymsg seat seat0 hide_cursor 1 >/dev/null 2>&1 || true
    else
        swaymsg seat seat0 hide_cursor 0 >/dev/null 2>&1 || true
    fi

    [ -n "$output" ] || return 0

    swaymsg output "$output" transform "$(config_rotate_to_sway "$rotate")" >/dev/null 2>&1 || true
    swaymsg input type:touch map_to_output "$output" >/dev/null 2>&1 || true

    sway_mode=$(config_mode_to_sway "$mode")
    if [ -n "$sway_mode" ]; then
        swaymsg output "$output" mode "$sway_mode" >/dev/null 2>&1 || true
    fi
}

main "$@"
