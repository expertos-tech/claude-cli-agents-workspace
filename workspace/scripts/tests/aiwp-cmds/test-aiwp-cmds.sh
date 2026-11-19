#!/usr/bin/env bash
# Tests of scripts/aiwp-cmds.sh in a throwaway workspace: a project with a bare remote, a custom/ repo with none, and
# stubs for the secret scan and for docker. The real workspace is never touched.
# Run: bash scripts/tests/aiwp-cmds/test-aiwp-cmds.sh [--only <test_name>]
# check takes the status of the test right before it on purpose: SC2319 does not apply.
# shellcheck disable=SC2319
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$HERE/../.." && pwd)"
SCRIPT="$SCRIPT_DIR/aiwp-cmds.sh"
BASE="$(cd "$(mktemp -d)" && pwd -P)"
trap 'real_cleanup; rm -rf "$BASE"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
# The commits open and close make in custom/ carry [#automatic-agent-commit] only inside Claude Code.
unset CLAUDECODE
FAILED=0
COUNT=0
OUT=""
RC=0
CURRENT=""
R=""
W="2026-11-16-sample-change"

check() { # description, status (0 = ok)
  if [ "$2" -ne 0 ]; then
    FAILED=$((FAILED + 1))
    echo "FAIL $CURRENT: $1 (rc=$RC out=[$OUT])"
  fi
}
has() { case "$OUT" in *"$1"*) check "has [$1]" 0 ;; *) check "missing [$1]" 1 ;; esac; }
hasnt() { case "$OUT" in *"$1"*) check "unexpected [$1]" 1 ;; *) check "no [$1]" 0 ;; esac; }
rc_is() { [ "$RC" -eq "$1" ]; check "rc $1" $?; }
eq() { [ "$2" = "$3" ]; check "$1: expected [$2] got [$3]" $?; }

# Fresh workspace: scripts/aiwp-cmds.sh, projects/app (developer and main, a bare remote, a git-ignored .env) and a
# custom/ repo with no remote.
fixture() {
  R="$BASE/ws.$CURRENT"
  rm -rf "$R" "$BASE/remote.$CURRENT.git"
  mkdir -p "$R/scripts/lib" "$R/projects" "$R/tmp"
  cp "$SCRIPT" "$R/scripts/aiwp-cmds.sh"
  cp "$(dirname "$SCRIPT")/lib/projects.sh" "$R/scripts/lib/"
  cp "$(dirname "$SCRIPT")/agent-copy.py" "$R/scripts/"
  git init -q --bare -b main "$BASE/remote.$CURRENT.git"
  git init -q -b main "$R/projects/app"
  printf '.env\n' >"$R/projects/app/.gitignore"
  printf 'v1\n' >"$R/projects/app/app.txt"
  git -C "$R/projects/app" add -A
  git -C "$R/projects/app" commit -q -m base
  git -C "$R/projects/app" branch developer
  git -C "$R/projects/app" switch -q developer
  git -C "$R/projects/app" remote add origin "$BASE/remote.$CURRENT.git"
  git -C "$R/projects/app" push -q origin main developer
  printf 'KEY=local\n' >"$R/projects/app/.env"
  git init -q -b main "$R/custom"
  printf '# custom\n' >"$R/custom/README.md"
  git -C "$R/custom" add -A
  git -C "$R/custom" commit -q -m base
  # The secret scan stub: a commit in the range that adds a line with LEAKED is a finding; SCAN_EXIT forces an exit.
  cat >"$BASE/scan.sh" <<'STUB'
#!/usr/bin/env bash
[ -z "${SCAN_EXIT:-}" ] || exit "$SCAN_EXIT"
[ -z "${SCAN_EAT_STDIN:-}" ] || cat >/dev/null
# shellcheck disable=SC2086  # the range is a list of revisions
if git -C "$1" log -p -m $2 | grep -q '^+.*LEAKED'; then echo "finding in $2"; exit 1; fi
exit 0
STUB
  chmod +x "$BASE/scan.sh"
  export AIWP_SECRETS_CMD="$BASE/scan.sh"
  unset SCAN_EXIT
  # The file scan open --request runs on a request it commits: docker info answers DOCKER_INFO_EXIT (default 0); the
  # validate.sh stub logs each call and finds a GitHub token shape in a listed file, printing what gitleaks prints.
  cat >"$BASE/docker-info.sh" <<'STUB'
#!/usr/bin/env bash
exit "${DOCKER_INFO_EXIT:-0}"
STUB
  cat >"$BASE/validate.sh" <<'STUB'
#!/usr/bin/env bash
echo "validate $*" >>"$VALIDATE_LOG"
list=""
while [ $# -gt 0 ]; do [ "$1" = --files ] && list="$2"; shift; done
while IFS= read -r p; do
  if grep -Eq 'ghp_[0-9A-Za-z]{36}' "$p"; then
    printf 'Finding:     REDACTED\nRuleID:      github-pat\nFile:        /work/%s\nleaks found: 1\n' "$p"
    exit 1
  fi
done <"$list"
echo "PASS secrets"
STUB
  chmod +x "$BASE/docker-info.sh" "$BASE/validate.sh"
  export AIWP_DOCKER="$BASE/docker-info.sh" AIWP_VALIDATE="$BASE/validate.sh" VALIDATE_LOG="$BASE/validate.$CURRENT.log"
  rm -f "$VALIDATE_LOG"
  unset DOCKER_INFO_EXIT
}

run() {
  OUT="$(cd "$R" && bash "$R/scripts/aiwp-cmds.sh" "$@" 2>&1)"
  RC=$?
}

clone() { echo "$R/tmp/work/$W/${1:-app}"; }
remote_sha() { git -C "$BASE/remote.$CURRENT.git" rev-parse -q --verify "refs/heads/$1" 2>/dev/null || echo none; }
commit_in() { # clone, file, content: commits and returns the hook output in OUT
  printf '%s\n' "$3" >"$1/$2"
  git -C "$1" add -- "$2"
  OUT="$(git -C "$1" commit -q -m "change $2" 2>&1)"
  RC=$?
}

test_open_creates_a_pushed_clone() {
  fixture
  run open "$W" app
  rc_is 0
  has "path: tmp/work/$W/app"
  has "pushed: feat/sample-change"
  has "copied: .env"
  local c
  c="$(clone)"
  eq "branch" "feat/sample-change" "$(git -C "$c" symbolic-ref --short HEAD)"
  eq "origin is the real remote" "$BASE/remote.$CURRENT.git" "$(git -C "$c" remote get-url origin)"
  eq "starts at the base" "$(git -C "$R/projects/app" rev-parse developer)" "$(git -C "$c" rev-parse HEAD)"
  eq "branch on the remote" "$(git -C "$c" rev-parse HEAD)" "$(remote_sha feat/sample-change)"
  [ -x "$(git -C "$c" rev-parse --git-path hooks)/pre-push" ] || [ -x "$c/.git/hooks/pre-push" ]; check "pre-push hook" $?
  [ -f "$c/.env" ]; check ".env copied" $?
  eq "base recorded" developer "$(git -C "$c" config aiwp.base)"
  run open "$W" app
  rc_is 0
  has "(already open)"
}

test_open_refuses_bad_arguments() {
  fixture
  run open not-a-work app
  rc_is 2
  run open "$W" ../outside
  rc_is 2
  run open "$W" missing
  rc_is 1
  run open "$W" app --branch main
  rc_is 2
  run open "$W" app --branch feat/developer
  rc_is 2
  [ ! -e "$R/tmp/work/$W" ]; check "nothing created" $?
}

test_every_commit_is_pushed() {
  fixture
  run open "$W" app
  local c
  c="$(clone)"
  commit_in "$c" a.txt one
  has "aiwp: pushed feat/sample-change"
  eq "remote has the commit" "$(git -C "$c" rev-parse HEAD)" "$(remote_sha feat/sample-change)"
  printf 'two\n' >>"$c/a.txt"
  OUT="$(git -C "$c" commit -q -am amended --amend 2>&1)"
  eq "an amend is pushed with lease" "$(git -C "$c" rev-parse HEAD)" "$(remote_sha feat/sample-change)"
  commit_in "$c" b.txt b
  commit_in "$c" c.txt c
  OUT="$(GIT_SEQUENCE_EDITOR=true git -C "$c" rebase -q -i "HEAD~2" --exec true 2>&1)"
  hasnt "HEAD is not on"
  eq "a rebase is pushed at the end" "$(git -C "$c" rev-parse HEAD)" "$(remote_sha feat/sample-change)"
  git -C "$c" commit -q --amend -m "rewritten again" --no-verify
  eq "--no-verify does not skip the push" "$(git -C "$c" rev-parse HEAD)" "$(remote_sha feat/sample-change)"
}

test_prepush_refuses_bases_env_files_and_secrets() {
  fixture
  run open "$W" app
  local c before
  c="$(clone)"
  before="$(remote_sha developer)"
  commit_in "$c" n.txt new
  OUT="$(git -C "$c" push origin HEAD:developer 2>&1)"
  RC=$?
  [ "$RC" -ne 0 ]; check "push to developer refused" $?
  has "a clone never pushes to developer"
  eq "developer untouched" "$before" "$(remote_sha developer)"
  printf 'K=1\n' >"$c/conf.env"
  printf 'K=1\n' >"$c/.env"
  git -C "$c" add -f .env
  OUT="$(git -C "$c" commit -q -m env 2>&1)"
  has "carry a local env file"
  has "NOT pushed"
  [ "$(remote_sha feat/sample-change)" != "$(git -C "$c" rev-parse HEAD)" ]; check "env commit stays local" $?
  git -C "$c" reset -q --hard HEAD~1
  commit_in "$c" s.txt "token LEAKED"
  has "a secret in the commits above"
  [ "$(remote_sha feat/sample-change)" != "$(git -C "$c" rev-parse HEAD)" ]; check "secret stays local" $?
  run status "$W"
  has "not-pushed=1"
  git -C "$c" reset -q --hard HEAD~1
  export SCAN_EXIT=3
  commit_in "$c" ok.txt fine
  has "the secret scan did not run (exit 3)"
  unset SCAN_EXIT
  run push "$W/app"
  rc_is 0
  has "aiwp: pushed"
  eq "pushed once the scan runs" "$(git -C "$c" rev-parse HEAD)" "$(remote_sha feat/sample-change)"
}

test_stop_check_blocks_once_while_a_commit_is_off_the_remote() {
  fixture
  run open "$W" app
  local c
  c="$(clone)"
  OUT="$(echo '{"stop_hook_active": false}' | bash "$R/scripts/aiwp-cmds.sh" _stop-check)"
  eq "all pushed: silent" "" "$OUT"
  export SCAN_EXIT=3
  commit_in "$c" x.txt x
  unset SCAN_EXIT
  OUT="$(echo '{"stop_hook_active": false}' | bash "$R/scripts/aiwp-cmds.sh" _stop-check)"
  has '"decision": "block"'
  has "$W/app"
  OUT="$(echo '{"stop_hook_active": true}' | bash "$R/scripts/aiwp-cmds.sh" _stop-check)"
  eq "second stop in a row passes" "" "$OUT"
  OUT="$(echo 'not json' | bash "$R/scripts/aiwp-cmds.sh" _stop-check)"
  has '"decision": "block"'
}

test_close_keeps_what_would_be_lost() {
  fixture
  run open "$W" app
  local c
  c="$(clone)"
  commit_in "$c" a.txt a
  printf 'dirty\n' >"$c/d.txt"
  run close "$W"
  rc_is 1
  has "files changed and not committed"
  has "is not in developer"
  rm "$c/d.txt"
  git -C "$R/projects/app" fetch -q origin feat/sample-change
  git -C "$R/projects/app" merge -q --ff-only FETCH_HEAD
  run close "$W"
  rc_is 0
  has "closed: tmp/work/$W"
  [ ! -e "$R/tmp/work/$W" ]; check "folder deleted" $?
  run open "$W" app
  rc_is 1
  has "already exists on the remote"
  run open "$W" app --branch fix/second-try
  c="$(clone)"
  commit_in "$c" b.txt b
  run close "$W" --discard
  rc_is 0
  [ "$(remote_sha feat/sample-change)" != none ]; check "discard keeps the remote branch" $?
}

test_run_and_status() {
  fixture
  run open "$W" app
  run run "$W/app" -- pwd
  rc_is 0
  has "tmp/work/$W/app"
  run run "$W/app" pwd
  rc_is 2
  run run ../../projects/app -- pwd
  rc_is 1
  has "is not a clone under tmp/work"
  run run "$W/nowhere" -- pwd
  rc_is 1
  has "not found"
  OUT="$(cd "$R" && bash scripts/aiwp-cmds.sh run "$R/projects/app" -- pwd 2>&1)"
  RC=$?
  rc_is 1
  has "is not a clone under tmp/work"
  run status
  has "tmp/work/$W/app  branch=feat/sample-change base=developer ahead=0 not-pushed=0 uncommitted=0"
}

test_open_custom_for_a_poc() {
  fixture
  run open "$W" custom --branch poc/sample
  rc_is 0
  has "has no remote"
  local c
  c="$(clone custom)"
  eq "base of a repo with no developer" main "$(git -C "$c" config aiwp.base)"
  commit_in "$c" pocs.md poc
  eq "pushed to custom itself" "$(git -C "$c" rev-parse HEAD)" "$(git -C "$R/custom" rev-parse refs/heads/poc/sample)"
}

# Fake docker on PATH: records every call in DOCKER_LOG. The state it answers from lives in $STUB: containers/<project>
# (one line: the compose folder; the container is c-<project>, running, web 80/tcp on host port 61500), mounts/<project>
# (the source of one bind of that container),
# res/<kind>.<project> (the lines of docker <kind> ls for that label), config.json (docker compose config --format json).
docker_stub() {
  STUB="$BASE/stub.$CURRENT"
  rm -rf "$STUB"
  mkdir -p "$BASE/bin" "$STUB/containers" "$STUB/res" "$STUB/mounts"
  export STUB
  cat >"$BASE/bin/docker" <<'STUB'
#!/usr/bin/env bash
echo "docker $*" >>"$DOCKER_LOG"
label="com.docker.compose.project"
case "$*" in
  "version "*) [ -z "${DOCKER_DOWN:-}" ] || exit 1; echo 28.0 ;;
  "ps -aq --filter label=$label="*) p="${4##*=}"; [ ! -f "$STUB/containers/$p" ] || echo "c-$p" ;;
  "ps -aq --filter label=$label" | "ps -aq") for f in "$STUB"/containers/*; do [ -f "$f" ] && echo "c-${f##*/}"; done ;;
  "ps --format "*) [ -z "${BUSY:-}" ] || echo "0.0.0.0:$BUSY->80/tcp" ;;
  "inspect -f "*) echo "app-web sha256:aaa" ;;
  "inspect "*)
    shift
    sep=""
    printf '['
    for id in "$@"; do
      p="${id#c-}"
      mounts="[]"
      [ ! -f "$STUB/mounts/$p" ] || mounts="[{\"Source\":\"$(cat "$STUB/mounts/$p")\"}]"
      printf '%s{"Id":"%s","Name":"/%s-web-1","Config":{"Labels":{"%s":"%s","%s.working_dir":"%s","com.docker.compose.service":"web"}},"State":{"Running":true},"NetworkSettings":{"Ports":{"80/tcp":[{"HostIp":"0.0.0.0","HostPort":"61500"}]}},"Mounts":%s}' \
        "$sep" "$id" "$p" "$label" "$p" "$label" "$(cat "$STUB/containers/$p")" "$mounts"
      sep=","
    done
    printf ']\n'
    ;;
  "network ls --filter label=$label="* | "volume ls --filter label=$label="* | "image ls --filter label=$label="*)
    kind="${1}"
    p="${4#label="$label"=}"
    [ ! -f "$STUB/res/$kind.$p" ] || cat "$STUB/res/$kind.$p"
    ;;
  "image ls --format "*) printf 'rollback-20260101-000001\nrollback-20260102-000001\nrollback-20260103-000001\nrollback-20260104-000001\npublished-20260105-000001-abc1234\nlatest\n' ;;
  "image inspect app-web:rollback-latest") [ -z "${NO_ROLLBACK:-}" ]; exit ;;
  compose*" config --format json"* | compose*" config --no-path-resolution --format json"*) cat "$STUB/config.json" ;;
  compose*" config --images"*) echo app-web ;;
  compose*" ps -aq"*) [ -n "${STACK_DOWN:-}" ] || echo c1 ;;
  compose*" up -d --build"*)
    echo "cwd $PWD" >>"$DOCKER_LOG"
    for a in "$@"; do case "$a" in *.binds.compose.yaml) cp "$a" "$STUB/binds.yaml" ;; esac; done
    [ -z "${UP_FAILS:-}" ] || exit 1
    ;;
