#!/usr/bin/env bash
# Unit tests of the runtime scripts with fake colima, docker, osascript and launchctl on PATH.
# Each case has its own HOME and state folder. Nothing reaches the real VM, Docker or launchd; plutil is the real one.
set -euo pipefail

runtime_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly runtime_dir
readonly AGENT_LABEL="io.github.expertos-tech.claude-cli-agents-workspace.container-runtime"
readonly NOTIFICATION_CALL='osascript -e display notification "The container runtime did not start at login. See ~/Library/Logs/container-console-colima/runtime.log." with title "Container runtime"'
readonly FICTITIOUS_PERSONAL_TEXT="fictitious-user"

verbose=0
passed=0
failed=0
case_count=0
work_root=""
current_case=""
case_dir=""
case_bin=""
state_dir=""
sandbox_home=""
compose_file=""
log_path=""
plist_path=""
output_file=""
last_exit=0

# Prints the command usage.
usage() {
  cat <<'USAGE'
Usage: tests/test-login-start.sh [--verbose] [--help]

Runs the unit tests of login-start.sh, install-runtime.sh and uninstall-runtime.sh with
fakes on PATH. Prints failures and a summary. Exit 0 when all pass, 1 on failure, 2 on usage error.

Options:
  --verbose   Also print the passed checks.
  --help      Show this help.
USAGE
}

# Writes an executable fake command: name, then its body on stdin.
write_fake() {
  {
    cat <<'HEADER'
#!/bin/bash
set -u
printf '%s %s\n' "$(basename "$0")" "$*" >>"$FAKE_STATE_DIR/calls"
HEADER
    cat
  } >"$work_root/bin/$1"
  chmod +x "$work_root/bin/$1"
}

# Writes the fakes, whose behavior comes from flag files in $FAKE_STATE_DIR.
write_fakes() {
  mkdir -p "$work_root/bin"
  write_fake colima <<'FAKE'
state="$FAKE_STATE_DIR"
echo "noise from /Users/fictitious-user/.colima" >&2
case "$*" in
  "status --json")
    [ -f "$state/vm-running" ] || exit 1
    if [ -f "$state/status-json" ]; then cat "$state/status-json"; exit 0; fi
    printf '{"display_name":"colima","kubernetes":%s}\n' "$(cat "$state/kubernetes")"
    ;;
  "start --kubernetes=false")
    echo "started by /Users/fictitious-user"
    failures="$(cat "$state/start-failures" 2>/dev/null || echo 0)"
    if [ "$failures" -gt 0 ]; then
      echo "$((failures - 1))" >"$state/start-failures"
      exit 1
    fi
    touch "$state/vm-running"
    echo false >"$state/kubernetes"
    ;;
  "stop --force") rm -f "$state/vm-running" ;;
  "kubernetes stop")
    [ ! -f "$state/kubernetes-stop-fails" ] || exit 1
    echo false >"$state/kubernetes"
    ;;
  *) exit 64 ;;
esac
FAKE
  write_fake docker <<'FAKE'
state="$FAKE_STATE_DIR"
[ -f "$3" ] || exit 65
echo "compose output from /Users/fictitious-user"
[ ! -f "$state/compose-hangs" ] || exec sleep 30
[ ! -f "$state/compose-fails" ] || exit 1
FAKE
  write_fake osascript <<'FAKE'
[ ! -f "$FAKE_STATE_DIR/osascript-fails" ] || exit 1
FAKE
  write_fake launchctl <<'FAKE'
state="$FAKE_STATE_DIR"
case "$1" in
  print) [ -f "$state/agent-loaded" ] ;;
  bootout)
    [ -f "$state/bootout-stuck" ] || rm -f "$state/agent-loaded"
    ;;
  bootstrap)
    [ ! -f "$state/bootstrap-fails" ] || { echo "Bootstrap failed: 5" >&2; exit 5; }
    touch "$state/agent-loaded"
    ;;
  *) exit 64 ;;
esac
FAKE
}

