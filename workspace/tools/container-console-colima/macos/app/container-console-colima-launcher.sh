#!/usr/bin/env bash
# Action of the Dock icon: makes sure the console service answers, then opens it in the default browser.
# It is copied into the app bundle and runs alone there, under the system bash 3.2 and the minimal PATH
# LaunchServices gives: it cannot source anything from the workspace.
set -euo pipefail

readonly AGENT_LABEL="io.github.expertos-tech.claude-cli-agents-workspace.container-console-colima"
readonly CONSOLE_URL="http://127.0.0.1:17850/"
readonly HEALTH_URL="${CONSOLE_URL}healthz"
readonly START_TIMEOUT_SECONDS=5
readonly POLL_SECONDS=0.2
readonly REQUEST_TIMEOUT_SECONDS=1

# Prints the command usage.
usage() {
  cat <<'USAGE'
Usage: container-console-colima-launcher [--help]

Checks the service health and starts the LaunchAgent when it does not answer. Then opens
the console in the default browser. When the service does not answer within 5 s, shows an
alert with the log paths.
Exit 0 when the browser was asked to open, 1 on failure, 2 on usage error.

Options:
  --help   Show this help.
USAGE
}

# Validates the command line.
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --help | -h)
        usage
        exit 0
        ;;
      # Process serial number that LaunchServices may still pass to an app: not an option of this script.
      -psn_*) ;;
      *)
        echo "error: unknown option: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
    shift
  done
}

# Succeeds when the service answers its health route.
service_answers() {
  curl --silent --fail --output /dev/null --noproxy '127.0.0.1' \
    --max-time "$REQUEST_TIMEOUT_SECONDS" "$HEALTH_URL"
}

# Waits for the service to answer, until the start timeout.
wait_for_service() {
  SECONDS=0
  while [ "$SECONDS" -lt "$START_TIMEOUT_SECONDS" ]; do
    service_answers && return 0
    sleep "$POLL_SECONDS"
  done
  return 1
}

# Asks launchd to start the agent. A running process is not restarted, so open terminals survive
# a slow answer. The status is not used: an agent that is not loaded fails here, and the wait decides.
start_agent() {
  launchctl kickstart "gui/$UID/$AGENT_LABEL" >/dev/null 2>&1 || true
}

# Shows an alert that the service did not start, with the path of its logs.
show_start_failure() {
  local log_dir="$HOME/Library/Logs/container-console-colima"
  osascript \
    -e 'on run argv' \
    -e 'activate' \
    -e 'display alert "Container Console did not start" message (item 1 of argv) as critical' \
    -e 'end run' \
    "The service did not answer within $START_TIMEOUT_SECONDS seconds. Check $log_dir/console.log and $log_dir/launchd-stderr.log." \
    >/dev/null 2>&1 || true
}

# Entry point.
main() {
  parse_args "$@"
  if ! service_answers; then
    start_agent
    if ! wait_for_service; then
      show_start_failure
      exit 1
    fi
  fi
  open "$CONSOLE_URL"
}

main "$@"