esac
exit 0
STUB
  chmod +x "$BASE/bin/docker"
  export DOCKER_LOG="$BASE/docker.$CURRENT.log"
  : >"$DOCKER_LOG"
  unset DOCKER_DOWN BUSY STACK_DOWN NO_ROLLBACK UP_FAILS
}

# The compose config of the app with the docker stub: a built web with a fixed image and container name, a database
# and a worker on the web's image, a fixed network and volume name. $1 = external: the volume is external.
stub_config() {
  local volume='{"name":"app-data"}' name="${2:-agent_1116-sample-change}"
  [ "${1:-}" != external ] || volume='{"name":"shared-data","external":true}'
  printf '{"name":"%s","services":{"web":{"build":{"context":"%s","dockerfile":"Dockerfile"},"image":"app-web","container_name":"app-web","ports":[{"target":80,"published":"8080","protocol":"tcp","host_ip":"127.0.0.1"}]},"db":{"image":"postgres:16","ports":[{"target":5432,"published":"5432","protocol":"tcp"}]},"worker":{"image":"app-web"}},"networks":{"default":{"name":"app-net"}},"volumes":{"data":%s}}\n' \
    "$name" "$(clone)" "$volume" >"$STUB/config.json"
}

dock() { # aiwp-cmds.sh with the docker stub first on PATH; output in OUT
  OUT="$(cd "$R" && PATH="$BASE/bin:$PATH" bash scripts/aiwp-cmds.sh "$@" 2>&1)"
  RC=$?
}

test_up_publishes_the_copy_in_its_own_group() {
  fixture
  docker_stub
  stub_config
  run open "$W" app
  printf 'services: {}\n' >"$(clone)/compose.yaml"
  dock up "$W/app"
  rc_is 0
  local g=agent_1116-sample-change ov="$R/tmp/work/$W/agent-app.compose.yaml" web db
  has "group: $g"
  has "published: $g"
  web="$(printf '%s\n' "$OUT" | sed -n 's|^port: web 80/tcp -> \([0-9]*\) http://localhost:[0-9]* AGENT_PORT_WEB_80$|\1|p')"
  db="$(printf '%s\n' "$OUT" | sed -n 's|^port: db 5432/tcp -> \([0-9]*\) .*AGENT_PORT_DB_5432$|\1|p')"
  [ -n "$web" ] && [ "$web" -ge 61000 ] && [ "$web" -le 65535 ]; check "web port in 61000-65535: [$web]" $?
  [ -n "$db" ] && [ "$db" -ge 61000 ] && [ "$db" -le 65535 ] && [ "$db" != "$web" ]; check "db port in range, its own: [$db]" $?
  grep -q "^docker compose -p $g -f compose.yaml -f $ov up -d --build$" "$DOCKER_LOG"; check "up in the group with the override" $?
  grep -qx "cwd $(clone)" "$DOCKER_LOG"; check "from the clone" $?
  ! grep -q '^docker tag ' "$DOCKER_LOG"; check "no rollback tag for a copy" $?
  ! grep -q -- 'down\|volume rm\|rm -f' "$DOCKER_LOG"; check "nothing removed" $?
  grep -qx "name: \"$g\"" "$ov"; check "override names the group" $?
  [ "$(grep -c "image: \"$g-web\"" "$ov")" -eq 2 ]; check "web and its worker run the group's image" $?
  ! grep -q 'postgres' "$ov"; check "a pulled image stays" $?
  grep -q 'container_name: !reset null' "$ov"; check "fixed container name dropped" $?
  [ "$(grep -c '^    name: !reset null' "$ov")" -eq 2 ]; check "fixed network and volume names dropped" $?
  grep -q "published: \"$web\"" "$ov" && grep -q 'host_ip: "127.0.0.1"' "$ov"; check "web port moved, host ip kept" $?
  grep -q "AGENT_PORT_WEB_80: \"$web\"" "$ov"; check "port variable in the environment" $?
  eq "ports file" "AGENT_GROUP=$g AGENT_PORT_DB_5432=$db AGENT_PORT_WEB_80=$web" "$(sort "$R/tmp/work/$W/agent-app.ports.env" | tr '\n' ' ' | sed 's/ $//')"
  [ -z "$(git -C "$(clone)" status --porcelain -- . ':!compose.yaml')" ]; check "nothing written in the clone" $?
  # Again: the same group and the same ports while they are free.
  dock up "$W/app"
  rc_is 0
  has "port: web 80/tcp -> $web "
  # Closing the work: refused with work not merged, so no group is destroyed; --discard destroys it.
  run close "$W"
  rc_is 1
  hasnt "agent-app"
  hasnt "not a clone made by open"
}

