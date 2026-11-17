#!/usr/bin/env bash
# Tests of scripts/aiwp-cmds.sh in a throwaway workspace: a project with a bare remote, a custom/ repo with none, and
# stubs for the secret scan and for docker. The real workspace is never touched.
# Run: bash scripts/tests/aiwp-cmds/test-aiwp-cmds.sh [--only <test_name>]
# check takes the status of the test right before it on purpose: SC2319 does not apply.
# shellcheck disable=SC2319
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(cd "$HERE/../.." && pwd)/aiwp-cmds.sh"
BASE="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$BASE"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
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

# Fake docker on PATH: records every call; answers ps, inspect, image ls, image inspect and compose config.
docker_stub() {
  mkdir -p "$BASE/bin"
  cat >"$BASE/bin/docker" <<'STUB'
#!/usr/bin/env bash
echo "docker $*" >>"$DOCKER_LOG"
case "$*" in
  compose*" ps -aq"*) [ -n "${STACK_DOWN:-}" ] || echo c1 ;;
  "inspect -f "*) echo "app-web sha256:aaa" ;;
  "image ls "*) printf 'rollback-20260101-000001\nrollback-20260102-000001\nrollback-20260103-000001\nrollback-20260104-000001\npublished-20260105-000001-abc1234\nlatest\n' ;;
  compose*" config --images"*) echo app-web ;;
  "image inspect app-web:rollback-latest") [ -z "${NO_ROLLBACK:-}" ]; exit ;;
esac
exit 0
STUB
  chmod +x "$BASE/bin/docker"
  export DOCKER_LOG="$BASE/docker.$CURRENT.log"
  : >"$DOCKER_LOG"
}

test_up_tags_the_last_publication_first() {
  fixture
  docker_stub
  run open "$W" app
  OUT="$(cd "$R" && PATH="$BASE/bin:$PATH" bash scripts/aiwp-cmds.sh up "$W/app" -- -f compose.yaml 2>&1)"
  RC=$?
  rc_is 0
  local log first_up rollback published
  log="$(cat "$DOCKER_LOG")"
  rollback="$(grep -n 'tag sha256:aaa app-web:rollback-latest' "$DOCKER_LOG" | head -1 | cut -d: -f1)"
  first_up="$(grep -n 'compose -f compose.yaml up -d --build' "$DOCKER_LOG" | head -1 | cut -d: -f1)"
  published="$(grep -n 'tag sha256:aaa app-web:published-' "$DOCKER_LOG" | head -1 | cut -d: -f1)"
  [ -n "$rollback" ] && [ -n "$first_up" ] && [ "$rollback" -lt "$first_up" ]; check "rollback tag before the build" $?
  [ -n "$published" ] && [ "$published" -gt "$first_up" ]; check "published tag after the build" $?
  case "$log" in *"image rm app-web:rollback-20260101-000001"*) check "keeps the newest 3" 0 ;; *) check "keeps the newest 3" 1 ;; esac
  case "$log" in *"rm app-web:rollback-20260104"*) check "newest tag removed" 1 ;; *) check "newest tag kept" 0 ;; esac
  case "$log" in *volume*|*"down -v"*) check "no volume touched" 1 ;; *) check "no volume touched" 0 ;; esac
  OUT="$(cd "$R" && PATH="$BASE/bin:$PATH" bash scripts/aiwp-cmds.sh up app 2>&1)"
  RC=$?
  rc_is 0
  has "published: projects/app"
}

test_rollback_points_back_and_never_builds() {
  fixture
  docker_stub
  run open "$W" app
  OUT="$(cd "$R" && PATH="$BASE/bin:$PATH" bash scripts/aiwp-cmds.sh rollback "$W/app" 2>&1)"
  RC=$?
  rc_is 0
  has "rolled back: app-web <- app-web:rollback-latest"
  grep -q 'compose up -d --no-build' "$DOCKER_LOG"; check "up without build" $?
  ! grep -q 'build' <(grep -v -- '--no-build' "$DOCKER_LOG"); check "no build" $?
  OUT="$(cd "$R" && NO_ROLLBACK=1 PATH="$BASE/bin:$PATH" bash scripts/aiwp-cmds.sh rollback "$W/app" 2>&1)"
  RC=$?
  rc_is 1
  has "no rollback-latest tag"
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

test_up_with_the_stack_down_uses_the_last_publication() {
  fixture
  docker_stub
  run open "$W" app
  OUT="$(cd "$R" && STACK_DOWN=1 PATH="$BASE/bin:$PATH" bash scripts/aiwp-cmds.sh up "$W/app" 2>&1)"
  RC=$?
  rc_is 0
  has "rollback: app-web:rollback-latest (published-20260105-000001-abc1234)"
  grep -q 'tag app-web:published-20260105-000001-abc1234 app-web:rollback-latest' "$DOCKER_LOG"; check "checkpoint from the published tag" $?
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

test_usage() {
  fixture
  run --help
  rc_is 0
  has "Usage: scripts/aiwp-cmds.sh"
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
