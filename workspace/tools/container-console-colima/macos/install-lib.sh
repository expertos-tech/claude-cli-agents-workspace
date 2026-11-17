#!/usr/bin/env bash
# Paths and launchd, app and Dock helpers shared by install-console.sh and uninstall-console.sh.
# Source it; it does nothing when run.

# shellcheck disable=SC2034 # read by agent-lib.sh
AGENT_LABEL="io.github.expertos-tech.claude-cli-agents-workspace.container-console-colima"
# shellcheck disable=SC2034 # read by agent-lib.sh
AGENT_INSTALLER="install-console.sh"
# shellcheck disable=SC2034 # read by agent-lib.sh
AGENT_OWNER_MARKER="Installed by container-console-colima/macos/install-console.sh."
# Must outlast the 10 s the service may take to shut down after SIGTERM.
# shellcheck disable=SC2034 # read by agent-lib.sh
BOOTOUT_TIMEOUT_SECONDS=15
# shellcheck disable=SC1091 # path computed at run time
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../runtime/launchd/agent-lib.sh"

readonly APP_BUNDLE_ID="io.github.expertos-tech.claude-cli-agents-workspace.container-console-colima.launcher"
readonly BINARY_NAME="container-console-colima"
readonly LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

readonly STATE_DIR="$HOME/Library/Application Support/container-console-colima"
readonly BINARY_DIR="$STATE_DIR/bin"
# shellcheck disable=SC2034 # used by the scripts that source this file
readonly BINARY_PATH="$BINARY_DIR/$BINARY_NAME"
readonly APP_PATH="$HOME/Applications/Container Console (Colima).app"

# Exits with an error unless HOME is an existing absolute folder, because every path here derives from it.
check_home() {
  case "$HOME" in
    /*[[:cntrl:]]*) echo "error: HOME has control characters" >&2; exit 1 ;;
    /?*) ;;
    *) echo "error: HOME is not an absolute path" >&2; exit 1 ;;
  esac
  [ -d "$HOME" ] || { echo "error: HOME does not exist" >&2; exit 1; }
}

# Succeeds when the app bundle at APP_PATH carries the bundle id of this tool.
app_is_ours() {
  [ "$(plutil -extract CFBundleIdentifier raw -o - "$APP_PATH/Contents/Info.plist" 2>/dev/null)" = "$APP_BUNDLE_ID" ]
}

# Exits with an error when APP_PATH holds something that install-console.sh did not write.
refuse_foreign_app() {
  if [ -e "$APP_PATH" ] && ! app_is_ours; then
    echo "error: $APP_PATH was not installed by install-console.sh; nothing changed" >&2
    exit 1
  fi
}

# Tells LaunchServices about the app, with -f to register it and -u to forget it. Best effort: it only
# affects how soon the icon shows, and the tool is not a documented interface.
update_launch_services() {
  [ -x "$LSREGISTER" ] || return 0
  "$LSREGISTER" "$1" "$APP_PATH" >/dev/null 2>&1 || true
}

# Exports the Dock preferences to a new temp file and prints its path.
export_dock_preferences() {
  local file
  file="$(mktemp "${TMPDIR:-/tmp}/container-console-colima-dock.XXXXXX")" || return 1
  if ! defaults export com.apple.dock "$file" >/dev/null 2>&1; then
    rm -f "$file"
    return 1
  fi
  printf '%s\n' "$file"
}

# Succeeds when a tile location points at the app. install-console.sh writes a plain path, and the Dock
# rewrites it as a file URL with a trailing slash.
dock_location_is_app() {
  local location="${1#file://}"
  location="${location%/}"
  [ "${location//\%20/ }" = "$APP_PATH" ]
}

# Prints, highest first, the positions of the app's tiles in the persistent-apps list of an exported file.
# A tile counts by bundle id or by location. A file without the list has no tiles.
dock_tile_indexes() {
  local file="$1" count index tile
  count="$(plutil -extract persistent-apps raw -expect array -o - "$file" 2>/dev/null)" || return 0
  index=$((count - 1))
  while [ "$index" -ge 0 ]; do
    tile="persistent-apps.$index.tile-data"
    if [ "$(plutil -extract "$tile.bundle-identifier" raw -o - "$file" 2>/dev/null)" = "$APP_BUNDLE_ID" ] ||
      dock_location_is_app "$(plutil -extract "$tile.file-data._CFURLString" raw -o - "$file" 2>/dev/null)"; then
      printf '%s\n' "$index"
    fi
    index=$((index - 1))
  done
}