test_a_second_clone_or_another_folder_gets_its_own_group() {
  fixture
  docker_stub
  stub_config
  run open "$W" app
  printf 'services: {}\n' >"$(clone)/compose.yaml"
  printf 'name: "agent_1116-sample-change"\n' >"$R/tmp/work/$W/agent-api.compose.yaml"
  # The base group of another work, 2026-11-16-sample-change-app, is never this clone's: the clone's name follows --.
  echo /elsewhere/sample-change-app >"$STUB/containers/agent_1116-sample-change-app"
  dock up "$W/app"
  rc_is 0
  has "group: agent_1116-sample-change--app"
  rm "$R/tmp/work/$W/agent-api.compose.yaml" "$R/tmp/work/$W/agent-app.compose.yaml"
  # The work's group runs from another folder: this clone takes its own name.
  echo /elsewhere/api >"$STUB/containers/agent_1116-sample-change"
  dock up "$W/app"
  rc_is 0
  has "group: agent_1116-sample-change--app"
  hasnt "group: agent_1116-sample-change"$'\n'
}

test_up_refuses_what_it_cannot_isolate_and_the_final_stack() {
  fixture
  docker_stub
  stub_config external
  run open "$W" app
  printf 'services: {}\n' >"$(clone)/compose.yaml"
  dock up "$W/app"
  rc_is 1
  has "volume data sets external"
  ! grep -q 'up -d' "$DOCKER_LOG"; check "nothing started" $?
  dock up app
  rc_is 1
  has "/docker-deploy"
  has "deploy app [developer|main]"
  stub_config
  local opt
  for opt in "-p other" -pother --project-name=other; do
    # shellcheck disable=SC2086  # "-p other" is two options on purpose
    dock up "$W/app" -- $opt
    rc_is 1
    has "drop -p/--project-name"
  done
  DOCKER_DOWN=1 dock up "$W/app"
  rc_is 1
  has "Docker: not reachable"
  rm "$(clone)/compose.yaml"
  dock up "$W/app"
  rc_is 1
  has "no compose file in"
}

# A service off the copy's safe list (privileged) only polices the person's compose: the copy starts and says so once.
test_up_starts_a_service_off_the_safe_list_with_a_warning() {
  fixture
  docker_stub
  run open "$W" app
  printf 'services: {}\n' >"$(clone)/compose.yaml"
  printf '{"name":"agent_1116-sample-change","services":{"web":{"image":"acme/web","privileged":true,"ports":[{"target":80,"protocol":"tcp"}]},"db":{"image":"postgres:16"}}}\n' >"$STUB/config.json"
  dock up "$W/app"
  rc_is 0
  has "WARNING: service web sets privileged, off the safe list of a copy — "
  has "so exec in web falls back to the permission mode"
  hasnt "service db sets"
  has "published: agent_1116-sample-change"
  grep -q 'up -d --build$' "$DOCKER_LOG"; check "the copy started" $?
  grep -q 'internal: true' "$R/tmp/work/$W/agent-app.compose.yaml"; check "its networks still internal" $?
  [ "$(grep -c '"com.aiwp.copy.safe": "false"' "$R/tmp/work/$W/agent-app.compose.yaml")" = 1 ]; check "web labeled unsafe" $?
  [ "$(grep -c '"com.aiwp.copy.safe": "true"' "$R/tmp/work/$W/agent-app.compose.yaml")" = 1 ]; check "db labeled safe" $?
}

test_down_stops_the_group_and_keeps_volumes() {
  fixture
  docker_stub
  stub_config
  run open "$W" app
  printf 'services: {}\n' >"$(clone)/compose.yaml"
  dock up "$W/app"
  dock down "$W/app"
  rc_is 0
  has "down: agent_1116-sample-change (volumes and images kept)"
  grep -qx 'docker compose -p agent_1116-sample-change down' "$DOCKER_LOG"; check "compose down of the group, no -v" $?
  dock down app
  rc_is 2
}

test_status_lists_the_groups_of_each_clone() {
  fixture
  docker_stub
  run open "$W" app
  clone >"$STUB/containers/agent_1116-sample-change"
  echo /elsewhere >"$STUB/containers/agent_0101-other"
  dock status
  rc_is 0
  has "copy: agent_1116-sample-change running 1/1 ports=web:80->61500"
  hasnt "agent_0101-other"
  printf 'name: "agent_1116-sample-change--app"\n' >"$R/tmp/work/$W/agent-app.compose.yaml"
  dock status "$W"
  has "copy: agent_1116-sample-change--app down ports=-"
  DOCKER_DOWN=1 dock status
  rc_is 0
  has "Docker: not reachable"
  [ "$(printf '%s\n' "$OUT" | grep -c 'Docker: not reachable')" -eq 1 ]; check "said once" $?
}

test_close_destroys_only_the_copy_groups_by_label() {
  fixture
  docker_stub
  run open "$W" app
  local g=agent_1116-sample-change
  clone >"$STUB/containers/$g"
  # A project that is not a copy, started by hand in the clone: never touched.
  clone >"$STUB/containers/app"
  echo "${g}_default" >"$STUB/res/network.$g"
  echo "${g}_data" >"$STUB/res/volume.$g"
  printf 'sha256:bbb %s-web:latest\nsha256:ccc other-name:latest\nsha256:ddd <none>:<none>\n' "$g" >"$STUB/res/image.$g"
  echo "app_data" >"$STUB/res/volume.app"
  dock close "$W" --discard
  rc_is 0
  has "destroyed: $g (1 containers, 1 networks, 1 volumes, 2 images)"
  has "kept: app (not a copy group)"
  has "kept: other-name:latest"
  grep -qx "docker rm -f c-$g" "$DOCKER_LOG"; check "containers by label" $?
  grep -qx "docker network rm ${g}_default" "$DOCKER_LOG"; check "networks" $?
  grep -qx "docker volume rm -f ${g}_data" "$DOCKER_LOG"; check "volumes" $?
  grep -qx "docker image rm $g-web:latest" "$DOCKER_LOG"; check "built image" $?
  grep -qx "docker image rm sha256:ddd" "$DOCKER_LOG"; check "untagged image of the group" $?
  grep -q 'other-name\|c-app\|app_data\|label=com.docker.compose.project=app ' "$DOCKER_LOG" &&
    ! grep -q 'rm .*\(other-name\|c-app\|app_data\)' "$DOCKER_LOG"; check "another project removed" $?
  [ ! -e "$R/tmp/work/$W" ]; check "folder closed" $?
}

test_a_name_that_is_not_a_copy_group_is_never_destroyed() {
  fixture
  docker_stub
  echo /x >"$STUB/containers/app"
  echo "app_data" >"$STUB/res/volume.app"
  local name
  for name in app agent_1116 agent_11-x AGENT_1116-x agent_1116-X agent_1116--x/.. claude-cli-agents-tools; do
    OUT="$(PATH="$BASE/bin:$PATH" python3 -I "$R/scripts/agent-copy.py" destroy "$name" 2>&1)"
    RC=$?
    rc_is 1
    has "refused: $name is not a copy group"
  done
  ! grep -q '^docker \(rm\|network rm\|volume rm\|image rm\)' "$DOCKER_LOG"; check "nothing removed" $?
  OUT="$(PATH="$BASE/bin:$PATH" python3 -I "$R/scripts/agent-copy.py" destroy agent_1116-x 2>&1)"
  RC=$?
  rc_is 0
  has "nothing to destroy: agent_1116-x"
  OUT="$(DOCKER_DOWN=1 PATH="$BASE/bin:$PATH" python3 -I "$R/scripts/agent-copy.py" destroy agent_1116-x 2>&1)"
  RC=$?
  rc_is 1
  has "Docker: not reachable: nothing destroyed"
}

