#!/usr/bin/env bash
# End-to-end check of the observability stack, isolated in its own compose project, network, ports and temp dir,
# so that simultaneous runs do not share anything.
set -euo pipefail

readonly SMOKE_PROJECT="observability-smoke-$$"
readonly SERVICE="otel-lgtm"
readonly HTTP_TIMEOUT_SECONDS=5
readonly POLL_TIMEOUT_SECONDS=180
readonly START_TIMEOUT_SECONDS=240
readonly PROVISIONING_LOG_LINES=100
# Built-in dashboards of the image (AC-4) and source dashboards that were not brought (AC-5).
readonly FORBIDDEN_DASHBOARDS='"(uid|title)":"[^"]*(red metrics|jvm)'
# Fictitious attributes that must not survive the collector (AC-6), as sent and as Prometheus and Loki rename them.
readonly FAKE_VALUE="fake@example.com"
readonly PERSONAL_ATTRIBUTES="user.email user.id user.account_uuid user.account_id organization.id process.owner process_owner tool_input tool_parameters process.command_args process.executable.path full_command file_path bash_argv0 error"
readonly PERSONAL_TRACES='user[._]email|user[._]id|user[._]account|organization[._]id|process[._]owner|tool_input|tool_parameters|process[._]command_args|process[._]executable|full_command|file_path|bash_argv0|"error"|fake@example'
readonly PROBE_SERVICE="smoke-probe"
readonly PROBE_TRACE_ID="5b8efff798038103d269b633813fc60c"

# Prints the command usage.
usage() {
  cat <<'USAGE'
Usage: tests/run-smoke.sh [--verbose] [--help]

Starts the stack as compose project "observability-smoke-<pid>", on loopback ports chosen
by Docker, with temporary data and fictitious projects, checks the acceptance criteria
through the Grafana HTTP API and removes everything at the end. Never touches any other
compose project, so several runs can happen at the same time.
Exit 0 when every check passes, 1 on failure, 2 on usage error.

Options:
  --verbose   Show compose progress and, on failure, the full container logs.
  --help      Show this help.
USAGE
}

verbose=0
while [ $# -gt 0 ]; do
  case "$1" in
    --verbose) verbose=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

for required_command in docker curl python3; do
  command -v "$required_command" >/dev/null 2>&1 || { echo "error: $required_command not found" >&2; exit 2; }
done

tool_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_flags=(-p "$SMOKE_PROJECT" -f "$tool_dir/compose.yaml" -f "$tool_dir/tests/compose.smoke.yaml")
[ "$verbose" -eq 1 ] || compose_flags=(--progress quiet "${compose_flags[@]}")
grafana_url=""
otlp_url=""
isolation_checked=0

# Runs docker compose, always scoped to the smoke project.
smoke_compose() {
  docker compose "${compose_flags[@]}" "$@"
}

# Reads the URLs of the stack: Docker picks the host ports, and picks them again at each restart.
read_stack_urls() {
  grafana_url="http://$(smoke_compose port "$SERVICE" 3000)"
  otlp_url="http://$(smoke_compose port "$SERVICE" 4318)"
}

# Restarts the stack and reads its URLs again.
restart_stack() {
  smoke_compose restart "$SERVICE"
  read_stack_urls
}

# Prints the end of the container logs, in full with --verbose, and the Grafana provisioning lines; keeps the full
# log in a file, since the container is about to be removed.
print_logs() {
  local kept_log
  kept_log="$(mktemp "${TMPDIR:-/tmp}/$SMOKE_PROJECT.XXXXXX")" || return 0
  smoke_compose logs --no-color "$SERVICE" >"$kept_log" 2>&1 || true
  if [ "$verbose" -eq 1 ]; then
    cat "$kept_log" >&2
  else
    tail -n 30 "$kept_log" >&2
  fi
  echo "--- Grafana provisioning log (last $PROVISIONING_LOG_LINES lines)" >&2
  grep -F 'logger=provisioning.dashboard' "$kept_log" | tail -n "$PROVISIONING_LOG_LINES" >&2 || true
  echo "--- full container log kept in $kept_log" >&2
}