# Starts a new case with its own sandbox: case description.
new_case() {
  current_case="$1"
  case_count=$((case_count + 1))
  case_dir="$work_root/case-$case_count"
  case_bin="$case_dir/bin"
  state_dir="$case_dir/state"
  sandbox_home="$case_dir/home"
  compose_file="$sandbox_home/observability/compose.yaml"
  log_path="$sandbox_home/Library/Logs/container-console-colima/runtime.log"
  plist_path="$sandbox_home/Library/LaunchAgents/$AGENT_LABEL.plist"
  output_file="$case_dir/output"
  mkdir -p "$case_bin" "$state_dir" "$(dirname "$compose_file")"
  : >"$compose_file"
  : >"$state_dir/calls"
  last_exit=0
}

# Runs a script from the runtime folder, with a clean environment: script name, then its arguments.
run_script() {
  local script="$1"
  shift
  last_exit=0
  env -i HOME="$sandbox_home" TMPDIR="$case_dir" FAKE_STATE_DIR="$state_dir" \
    PATH="$case_bin:$work_root/bin:/usr/bin:/bin" \
    /bin/bash "$runtime_dir/$script" "$@" >"$output_file" 2>&1 || last_exit=$?
}

# Runs login-start.sh on the case's compose file, with extra arguments.
run_login_start() {
  run_script login-start.sh --compose-file "$compose_file" "$@"
}

# Puts the fake VM in the running state with Kubernetes on (true) or off (false).
given_vm_running() {
  touch "$state_dir/vm-running"
  echo "$1" >"$state_dir/kubernetes"
}

# Creates a flag file that changes the behavior of a fake.
given_flag() {
  touch "$state_dir/$1"
}

# Prints the launchctl argument that names the agent.
service_target() {
  printf 'gui/%s/%s\n' "$UID" "$AGENT_LABEL"
}

# Prints the exact compose call expected for the case's compose file.
compose_call() {
  printf 'docker compose -f %s up -d --wait --wait-timeout 90\n' "$compose_file"
}

# Records a passed check.
pass() {
  passed=$((passed + 1))
  if [ "$verbose" -eq 1 ]; then
    echo "PASS $current_case: $1"
  fi
}