test_deploy_developer_tags_the_last_publication_first() {
  fixture
  docker_stub
  stub_config "" app
  dock deploy app
  rc_is 0
  local log first_up rollback published
  log="$(cat "$DOCKER_LOG")"
  rollback="$(grep -n 'tag sha256:aaa app-web:rollback-latest' "$DOCKER_LOG" | head -1 | cut -d: -f1)"
  first_up="$(grep -n 'compose -p app up -d --build' "$DOCKER_LOG" | head -1 | cut -d: -f1)"
  published="$(grep -n 'tag sha256:aaa app-web:published-' "$DOCKER_LOG" | head -1 | cut -d: -f1)"
  [ -n "$rollback" ] && [ -n "$first_up" ] && [ "$rollback" -lt "$first_up" ]; check "rollback tag before the build" $?
  [ -n "$published" ] && [ "$published" -gt "$first_up" ]; check "published tag after the build" $?
  case "$log" in *"image rm app-web:rollback-20260101-000001"*) check "keeps the newest 3" 0 ;; *) check "keeps the newest 3" 1 ;; esac
  case "$log" in *"rm app-web:rollback-20260104"*) check "newest tag removed" 1 ;; *) check "newest tag kept" 0 ;; esac
  case "$log" in *volume*|*"down"*) check "no volume touched" 1 ;; *) check "no volume touched" 0 ;; esac
  grep -qx "cwd $R/projects/app" "$DOCKER_LOG"; check "built from projects/app" $?
  has "deployed: app from projects/app developer at $(git -C "$R/projects/app" rev-parse --short developer)"
  # The stack is down: the checkpoint is the newest published tag.
  : >"$DOCKER_LOG"
  STACK_DOWN=1 dock deploy app developer
  rc_is 0
  has "rollback: app-web:rollback-latest (published-20260105-000001-abc1234)"
  grep -q 'tag app-web:published-20260105-000001-abc1234 app-web:rollback-latest' "$DOCKER_LOG"; check "checkpoint from the published tag" $?
}

test_deploy_main_builds_a_checkout_of_main_under_the_final_name() {
  fixture
  docker_stub
  stub_config "" app
  printf 'services: {}\n' >"$R/projects/app/compose.yaml"
  git -C "$R/projects/app" add compose.yaml
  git -C "$R/projects/app" commit -q -m stack
  git -C "$R/projects/app" branch -f main developer
  git -C "$R/projects/app" push -q origin main
  printf 'v2\n' >"$R/projects/app/app.txt"
  git -C "$R/projects/app" commit -q -am "developer only"
  dock deploy app main
  rc_is 0
  grep -q "^cwd $R/tmp/deploy/app-main$" "$DOCKER_LOG"; check "built from the checkout of main" $?
  grep -q 'compose -p app -f compose.yaml up -d --build' "$DOCKER_LOG"; check "-p forced to the final name" $?
  has "deployed: app from projects/app main at $(git -C "$R/projects/app" rev-parse --short main)"
  has "copied: .env"
  [ ! -e "$R/tmp/deploy/app-main" ]; check "checkout removed" $?
  eq "projects/app stays on developer" developer "$(git -C "$R/projects/app" symbolic-ref --short HEAD)"
}

# The review finding on deploy main: a bind of the checkout would run the final stack on the checkout's empty data,
# and the next deploy would delete it while bound.
test_deploy_main_binds_the_data_of_projects_and_never_deletes_a_bound_checkout() {
  fixture
  docker_stub
  local app="$R/projects/app" co="$R/tmp/deploy/app-main"
  printf 'pgdata/\n' >>"$app/.gitignore"
  printf 'services: {}\n' >"$app/compose.yaml"
  printf 'services: {}\n' >"$app/compose.prod.yaml"
  # The repo's .env (git-ignored, copied into the checkout) names the compose files, as compose reads it.
  printf 'COMPOSE_FILE=compose.yaml:compose.prod.yaml\n' >>"$app/.env"
  printf 'server {}\n' >"$app/nginx.conf"
  git -C "$app" add -A
  git -C "$app" commit -q -m "stack"
  git -C "$app" branch -f main developer
  git -C "$app" push -q origin main developer
  mkdir -p "$app/pgdata"
  printf '{"name":"app","services":{"db":{"image":"postgres:16","volumes":[{"type":"bind","source":"./pgdata","target":"/var/lib/postgresql/data","bind":{"create_host_path":true}},{"type":"bind","source":"./nginx.conf","target":"/etc/nginx.conf","read_only":true},{"type":"bind","source":"/srv/acme","target":"/srv"}]}}}\n' >"$STUB/config.json"
  dock deploy app main
  rc_is 0
  grep -q "^docker compose -p app -f compose.yaml -f compose.prod.yaml -f $co.binds.compose.yaml up -d --build$" "$DOCKER_LOG"
  check "the compose files of the repo's .env, then the binds override" $?
  grep -q "\"source\": \"$app/pgdata\"" "$STUB/binds.yaml"; check "data from projects/app" $?
  grep -q "\"source\": \"$app/nginx.conf\"" "$STUB/binds.yaml"; check "the same tracked file from projects/app" $?
  grep -q '"create_host_path": true' "$STUB/binds.yaml" && grep -q '"read_only": true' "$STUB/binds.yaml"; check "bind options kept" $?
  ! grep -q '/srv/acme' "$STUB/binds.yaml"; check "a bind outside the checkout stays" $?
  [ ! -e "$co" ] && [ ! -e "$co.binds.compose.yaml" ]; check "checkout and override removed" $?
  # A tracked file of the bind that differs between main and projects/app: refused, nothing deployed.
  printf 'server { listen 81; }\n' >"$app/nginx.conf"
  : >"$DOCKER_LOG"
  dock deploy app main
  rc_is 1
  has "main differs from the repo checkout in nginx.conf"
  ! grep -q 'up -d' "$DOCKER_LOG"; check "nothing deployed" $?
  [ ! -e "$co" ]; check "refused checkout removed" $?
  git -C "$app" checkout -q -- nginx.conf
  # A checkout a container still binds is never deleted.
  mkdir -p "$co/pgdata"
  echo "$app" >"$STUB/containers/app"
  echo "$co/pgdata" >"$STUB/mounts/app"
  dock deploy app main
  rc_is 1
  has "refused: a container binds tmp/deploy/app-main"
  [ -d "$co/pgdata" ]; check "bound checkout kept" $?
  ! grep -q 'up -d' "$DOCKER_LOG"; check "still nothing deployed" $?
}

test_deploy_refuses_a_moved_checkout_a_copy_and_a_clone() {
  fixture
  docker_stub
  stub_config "" app
  printf 'dirty\n' >>"$R/projects/app/app.txt"
  dock deploy app
  rc_is 1
  has "has changes in its checkout"
  git -C "$R/projects/app" checkout -q -- app.txt
  git -C "$R/projects/app" switch -q main
  dock deploy app developer
  rc_is 1
  has "is on main, not developer"
  git -C "$R/projects/app" switch -q developer
  stub_config "" agent_1116-x
  dock deploy app
  rc_is 1
  has "is a task's copy group, not a final stack"
  run open "$W" app
  dock deploy "$W/app"
  rc_is 1
  has "is a clone"
  ! grep -q 'up -d' "$DOCKER_LOG"; check "nothing deployed" $?
  dock deploy
  rc_is 2
}

test_rollback_points_the_final_stack_back_and_never_builds() {
  fixture
  docker_stub
  run open "$W" app
  dock rollback app
  rc_is 0
  has "rolled back: app-web <- app-web:rollback-latest"
  grep -q 'compose up -d --no-build' "$DOCKER_LOG"; check "up without build" $?
  ! grep -q 'build' <(grep -v -- '--no-build' "$DOCKER_LOG"); check "no build" $?
  NO_ROLLBACK=1 dock rollback app
  rc_is 1
  has "no rollback-latest tag"
  dock rollback "$W/app"
  rc_is 1
  has "its copy has no rollback tags"
}

# Real Docker, only names this test generates (aiwpt<random>, agent_<MMDD>-t<random>): the final stack of a project
# and a task's copy of the same compose file side by side, then the copy destroyed. Skipped when Docker is not
# reachable or the base image is not on this machine (a test never downloads one).
REAL_FINAL=""
REAL_GROUP=""
real_cleanup() {
  [ -n "$REAL_FINAL" ] || return 0
  (cd "$R/projects/app" 2>/dev/null && docker compose -p "$REAL_FINAL" down -v >/dev/null 2>&1)
  local name
  for name in "$REAL_FINAL-web" "$REAL_FINAL-db"; do
    docker image ls --format '{{.Repository}}:{{.Tag}}' "$name" | while IFS= read -r ref; do docker image rm "$ref" >/dev/null 2>&1; done
  done
  python3 -I "$SCRIPT_DIR/agent-copy.py" destroy "$REAL_GROUP" >/dev/null 2>&1
  REAL_FINAL=""
}

