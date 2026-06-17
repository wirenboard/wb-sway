#!/bin/sh
set -eu

# This helper keeps Firefox running in the kiosk session.
# It uses a dedicated Wiren Board profile, applies kiosk or window layout,
# disables crash and session prompts, and removes stale profile state before
# each start. A lock directory prevents duplicate launcher loops.
# The URL and Firefox mode come from /run/wb-sway-kiosk, with
# /etc/wb-hardware.conf as a fallback.

RUNTIME_CONFIG_DIR=/run/wb-sway-kiosk
LOCK_DIR=/run/wb-sway-kiosk/wb-kiosk-firefox.lock

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

read_runtime_value() {
	name=$1
	path="${RUNTIME_CONFIG_DIR}/${name}"

	if [ -r "$path" ]; then
		head -n 1 "$path"
		return 0
	fi

	return 1
}

get_config_value() {
	name=$1
	query=$2
	default=$3

	value=$(read_runtime_value "$name" 2>/dev/null || true)
	if [ -z "$value" ] || [ "$value" = "null" ]; then
		value=$(jq -r "$query" /etc/wb-hardware.conf 2>/dev/null || true)
	fi
	if [ -z "$value" ] || [ "$value" = "null" ]; then
		value=$default
	fi
	printf '%s\n' "$value"
}

url=$(get_config_value url '.mod4.options.url // "http://localhost"' "http://localhost")
ff_mode=$(get_config_value ff_mode '.mod4.options.ff_mode // "kiosk"' "kiosk")

PROFILE_NAME="wirenboard"
MOZILLA_DIR="${HOME}/.mozilla"
PROFILE_DIR="${MOZILLA_DIR}/firefox/${PROFILE_NAME}"
USER_JS="$PROFILE_DIR/user.js"
XULSTORE="$PROFILE_DIR/xulstore.json"
USER_CHROME_DIR="$PROFILE_DIR/chrome"
USER_CHROME="$USER_CHROME_DIR/userChrome.css"

ensure_profile() {
	if [ -d "$PROFILE_DIR" ]; then
		return
	fi

	mkdir -p "$(dirname "$PROFILE_DIR")"
	firefox-esr --no-remote -CreateProfile "$PROFILE_NAME $PROFILE_DIR"
	for i in $(seq 1 10); do
		[ -d "$PROFILE_DIR" ] && break
		sleep 0.5
	done

	cat <<-'EOF' > "$USER_JS"
	user_pref("browser.sessionstore.resume_from_crash", false);
	user_pref("browser.shell.checkDefaultBrowser", false);
	user_pref("toolkit.startup.max_resumed_crashes", -1);
	user_pref("browser.crashReports.unsubmittedCheck.enabled", false);
	user_pref("datareporting.policy.dataSubmissionEnabled", false);
	user_pref("signon.rememberSignons", false);
	user_pref("signon.autofillForms", false);
	user_pref("signon.autologin.proxy", false);
	EOF
}

ensure_pref() {
	pref_line=$1

	grep -Fqx "$pref_line" "$USER_JS" 2>/dev/null && return
	printf '%s\n' "$pref_line" >> "$USER_JS"
}

apply_browser_layout() {
	mkdir -p "$USER_CHROME_DIR"

	cat <<-'EOF' > "$XULSTORE"
	{"chrome://browser/content/browser.xhtml":{"main-window":{"sizemode":"maximized","screenX":"0","screenY":"0","width":"1024","height":"600"}}}
	EOF

	if [ "$ff_mode" = "window" ]; then
		rm -f "$USER_CHROME"
		return
	fi

	cat <<-'EOF' > "$USER_CHROME"
	#navigator-toolbox,
	#TabsToolbar,
	#titlebar,
	#PersonalToolbar,
	#sidebar-box,
	#sidebar-header {
	  visibility: collapse !important;
	  min-height: 0 !important;
	  max-height: 0 !important;
	}

	#main-window,
	#browser,
	#appcontent,
	#tabbrowser-tabbox,
	#tabbrowser-tabpanels {
	  margin: 0 !important;
	  padding: 0 !important;
	}
	EOF
}

cleanup_profile_state() {
	rm -f "$PROFILE_DIR/.startup-incomplete" 2>/dev/null || true
	rm -f "$PROFILE_DIR/sessionCheckpoints.json" 2>/dev/null || true
	rm -f "$PROFILE_DIR/sessionstore.jsonlz4" "$PROFILE_DIR/sessionstore.js" "$PROFILE_DIR/sessionstore.bak" 2>/dev/null || true
	rm -rf "$PROFILE_DIR/sessionstore-backups" 2>/dev/null || true
	rm -rf "$PROFILE_DIR/cache2" "$PROFILE_DIR/startupCache" 2>/dev/null || true
	rm -rf "$PROFILE_DIR/crashes" "$PROFILE_DIR/minidumps" 2>/dev/null || true
	rm -f "$PROFILE_DIR/datareporting/aborted-session-ping" 2>/dev/null || true
	rm -rf "$PROFILE_DIR/datareporting/glean/pending_pings" 2>/dev/null || true
	rm -rf "${MOZILLA_DIR}/firefox/Crash Reports" 2>/dev/null || true
	rm -rf "${MOZILLA_DIR}/firefox/Pending Pings" 2>/dev/null || true
	rm -rf "${MOZILLA_DIR}/Crash Reports" 2>/dev/null || true
	rm -rf "${MOZILLA_DIR}/Pending Pings" 2>/dev/null || true
	rm -f "$PROFILE_DIR/lock" "$PROFILE_DIR/.parentlock" 2>/dev/null || true
	rm -f "$PROFILE_DIR/Telemetry.ShutdownTime.txt" "$PROFILE_DIR/times.json" 2>/dev/null || true
	rm -f "$PROFILE_DIR/datareporting/session-state.json" "$PROFILE_DIR/datareporting/state.json" 2>/dev/null || true
}

ensure_profile
ensure_pref 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'

while true; do
	apply_browser_layout
	cleanup_profile_state
	firefox-esr --no-remote --profile "$PROFILE_DIR" "$url" || true
	sleep 1
done