# Records a failed check, with optional details.
fail() {
  failed=$((failed + 1))
  echo "FAIL $current_case: $1" >&2
  if [ $# -ge 2 ]; then
    printf '%s\n' "$2" >&2
  fi
}

# Checks that a command succeeds: description, then the command.
assert_true() {
  local description="$1"
  shift
  if "$@"; then pass "$description"; else fail "$description"; fi
}

# Checks that a command fails: description, then the command.
assert_false() {
  local description="$1"
  shift
  if "$@"; then fail "$description"; else pass "$description"; fi
}

# Checks the exit status of the last script: expected status.
assert_exit() {
  if [ "$last_exit" -eq "$1" ]; then
    pass "exit status is $1"
  else
    fail "exit status is $1" "got $last_exit; output: $(cat "$output_file")"
  fi
}

# Checks the exact, ordered list of calls to the fakes: one expected call per argument.
assert_calls() {
  local expected="" actual
  if [ $# -gt 0 ]; then expected="$(printf '%s\n' "$@")"; fi
  actual="$(cat "$state_dir/calls")"
  if [ "$actual" = "$expected" ]; then
    pass "calls are in the expected order"
  else
    fail "calls are in the expected order" "expected:
$expected
got:
$actual"
  fi
}

# Checks whether a file contains a fixed string: description, fixed string, file.
assert_file_has() {
  assert_true "$1" grep -qF -- "$2" "$3"
}

# Checks that a file lacks a fixed string: description, fixed string, file.
assert_file_lacks() {
  assert_false "$1" grep -qF -- "$2" "$3"
}

# Checks that the case raised exactly one notification, with the fixed text.
assert_notified() {
  local count
  count="$(grep -cF -- "$NOTIFICATION_CALL" "$state_dir/calls" || true)"
  if [ "$count" -eq 1 ]; then pass "notified once, with the fixed text"; else fail "notified once, with the fixed text" "got $count"; fi
}

# Checks that the case raised no notification.
assert_not_notified() {
  assert_file_lacks "no notification" "osascript" "$state_dir/calls"
}

# Checks a plist value through plutil: description, key path, expected raw value, plist file.
assert_plist_value() {
  local actual
  actual="$(plutil -extract "$2" raw -o - "$4" 2>/dev/null || echo "<absent>")"
  if [ "$actual" = "$3" ]; then pass "$1"; else fail "$1" "expected $3; got $actual"; fi
}

# with the VM off, it starts in Docker-only mode and the stack comes up.
test_vm_off_starts_docker_only() {
  new_case "VM off"
  run_login_start
  assert_exit 0
  assert_calls "colima status --json" "colima start --kubernetes=false" "colima status --json" "$(compose_call)"
  assert_not_notified
}

# a first start that fails (Broken after a reboot) gets a forced stop and a retry.
test_failed_start_is_retried() {
  new_case "first start fails"
  echo 1 >"$state_dir/start-failures"
  run_login_start
  assert_exit 0
  assert_calls "colima status --json" "colima start --kubernetes=false" "colima stop --force" \
    "colima start --kubernetes=false" "colima status --json" "$(compose_call)"
  assert_not_notified
}

# A retry that also fails exits non-zero, notifies and does not try compose.
test_failed_retry_notifies() {
  new_case "retry also fails"
  echo 2 >"$state_dir/start-failures"
  run_login_start
  assert_exit 1
  assert_calls "colima status --json" "colima start --kubernetes=false" "colima stop --force" \
    "colima start --kubernetes=false" "$NOTIFICATION_CALL"
  assert_notified
}

# a VM already on with Kubernetes gets Kubernetes stopped.
test_vm_on_with_kubernetes_stops_it() {
  new_case "VM on with Kubernetes"
  given_vm_running true
  run_login_start
  assert_exit 0
  assert_calls "colima status --json" "colima status --json" "colima kubernetes stop" "$(compose_call)"
  assert_not_notified
}

# a VM already on without Kubernetes is left alone, and compose still runs, which brings back a Grafana stopped by hand.
test_vm_on_without_kubernetes_keeps_it() {
  new_case "VM on without Kubernetes, Grafana stopped by hand"
  given_vm_running false
  run_login_start
  assert_exit 0
  assert_calls "colima status --json" "colima status --json" "$(compose_call)"
  assert_not_notified
}

# A compose failure exits non-zero and notifies.
test_compose_failure_notifies() {
  new_case "compose fails"
  given_vm_running false
  given_flag compose-fails
  run_login_start
  assert_exit 1
  assert_calls "colima status --json" "colima status --json" "$(compose_call)" "$NOTIFICATION_CALL"
  assert_notified
}

# A hung command is stopped at the time limit and handled as a failure.
test_hung_command_is_stopped() {
  new_case "compose hangs"
  given_vm_running false
  given_flag compose-hangs
  run_login_start --command-timeout 1
  assert_exit 1
  assert_file_has "the log has the stop signal" "step=compose_up exit=143" "$log_path"
  assert_notified
}

# A compose file that disappeared does not keep the VM down, and it is reported.
test_missing_compose_file_at_login() {
  new_case "compose file gone at login"
  rm -f "$compose_file"
  run_login_start
  assert_exit 1
  assert_calls "colima status --json" "colima start --kubernetes=false" "colima status --json" "$NOTIFICATION_CALL"
  assert_notified
}

# A compose path with spaces reaches docker as one argument.
test_compose_path_with_spaces() {
  new_case "compose path with spaces"
  compose_file="$sandbox_home/my stack/compose.yaml"
  mkdir -p "$(dirname "$compose_file")"
  : >"$compose_file"
  given_vm_running false
  run_login_start
  assert_exit 0
  assert_not_notified
}

# A Kubernetes that could not be stopped is reported, but Grafana still comes up.
test_kubernetes_stop_failure_keeps_compose() {
  new_case "kubernetes stop fails"
  given_vm_running true
  given_flag kubernetes-stop-fails
  run_login_start
  assert_exit 1
  assert_calls "colima status --json" "colima status --json" "colima kubernetes stop" "$(compose_call)" "$NOTIFICATION_CALL"
  assert_notified
}

# A status without a valid "kubernetes" field is reported, but Grafana still comes up: status text, description.
check_bad_status() {
  new_case "$2"
  given_vm_running false
  printf '%s' "$1" >"$state_dir/status-json"
  run_login_start
  assert_exit 1
  assert_calls "colima status --json" "colima status --json" "$(compose_call)" "$NOTIFICATION_CALL"
  assert_file_lacks "the raw status is not logged" "banana" "$log_path"
}

# Unreadable and unexpected Kubernetes states.
test_bad_status() {
  check_bad_status 'not json' "status is not JSON"
  check_bad_status '{"cpu":4}' "status has no kubernetes field"
  check_bad_status '{"kubernetes":"banana"}' "status has an unexpected kubernetes value"
}

# The log restarts at each run, every line has a timestamp, durations are present and nothing personal gets in.
test_log_content() {
  new_case "log content"
  mkdir -p "$(dirname "$log_path")"
  echo "line from the previous login" >"$log_path"
  echo 1 >"$state_dir/start-failures"
  run_login_start
  assert_exit 0
  assert_file_lacks "log is truncated at each run" "previous login" "$log_path"
  assert_false "every line starts with a UTC timestamp" grep -qvE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z ' "$log_path"
  assert_file_has "log has the step durations" "step=compose_up exit=0 duration_seconds=" "$log_path"
  assert_file_has "log has the total time" "result=ok total_seconds=" "$log_path"
  assert_file_has "log has the failed first start" "step=colima_start exit=1" "$log_path"
  assert_file_lacks "log has no command output" "$FICTITIOUS_PERSONAL_TEXT" "$log_path"
  assert_file_lacks "log has no home path" "$sandbox_home" "$log_path"
  assert_file_lacks "output has no command output by default" "$FICTITIOUS_PERSONAL_TEXT" "$output_file"
}

# --verbose shows the command output, and the log still does not get it.
test_verbose_output() {
  new_case "verbose"
  run_login_start --verbose
  assert_exit 0
  assert_file_has "output has the command output" "$FICTITIOUS_PERSONAL_TEXT" "$output_file"
  assert_file_lacks "log has no command output" "$FICTITIOUS_PERSONAL_TEXT" "$log_path"
}

# A log that cannot be written does not keep the runtime down.
test_unwritable_log() {
  new_case "log cannot be written"
  mkdir -p "$sandbox_home/Library"
  : >"$sandbox_home/Library/Logs"
  run_login_start
  assert_exit 0
  assert_file_has "warns about the log" "cannot write the log file" "$output_file"
  assert_file_has "the stack still comes up" "docker compose" "$state_dir/calls"
}

# A failed notification does not change the exit status of the failure it reports.
test_notification_failure_keeps_exit() {
  new_case "notification fails"
  given_vm_running false
  given_flag compose-fails
  given_flag osascript-fails
  run_login_start
  assert_exit 1
  assert_file_has "the failed notification is logged" "step=notify exit=1" "$log_path"
}

# Runs login-start.sh with invalid arguments, expecting status 2 and no call: description, then arguments.
check_login_usage_error() {
  local description="$1"
  shift
  new_case "login-start usage: $description"
  run_script login-start.sh "$@"
  assert_exit 2
  assert_calls
}

# Argument validation of login-start.sh, and its help.
test_login_arguments() {
  check_login_usage_error "no arguments"
  check_login_usage_error "unknown option" --compose-file /fictitious/compose.yaml --bogus
  check_login_usage_error "compose file without a value" --compose-file
  check_login_usage_error "relative compose file" --compose-file compose.yaml
  check_login_usage_error "timeout without a value" --compose-file /fictitious/compose.yaml --command-timeout
  check_login_usage_error "non-numeric timeout" --compose-file /fictitious/compose.yaml --command-timeout abc
  check_login_usage_error "zero timeout" --compose-file /fictitious/compose.yaml --command-timeout 0
  new_case "login-start help"
  run_script login-start.sh --help
  assert_exit 0
  assert_file_has "help shows the usage" "Usage: login-start.sh" "$output_file"
  assert_calls
}

# Install rejects an invalid compose file before touching anything: description, then the install arguments.
check_install_rejected() {
  local description="$1"
  shift
  new_case "install rejects $description"
  run_script install-runtime.sh "$@"
  assert_exit 2
  assert_calls
  assert_false "no plist is written" test -e "$plist_path"
}

# Argument validation of install-runtime.sh, and its help.
test_install_arguments() {
  check_install_rejected "no arguments"
  check_install_rejected "an unknown option" --bogus
  check_install_rejected "a compose file without a value" --compose-file
  check_install_rejected "a compose file that does not exist" --compose-file "$work_root/does-not-exist.yaml"
  check_install_rejected "a folder as compose file" --compose-file "$work_root"

  new_case "install rejects control characters"
  local control_path="$case_dir/line"$'\n'"break.yaml"
  : >"$control_path"
  run_script install-runtime.sh --compose-file "$control_path"
  assert_exit 2
  assert_calls

  new_case "install help"
  run_script install-runtime.sh --help
  assert_exit 0
  assert_file_has "help shows the usage" "Usage: install-runtime.sh" "$output_file"
}

# the rendered plist is valid XML with the keys the agent needs.
test_plist_rendering() {
  new_case "plist rendering"
  run_script install-runtime.sh --compose-file "$compose_file"
  assert_exit 0
  assert_true "plutil -lint accepts it" plutil -lint -s "$plist_path"
  assert_plist_value "Label" Label "$AGENT_LABEL" "$plist_path"
  assert_plist_value "RunAtLoad is true" RunAtLoad true "$plist_path"
  assert_plist_value "KeepAlive is absent" KeepAlive "<absent>" "$plist_path"
  assert_plist_value "AbandonProcessGroup is true" AbandonProcessGroup true "$plist_path"
  assert_plist_value "LimitLoadToSessionType is Aqua" LimitLoadToSessionType Aqua "$plist_path"
  assert_plist_value "runs with the system bash" ProgramArguments.0 /bin/bash "$plist_path"
  assert_plist_value "references login-start.sh" ProgramArguments.1 "$runtime_dir/login-start.sh" "$plist_path"
  assert_plist_value "passes the compose option" ProgramArguments.2 --compose-file "$plist_path"
  assert_plist_value "passes the compose file" ProgramArguments.3 "$compose_file" "$plist_path"
  assert_file_has "PATH has Homebrew" "<string>/opt/homebrew/bin:" "$plist_path"
  assert_plist_value "PATH is the expected one" EnvironmentVariables.PATH "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin" "$plist_path"
  assert_file_lacks "no placeholder is left" "@" "$plist_path"
  assert_file_lacks "the committed template has no user path" "/Users/" "$runtime_dir/launchd/$AGENT_LABEL.plist.tmpl"
}

# XML-special characters in a path are escaped, and the path survives the round trip.
test_plist_escapes_paths() {
  new_case "plist escapes paths"
  compose_file="$sandbox_home/R&D <stack> \$1 \\ 'x'/compose.yaml"
  mkdir -p "$(dirname "$compose_file")"
  : >"$compose_file"
  run_script install-runtime.sh --compose-file "$compose_file"
  assert_exit 0
  assert_true "plutil -lint accepts it" plutil -lint -s "$plist_path"
  assert_plist_value "the path survives" ProgramArguments.3 "$compose_file" "$plist_path"
}

# A relative compose file goes into the plist as an absolute path.
test_relative_compose_file() {
  new_case "relative compose file"
  last_exit=0
  (cd "$(dirname "$compose_file")" && env -i HOME="$sandbox_home" TMPDIR="$case_dir" FAKE_STATE_DIR="$state_dir" \
    PATH="$case_bin:$work_root/bin:/usr/bin:/bin" \
    /bin/bash "$runtime_dir/install-runtime.sh" --compose-file compose.yaml >"$output_file" 2>&1) || last_exit=$?
  assert_exit 0
  assert_plist_value "the path is absolute" ProgramArguments.3 "$compose_file" "$plist_path"
}

# A first install bootstraps once and leaves only the plist behind.
test_first_install() {
  new_case "first install"
  run_script install-runtime.sh --compose-file "$compose_file"
  assert_exit 0
  assert_calls "launchctl print $(service_target)" "launchctl bootstrap gui/$UID $plist_path"
  assert_true "the agent is loaded" test -f "$state_dir/agent-loaded"
  local entries
  entries="$(ls -A "$(dirname "$plist_path")")"
  if [ "$entries" = "$AGENT_LABEL.plist" ]; then pass "no temp file is left"; else fail "no temp file is left" "$entries"; fi
}

# Installing again unloads first, and the new compose file takes effect.
test_install_is_idempotent() {
  new_case "install again"
  run_script install-runtime.sh --compose-file "$compose_file"
  : >"$state_dir/calls"
  local other_compose="$case_dir/other-compose.yaml"
  : >"$other_compose"
  run_script install-runtime.sh --compose-file "$other_compose"
  assert_exit 0
  assert_calls "launchctl print $(service_target)" "launchctl bootout $(service_target)" \
    "launchctl print $(service_target)" "launchctl bootstrap gui/$UID $plist_path"
  assert_plist_value "the new compose file is in use" ProgramArguments.3 "$other_compose" "$plist_path"
}

# An invalid rendered plist changes nothing in launchd. Uses a fake plutil, because validated input cannot produce one.
test_invalid_render_changes_nothing() {
  new_case "plutil rejects the render"
  printf '#!/bin/bash\nexit 1\n' >"$case_bin/plutil"
  chmod +x "$case_bin/plutil"
  given_flag agent-loaded
  run_script install-runtime.sh --compose-file "$compose_file"
  assert_exit 1
  assert_calls
  assert_false "no plist is written" test -e "$plist_path"
}

# Install does not overwrite a plist with the same name that it did not write.
test_install_refuses_foreign_plist() {
  new_case "install finds a foreign plist"
  mkdir -p "$(dirname "$plist_path")"
  echo "hand-made" >"$plist_path"
  run_script install-runtime.sh --compose-file "$compose_file"
  assert_exit 1
  assert_calls
  assert_file_has "the foreign plist is intact" "hand-made" "$plist_path"
}

# An agent that launchd does not let go fails the install, keeps the old plist and skips the bootstrap.
test_install_with_stuck_agent() {
  new_case "install with a stuck agent"
  run_script install-runtime.sh --compose-file "$compose_file"
  given_flag bootout-stuck
  : >"$state_dir/calls"
  local other_compose="$case_dir/other-compose.yaml"
  : >"$other_compose"
  run_script install-runtime.sh --compose-file "$other_compose"
  assert_exit 1
  assert_file_lacks "no new bootstrap" "bootstrap" "$state_dir/calls"
  assert_plist_value "the old plist stays" ProgramArguments.3 "$compose_file" "$plist_path"
}

# A failed bootstrap fails the install and shows the reason.
test_install_with_failed_bootstrap() {
  new_case "install with a failed bootstrap"
  given_flag bootstrap-fails
  run_script install-runtime.sh --compose-file "$compose_file"
  assert_exit 1
  assert_file_has "shows the launchctl error" "Bootstrap failed: 5" "$output_file"
}

# Uninstall reverses install and removes only its own plist, keeping sibling plists and the log.
test_uninstall_reverses_install() {
  new_case "uninstall after install"
  run_script install-runtime.sh --compose-file "$compose_file"
  local sibling
  sibling="$(dirname "$plist_path")/com.example.other.plist"
  echo "other agent" >"$sibling"
  mkdir -p "$(dirname "$log_path")"
  echo "kept" >"$log_path"
  : >"$state_dir/calls"
  run_script uninstall-runtime.sh
  assert_exit 0
  assert_calls "launchctl print $(service_target)" "launchctl bootout $(service_target)" "launchctl print $(service_target)"
  assert_false "the plist is gone" test -e "$plist_path"
  assert_false "the agent is unloaded" test -f "$state_dir/agent-loaded"
  assert_true "the sibling plist stays" test -f "$sibling"
  assert_true "the log stays" test -f "$log_path"
}

# Uninstall with nothing installed succeeds and changes nothing.
test_uninstall_is_idempotent() {
  new_case "uninstall with nothing installed"
  run_script uninstall-runtime.sh
  assert_exit 0
  assert_calls "launchctl print $(service_target)"
}

# Uninstall leaves alone a plist with the same name that install did not write, and its agent too.
test_uninstall_refuses_foreign_plist() {
  new_case "uninstall finds a foreign plist"
  mkdir -p "$(dirname "$plist_path")"
  echo "hand-made" >"$plist_path"
  given_flag agent-loaded
  run_script uninstall-runtime.sh
  assert_exit 1
  assert_calls
  assert_file_has "the foreign plist is intact" "hand-made" "$plist_path"
}

# An agent that launchd does not let go fails the uninstall and keeps the plist.
test_uninstall_with_stuck_agent() {
  new_case "uninstall with a stuck agent"
  run_script install-runtime.sh --compose-file "$compose_file"
  given_flag bootout-stuck
  run_script uninstall-runtime.sh
  assert_exit 1
  assert_true "the plist stays" test -f "$plist_path"
}

# Argument validation of uninstall-runtime.sh, and its help.
test_uninstall_arguments() {
  new_case "uninstall rejects an unknown option"
  run_script uninstall-runtime.sh --bogus
  assert_exit 2
  assert_calls
  new_case "uninstall help"
  run_script uninstall-runtime.sh --help
  assert_exit 0
  assert_file_has "help shows the usage" "Usage: uninstall-runtime.sh" "$output_file"
}

# --verbose of install and uninstall shows the steps.
test_install_uninstall_verbose() {
  new_case "install and uninstall verbose"
  run_script install-runtime.sh --compose-file "$compose_file" --verbose
  assert_exit 0
  assert_file_has "install shows the steps" "loading $AGENT_LABEL" "$output_file"
  run_script uninstall-runtime.sh --verbose
  assert_exit 0
  assert_file_has "uninstall shows the steps" "removing " "$output_file"
}

# Removes the temp folder of the run, created by this script.
cleanup() {
  rm -rf "$work_root"
}

# Entry point.
main() {
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

  work_root="$(cd "$(mktemp -d)" && pwd -P)"
  trap cleanup EXIT
  write_fakes

  test_vm_off_starts_docker_only
  test_failed_start_is_retried
  test_failed_retry_notifies
  test_vm_on_with_kubernetes_stops_it
  test_vm_on_without_kubernetes_keeps_it
  test_compose_failure_notifies
  test_hung_command_is_stopped
  test_missing_compose_file_at_login
  test_compose_path_with_spaces
  test_kubernetes_stop_failure_keeps_compose
  test_bad_status
  test_log_content
  test_verbose_output
  test_unwritable_log
  test_notification_failure_keeps_exit
  test_login_arguments
  test_install_arguments
  test_plist_rendering
  test_plist_escapes_paths
  test_relative_compose_file
  test_first_install
  test_install_is_idempotent
  test_invalid_render_changes_nothing
  test_install_refuses_foreign_plist
  test_install_with_stuck_agent
  test_install_with_failed_bootstrap
  test_uninstall_reverses_install
  test_uninstall_is_idempotent
  test_uninstall_refuses_foreign_plist
  test_uninstall_with_stuck_agent
  test_uninstall_arguments
  test_install_uninstall_verbose

  echo "$passed checks passed, $failed failed, in $case_count cases"
  [ "$failed" -eq 0 ]
}

main "$@"