test_real_docker_copy_beside_the_final_stack() {
  local image="${AIWP_TEST_BASE_IMAGE:-alpine:3.20}" rnd port final_id final_image copy_port w2 g
  if ! docker version >/dev/null 2>&1 || ! docker image inspect "$image" >/dev/null 2>&1; then
    echo "SKIP $CURRENT: Docker not reachable or $image not on this machine"
    return 0
  fi
  fixture
  rnd="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  w2="$(date +%Y-%m-%d)-t$rnd"
  g="agent_$(date +%m%d)-t$rnd"
  REAL_FINAL="aiwpt$rnd"
  REAL_GROUP="$g"
  port="$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')"
  # A one-line HTTP answer from busybox nc: the base image has no web server.
  cat >"$R/projects/app/http.sh" <<'SH'
#!/bin/sh
printf 'HTTP/1.0 200 OK\r\nContent-Length: 3\r\n\r\nok\n'
SH
  printf 'FROM %s\nCOPY http.sh /http.sh\nRUN chmod 755 /http.sh\nCMD ["sh", "-c", "sleep 600"]\n' "$image" >"$R/projects/app/Dockerfile"
  cat >"$R/projects/app/compose.yaml" <<YAML
name: $REAL_FINAL
services:
  web:
    build: .
    image: $REAL_FINAL-web:latest
    container_name: $REAL_FINAL-web
    command: ["nc", "-lk", "-p", "80", "-e", "/http.sh"]
    ports: ["127.0.0.1:$port:80"]
    volumes: [data:/data]
    networks: [net]
  db:
    build: .
    image: $REAL_FINAL-db:latest
    networks:
      net:
        aliases: [database]
networks:
  net:
    name: $REAL_FINAL-net
volumes:
  data:
    name: $REAL_FINAL-data
YAML
  git -C "$R/projects/app" add -A
  git -C "$R/projects/app" commit -q -m stack
  git -C "$R/projects/app" push -q origin developer
  OUT="$(cd "$R" && bash scripts/aiwp-cmds.sh deploy app 2>&1)"
  RC=$?
  rc_is 0
  final_id="$(docker ps -q --filter "name=^$REAL_FINAL-web$")"
  final_image="$(docker image inspect -f '{{.Id}}' "$REAL_FINAL-web:latest")"
  [ -n "$final_id" ]; check "final stack running" $?
  run open "$w2" app
  OUT="$(cd "$R" && bash scripts/aiwp-cmds.sh up "$w2/app" 2>&1)"
  RC=$?
  rc_is 0
  has "group: $g"
  copy_port="$(printf '%s\n' "$OUT" | sed -n 's|^port: web 80/tcp -> \([0-9]*\) .*|\1|p')"
  [ -n "$copy_port" ] && [ "$copy_port" -ge 61000 ] && [ "$copy_port" -le 65535 ]; check "copy port in range [$copy_port]" $?
  eq "copy publishes its port" "127.0.0.1:$copy_port" "$(docker port "$(docker ps -q --filter "label=com.docker.compose.project=$g" --filter label=com.docker.compose.service=web)" 80/tcp)"
  eq "final container kept" "$final_id" "$(docker ps -q --filter "name=^$REAL_FINAL-web$")"
  eq "final port kept" "127.0.0.1:$port" "$(docker port "$final_id" 80/tcp)"
  eq "final image tag kept" "$final_image" "$(docker image inspect -f '{{.Id}}' "$REAL_FINAL-web:latest")"
  [ -n "$(docker volume ls -q --filter "label=com.docker.compose.project=$g")" ]; check "the copy has its own volume" $?
  # The copy reaches outside Docker only from web, through <group>_edge; db is on internal networks only.
  has "network: db internal"
  has "network: web edge"
  local db_id web_id net nets
  db_id="$(docker ps -q --filter "label=com.docker.compose.project=$g" --filter label=com.docker.compose.service=db)"
  web_id="$(docker ps -q --filter "label=com.docker.compose.project=$g" --filter label=com.docker.compose.service=web)"
  # No WARNING for either service: the override marks both safe, the label guard-bash reads before an exec.
  eq "db marked safe" "true" "$(docker inspect -f '{{index .Config.Labels "com.aiwp.copy.safe"}}' "$db_id")"
  eq "web marked safe" "true" "$(docker inspect -f '{{index .Config.Labels "com.aiwp.copy.safe"}}' "$web_id")"
  nets="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$db_id")"
  [ -n "$nets" ]; check "db has networks" $?
  for net in $nets; do
    eq "db network $net internal" "true $g" "$(docker network inspect -f '{{.Internal}} {{index .Labels "com.docker.compose.project"}}' "$net")"
    eq "db network $net has no gateway to the host" "isolated isolated" \
      "$(docker network inspect -f '{{index .Options "com.docker.network.bridge.gateway_mode_ipv4"}} {{index .Options "com.docker.network.bridge.gateway_mode_ipv6"}}' "$net")"
  done
  eq "db has no route out of Docker" "" "$(docker exec "$db_id" ip route | grep '^default')"
  docker exec "$web_id" ip route | grep -q '^default'; check "web has its way out, through edge" $?
  # Nor any way to the host: a listener on every address of the host answers the host itself, never the db, whether
  # through the gateway of the db's own networks or the host's address on edge.
  local hostport listener addr
  hostport="$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("0.0.0.0", 0)); print(s.getsockname()[1])')"
  timeout 120 python3 -I -c '
import socket, sys
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("0.0.0.0", int(sys.argv[1])))
s.listen(5)
while True:
    c, _ = s.accept()
    c.sendall(b"hello\n")
    c.close()
' "$hostport" &
  listener=$!
  sleep 1
  eq "the host listener answers the host" hello "$(python3 -I -c 'import socket, sys; print(socket.create_connection(("127.0.0.1", int(sys.argv[1])), 5).recv(16).decode().strip())' "$hostport" 2>&1)"
  # shellcheck disable=SC2086  # $nets is the list of the db's networks
  for addr in $(docker network inspect -f '{{range .IPAM.Config}}{{.Gateway}} {{end}}' $nets "${g}_edge"); do
    eq "db cannot reach the host at $addr" "" "$(docker exec "$db_id" sh -c "nc -w 3 $addr $hostport </dev/null" 2>/dev/null)"
  done
  kill "$listener" 2>/dev/null
  wait "$listener" 2>/dev/null
  eq "edge keeps its gateway" "" "$(docker network inspect -f '{{index .Options "com.docker.network.bridge.gateway_mode_ipv4"}}' "${g}_edge")"
  eq "web on edge" "false $g" "$(docker network inspect -f '{{.Internal}} {{index .Labels "com.docker.compose.project"}}' "${g}_edge")"
  docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$web_id" | grep -q "${g}_edge"; check "web joined edge" $?
  eq "the published port answers" ok "$(python3 -I -c 'import sys, urllib.request; print(urllib.request.urlopen(sys.argv[1], timeout=10).read().decode().strip())' "http://127.0.0.1:$copy_port/" 2>&1)"
  eq "db reaches web by its name" ok "$(docker exec "$db_id" wget -q -T 5 -O- http://web/ 2>&1)"
  eq "web reaches db by its alias" 0 "$(docker exec "$web_id" sh -c 'ping -c 1 -W 3 database >/dev/null 2>&1; echo $?')"
  eq "final network unchanged" false "$(docker network inspect -f '{{.Internal}}' "$REAL_FINAL-net")"
  eq "final web on its network only" "$REAL_FINAL-net " "$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$final_id")"
  run status "$w2"
  has "copy: $g running 2/2 ports=web:80->$copy_port networks=db:internal,web:edge"
  # A second deploy of the final stack: rollback tags, no volume deleted.
  OUT="$(cd "$R" && bash scripts/aiwp-cmds.sh deploy app developer 2>&1)"
  RC=$?
  rc_is 0
  eq "rollback tag of the replaced image" "$final_image" "$(docker image inspect -f '{{.Id}}' "$REAL_FINAL-web:rollback-latest" 2>/dev/null)"
  docker volume inspect "$REAL_FINAL-data" >/dev/null 2>&1; check "final volume kept" $?
  # The copy goes with the work; the final stack stays.
  run close "$w2" --discard
  rc_is 0
  has "destroyed: $g"
  eq "copy containers gone" "" "$(docker ps -aq --filter "label=com.docker.compose.project=$g")"
  eq "copy volumes gone" "" "$(docker volume ls -q --filter "label=com.docker.compose.project=$g")"
  eq "copy networks gone" "" "$(docker network ls -q --filter "label=com.docker.compose.project=$g")"
  eq "copy images gone" "" "$(docker image ls -q --filter "label=com.docker.compose.project=$g")"
  eq "final container still there" "$final_id" "$(docker ps -q --filter "name=^$REAL_FINAL-web$")"
  local final="$REAL_FINAL"
  real_cleanup
  eq "final stack cleaned" "" "$(docker ps -aq --filter "label=com.docker.compose.project=$final")$(docker volume ls -q --filter "name=^$final")$(docker image ls -q "$final-web")"
}

test_prepush_reads_every_ref_before_the_scanner() {
  fixture
  run open "$W" app
  local c before
  c="$(clone)"
  before="$(remote_sha main)"
  commit_in "$c" a.txt a
  export SCAN_EAT_STDIN=1
  OUT="$(git -C "$c" push origin HEAD:refs/heads/feat/sample-change HEAD:refs/heads/main 2>&1)"
  RC=$?
  [ "$RC" -ne 0 ]; check "a second ref to main is still refused" $?
  eq "main untouched" "$before" "$(remote_sha main)"
  git -C "$c" switch -q -c fix/other
  commit_in "$c" s.txt "token LEAKED"
  OUT="$(git -C "$c" push origin feat/sample-change fix/other 2>&1)"
  RC=$?
  [ "$RC" -ne 0 ]; check "a secret in a second ref is still refused" $?
  eq "the secret branch never reached the remote" none "$(remote_sha fix/other)"
  unset SCAN_EAT_STDIN
}

test_prepush_scans_what_the_remote_lacks_not_the_local_tracking_refs() {
  fixture
  # projects/app has a local commit nobody pushed; the remote is unreachable when open runs.
  printf 'TOKEN=LEAKED\n' >"$R/projects/app/local.txt"
  git -C "$R/projects/app" add local.txt
  git -C "$R/projects/app" commit -q -m local
  mv "$BASE/remote.$CURRENT.git" "$BASE/away.git"
  run open "$W" app
  has "could not fetch developer"
  mv "$BASE/away.git" "$BASE/remote.$CURRENT.git"
  local c
  c="$(clone)"
  run push "$W/app"
  rc_is 1
  has "a secret in the commits above"
  eq "nothing reached the remote" none "$(remote_sha feat/sample-change)"
}

test_close_and_stop_look_at_branches_stashes_and_extra_files() {
  fixture
  run open "$W" app
  local c
  c="$(clone)"
  export SCAN_EXIT=3
  commit_in "$c" a.txt a
  unset SCAN_EXIT
  git -C "$c" switch -q --detach HEAD~1
  OUT="$(echo '{"stop_hook_active": false}' | bash "$R/scripts/aiwp-cmds.sh" _stop-check)"
  has '"decision": "block"'
  run close "$W"
  rc_is 1
  has "commits not on the remote"
  git -C "$c" switch -q feat/sample-change
  run push "$W/app"
  git -C "$R/projects/app" fetch -q origin feat/sample-change
  git -C "$R/projects/app" merge -q --ff-only FETCH_HEAD
  printf 'wip\n' >"$c/w.txt"
  git -C "$c" stash -q -u
  mkdir -p "$R/tmp/work/$W/notes"
  run close "$W"
  rc_is 1
  has "a stash"
  has "notes: not a clone made by open"
  [ -d "$R/tmp/work/$W" ]; check "nothing deleted" $?
}