# Removes the smoke project and the temp dir, keeping the exit status of the run.
cleanup() {
  local status=$?
  trap - EXIT INT TERM
  if [ "$isolation_checked" -eq 1 ]; then
    [ "$status" -eq 0 ] || print_logs
    # The container writes /data as root, so only a container can remove it on a native Docker engine.
    smoke_compose stop -t 5 >/dev/null 2>&1 || true
    smoke_compose run --rm --no-deps -T --entrypoint sh otel-lgtm -c 'rm -rf /data/* /data/.[!.]*' >/dev/null 2>&1 || true
    smoke_compose down -v -t 5 --remove-orphans >/dev/null 2>&1 || {
      echo "error: could not remove compose project $SMOKE_PROJECT" >&2
      status=1
    }
  fi
  rm -rf "$work_dir"
  exit "$status"
}

# Reports a passed check.
pass() {
  echo "PASS $1"
}

# Reports a failed check and aborts the run.
fail() {
  echo "FAIL $1" >&2
  exit 1
}

# Writes a fictitious minimal dashboard: file path, uid, title.
write_dashboard() {
  mkdir -p "$(dirname "$1")"
  printf '{"uid":"%s","title":"%s","schemaVersion":39,"panels":[]}\n' "$2" "$3" >"$1"
}

# Prints one flat JSON object per Grafana search hit, dashboards and folders alike.
search_hits() {
  curl -fsS -m "$HTTP_TIMEOUT_SECONDS" "$grafana_url/api/search" 2>/dev/null | grep -oE '\{[^{}]*\}'
}

# Succeeds when a single search hit contains every given fixed string.
has_hit() {
  local hits needle
  hits="$(search_hits)" || return 1
  for needle in "$@"; do
    hits="$(grep -F -- "$needle" <<<"$hits")" || return 1
  done
}

# Succeeds when Grafana answers the search and no hit has the given dashboard uid.
lacks_dashboard() {
  local hits
  hits="$(search_hits)" || return 1
  ! grep -qF -- "\"uid\":\"$1\"" <<<"$hits"
}

# Prints the answer of a datasource through the Grafana proxy: datasource uid, path, then extra curl arguments.
proxy_get() {
  local datasource="$1" path="$2"
  shift 2
  curl -fsS -m "$HTTP_TIMEOUT_SECONDS" -G "$grafana_url/api/datasources/proxy/uid/$datasource/$path" "$@" 2>/dev/null
}

# Succeeds when a datasource answer contains a fixed string: the string, then the proxy_get arguments.
response_has() {
  local needle="$1" body
  shift
  body="$(proxy_get "$@")" || return 1
  grep -qF -- "$needle" <<<"$body"
}

# Fails when a datasource answer matches an extended regex: description, regex, then the proxy_get arguments.
assert_response_lacks() {
  local description="$1" pattern="$2" body
  shift 2
  body="$(proxy_get "$@")" || fail "$description (request failed)"
  if grep -qE -- "$pattern" <<<"$body"; then
    fail "$description"
  fi
  pass "$description"
}

# Prints the JSON of an OTLP attribute with a string value: key, value.
otlp_attribute() {
  printf '{"key":"%s","value":{"stringValue":"%s"}}' "$1" "$2"
}

# Prints the personal attributes as a comma-separated list of OTLP attributes.
personal_attributes() {
  local name separator=""
  for name in $PERSONAL_ATTRIBUTES; do
    printf '%s%s' "$separator" "$(otlp_attribute "$name" "$FAKE_VALUE")"
    separator=","
  done
}

