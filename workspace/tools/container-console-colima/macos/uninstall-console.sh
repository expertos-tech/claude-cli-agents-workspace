#!/usr/bin/env bash
# Reverses install-console.sh: removes the Dock icon, the app, the LaunchAgent and the binary. Safe to run again.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir

# shellcheck source-path=SCRIPTDIR
# shellcheck source=install-lib.sh
source "$script_dir/install-lib.sh"

# Prints the command usage.
usage() {
  cat <<'USAGE'
Usage: uninstall-console.sh [--verbose] [--help]

Removes only what install-console.sh wrote: the Dock tile, ~/Applications/Container Console (Colima).app,
the LaunchAgent and the binary. Leaves the runtime agent, the VM, the containers, the logs and
the list of Compose projects as they are. A plist or an app with the same name that this tool
did not write stays in place, and the script fails.
Exit 0 when the console is gone, 1 on failure, 2 on usage error.

Options:
  --verbose   Show each step.
  --help      Show this help.
USAGE
}

# Fills the global settings from the command line.
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --verbose) verbose=1 ;;
      --help | -h)
        usage
        exit 0
        ;;
      *)
        echo "error: unknown option: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
    shift
  done
}

# Fails when a required macOS tool is missing. The Dock tools are optional.
check_prerequisites() {
  local required_command
  for required_command in launchctl plutil; do
    command -v "$required_command" >/dev/null 2>&1 || { echo "error: $required_command not found" >&2; exit 1; }
  done
}

# Removes every tile of the app from the Dock, and nothing else. Fails, without exiting, on any step that fails.
unpin_app_from_dock() {
  local exported tiles index
  exported="$(export_dock_preferences)" || return 1
  tiles="$(dock_tile_indexes "$exported")"
  if [ -z "$tiles" ]; then
    rm -f "$exported"
    return 0
  fi
  for index in $tiles; do
    if ! plutil -remove "persistent-apps.$index" "$exported" >/dev/null 2>&1; then
      rm -f "$exported"
      return 1
    fi
  done
  if ! defaults import com.apple.dock "$exported" >/dev/null 2>&1; then
    rm -f "$exported"
    return 1
  fi
  rm -f "$exported"
  killall Dock >/dev/null 2>&1
}

# Removes the app, which refuse_foreign_app already proved is ours.
remove_app() {
  if [ -e "$APP_PATH" ]; then
    update_launch_services -u
    rm -rf "$APP_PATH"
  fi
}

# Removes the binary, then its folder and the state folder when nothing else is left in them.
remove_binary() {
  rm -f "$BINARY_PATH"
  if [ -d "$BINARY_DIR" ]; then
    rmdir "$BINARY_DIR" 2>/dev/null || true
  fi
  if [ -d "$STATE_DIR" ]; then
    rmdir "$STATE_DIR" 2>/dev/null || true
  fi
}

# Entry point.
main() {
  local plist
  parse_args "$@"
  check_home
  check_prerequisites
  plist="$(agent_plist_path)"
  refuse_foreign_plist "$plist"
  refuse_foreign_app

  show_step "removing the app from the Dock"
  if ! unpin_app_from_dock; then
    echo "warning: could not update the Dock; remove the icon by hand" >&2
  fi
  show_step "removing $APP_PATH"
  remove_app
  show_step "unloading $AGENT_LABEL"
  bootout_agent_if_loaded
  if [ -e "$plist" ]; then
    show_step "removing $plist"
    rm -f "$plist"
  fi
  show_step "removing the binary"
  remove_binary
  echo "uninstalled $AGENT_LABEL and $APP_PATH"
}

main "$@"