test_every_kind_of_env_file_commit_is_refused() {
  fixture
  run open "$W" app
  local c
  c="$(clone)"
  rm -f "$c/.env"
  printf 'K=1\n' >"$c/a.env"
  git -C "$c" add a.env
  git -C "$c" commit -q -m "a.env" >/dev/null 2>&1
  OUT="$(git -C "$c" mv a.env .env 2>&1 && git -C "$c" commit -q -m rename 2>&1)"
  has "carry a local env file"
  git -C "$c" reset -q --hard HEAD~1
  git -C "$c" switch -q -c side
  printf 'K=1\n' >"$c/.env"
  git -C "$c" add -f .env
  git -C "$c" commit -q -m side-env >/dev/null 2>&1
  git -C "$c" switch -q feat/sample-change
  OUT="$(git -C "$c" merge -q --no-ff -m merge side 2>&1)"
  has "carry a local env file"
  [ "$(remote_sha feat/sample-change)" != "$(git -C "$c" rev-parse HEAD)" ]; check "merge with .env not pushed" $?
}

test_a_merge_is_pushed() {
  fixture
  run open "$W" app
  local c
  c="$(clone)"
  git -C "$c" switch -q -c side
  commit_in "$c" s.txt s
  git -C "$c" switch -q feat/sample-change
  commit_in "$c" m.txt m
  git -C "$c" merge -q --no-ff -m merge side >/dev/null 2>&1
  eq "post-merge pushed" "$(git -C "$c" rev-parse HEAD)" "$(remote_sha feat/sample-change)"
}

test_prepush_scans_against_the_remote_being_pushed_to() {
  fixture
  printf 'token=LEAKED\n' >"$R/custom/local.txt"
  git -C "$R/custom" add local.txt
  git -C "$R/custom" commit -q -m local
  run open "$W" custom --branch poc/sample
  local c
  c="$(clone custom)"
  git init -q --bare "$BASE/external.$CURRENT.git"
  OUT="$(git -C "$c" push "$BASE/external.$CURRENT.git" HEAD:refs/heads/x 2>&1)"
  RC=$?
  [ "$RC" -ne 0 ]; check "a push to another remote is scanned against that remote" $?
  has "a secret in the commits above"
  ! git -C "$BASE/external.$CURRENT.git" rev-parse -q --verify refs/heads/x >/dev/null; check "nothing reached the other remote" $?
}

test_a_commit_on_a_detached_head_is_not_lost() {
  fixture
  run open "$W" app
  local c
  c="$(clone)"
  git -C "$c" switch -q --detach
  printf 'precious\n' >"$c/p.txt"
  git -C "$c" add p.txt
  git -C "$c" commit -q -m precious >/dev/null 2>&1
  OUT="$(echo '{"stop_hook_active": false}' | bash "$R/scripts/aiwp-cmds.sh" _stop-check)"
  has '"decision": "block"'
  run close "$W"
  rc_is 1
  has "commits not on the remote"
  [ -d "$c" ]; check "the clone stays" $?
}

# Creates a repo at projects/$1 with one commit on main and developer, and no remote.
local_repo() {
  git init -q -b main "$R/projects/$1"
  printf '%s\n' "$1" >"$R/projects/$1/readme.txt"
  git -C "$R/projects/$1" add readme.txt
  git -C "$R/projects/$1" commit -q -m base
  git -C "$R/projects/$1" switch -q -c developer
}

# A repo inside a repo: its clone is named after its whole path (/ as --), run and status reach it, a clone opened
# under the last folder (as before) is reused, and a clone folder of another repo with the same name is refused.
test_open_names_a_nested_repo_after_its_path() {
  fixture
  local_repo app/inner
  run open "$W" app/inner
  rc_is 0
  has "path: tmp/work/$W/app--inner"
  eq "source" "$R/projects/app/inner" "$(git -C "$(clone app--inner)" config aiwp.source)"
  run run "$W/app--inner" -- git rev-parse --abbrev-ref HEAD
  rc_is 0
  has "feat/sample-change"
  run status "$W"
  has "tmp/work/$W/app--inner  branch=feat/sample-change"
  mv "$(clone app--inner)" "$(clone inner)"
  run open "$W" app/inner
  rc_is 0
  has "path: tmp/work/$W/inner (already open)"
  [ ! -e "$(clone app--inner)" ]; check "no second clone of the same repo" $?
  local w2="2026-11-17-other-change"
  local_repo app--inner
  run open "$w2" app--inner
  rc_is 0
  has "path: tmp/work/$w2/app--inner"
  run open "$w2" app/inner
  rc_is 1
  has "tmp/work/$w2/app--inner exists and is not a clone of app/inner"
  run open "$w2" .
  rc_is 2
}

# AC-1: a hotfix clone starts from main of the remote (production), never from developer nor from a local main behind
# the remote, and records the base main.
test_open_from_main_starts_from_the_remote_main() {
  fixture
  local hw="2026-11-17-hotfix-login-null" remote="$BASE/remote.$CURRENT.git" c
  printf 'unreleased\n' >"$R/projects/app/unreleased.txt"
  git -C "$R/projects/app" add unreleased.txt
  git -C "$R/projects/app" commit -q -m "unreleased work"
  git -C "$R/projects/app" push -q origin developer
  rm -rf "$BASE/other"
  git clone -q -b main "$remote" "$BASE/other"
  printf 'released later\n' >"$BASE/other/released.txt"
  git -C "$BASE/other" add released.txt
  git -C "$BASE/other" commit -q -m "released by another release"
  git -C "$BASE/other" push -q origin main
  run open "$hw" app --from-main
  rc_is 0
  has "hotfix: fix/login-null starts from main"
  has "pushed: fix/login-null"
  has "path: tmp/work/$hw/app"
  c="$R/tmp/work/$hw/app"
  eq "branch" fix/login-null "$(git -C "$c" symbolic-ref --short HEAD)"
  eq "starts at the remote main" "$(remote_sha main)" "$(git -C "$c" rev-parse HEAD)"
  if git -C "$c" merge-base --is-ancestor "$(remote_sha developer)" HEAD; then check "no commit of developer" 1; fi
  eq "base recorded" main "$(git -C "$c" config aiwp.base)"
  eq "hotfix recorded" 1 "$(git -C "$c" config aiwp.hotfix)"
  # Regression: git clone --local copied the checked-out developer as a local branch, which close saw as commits off
  # the remote; a hotfix clone holds only its fix branch.
  eq "only the fix branch" fix/login-null "$(git -C "$c" for-each-ref --format='%(refname:short)' refs/heads)"
  run close "$hw"
  rc_is 1
  has "fix/login-null is not in main"
  hasnt "commits not on the remote"
  eq "projects/app untouched" developer "$(git -C "$R/projects/app" symbolic-ref --short HEAD)"
  run status "$hw"
  has "branch=fix/login-null base=main ahead=0"
  run open "$hw" app --from-main
  rc_is 0
  has "(already open)"
  run open "$hw" app
  rc_is 1
  has "is open already as a hotfix clone"
  run open "$W" app
  run open "$W" app --from-main
  rc_is 1
  has "is open already from its base"
  run open 2026-11-17-other-fix app --from-main --branch fix/session-expiry
  rc_is 0
  has "pushed: fix/session-expiry"
}

# Regression: projects/<repo> cloned with developer as its default branch has no local main; open --from-main read
# refs/heads/main, exited 128 and left a half-made clone behind.
test_open_from_main_without_a_local_main() {
  fixture
  local hw="2026-11-17-hotfix-no-local-main" c
  git -C "$R/projects/app" branch -q -D main
  run open "$hw" app --from-main
  rc_is 0
  has "pushed: fix/no-local-main"
  c="$R/tmp/work/$hw/app"
  eq "branch" fix/no-local-main "$(git -C "$c" symbolic-ref --short HEAD)"
  eq "starts at the remote main" "$(remote_sha main)" "$(git -C "$c" rev-parse HEAD)"
  eq "projects/app still has no local main" "" "$(git -C "$R/projects/app" branch --list main)"
}

# AC-8: a repo with no main, or with no developer, stops the hotfix with a warning, and nothing is created for any repo.
test_open_from_main_refuses_a_repo_without_main_or_developer() {
  fixture
  local hw="2026-11-17-hotfix-login-null" remote="$BASE/remote.$CURRENT.git"
  git -C "$remote" update-ref -d refs/heads/main
  run open "$hw" app --from-main
  rc_is 1
  has "app has no main on its remote: a hotfix starts from main (production); nothing was created"
  [ ! -e "$R/tmp/work/$hw" ]; check "no clone folder" $?
  eq "no branch on the remote" none "$(remote_sha fix/login-null)"
  local_repo solo
  git -C "$R/projects/solo" branch -q -D main
  run open "$hw" solo --from-main
  rc_is 1
  has "solo has no main: a hotfix starts from main (production)"
  git init -q -b main "$R/projects/mainonly"
  git -C "$R/projects/mainonly" commit -q --allow-empty -m base
  run open "$hw" mainonly --from-main
  rc_is 1
  has "mainonly has no developer: its base is main, and the normal flow already works from it (open without --from-main)"
  # Several repos: one refused, none created.
  local_repo good
  run open "$hw" good mainonly --from-main
  rc_is 1
  [ ! -e "$R/tmp/work/$hw" ]; check "nothing created for the good repo either" $?
  # Regression: a repo that does not exist stops the check of the others, never passes as an empty folder.
  run open "$hw" good missing --from-main
  rc_is 1
  has "repo not found: missing"
  hasnt "missing has no main"
  [ ! -e "$R/tmp/work/$hw" ]; check "nothing created with a missing repo" $?
  run open "$hw" good --from-main --branch feat/x
  rc_is 2
  has "--from-main needs a branch fix/<kebab-slug>"
  run open "$hw" good --from-main --branch fix/main
  rc_is 2
  [ ! -e "$R/tmp/work/$hw" ]; check "still nothing created" $?
  run open "$hw" good --from-main
  rc_is 0
  has "attention: good has no remote"
  eq "no remote: from the local main" "$(git -C "$R/projects/good" rev-parse main)" "$(git -C "$R/tmp/work/$hw/good" rev-parse HEAD)"
}

