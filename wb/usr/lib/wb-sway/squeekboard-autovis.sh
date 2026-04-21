#!/bin/sh
set -eu

# This helper controls when Squeekboard is shown in the kiosk session.
# Squeekboard does not hide itself reliably after key presses, so the script
# watches its Wayland debug log and calls the OSK DBus API directly.
# It shows the keyboard when an input method is activated.
# It hides the keyboard when the special hide key is pressed.
# A lock directory prevents running more than one watcher at the same time.

LOCK_DIR=/run/wb-sway-kiosk/squeekboard-autovis.lock

mkdir -p /run/wb-sway-kiosk
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
	exit 0
fi
trap 'rmdir "$LOCK_DIR"' EXIT INT TERM

LOG_FILE=${XDG_RUNTIME_DIR:-/tmp}/squeekboard.log
HIDE_KEYSYM=F13
HIDE_KEYCODE=

# F13 is emitted by the WB keyboard layouts and is not meant for applications.

show_osk() {
    gdbus call --session \
        --dest sm.puri.OSK0 \
        --object-path /sm/puri/OSK0 \
        --method sm.puri.OSK0.SetVisible true >/dev/null 2>&1 || true
}

hide_osk() {
    gdbus call --session \
        --dest sm.puri.OSK0 \
        --object-path /sm/puri/OSK0 \
        --method sm.puri.OSK0.SetVisible false >/dev/null 2>&1 || true
}

find_keysym_code() {
    keysym=$1
    uid=$(id -u)
    pid=$(pgrep -u "$uid" -x squeekboard | head -n1 2>/dev/null || true)
    [ -n "$pid" ] || return 1

    for fd in /proc/$pid/fd/*; do
        target=$(readlink "$fd" 2>/dev/null || true)
        case "$target" in
            *eek_keymap*|*/dev/shm/*)
                code=$(awk -v sym="$keysym" '
                    $0 ~ ("\\[[[:space:]]*" sym "[[:space:]]*\\]") {
                        if (match($0, /<I[0-9]+>/)) {
                            n = substr($0, RSTART + 2, RLENGTH - 3)
                            print n - 8
                            exit
                        }
                    }
                ' "$fd" 2>/dev/null || true)
                [ -n "$code" ] || continue
                printf '%s\n' "$code"
                return 0
                ;;
        esac
    done

    return 1
}

refresh_keycode() {
    HIDE_KEYCODE=$(find_keysym_code "$HIDE_KEYSYM" || true)
}

for _ in $(seq 1 50); do
    if gdbus call --session \
        --dest org.freedesktop.DBus \
        --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.NameHasOwner sm.puri.OSK0 >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

hide_osk

touch "$LOG_FILE"
refresh_keycode

tail -n0 -F "$LOG_FILE" | while IFS= read -r line; do
    case "$line" in
        *"zwp_input_method_v2@"*"activate()"*)
            show_osk
            refresh_keycode
            ;;
        *"zwp_virtual_keyboard_v1@"*".key("*)
            key_event=$(printf '%s\n' "$line" | sed -n 's/.*\.key([^,]*, \([0-9][0-9]*\), \([01]\)).*/\1 \2/p')
            [ -n "$key_event" ] || continue
            set -- $key_event
            code=$1
            state=$2
            [ "$state" = 1 ] || continue
            [ -n "$HIDE_KEYCODE" ] || refresh_keycode
            if [ -n "$HIDE_KEYCODE" ] && [ "$code" = "$HIDE_KEYCODE" ]; then
                hide_osk
            fi
            ;;
    esac
done
