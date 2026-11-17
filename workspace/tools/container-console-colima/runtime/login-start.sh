#!/usr/bin/env bash
# Brings the container runtime up at session login: the Colima VM in Docker-only mode, then the Grafana stack.
# Runs under launchd with /bin/bash, so it stays compatible with bash 3.2.
set -euo pipefail

readonly COMPOSE_WAIT_SECONDS=90
readonly DEFAULT_COMMAND_TIMEOUT_SECONDS=180
readonly KILL_GRACE_SECONDS=2
readonly POLL_INTERVAL_SECONDS=0.1
readonly LOG_RELATIVE_PATH="Library/Logs/container-console-colima/runtime.log"
readonly FAILURE_NOTIFICATION='display notification "The container runtime did not start at login. See ~/Library/Logs/container-console-colima/runtime.log." with title "Container runtime"'

compose_file=""
command_timeout="$DEFAULT_COMMAND_TIMEOUT_SECONDS"
verbose=0
log_file="/dev/null"

# Prints the command usage.
usage() {
  cat <<'USAGE'
Usage: login-start.sh --compose-file <absolute path> [--command-timeout <seconds>] [--verbose] [--help]

Starts the Colima VM with Kubernetes off when it is not running, retrying once after a
forced stop. Stops Kubernetes when it is on. Then runs "docker compose up" on the given
file, which also brings back a stack stopped by hand.

Writes timestamps and durations to ~/Library/Logs/container-console-colima/runtime.log, restarted
at each run, and never the output of colima or docker. A failure raises a macOS notification.
Exit 0 when everything is up, 1 on failure, 2 on usage error.

Options:
  --compose-file <path>       Absolute path of the compose file to bring up. Required.
  --command-timeout <seconds> Time limit of each colima, docker and osascript call. Default: 180.
  --verbose                   Show the output of colima and docker. It never goes to the log.
  --help                      Show this help.
USAGE
}

# Reports a usage error and exits with status 2.
usage_error() {
  echo "error: $1" >&2
  usage >&2
  exit 2
}

# Fills the global settings from the command line, rejecting anything invalid.
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --compose-file)
        [ $# -ge 2 ] || usage_error "--compose-file needs a value"
        compose_file="$2"
        shift
        ;;
      --command-timeout)
        [ $# -ge 2 ] || usage_error "--command-timeout needs a value"
        command_timeout="$2"
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
  validate_args
}

# Rejects missing or malformed settings. The compose file is checked later, so a moved file does not keep the VM down.
validate_args() {
  case "$compose_file" in
    "") usage_error "--compose-file is required" ;;
    /*) ;;
    *) usage_error "--compose-file must be an absolute path" ;;
  esac
  case "$command_timeout" in
    "" | *[!0-9]* | 0*) usage_error "--command-timeout must be a positive integer" ;;
  esac
  [ -n "${HOME:-}" ] || usage_error "HOME is not set"
}

# Starts the log of this run, keeping the previous run in runtime.log.1. An unusable log falls back to no log,
# because it must not keep the runtime down.
prepare_log() {
  local candidate="$HOME/$LOG_RELATIVE_PATH"
  mv -f "$candidate" "$candidate.1" 2>/dev/null || true
  if mkdir -p "$(dirname "$candidate")" 2>/dev/null && : 2>/dev/null >"$candidate"; then
    log_file="$candidate"
  else
    echo "warning: cannot write the log file; continuing without it" >&2
  fi
}

# Appends one timestamped line to the log. Callers pass fixed text and numbers only, never paths or command output.
log_event() {
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >>"$log_file"
}

# Runs a command with the time limit of --command-timeout and returns its exit status.
run_with_timeout() {
  local deadline=$((SECONDS + command_timeout)) pid status=0
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      kill -TERM "$pid" 2>/dev/null || true
      sleep "$KILL_GRACE_SECONDS"
      kill -KILL "$pid" 2>/dev/null || true
      break
    fi
    sleep "$POLL_INTERVAL_SECONDS"
  done
  wait "$pid" 2>/dev/null || status=$?
  return "$status"
}

# Runs a command under the time limit, showing its output only with --verbose.
run_quietly() {
  if [ "$verbose" -eq 1 ]; then
    run_with_timeout "$@"
  else
    run_with_timeout "$@" >/dev/null 2>&1
  fi
}

# Runs a named step and logs its exit status and duration: step name, then the command.
run_step() {
  local name="$1" started="$SECONDS" status=0
  shift
  run_quietly "$@" || status=$?
  log_event "step=$name exit=$status duration_seconds=$((SECONDS - started))"
  return "$status"
}

# Makes sure the VM is running. A failed start gets a forced stop and one retry, because the VM can be Broken after a reboot.
ensure_vm_running() {
  run_step colima_status colima status --json && return 0
  run_step colima_start colima start --kubernetes=false && return 0
  run_step colima_force_stop colima stop --force || true
  run_step colima_start_retry colima start --kubernetes=false
}

# Prints the "kubernetes" field of the Colima status.
read_kubernetes_state() {
  local status_json
  status_json="$(run_with_timeout colima status --json 2>/dev/null)" || return 1
  plutil -extract kubernetes raw -o - - 2>/dev/null <<<"$status_json"
}

# Stops Kubernetes when it is on, and fails when its state cannot be read.
ensure_kubernetes_off() {
  local state
  if ! state="$(read_kubernetes_state)"; then
    log_event "step=kubernetes_state result=unreadable"
    return 1
  fi
  case "$state" in
    true)
      log_event "step=kubernetes_state result=on"
      run_step colima_kubernetes_stop colima kubernetes stop
      ;;
    false) log_event "step=kubernetes_state result=off" ;;
    *)
      log_event "step=kubernetes_state result=unexpected"
      return 1
      ;;
  esac
}

# Brings the compose stack up and waits for it to be healthy.
start_compose() {
  if [ ! -f "$compose_file" ]; then
    log_event "step=compose_up result=compose_file_missing"
    return 1
  fi
  run_step compose_up docker compose -f "$compose_file" up -d --wait --wait-timeout "$COMPOSE_WAIT_SECONDS"
}

# Runs the login sequence. A Kubernetes failure does not hold Grafana back, so telemetry keeps flowing while the failure is reported.
start_runtime() {
  local status=0
  ensure_vm_running || return 1
  ensure_kubernetes_off || status=1
  start_compose || status=1
  return "$status"
}

# Reports the failure through the log, a macOS notification and stderr. A failed notification changes nothing else.
report_failure() {
  log_event "result=failed total_seconds=$SECONDS"
  run_step notify osascript -e "$FAILURE_NOTIFICATION" || true
  echo "error: container runtime did not start; see ~/$LOG_RELATIVE_PATH" >&2
}

# Entry point.
main() {
  parse_args "$@"
  prepare_log
  log_event "event=login_start"
  if ! start_runtime; then
    report_failure
    exit 1
  fi
  log_event "result=ok total_seconds=$SECONDS"
  echo "container runtime ready in ${SECONDS}s"
}

main "$@"