# A request committed in custom/requests/ (or the path given, relative to custom/).
request_in_custom() { # file relative to custom/, content
  mkdir -p "$(dirname "$R/custom/$1")"
  printf '%s\n' "$2" >"$R/custom/$1"
  git -C "$R/custom" add -- "$1"
  git -C "$R/custom" commit -q -m "add $1" -- "$1"
}
custom_commits() { git -C "$R/custom" rev-list --count HEAD; }
custom_title() { git -C "$R/custom" log -1 --format=%s; }

test_open_request_moves_it_to_doing_once() {
  fixture
  git init -q --bare -b main "$BASE/custom.$CURRENT.git"
  git -C "$R/custom" remote add origin "$BASE/custom.$CURRENT.git"
  request_in_custom requests/r.md "# R"
  local before
  before="$(custom_commits)"
  export CLAUDECODE=1
  run open "$W" app --request r.md
  unset CLAUDECODE
  rc_is 0
  has "path: tmp/work/$W/app"
  has "committed in custom/"
  has "chore(requests): start r.md"
  has "pushed: custom/ main"
  has "request: custom/requests/doing/r.md (in progress in tmp/work/$W)"
  [ -f "$R/custom/requests/doing/r.md" ] && [ ! -e "$R/custom/requests/r.md" ]; check "moved to doing/" $?
  eq "one commit in custom/" "$((before + 1))" "$(custom_commits)"
  eq "start commit title" "chore(requests): start r.md" "$(custom_title)"
  git -C "$R/custom" log -1 --format=%B | grep -q "in progress: tmp/work/$W, branch feat/sample-change, repos app"; check "body names the work" $?
  git -C "$R/custom" log -1 --format=%B | grep -qx '\[#automatic-agent-commit\]'; check "agent trailer inside Claude Code" $?
  eq "a pure rename" "R100	requests/r.md	requests/doing/r.md" "$(git -C "$R/custom" show -M --format= --name-status HEAD)"
  eq "custom/ clean" "" "$(git -C "$R/custom" status --porcelain)"
  eq "pushed to the remote of custom/" "$(git -C "$R/custom" rev-parse HEAD)" "$(git -C "$BASE/custom.$CURRENT.git" rev-parse main)"
  eq "the work records it" "custom/requests/doing/r.md" "$(cat "$R/tmp/work/$W/.request")"
  run status
  has "tmp/work/$W  request=custom/requests/doing/r.md"
  has "tmp/work/$W/app  branch=feat/sample-change"
  hasnt "stale:"
  # Resume in the same work: the bare name is found in doing/, the clone reused, no new commit.
  run open "$W" app --request r.md
  rc_is 0
  has "(already open)"
  eq "no second start commit" "$((before + 1))" "$(custom_commits)"
}

# The state of custom/ the tests compare: every commit and the porcelain status with untracked files.
custom_state() { git -C "$R/custom" rev-parse HEAD; git -C "$R/custom" status --porcelain --untracked-files=all; }

test_open_request_commits_an_untracked_request_then_moves_it() {
  fixture
  mkdir -p "$R/custom/requests"
  printf '# U, written by hand\n' >"$R/custom/requests/u.md"
  # Unrelated work in custom/: an untracked note, a staged file and a changed tracked one stay as they are.
  printf 'draft\n' >"$R/custom/notes.md"
  printf 'staged\n' >"$R/custom/staged.md"
  git -C "$R/custom" add -- staged.md
  printf 'changed\n' >>"$R/custom/README.md"
  local before
  before="$(custom_commits)"
  run open "$W" app --request u.md
  rc_is 0
  has "committed in custom/: "
  has "chore(requests): add u.md"
  has "chore(requests): start u.md"
  has "request: custom/requests/doing/u.md (in progress in tmp/work/$W)"
  [ -f "$R/custom/requests/doing/u.md" ] && [ ! -e "$R/custom/requests/u.md" ]; check "moved to doing/" $?
  eq "two commits in custom/" "$((before + 2))" "$(custom_commits)"
  eq "the add commit holds only the request" "A	requests/u.md" "$(git -C "$R/custom" show --format= --name-status HEAD~1)"
  eq "the file as written" "# U, written by hand" "$(git -C "$R/custom" show HEAD~1:requests/u.md)"
  eq "then a pure rename" "R100	requests/u.md	requests/doing/u.md" "$(git -C "$R/custom" show -M --format= --name-status HEAD)"
  grep -q "^validate --only secrets --path custom --files " "$VALIDATE_LOG"; check "the file was scanned" $?
  eq "the rest of custom/ untouched" "A  staged.md
 M README.md
?? notes.md" "$(git -C "$R/custom" status --porcelain --untracked-files=all | sort)"
  eq "staged.md still staged, not committed" "staged" "$(git -C "$R/custom" show :staged.md)"
  eq "the work records it" "custom/requests/doing/u.md" "$(cat "$R/tmp/work/$W/.request")"
}

test_open_request_commits_a_changed_request_then_moves_it() {
  fixture
  request_in_custom requests/c.md "# C"
  printf 'more, not committed\n' >>"$R/custom/requests/c.md"
  printf 'draft\n' >"$R/custom/notes.md"
  local before
  before="$(custom_commits)"
  run open "$W" app --request c.md
  rc_is 0
  has "chore(requests): add c.md"
  has "chore(requests): start c.md"
  eq "two commits in custom/" "$((before + 2))" "$(custom_commits)"
  eq "the change committed first" "M	requests/c.md" "$(git -C "$R/custom" show --format= --name-status HEAD~1)"
  eq "with the text on disk" "# C
more, not committed" "$(git -C "$R/custom" show HEAD:requests/doing/c.md)"
  eq "then a pure rename" "R100	requests/c.md	requests/doing/c.md" "$(git -C "$R/custom" show -M --format= --name-status HEAD)"
  eq "only notes.md left out" "?? notes.md" "$(git -C "$R/custom" status --porcelain --untracked-files=all)"
  # A committed request needs no scan: the next one goes straight to the rename.
  rm -f "$VALIDATE_LOG"
  request_in_custom requests/d.md "# D"
  run open 2026-11-17-other app --branch feat/other --request d.md
  rc_is 0
  hasnt "chore(requests): add d.md"
  [ ! -e "$VALIDATE_LOG" ]; check "no scan of a committed request" $?
}

test_open_request_with_a_secret_is_refused_with_nothing_changed() {
  fixture
  mkdir -p "$R/custom/requests"
  # An invented token in the shape gitleaks' github-pat rule finds, built at run time so no file holds it.
  printf '# S\ntoken: %s%s\n' "ghp_" "0123456789abcdefghijABCDEFGHIJabcdef" >"$R/custom/requests/s.md"
  printf 'draft\n' >"$R/custom/notes.md"
  local before
  before="$(custom_state)"
  run open "$W" app --request s.md
  rc_is 1
  has "leaks found"
  has "custom/requests/s.md holds a secret"
  hasnt "ghp_0123"
  [ ! -e "$R/tmp/work/$W" ]; check "nothing cloned" $?
  eq "no branch on the remote" none "$(remote_sha feat/sample-change)"
  eq "custom/ unchanged" "$before" "$(custom_state)"
  [ ! -e "$R/custom/requests/doing" ]; check "nothing moved" $?
  # The same file tracked, with the secret as a change not committed: refused the same way.
  printf '# S\n' >"$R/custom/requests/t.md"
  git -C "$R/custom" add -- requests/t.md
  git -C "$R/custom" commit -q -m "add t" -- requests/t.md
  cp "$R/custom/requests/s.md" "$R/custom/requests/t.md"
  before="$(custom_state)"
  run open "$W" app --request t.md
  rc_is 1
  has "custom/requests/t.md holds a secret"
  eq "custom/ unchanged again" "$before" "$(custom_state)"
  [ ! -e "$R/tmp/work/$W" ]; check "still nothing cloned" $?
}

test_open_request_refuses_when_the_scan_cannot_run() {
  fixture
  mkdir -p "$R/custom/requests"
  printf '# U\n' >"$R/custom/requests/u.md"
  local before
  before="$(custom_state)"
  export DOCKER_INFO_EXIT=1
  run open "$W" app --request u.md
  unset DOCKER_INFO_EXIT
  rc_is 1
  has "the secret scan of custom/requests/u.md did not run (Docker did not respond)"
  has "commit it by path in custom/"
  [ ! -e "$VALIDATE_LOG" ]; check "validate not called without Docker" $?
  [ ! -e "$R/tmp/work/$W" ]; check "nothing cloned" $?
  eq "custom/ unchanged" "$before" "$(custom_state)"
  # validate.sh failing with no finding (a tool error) is no pass either.
  printf '#!/usr/bin/env bash\necho "FAIL secrets: image pull failed"\nexit 1\n' >"$BASE/validate.sh"
  run open "$W" app --request u.md
  rc_is 1
  has "the secret scan of custom/requests/u.md did not run"
  eq "custom/ still unchanged" "$before" "$(custom_state)"
  # A request named like a local secret file, which the scan skips, is never committed by open.
  printf '{}\n' >"$R/custom/requests/local.settings.json"
  run open "$W" app --request local.settings.json
  rc_is 1
  has "local secret file"
  # Ignored by custom/.gitignore: refused before any scan.
  printf 'requests/ignored.md\n' >"$R/custom/.gitignore"
  printf '# I\n' >"$R/custom/requests/ignored.md"
  run open "$W" app --request ignored.md
  rc_is 1
  has "custom/requests/ignored.md is ignored by git in custom/"
  [ ! -e "$R/tmp/work/$W" ]; check "still nothing cloned" $?
}

