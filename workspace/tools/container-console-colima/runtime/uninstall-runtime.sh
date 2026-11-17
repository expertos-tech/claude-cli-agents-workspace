#!/usr/bin/env bash
# Reverses install-runtime.sh: unloads the login LaunchAgent and removes the plist it installed. Safe to run again.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir

# shellcheck source-path=SCRIPTDIR
# shellcheck source=launchd/agent-lib.sh
source "$script_dir/launchd/agent-lib.sh"

# Prints the command usage.
usage() {
  cat <<'USAGE'
Usage: uninstall-runtime.sh [--verbose] [--help]

Unloads the LaunchAgent and removes only the plist written by install-runtime.sh. Leaves
the running VM, the containers and the log as they are. A plist with the same name that
this tool did not write stays in place, and the script fails.
Exit 0 when the agent is gone, 1 on failure, 2 on usage error.

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

# Fails when launchctl is missing.
check_prerequisites() {
  command -v launchctl >/dev/null 2>&1 || { echo "error: launchctl not found" >&2; exit 1; }
}

# Entry point.
main() {
  local plist
  parse_args "$@"
  check_prerequisites
  plist="$(agent_plist_path)"
  refuse_foreign_plist "$plist"

  show_step "unloading $AGENT_LABEL"
  bootout_agent_if_loaded
  if [ -e "$plist" ]; then
    show_step "removing $plist"
    rm -f "$plist"
  fi
  echo "uninstalled $AGENT_LABEL"
}

main "$@"