# Posts a fictitious metric, log and span carrying the personal attributes at both the resource and the item level.
post_probes() {
  local now_nanos email resource
  now_nanos="$(date +%s)000000000"
  email="$(personal_attributes)"
  resource="{\"attributes\":[$(otlp_attribute service.name "$PROBE_SERVICE"),$(otlp_attribute smoke.kept yes),$email]}"
  post_otlp metrics "{\"resourceMetrics\":[{\"resource\":$resource,\"scopeMetrics\":[{\"metrics\":[{\"name\":\"smoke_probe\",\"gauge\":{\"dataPoints\":[{\"asDouble\":1,\"timeUnixNano\":\"$now_nanos\",\"attributes\":[$email]}]}}]}]}]}"
  post_otlp logs "{\"resourceLogs\":[{\"resource\":$resource,\"scopeLogs\":[{\"logRecords\":[{\"timeUnixNano\":\"$now_nanos\",\"severityText\":\"INFO\",\"body\":{\"stringValue\":\"smoke probe\"},\"attributes\":[$(otlp_attribute event.name api_error),$email]}]}]}]}"
  post_otlp traces "{\"resourceSpans\":[{\"resource\":$resource,\"scopeSpans\":[{\"spans\":[{\"traceId\":\"$PROBE_TRACE_ID\",\"spanId\":\"eee19b7ec3c1b174\",\"name\":\"smoke-span\",\"kind\":1,\"startTimeUnixNano\":\"$now_nanos\",\"endTimeUnixNano\":\"$now_nanos\",\"attributes\":[$email]}]}]}]}"
}

# Posts one OTLP/HTTP JSON payload: signal, body.
post_otlp() {
  curl -fsS -m "$HTTP_TIMEOUT_SECONDS" -o /dev/null -H 'Content-Type: application/json' -d "$2" "$otlp_url/v1/$1" \
    || fail "OTLP $1 post was refused"
}

# Polls a condition until it holds or the deadline passes: description, then the condition command.
wait_until() {
  local description="$1" deadline=$((SECONDS + POLL_TIMEOUT_SECONDS))
  shift
  until "$@"; do
    [ "$SECONDS" -lt "$deadline" ] || fail "$description (timed out after ${POLL_TIMEOUT_SECONDS}s)"
    sleep 2
  done
  pass "$description"
}

# Prints how many times Grafana walked the folder of a dashboard provider.
provider_walks() {
  smoke_compose logs --no-color "$SERVICE" 2>/dev/null | grep -F "name=$1 " | grep -cF 'msg="Start walking disk"' || true
}

# Succeeds when a dashboard provider walked its folder more times than the given count: provider, count.
provider_walked_since() {
  [ "$(provider_walks "$1")" -gt "$2" ]
}

# Fails when any search hit matches a case-insensitive extended regex; a failed request also fails.
assert_no_hit() {
  local description="$1" pattern="$2" hits
  hits="$(search_hits)" || fail "$description (Grafana search failed)"
  if grep -qiE -- "$pattern" <<<"$hits"; then
    fail "$description"
  fi
  pass "$description"
}