test_open_request_refuses_before_anything_is_created() {
  fixture
  mkdir -p "$R/custom/requests"
  request_in_custom requests/c.md "# C"
  run open "$W" app --request nope.md
  rc_is 1
  has "request not found: custom/requests/nope.md nor custom/requests/doing/nope.md"
  run open "$W" app --request tmp/request.md
  rc_is 2
  run open "$W" app --request custom/requests/qa/app/c.md
  rc_is 2
  run open "$W" app --request
  rc_is 2
  request_in_custom requests/doing/c.md "# C in progress"
  run open "$W" app --request c.md
  rc_is 1
  has "custom/requests/doing/c.md exists: that request is in progress"
  [ ! -e "$R/tmp/work/$W" ]; check "nothing created" $?
  eq "no branch on the remote" none "$(remote_sha feat/sample-change)"
  [ -f "$R/custom/requests/c.md" ]; check "the request did not move" $?
  # Another work records the request in doing/; a work that records another request.
  run open "$W" app --request custom/requests/doing/c.md
  rc_is 0
  run open 2026-11-17-other app --branch feat/other --request custom/requests/doing/c.md
  rc_is 1
  has "is in progress in tmp/work/$W: resume it there, or start over"
  [ ! -e "$R/tmp/work/2026-11-17-other" ]; check "no other work created" $?
  request_in_custom requests/d.md "# D"
  run open "$W" app --request d.md
  rc_is 1
  has "tmp/work/$W records another request (custom/requests/doing/c.md)"
  [ -f "$R/custom/requests/d.md" ]; check "d did not move" $?
}

test_close_discard_puts_the_request_back_in_pending() {
  fixture
  request_in_custom requests/r.md "# R"
  run open "$W" app --request r.md
  local c before
  c="$(clone)"
  commit_in "$c" a.txt half-done
  # A pending file of the same name, or a change not committed in doing/: refused, nothing deleted.
  request_in_custom requests/r.md "# another R"
  run close "$W" --discard
  rc_is 1
  has "custom/requests/r.md exists"
  [ -d "$c" ]; check "folder kept" $?
  git -C "$R/custom" rm -q -- requests/r.md
  git -C "$R/custom" commit -q -m "drop the other r" -- requests/r.md
  printf 'not committed\n' >>"$R/custom/requests/doing/r.md"
  run close "$W" --discard
  rc_is 1
  has "has changes not committed"
  [ -d "$c" ]; check "folder kept again" $?
  git -C "$R/custom" checkout -q -- requests/doing/r.md
  before="$(custom_commits)"
  run close "$W" --discard
  rc_is 0
  has "closed: tmp/work/$W"
  has "attention: custom/ has no remote: the commit stays in custom/"
  has "request: custom/requests/r.md (pending again)"
  [ -f "$R/custom/requests/r.md" ] && [ ! -e "$R/custom/requests/doing/r.md" ]; check "back in pending" $?
  eq "one commit in custom/" "$((before + 1))" "$(custom_commits)"
  eq "put back title" "chore(requests): put back r.md" "$(custom_title)"
  ! git -C "$R/custom" log -1 --format=%B | grep -q '\[#automatic-agent-commit\]'; check "no agent trailer outside Claude Code" $?
  eq "custom/ clean" "" "$(git -C "$R/custom" status --porcelain)"
  [ "$(remote_sha feat/sample-change)" != none ]; check "discard keeps the remote branch" $?
  run close 2026-11-17-none --start-over
  rc_is 2
  run close "$W" --bogus
  rc_is 2
}

test_status_names_the_request_and_flags_stale_doing_files() {
  fixture
  request_in_custom requests/doing/old.md "# old"
  request_in_custom requests/r.md "# R"
  run status
  has "no clone under tmp/work/"
  has "stale: custom/requests/doing/old.md (no open work records it: /request old.md resumes it or starts over)"
  run open "$W" app --request r.md
  run status
  has "tmp/work/$W  request=custom/requests/doing/r.md"
  has "stale: custom/requests/doing/old.md"
  hasnt "stale: custom/requests/doing/r.md"
  run status "$W"
  has "tmp/work/$W  request=custom/requests/doing/r.md"
  hasnt "stale:"
  # The file left doing/ while the work stays open: named missing.
  git -C "$R/custom" mv requests/doing/r.md requests/r2.md
  run status
  has "tmp/work/$W  request=custom/requests/doing/r.md (missing)"
  # A plain close after the work merged: the work goes; a file still in doing/ becomes stale.
  git -C "$R/custom" mv requests/r2.md requests/doing/r.md
  git -C "$R/projects/app" fetch -q origin feat/sample-change
  git -C "$R/projects/app" merge -q --ff-only FETCH_HEAD
  run close "$W"
  rc_is 0
  has "attention: custom/requests/doing/r.md is still in doing/"
  run status
  has "stale: custom/requests/doing/r.md"
}

test_start_over_deletes_the_work_and_its_remote_branch() {
  fixture
  request_in_custom requests/r.md "# R"
  run open "$W" app --request r.md
  local c dev before w2="2026-11-17-sample-change"
  c="$(clone)"
  dev="$(remote_sha developer)"
  commit_in "$c" a.txt half-done
  printf -- '---\n\n## Stopped — 2026-11-16\n\nwave 1 done\n' >>"$R/custom/requests/doing/r.md"
  git -C "$R/custom" commit -q -m stopped -- requests/doing/r.md
  # Someone else pushed to the branch: the lease keeps it, nothing deleted.
  git clone -q -b feat/sample-change "$BASE/remote.$CURRENT.git" "$BASE/other.$CURRENT"
  git -C "$BASE/other.$CURRENT" commit -q --allow-empty -m "from elsewhere"
  git -C "$BASE/other.$CURRENT" push -q origin feat/sample-change
  run close "$W" --discard --start-over
  rc_is 1
  has "could not be deleted on the remote"
  [ -d "$c" ]; check "folder kept" $?
  eq "branch kept" "$(git -C "$BASE/other.$CURRENT" rev-parse HEAD)" "$(remote_sha feat/sample-change)"
  git -C "$c" pull -q --no-rebase --no-edit origin feat/sample-change
  before="$(custom_commits)"
  run close "$W" --discard --start-over
  rc_is 0
  has "deleted on the remote: feat/sample-change (app)"
  has "closed: tmp/work/$W"
  has "request: custom/requests/doing/r.md stays in doing/"
  [ ! -e "$R/tmp/work/$W" ]; check "no old work folder" $?
  eq "no remote branch" none "$(remote_sha feat/sample-change)"
  eq "developer untouched" "$dev" "$(remote_sha developer)"
  eq "still in doing/" "Discarded on $(date +%Y-%m-%d): started over." "$(tail -n 1 "$R/custom/requests/doing/r.md")"
  eq "one commit in custom/" "$((before + 1))" "$(custom_commits)"
  eq "start over title" "chore(requests): start over r.md" "$(custom_title)"
  eq "custom/ clean" "" "$(git -C "$R/custom" status --porcelain)"
  # The new clone: same branch name, from the base, no start commit.
  run open "$w2" app --branch feat/sample-change --request r.md
  rc_is 0
  has "pushed: feat/sample-change"
  eq "new clone from the base" "$(git -C "$R/projects/app" rev-parse developer)" "$(git -C "$R/tmp/work/$w2/app" rev-parse HEAD)"
  eq "no new commit in custom/" "$((before + 1))" "$(custom_commits)"
  eq "the new work records it" "custom/requests/doing/r.md" "$(cat "$R/tmp/work/$w2/.request")"
  # A ## Stopped section already marked: no second line, no commit.
  run close "$w2" --discard --start-over
  rc_is 0
  eq "no second Discarded line" 1 "$(grep -c '^Discarded on' "$R/custom/requests/doing/r.md")"
  eq "no commit for an unchanged file" "$((before + 1))" "$(custom_commits)"
}

test_resume_opens_the_remote_branch_when_the_folder_is_gone() {
  fixture
  request_in_custom requests/r.md "# R"
  run open "$W" app --request r.md
  local c sha before
  c="$(clone)"
  commit_in "$c" a.txt wave-one
  sha="$(git -C "$c" rev-parse HEAD)"
  rm -rf "${R:?}/tmp/work/$W"
  before="$(custom_commits)"
  run status
  has "stale: custom/requests/doing/r.md"
  run open "$W" app --request r.md
  rc_is 1
  has "already exists on the remote of app: choose another --branch (or --resume to go on with it)"
  run open "$W" app --request r.md --resume
  rc_is 0
  has "resumed: feat/sample-change from the remote"
  eq "on the remote branch" "$sha" "$(git -C "$c" rev-parse HEAD)"
  eq "no commit in custom/" "$before" "$(custom_commits)"
  commit_in "$c" b.txt wave-two
  has "aiwp: pushed feat/sample-change"
  eq "the next commit is pushed" "$(git -C "$c" rev-parse HEAD)" "$(remote_sha feat/sample-change)"
  run status "$W"
  has "not-pushed=0"
  run open 2026-11-17-fresh app --branch feat/fresh --resume
  rc_is 0
  has "attention: feat/fresh is not on the remote of app: it starts from developer"
}

test_usage() {
  fixture
  run --help
  rc_is 0
  has "Usage: scripts/aiwp-cmds.sh"
  has "open <work> <repo>... [--branch <type>/<slug>] [--from-main] [--request <file>] [--resume]"
  has "close <work> [--discard [--start-over]]"
  has "gate, release, hotfix, hotfix-tag, hotfix-down, apply"
  has "up <work>/<clone> [-- <docker compose options>...]"
  has "down <work>/<clone>"
  has "deploy <repo> [developer|main] [-- <docker compose options>...]"
  has "rollback <repo> [-- <docker compose options>...]"
  has "^agent_[0-9]{4}-[a-z0-9][a-z0-9-]*$"
  run
  rc_is 2
  run nope
  rc_is 2
}

only=""
if [ "${1:-}" = "--only" ]; then
  [ $# -ge 2 ] || { echo "error: --only needs a test name" >&2; exit 2; }
  only="$2"
fi
tests="$(declare -F | awk '{print $3}' | grep '^test_')"
[ -z "$only" ] || tests="$only"
for t in $tests; do
  CURRENT="$t"
  "$t"
  COUNT=$((COUNT + 1))
done
if [ "$FAILED" -eq 0 ]; then echo "ok: $COUNT tests"; else echo "failed: $FAILED checks"; exit 1; fi
