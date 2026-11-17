#!/usr/bin/env bash
# Installs the login LaunchAgent of the container runtime for the current user. Safe to run again.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
readonly TEMPLATE_FILE="$script_dir/launchd/io.github.expertos-tech.claude-cli-agents-workspace.container-runtime.plist.tmpl"
readonly LOGIN_START_SCRIPT="$script_dir/login-start.sh"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=launchd/agent-lib.sh
source "$script_dir/launchd/agent-lib.sh"

compose_file=""
rendered_file=""

# Prints the command usage.
usage() {
  cat <<'USAGE'
Usage: install-runtime.sh --compose-file <path> [--verbose] [--help]

Renders the LaunchAgent plist into ~/Library/LaunchAgents and loads it with launchctl,
unloading a previous copy first. Loading runs the agent right away, because of RunAtLoad.
The plist points at login-start.sh in this folder: moving the workspace needs a new install.
Exit 0 when installed, 1 on failure, 2 on usage error.

Options:
  --compose-file <path>   Compose file the agent brings up at login. Required; must exist.
  --verbose               Show each step.
  --help                  Show this help.
USAGE
}

# Reports a usage error and exits with status 2.
usage_error() {
  echo "error: $1" >&2
  usage >&2
  exit 2
}

# Fills the global settings from the command line.
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --compose-file)
        [ $# -ge 2 ] || usage_error "--compose-file needs a value"
        compose_file="$2"
        shift
        ;;
      --verbose) verbose=1 ;;
      --help | -h)
        usage
        exit 0
        ;;
      *) usage_error "unknown option: $1" ;;
    esac
    shift
  done
}

# Prints the absolute form of an existing file path.
absolute_path() {
  local directory
  directory="$(CDPATH='' cd -- "$(dirname -- "$1")" && pwd)"
  printf '%s/%s\n' "$directory" "$(basename -- "$1")"
}

# Validates the compose file and turns it into an absolute path.
validate_compose_file() {
  [ -n "$compose_file" ] || usage_error "--compose-file is required"
  [ -f "$compose_file" ] || usage_error "compose file not found: $compose_file"
  compose_file="$(absolute_path "$compose_file")"
  case "$compose_file" in
    *[[:cntrl:]]*) usage_error "the compose file path has control characters" ;;
  esac
}

# Fails when this script's own files or the macOS tools it needs are missing.
check_prerequisites() {
  local required_command
  [ -f "$LOGIN_START_SCRIPT" ] || { echo "error: login-start.sh not found next to this script" >&2; exit 1; }
  [ -f "$TEMPLATE_FILE" ] || { echo "error: plist template not found" >&2; exit 1; }
  for required_command in launchctl plutil; do
    command -v "$required_command" >/dev/null 2>&1 || { echo "error: $required_command not found" >&2; exit 1; }
  done
}

# Prints a value escaped for XML text.
xml_escape() {
  printf '%s' "$1" | LC_ALL=C sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Prints a text with the first occurrence of a placeholder replaced literally: text, placeholder, value.
replace_placeholder() {
  printf '%s%s%s' "${1%%"$2"*}" "$3" "${1#*"$2"}"
}

# Prints the plist, with the paths known only at install time.
render_plist() {
  local rendered
  rendered="$(<"$TEMPLATE_FILE")"
  rendered="$(replace_placeholder "$rendered" "@LOGIN_START_SCRIPT@" "$(xml_escape "$LOGIN_START_SCRIPT")")"
  rendered="$(replace_placeholder "$rendered" "@COMPOSE_FILE@" "$(xml_escape "$compose_file")")"
  printf '%s\n' "$rendered"
}

# Writes the rendered plist to a temp file next to its destination and lints it, before anything changes in launchd.
prepare_plist() {
  local plist="$1"
  mkdir -p "$(dirname "$plist")"
  rendered_file="$(mktemp "$(dirname "$plist")/.$AGENT_LABEL.XXXXXX")"
  render_plist >"$rendered_file"
  chmod 644 "$rendered_file"
  if ! plutil -lint -s "$rendered_file" >/dev/null 2>&1; then
    echo "error: the rendered plist is not valid; nothing changed" >&2
    exit 1
  fi
}

# Loads the installed plist into the user's launchd domain.
bootstrap_agent() {
  local plist="$1" output
  if ! output="$(launchctl bootstrap "$(agent_domain)" "$plist" 2>&1)"; then
    echo "error: launchctl bootstrap failed: $output" >&2
    exit 1
  fi
}

# Removes the temp file when the install stops early.
cleanup() {
  if [ -n "$rendered_file" ]; then
    rm -f "$rendered_file"
  fi
}

# Entry point.
main() {
  local plist
  parse_args "$@"
  validate_compose_file
  check_prerequisites
  plist="$(agent_plist_path)"
  refuse_foreign_plist "$plist"

  trap cleanup EXIT
  show_step "rendering $plist"
  prepare_plist "$plist"
  show_step "unloading any previous copy"
  bootout_agent_if_loaded
  mv -f "$rendered_file" "$plist"
  rendered_file=""
  show_step "loading $AGENT_LABEL"
  bootstrap_agent "$plist"
  echo "installed $AGENT_LABEL"
}

main "$@"