# Fails unless the Grafana folders are exactly the given titles, JSON-escaped: description, then titles.
assert_folders() {
  local description="$1" hits expected actual
  shift
  expected="$(printf '"title":"%s"\n' "$@" | sort)"
  hits="$(search_hits)" || fail "$description (Grafana search failed)"
  actual="$(grep -F '"type":"dash-folder"' <<<"$hits" | grep -oE '"title":"([^"\\]|\\.)*"' | sort)"
  [ "$actual" = "$expected" ] || fail "$description (expected: $expected; got: $actual)"
  pass "$description"
}

# Fails unless Grafana serves claude-code as the home dashboard: the API answers with a redirect to its title slug.
assert_home_dashboard() {
  local description="home dashboard is claude-code" home
  home="$(curl -fsS -m "$HTTP_TIMEOUT_SECONDS" "$grafana_url/api/dashboards/home")" || fail "$description (request failed)"
  grep -qF '"redirectUri":"/d/default-home-dashboard/claude-code' <<<"$home" || fail "$description (got: $home)"
  pass "$description"
}

# Aborts before starting anything when the merged config would reach the ports, the data or the network of the real stack.
assert_isolated() {
  local merged_config
  merged_config="$(smoke_compose config)"
  if grep -qE '^name: observability$' <<<"$merged_config"; then
    fail "smoke project is the real compose project"
  fi
  if grep -qE 'published: "?(3000|4317|4318)"?$' <<<"$merged_config"; then
    fail "smoke project publishes a port of the real stack"
  fi
  if grep -qF -e "$tool_dir/.data" -e "$(dirname "$(dirname "$tool_dir")")/projects" <<<"$merged_config"; then
    fail "smoke project mounts data of the real stack"
  fi
  if grep -qE '^ +name: observability$' <<<"$merged_config"; then
    fail "smoke project uses the network of the real stack"
  fi
  isolation_checked=1
  pass "smoke project is isolated from the real stack"
}

# AC-12: every query of the Claude Code dashboard is accepted by its datasource, even with no data at all;
# time series keep their resolution and panels by model share one color map.
check_dashboard_queries() {
  local description="AC-12 dashboard queries are accepted with no data; panel resolution and model colors hold"
  python3 -I -B "$tool_dir/tests/check_dashboard_queries.py" --grafana "$grafana_url" --dashboard "$tool_dir/dashboards/workspace/claude-code.json" \
    || fail "$description"
  pass "$description"
}

# AC-9, AC-10, AC-11, AC-13: fictitious telemetry for two models proves what the dashboard queries return.
check_dashboard_behavior() {
  python3 -I -B "$tool_dir/tests/check_dashboard_behavior.py" --grafana "$grafana_url" --otlp "$otlp_url" --dashboard "$tool_dir/dashboards/workspace/claude-code.json" \
    || fail "dashboard behavior"
}

# AC-1, AC-3, AC-4, AC-5: with zero projects the stack starts and shows only the workspace folder.
check_zero_projects() {
  smoke_compose up -d --wait --wait-timeout "$START_TIMEOUT_SECONDS"
  read_stack_urls

  wait_until "AC-1 folder workspace holds claude-code" has_hit '"uid":"claude-code"' '"folderTitle":"workspace"'
  wait_until "AC-1 folder workspace holds a POC dashboard" has_hit '"uid":"smoke-poc"' '"folderTitle":"workspace"'
  assert_home_dashboard
  assert_no_hit "AC-4 AC-5 image dashboards are absent" "$FORBIDDEN_DASHBOARDS"
  assert_folders "AC-3 zero projects create no Grafana folder" "workspace"
}

# AC-2, AC-3: a restart picks up a new project, at the root or under a client; projects without dashboards and
# subfolders of a repo create no folder.
check_new_project() {
  write_dashboard "$SMOKE_PROJECTS_DIR/demo-app/observability/dashboards/demo.json" "smoke-demo" "Smoke demo"
  write_dashboard "$SMOKE_PROJECTS_DIR/quoted \"name\": #1/observability/dashboards/demo.json" "smoke-quoted" "Smoke quoted"
  write_dashboard "$SMOKE_PROJECTS_DIR/demo-client/client-app/observability/dashboards/demo.json" "smoke-client-app" "Smoke client app"
  write_dashboard "$SMOKE_PROJECTS_DIR/demo-client/demo-app/observability/dashboards/demo.json" "smoke-client-demo" "Smoke client demo"
  mkdir -p "$SMOKE_PROJECTS_DIR/no-dashboards" "$SMOKE_PROJECTS_DIR/empty-dashboards/observability/dashboards" "$SMOKE_PROJECTS_DIR/demo-client/no-dashboards"
  mkdir -p "$SMOKE_PROJECTS_DIR/repo-app/.git" "$SMOKE_PROJECTS_DIR/worktree-app"
  touch "$SMOKE_PROJECTS_DIR/worktree-app/.git"
  write_dashboard "$SMOKE_PROJECTS_DIR/repo-app/observability/dashboards/repo.json" "smoke-repo" "Smoke repo"
  write_dashboard "$SMOKE_PROJECTS_DIR/repo-app/repo-sub/observability/dashboards/sub.json" "smoke-repo-sub" "Smoke repo sub"
  write_dashboard "$SMOKE_PROJECTS_DIR/worktree-app/worktree-sub/observability/dashboards/sub.json" "smoke-worktree-sub" "Smoke worktree sub"
  restart_stack

  wait_until "AC-2 restart creates folder demo-app with the fixture" has_hit '"uid":"smoke-demo"' '"folderTitle":"demo-app"'
  wait_until "AC-2 project names are quoted in YAML" has_hit '"uid":"smoke-quoted"' '"folderTitle":"quoted \"name\": #1'
  wait_until "AC-2 a project under a client gets a folder with its own name" has_hit '"uid":"smoke-client-app"' '"folderTitle":"client-app"'
  wait_until "AC-2 a project under a client can share its name with a project at the root" has_hit '"uid":"smoke-client-demo"' '"folderTitle":"demo-app"'
  wait_until "AC-2 a repo with a .git folder gets a folder with its own name" has_hit '"uid":"smoke-repo"' '"folderTitle":"repo-app"'
  assert_no_hit "AC-3 a subfolder of a repo is not taken for a project under a client" '"uid":"smoke-(repo|worktree)-sub"'
  assert_folders "AC-3 no-dashboards, empty-dashboards, repo subfolders and the client itself create no folder" "workspace" "demo-app" "client-app" "repo-app" 'quoted \"name\": #1'
}

# AC-2: a JSON edit reaches Grafana through polling, without a restart.
check_json_edit() {
  write_dashboard "$SMOKE_PROJECTS_DIR/demo-app/observability/dashboards/demo.json" "smoke-demo" "Smoke demo edited"
  wait_until "AC-2 JSON edit is picked up by polling" has_hit '"uid":"smoke-demo"' '"title":"Smoke demo edited"'
}

# AC-6: personal attributes sent over OTLP reach none of the backends, while the rest of the telemetry does.
check_personal_data_removed() {
  post_probes

  wait_until "AC-6 metric arrives in Prometheus" response_has '"smoke_probe"' prometheus api/v1/query --data-urlencode 'query=smoke_probe'
  wait_until "AC-6 resource attributes arrive in Prometheus" response_has '"smoke_kept":"yes"' prometheus api/v1/query --data-urlencode 'query=target_info{smoke_kept="yes"}'
  assert_response_lacks "AC-6 no personal attribute in the Prometheus metric" "$PERSONAL_TRACES" prometheus api/v1/query --data-urlencode 'query=smoke_probe'
  assert_response_lacks "AC-6 no personal attribute in the Prometheus resource" "$PERSONAL_TRACES" prometheus api/v1/query --data-urlencode 'query=target_info{smoke_kept="yes"}'
  assert_response_lacks "AC-6 no personal attribute among the Prometheus labels" "$PERSONAL_TRACES" prometheus api/v1/labels

  local loki_query="query={service_name=\"$PROBE_SERVICE\"}"
  wait_until "AC-6 log and its metadata arrive in Loki" response_has 'smoke_kept' loki loki/api/v1/query_range --data-urlencode "$loki_query"
  assert_response_lacks "AC-6 no personal attribute in the Loki log" "$PERSONAL_TRACES" loki loki/api/v1/query_range --data-urlencode "$loki_query"
  wait_until "AC-6 an api_error event is still counted without its error text" response_has '"metric":{}' loki loki/api/v1/query \
    --data-urlencode "query=sum(count_over_time({service_name=\"$PROBE_SERVICE\"} | event_name=\"api_error\" [10m]))"

  wait_until "AC-6 span arrives in Tempo" response_has 'smoke-span' tempo "api/v2/traces/$PROBE_TRACE_ID"
  assert_response_lacks "AC-6 no personal attribute in the Tempo span" "$PERSONAL_TRACES" tempo "api/v2/traces/$PROBE_TRACE_ID"
}

# AC-7: retention that keeps the migrated data, read from the running components.
check_retention() {
  # Prometheus normalizes the configured 365d and reports it as 1y.
  wait_until "AC-7 Prometheus retention is 365d" response_has '"storage.tsdb.retention.time":"1y"' prometheus api/v1/status/flags
  wait_until "AC-7 Tempo retention is 365d" response_has 'block_retention: 8760h0m0s' tempo status/config
  assert_response_lacks "AC-7 Tempo has no 14d retention left" 'block_retention: 336h' tempo status/config
  wait_until "AC-7 Loki has retention disabled" response_has 'retention_enabled: false' loki config
}

# AC-14: Loki accepts a query longer than its default 30d1h limit.
check_loki_query_length() {
  wait_until "AC-14 Loki has no query length limit" response_has 'max_query_length: 0s' loki config
  wait_until "AC-14 Loki answers a 40-day query" response_has '"status":"success"' loki loki/api/v1/query_range \
    --data-urlencode 'query=sum(count_over_time({service_name="claude-code"}[1h]))' --data-urlencode "start=$(($(date +%s) - 40 * 86400))" --data-urlencode "end=$(date +%s)" --data-urlencode 'step=86400'
}

# AC-8: Grafana looks at the folders by timer, with no file changing: file events are not reliable on a bind mount.
check_polling() {
  local provider walks
  for provider in workspace project-demo-app; do
    walks="$(provider_walks "$provider")"
    wait_until "AC-8 provider $provider polls by timer, with no file event" provider_walked_since "$provider" "$walks"
  done
}

# AC-8: the JSON is the single source of truth, in the workspace folder and in a project.
check_json_removal() {
  local extra="$SMOKE_PROJECTS_DIR/demo-app/observability/dashboards/extra.json"
  write_dashboard "$extra" "smoke-extra" "Smoke extra"
  wait_until "AC-8 new JSON of a known project appears without a restart" has_hit '"uid":"smoke-extra"' '"folderTitle":"demo-app"'
  rm -f "$extra" "$SMOKE_DASHBOARDS_DIR/demo-poc.json"
  wait_until "AC-8 removing a project JSON removes its dashboard" lacks_dashboard "smoke-extra"
  wait_until "AC-8 removing a workspace JSON removes its dashboard" lacks_dashboard "smoke-poc"
}

# AC-8: a removed project loses its dashboards and leaves an empty folder, as the README says.
check_project_removal() {
  rm -rf "${SMOKE_PROJECTS_DIR:?}/quoted \"name\": #1"
  restart_stack
  wait_until "AC-8 removing a project removes its dashboards" lacks_dashboard "smoke-quoted"
  assert_folders "AC-8 removing a project leaves its Grafana folder" "workspace" "demo-app" "client-app" "repo-app" 'quoted \"name\": #1'
}

# Under $HOME: data stays on a local disk the Docker daemon can bind mount.
work_dir="$(mktemp -d "$HOME/.observability-smoke.XXXXXX")"
export SMOKE_NETWORK="$SMOKE_PROJECT"
export SMOKE_DATA_DIR="$work_dir/data"
export SMOKE_DASHBOARDS_DIR="$work_dir/dashboards"
export SMOKE_PROJECTS_DIR="$work_dir/projects"
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$SMOKE_DATA_DIR" "$SMOKE_PROJECTS_DIR"
cp -R "$tool_dir/dashboards/workspace" "$SMOKE_DASHBOARDS_DIR"
write_dashboard "$SMOKE_DASHBOARDS_DIR/demo-poc.json" "smoke-poc" "Smoke POC"

assert_isolated
check_zero_projects
check_dashboard_queries
check_dashboard_behavior
check_new_project
check_json_edit
check_personal_data_removed
check_retention
check_loki_query_length
check_polling
check_json_removal
check_project_removal
echo "smoke: all checks passed"
