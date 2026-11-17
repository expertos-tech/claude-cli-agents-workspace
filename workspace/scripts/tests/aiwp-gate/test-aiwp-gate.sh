#!/usr/bin/env bash
# Tests of scripts/aiwp-gate.sh (gate, release, apply) in a throwaway workspace: a project with a bare remote, a clone
# made by aiwp-cmds.sh open, and stubs for validate.sh, the secret scan and terraform. The real workspace is never
# touched.
# Run: bash scripts/tests/aiwp-gate/test-aiwp-gate.sh [--only <test_name>]
# check takes the status of the test right before it on purpose: SC2319 does not apply.
# shellcheck disable=SC2319
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../.." && pwd)"
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
REMOTE=""
W="2026-11-16-sample-change"

check() { # description, status (0 = ok)
  if [ "$2" -ne 0 ]; then
    FAILED=$((FAILED + 1))
    echo "FAIL $CURRENT: $1 (rc=$RC out=[$OUT])"
  fi
}
has() { case "$OUT" in *"$1"*) check "has [$1]" 0 ;; *) check "missing [$1]" 1 ;; esac; }
hasnt_out() { case "$OUT" in *"$1"*) check "unexpected [$1]" 1 ;; *) check "absent [$1]" 0 ;; esac; }
rc_is() { [ "$RC" -eq "$1" ]; check "rc $1" $?; }
eq() { [ "$2" = "$3" ]; check "$1: expected [$2] got [$3]" $?; }

# Fresh workspace with the scripts, a stub validate.sh, projects/app on developer with a bare remote, and a clone on
# OPEN_BRANCH (default feat/sample-change). The stub validate.sh fails, with VALIDATE_SECRETS set, when a run that
# includes the secrets check (every check, or --only with secrets) finds LEAKED anywhere in the target: the whole-tree
# scan of the ordinary gate.
fixture() {
  R="$BASE/ws.$CURRENT"
  REMOTE="$BASE/remote.$CURRENT.git"
  rm -rf "$R" "$REMOTE"
  mkdir -p "$R/scripts/lib" "$R/projects" "$R/tmp" "$R/migrations"
  cp "$SCRIPTS/aiwp-cmds.sh" "$SCRIPTS/aiwp-gate.sh" "$SCRIPTS/aiwp-project-state.sh" "$R/scripts/"
  cp "$SCRIPTS/lib/projects.sh" "$R/scripts/lib/"
  printf '0.1.0\n' >"$R/VERSION"
  printf '# 0.1.0\n' >"$R/migrations/0.1.0.md"
  cat >"$R/scripts/validate.sh" <<STUB
#!/usr/bin/env bash
echo "validate \$*" >>"$R/validate.log"
target=""
scan=1
while [ \$# -gt 0 ]; do
  case "\$1" in
    --path) target="\$2"; shift ;;
    --only) case ",\$2," in *,secrets,*) ;; *) scan=0 ;; esac; shift ;;
    --files) shift ;;
  esac
  shift
done
if [ -n "\${VALIDATE_SECRETS:-}" ] && [ "\$scan" = 1 ] && grep -rq --exclude-dir=.git LEAKED "$R/\$target"; then
  echo "FAIL secrets"
  exit 1
fi
exit "\${VALIDATE_RC:-0}"
STUB
  git init -q --bare -b main "$REMOTE"
  git init -q -b main "$R/projects/app"
  mkdir -p "$R/projects/app/tests" "$R/projects/app/infra"
  printf 'v1\n' >"$R/projects/app/app.txt"
  printf 'it("works", () => { expect(1).toBe(1) })\n' >"$R/projects/app/tests/a.test.js"
  printf 'terraform {}\n' >"$R/projects/app/infra/main.tf"
  git -C "$R/projects/app" add -A
  git -C "$R/projects/app" commit -q -m base
  git -C "$R/projects/app" branch developer
  git -C "$R/projects/app" switch -q developer
  git -C "$R/projects/app" remote add origin "$REMOTE"
  git -C "$R/projects/app" push -q origin main developer
  cat >"$BASE/scan.sh" <<'STUB'
#!/usr/bin/env bash
[ -z "${SCAN_EAT_STDIN:-}" ] || cat >/dev/null
# shellcheck disable=SC2086  # the range is a list of revisions
if git -C "$1" log -p -m $2 | grep -q '^+.*LEAKED'; then echo "finding in $2"; exit 1; fi
exit 0
STUB
  chmod +x "$BASE/scan.sh"
  export AIWP_SECRETS_CMD="$BASE/scan.sh"
  unset VALIDATE_RC VALIDATE_SECRETS
  (cd "$R" && bash scripts/aiwp-cmds.sh open "$W" app --branch "${OPEN_BRANCH:-feat/sample-change}" >/dev/null 2>&1)
}

gate() {
  OUT="$(cd "$R" && bash scripts/aiwp-gate.sh "$@" 2>&1)"
  RC=$?
}
c() { echo "$R/tmp/work/$W/app"; }
commit_in() { # file, content
  mkdir -p "$(dirname "$(c)/$1")"
  printf '%s\n' "$2" >"$(c)/$1"
  git -C "$(c)" add -A
  git -C "$(c)" commit -q -m "change $1" >/dev/null 2>&1
}
remote_sha() { git -C "$REMOTE" rev-parse -q --verify "refs/heads/$1" 2>/dev/null || echo none; }
# A second clone of the remote that moves developer, as another session's merge would.
move_remote_developer() {
  rm -rf "$BASE/other"
  git clone -q -b developer "$REMOTE" "$BASE/other"
  printf '%s\n' "$2" >"$BASE/other/$1"
  git -C "$BASE/other" add -A
  git -C "$BASE/other" commit -q -m "other $1"
  git -C "$BASE/other" push -q origin developer
}

test_gate_happy_path_then_merge() {
  fixture
  commit_in feature.txt one
  gate gate "$W/app" --test "test -f feature.txt"
  rc_is 0
  has "gate: checks passed for"
  local sha
  sha="$(git -C "$(c)" rev-parse HEAD)"
  [ -f "$R/tmp/work/$W/gate-app.md" ]; check "audit written" $?
  grep -q "validate --path tmp/work/$W/app" "$R/validate.log"; check "validate on the clone" $?
  gate gate --merge "$W/app" "$sha"
  rc_is 0
  has "merged: $sha into developer"
  eq "local developer" "$sha" "$(git -C "$R/projects/app" rev-parse developer)"
  eq "remote developer" "$sha" "$(remote_sha developer)"
  eq "work branch deleted from the remote" none "$(remote_sha feat/sample-change)"
  eq "main untouched" "$(git -C "$R/projects/app" rev-parse main)" "$(remote_sha main)"
  OUT="$(cd "$R" && bash scripts/aiwp-cmds.sh close "$W" 2>&1)"
  RC=$?
  rc_is 0
  has "closed: tmp/work/$W"
}

test_gate_needs_tests_unless_docs_only() {
  fixture
  commit_in feature.txt one
  gate gate "$W/app"
  rc_is 2
  has "--test"
  gate gate "$W/app" --docs-only
  rc_is 2
  has "changes more than documentation"
  fixture
  commit_in docs/guide.md "# guide"
  gate gate "$W/app" --docs-only
  rc_is 0
  has "SKIP tests: documentation only"
}

test_gate_stops_on_failing_tests_or_validate() {
  fixture
  commit_in feature.txt one
  gate gate "$W/app" --test "false"
  rc_is 1
  has "the tests failed"
  [ ! -f "$R/tmp/work/$W/.gate-app" ]; check "no record" $?
  export VALIDATE_RC=1
  gate gate "$W/app" --test true
  rc_is 1
  has "validate failed"
  unset VALIDATE_RC
}

test_gate_brings_the_updated_base_in() {
  fixture
  commit_in feature.txt one
  move_remote_developer other.txt two
  gate gate "$W/app" --test "test -f other.txt && test -f feature.txt"
  rc_is 0
  local sha
  sha="$(git -C "$(c)" rev-parse HEAD)"
  eq "merge commit pushed" "$sha" "$(remote_sha feat/sample-change)"
  gate gate --merge "$W/app" "$sha"
  rc_is 0
  git -C "$R/projects/app" merge-base --is-ancestor "$(git -C "$BASE/other" rev-parse HEAD)" developer; check "other work kept" $?
}

test_gate_merge_refuses_what_phase_one_did_not_check() {
  fixture
  commit_in feature.txt one
  gate gate --merge "$W/app" HEAD
  rc_is 1
  has "phase 1 did not pass"
  gate gate "$W/app" --test true
  local sha
  sha="$(git -C "$(c)" rev-parse HEAD)"
  gate gate --merge "$W/app" "$(git -C "$(c)" rev-parse HEAD~1)"
  rc_is 1
  has "is not the sha phase 1 checked"
  move_remote_developer late.txt late
  gate gate --merge "$W/app" "$sha"
  rc_is 1
  has "developer moved after phase 1"
  eq "developer not merged" "$(git -C "$BASE/other" rev-parse HEAD)" "$(remote_sha developer)"
  gate gate "$W/app" --test true
  commit_in after.txt after
  gate gate --merge "$W/app" "$sha"
  rc_is 1
}

test_gate_refuses_a_dirty_or_moved_source_and_conflicts() {
  fixture
  commit_in feature.txt one
  printf 'x\n' >"$R/projects/app/stray.txt"
  gate gate "$W/app" --test true
  rc_is 1
  has "has changes in its checkout"
  rm "$R/projects/app/stray.txt"
  git -C "$R/projects/app" switch -q main
  gate gate "$W/app" --test true
  rc_is 1
  has "is on main, not developer"
  git -C "$R/projects/app" switch -q developer
  commit_in app.txt mine
  move_remote_developer app.txt theirs
  gate gate "$W/app" --test true
  rc_is 1
  has "conflict merging developer"
  [ -z "$(git -C "$(c)" status --porcelain)" ]; check "merge aborted, clone clean" $?
}

test_gate_refuses_secrets_that_never_reached_the_remote() {
  fixture
  commit_in leak.txt "token LEAKED"
  gate gate "$W/app" --test true
  rc_is 1
  has "the branch is not on the remote"
}

test_audit_lists_what_leaves_the_base() {
  fixture
  git -C "$(c)" rm -q tests/a.test.js
  git -C "$(c)" commit -q -m "drop test" >/dev/null 2>&1
  commit_in tests/b.test.js 'it.skip("later", () => {})'
  commit_in db/migrations/002.sql "DROP TABLE users;"
  commit_in compose.yaml "services: {}"
  commit_in package.json '{"dependencies": {}}'
  printf 'API_KEY=sample-secret-value\nHOST: example.com\nbare-token-line\n' >"$R/projects/app/.env.example"
  git -C "$R/projects/app" add -A
  git -C "$R/projects/app" commit -q -m "sample env with values"
  git -C "$R/projects/app" push -q origin developer
  git -C "$(c)" fetch -q origin developer
  git -C "$(c)" merge -q --no-edit FETCH_HEAD >/dev/null 2>&1
  printf 'API_KEY=\n' >"$(c)/.env.example"
  git -C "$(c)" add -A
  git -C "$(c)" commit -q -m "no values" >/dev/null 2>&1
  gate gate "$W/app" --test true
  rc_is 0
  OUT="$(cat "$R/tmp/work/$W/gate-app.md")"
  has ".env.example: removed the line of API_KEY (its value is never copied here)"
  has ".env.example: removed the line of HOST"
  has ".env.example: removed a line with no key (never copied here)"
  hasnt_out "bare-token-line"
  hasnt_out "sample-secret-value"
  hasnt_out "example.com"
  has "- tests/a.test.js"
  has "deleted test file: tests/a.test.js"
  has "tests/b.test.js: 1 test(s) disabled"
  has "db/migrations/002.sql: DROP TABLE users;"
  has "changed migration: db/migrations/002.sql"
  has "A	compose.yaml"
  has "package.json"
}

test_release_moves_main_to_developer() {
  fixture
  commit_in feature.txt one
  gate gate "$W/app" --test true
  gate gate --merge "$W/app" "$(git -C "$(c)" rev-parse HEAD)"
  printf 'x\n' >"$R/projects/app/stray.txt"
  gate release app
  rc_is 1
  rm "$R/projects/app/stray.txt"
  gate release app
  rc_is 0
  eq "remote main" "$(remote_sha developer)" "$(remote_sha main)"
  eq "back on developer" developer "$(git -C "$R/projects/app" symbolic-ref --short HEAD)"
  rm -rf "$BASE/other"
  git clone -q -b main "$REMOTE" "$BASE/other"
  printf 'hotfix\n' >"$BASE/other/hot.txt"
  git -C "$BASE/other" add -A
  git -C "$BASE/other" commit -q -m hotfix
  git -C "$BASE/other" push -q origin main
  gate release app
  rc_is 1
  has "a hotfix on main of projects/app is not merged into developer yet"
  has "hotfix-down app"
  eq "still on developer" developer "$(git -C "$R/projects/app" symbolic-ref --short HEAD)"
}

# terraform stub: logs its arguments; "plan -out=<f>" writes f; AIWP_TF_FAIL makes apply fail.
tf_stub() {
  cat >"$BASE/tf.sh" <<'STUB'
#!/usr/bin/env bash
echo "terraform $* @ $(git rev-parse HEAD)" >>"$TF_LOG"
[ "$1" = init ] && echo "lock" >>.terraform.lock.hcl
for a in "$@"; do case "$a" in -out=*) echo plan >"${a#-out=}" ;; esac; done
[ "$1" = apply ] && [ -n "${AIWP_TF_FAIL:-}" ] && exit 1
exit 0
STUB
  chmod +x "$BASE/tf.sh"
  export AIWP_TERRAFORM="$BASE/tf.sh" TF_LOG="$BASE/tf.$CURRENT.log"
  : >"$TF_LOG"
}

test_apply_plans_from_main_and_applies_only_the_latest_plan() {
  fixture
  tf_stub
  local main_sha plan first
  main_sha="$(git -C "$R/projects/app" rev-parse main)"
  gate apply app infra
  rc_is 0
  has "next, only on the human's request"
  grep -q "terraform plan -input=false -out=.* @ $main_sha" "$TF_LOG"; check "plan ran on the main commit" $?
  ! grep -q '^terraform apply' "$TF_LOG"; check "phase 1 applies nothing" $?
  eq "projects/app never left developer" developer "$(git -C "$R/projects/app" symbolic-ref --short HEAD)"
  eq "projects/app clean, lock file included" "" "$(git -C "$R/projects/app" status --porcelain)"
  eq "no worktree left" 1 "$(git -C "$R/projects/app" worktree list | wc -l | tr -d ' ')"
  first="$(printf '%s\n' "$OUT" | sed -n 's/^plan: \([^ ]*\) .*/\1/p')"
  [ -n "$first" ] && [ -f "$R/$first" ]; check "plan file kept" $?
  sleep 1
  gate apply app infra
  plan="$(printf '%s\n' "$OUT" | sed -n 's/^plan: \([^ ]*\) .*/\1/p')"
  gate apply app infra --apply "$R/$first"
  rc_is 1
  has "not the latest plan shown"
  printf 'tampered\n' >>"$R/$plan"
  gate apply app infra --apply "$R/$plan"
  rc_is 1
  has "the plan file changed since it was shown"
  gate apply app infra
  plan="$(printf '%s\n' "$OUT" | sed -n 's/^plan: \([^ ]*\) .*/\1/p')"
  export AIWP_TF_FAIL=1
  gate apply app infra --apply "$R/$plan"
  rc_is 1
  eq "still on developer after a failed apply" developer "$(git -C "$R/projects/app" symbolic-ref --short HEAD)"
  unset AIWP_TF_FAIL
  gate apply app infra --apply "$R/$plan"
  rc_is 0
  grep -q "terraform apply -input=false $R/tmp/work/_apply/.applying-.*.tfplan @ $main_sha" "$TF_LOG"; check "applied a checked copy of the plan on the main commit" $?
  [ ! -f "$R/$plan" ]; check "plan consumed" $?
  eq "projects/app clean after apply" "" "$(git -C "$R/projects/app" status --porcelain)"
  gate apply app infra
  plan="$(printf '%s\n' "$OUT" | sed -n 's/^plan: \([^ ]*\) .*/\1/p')"
  rm -rf "$BASE/other"
  git clone -q -b main "$REMOTE" "$BASE/other"
  printf 'x\n' >"$BASE/other/new.txt"
  git -C "$BASE/other" add -A
  git -C "$BASE/other" commit -q -m newer
  git -C "$BASE/other" push -q origin main
  gate apply app infra --apply "$R/$plan"
  rc_is 1
  has "main changed since the plan"
  gate apply app ../escape
  rc_is 2
}

test_gate_checks_commits_already_on_the_remote() {
  fixture
  mkdir -p "$(c)/cfg"
  printf 'K=1\n' >"$(c)/cfg/.env"
  git -C "$(c)" add -f cfg/.env
  git -C "$(c)" commit -q --no-verify -m env >/dev/null 2>&1
  git -C "$(c)" push -q --no-verify origin HEAD:refs/heads/feat/sample-change 2>/dev/null
  gate gate "$W/app" --test true
  rc_is 1
  has "carry a local env file"
  [ ! -f "$R/tmp/work/$W/.gate-app" ]; check "no record" $?
}

test_gate_ignores_a_base_ref_the_session_moved() {
  fixture
  mkdir -p "$(c)/cfg"
  printf 'K=1\n' >"$(c)/cfg/.env"
  git -C "$(c)" add -f cfg/.env
  git -C "$(c)" commit -q --no-verify -m env >/dev/null 2>&1
  git -C "$(c)" push -q --no-verify origin HEAD:refs/heads/feat/sample-change 2>/dev/null
  gate gate "$W/app" --test "git update-ref refs/remotes/origin/developer HEAD"
  rc_is 1
  has "carry a local env file"
}

test_gate_refuses_a_tree_the_tests_rewrote() {
  fixture
  commit_in src/app.js broken
  gate gate "$W/app" --test "sed -i s/broken/fixed/ src/app.js && grep -q fixed src/app.js"
  rc_is 1
  has "changed tracked files of the clone"
  [ ! -f "$R/tmp/work/$W/.gate-app" ]; check "no record" $?
}

test_audit_sees_renames_that_take_tests_away() {
  fixture
  mkdir -p "$(c)/old"
  git -C "$(c)" mv tests/a.test.js old/a.test.js.bak
  git -C "$(c)" commit -q -m "move test away" >/dev/null 2>&1
  commit_in tests/c.test.js 'xit("later", () => {})'
  gate gate "$W/app" --test true
  rc_is 0
  OUT="$(cat "$R/tmp/work/$W/gate-app.md")"
  has "- tests/a.test.js"
  has "deleted test file: tests/a.test.js"
  has "tests/a.test.js: 1 test case(s) removed"
  has "tests/c.test.js: 1 test(s) disabled"
  fixture
  mkdir -p "$(c)/docs"
  git -C "$(c)" mv app.txt docs/app.md
  git -C "$(c)" commit -q -m "code into docs" >/dev/null 2>&1
  gate gate "$W/app" --docs-only
  rc_is 2
  has "changes more than documentation"
}

MARKER="<!-- AI-WORKSPACE-PROJECT 0.1.0 -->"

# A project whose base already holds an old token, normalized on feat/ai-workspace-migration.
norm_fixture() {
  fixture
  rm -rf "$R/tmp/work"
  mkdir -p "$R/projects/app/docs"
  printf 'token LEAKED-OLD\nport 80\n' >"$R/projects/app/docs/setup.md"
  git -C "$R/projects/app" add -A
  git -C "$R/projects/app" commit -q -m "setup notes with an old token"
  git -C "$R/projects/app" push -q origin developer
  (cd "$R" && bash scripts/aiwp-cmds.sh open "$W" app --branch "${1:-feat/ai-workspace-migration}" >/dev/null 2>&1)
}

# A bare remote hook that refuses any push to main, as a protected branch does.
protect_main() {
  # The $1 belongs to the hook: SC2016 does not apply.
  # shellcheck disable=SC2016
  printf '#!/bin/sh\n[ "$1" = refs/heads/main ] && { echo "main is protected" >&2; exit 1; }\nexit 0\n' >"$REMOTE/hooks/update"
  chmod +x "$REMOTE/hooks/update"
}

remote_tag() { git -C "$REMOTE" rev-parse -q --verify "refs/tags/$1" 2>/dev/null || echo none; }

test_gate_shows_the_project_state_without_blocking() {
  fixture
  commit_in feature.txt one
  gate gate "$W/app" --test true
  rc_is 0
  has "attention: projects/app has no AI-WORKSPACE-PROJECT marker"
  has "/normalize-projects app"
  OUT="$(cd "$R" && bash scripts/aiwp-cmds.sh open 2026-11-16-other app 2>&1)"
  has "attention: projects/app has no AI-WORKSPACE-PROJECT marker"
  has "path: tmp/work/2026-11-16-other/app"
}

test_normalization_gate_judges_only_what_the_branch_adds() {
  norm_fixture
  export VALIDATE_SECRETS=1
  commit_in README.md "$(printf '%s\n# app\n\n## How to test\n\n    true' "$MARKER")"
  printf 'token LEAKED-OLD\nport 8080\n' >"$(c)/docs/setup.md"
  git -C "$(c)" commit -q -am "touch the file with the old token" >/dev/null 2>&1
  gate gate "$W/app" --test true
  rc_is 0
  has "normalization: judged on what feat/ai-workspace-migration adds"
  has "the added lines only"
  hasnt_out "attention: projects/app has no AI-WORKSPACE-PROJECT marker"
  grep -q -- "--only shell,dockerfile,markdown,mermaid,python,typescript --files" "$R/validate.log"; check "lint checks on the changed files" $?
  ! grep -q "validate --path tmp/work/$W/app\$" "$R/validate.log"; check "no whole-tree validate" $?
  grep -q "## Normalization" "$R/tmp/work/$W/gate-app.md"; check "audit says normalization" $?
  # The same old token fails the ordinary gate, whose secrets check scans the whole tree.
  fixture
  printf 'token LEAKED-OLD\n' >"$R/projects/app/config.txt"
  git -C "$R/projects/app" add -A
  git -C "$R/projects/app" commit -q -m "config with an old token"
  git -C "$R/projects/app" push -q origin developer
  rm -rf "$R/tmp/work"
  (cd "$R" && bash scripts/aiwp-cmds.sh open "$W" app --branch feat/other-change >/dev/null 2>&1)
  export VALIDATE_SECRETS=1
  commit_in feature.txt one
  gate gate "$W/app" --test true
  rc_is 1
  has "validate failed"
  unset VALIDATE_SECRETS
}

test_normalization_gate_blocks_a_new_secret() {
  norm_fixture
  commit_in README.md "$(printf '%s\n# app' "$MARKER")"
  printf 'token LEAKED-OLD\nport 80\nnew LEAKED-NEW\n' >"$(c)/docs/setup.md"
  git -C "$(c)" commit -q -am "a new token" >/dev/null 2>&1
  gate gate "$W/app" --test true
  rc_is 1
  has "the branch is not on the remote"
  git -C "$(c)" push -q --no-verify origin HEAD:refs/heads/feat/ai-workspace-migration 2>/dev/null
  git -C "$(c)" config aiwp.pushed "$(git -C "$(c)" rev-parse HEAD)"
  gate gate "$W/app" --test true
  rc_is 1
  has "env files or secrets in the commits"
  [ ! -f "$R/tmp/work/$W/.gate-app" ]; check "no record" $?
  norm_fixture
  commit_in README.md "$(printf '%s\n# app' "$MARKER")"
  printf 'K=1\n' >"$(c)/.env"
  git -C "$(c)" add -f .env
  git -C "$(c)" commit -q --no-verify -m env >/dev/null 2>&1
  git -C "$(c)" push -q --no-verify origin HEAD:refs/heads/feat/ai-workspace-migration 2>/dev/null
  git -C "$(c)" config aiwp.pushed "$(git -C "$(c)" rev-parse HEAD)"
  gate gate "$W/app" --test true
  rc_is 1
  has "a normalization changes only documentation"
  has ".env"
  norm_fixture
  commit_in README.md "$(printf '%s\n# app' "$MARKER")"
  mkdir -p "$(c)/cfg"
  printf 'K=1\n' >"$(c)/cfg/.env"
  git -C "$(c)" add -f cfg/.env
  git -C "$(c)" rm -q app.txt
  git -C "$(c)" commit -q --no-verify -m "env in a commit whose files the scope allows" >/dev/null 2>&1
  git -C "$(c)" rm -q cfg/.env
  git -C "$(c)" commit -q --no-verify -m "untrack it again" >/dev/null 2>&1
  git -C "$(c)" push -q --no-verify origin HEAD:refs/heads/feat/ai-workspace-migration 2>/dev/null
  git -C "$(c)" config aiwp.pushed "$(git -C "$(c)" rev-parse HEAD)"
  gate gate "$W/app" --test true
  rc_is 1
  has "carry a local env file"
}

test_normalization_gate_needs_the_marker_and_changes_only_documentation() {
  norm_fixture
  commit_in README.md "# app without the marker"
  gate gate "$W/app" --test true
  rc_is 1
  has "a normalization ends with the marker on line 1 of README.md"
  commit_in README.md "$(printf '<!-- AI-WORKSPACE-PROJECT 0.0.9 -->\n# app')"
  gate gate "$W/app" --test true
  rc_is 1
  has "a normalization ends with the marker"
  commit_in README.md "$(printf '%s\n# app' "$MARKER")"
  commit_in package.json '{"dependencies": {}}'
  gate gate "$W/app" --test true
  rc_is 1
  has "a normalization changes only documentation"
  has "package.json"
  git -C "$(c)" rm -q package.json
  git -C "$(c)" commit -q -m "drop it" >/dev/null 2>&1
  commit_in app.txt "code changed"
  gate gate "$W/app" --test true
  rc_is 1
  has "app.txt"
  git -C "$(c)" rm -q app.txt infra/main.tf
  git -C "$(c)" commit -q -m "deletions are allowed" >/dev/null 2>&1
  commit_in deploy/README.md "# how it deploys"
  commit_in docs/diagram.png "png"
  commit_in .gitignore ".env"
  commit_in .env.example "API_KEY="
  gate gate "$W/app" --test true
  rc_is 0
}

test_normalization_gate_only_for_a_project_that_needs_it() {
  norm_fixture
  printf '%s\n# app\n' "$MARKER" >"$R/projects/app/README.md"
  git -C "$R/projects/app" add -A
  git -C "$R/projects/app" commit -q -m "already marked"
  git -C "$R/projects/app" push -q origin developer
  commit_in docs/more.md "more"
  commit_in README.md "$(printf '%s\n# app' "$MARKER")"
  gate gate "$W/app" --untested
  rc_is 1
  has "needs no normalization (state current)"
  [ ! -f "$R/tmp/work/$W/.gate-app" ]; check "no record" $?
  fixture
  rm -rf "$R/tmp/work"
  mkdir -p "$R/projects/app/workspace/scripts"
  printf '0.1.0\n' >"$R/projects/app/workspace/VERSION"
  printf 'x\n' >"$R/projects/app/workspace/scripts/aiwp-cmds.sh"
  git -C "$R/projects/app" add -A
  git -C "$R/projects/app" commit -q -m "the product layout"
  git -C "$R/projects/app" push -q origin developer
  (cd "$R" && bash scripts/aiwp-cmds.sh open "$W" app --branch feat/ai-workspace-migration >/dev/null 2>&1)
  commit_in README.md "$(printf '%s\n# app' "$MARKER")"
  gate gate "$W/app" --untested
  rc_is 1
  has "state workspace"
}

test_untested_is_only_for_a_normalization_and_one_test_option_at_a_time() {
  fixture
  commit_in feature.txt one
  gate gate "$W/app" --untested
  rc_is 2
  has "--untested is only for a normalization"
  gate gate "$W/app" --untested --test true
  rc_is 2
  has "use one of --test, --docs-only and --untested"
  norm_fixture
  commit_in README.md "$(printf '%s\n# app' "$MARKER")"
  gate gate "$W/app" --untested
  rc_is 0
  has "SKIP tests: the person chose to go on with the normalization untested"
  grep -q "Tests: not run; the person chose to go on untested" "$R/tmp/work/$W/gate-app.md"; check "audit records it" $?
}

test_normalization_end_to_end_on_a_local_bare_remote() {
  norm_fixture
  local dev0 main0 sha
  dev0="$(git -C "$R/projects/app" rev-parse developer)"
  main0="$(git -C "$R/projects/app" rev-parse main)"
  gate checkpoint app --date 2026-11-16
  rc_is 0
  has "pushed: ai-workspace-migration/2026-11-16/developer"
  has "pushed: ai-workspace-migration/2026-11-16/main"
  eq "developer tag on the remote, at the old head" "$dev0" "$(git -C "$REMOTE" rev-parse 'refs/tags/ai-workspace-migration/2026-11-16/developer^{commit}')"
  eq "main tag on the remote, at the old head" "$main0" "$(git -C "$REMOTE" rev-parse 'refs/tags/ai-workspace-migration/2026-11-16/main^{commit}')"
  eq "annotated" tag "$(git -C "$REMOTE" cat-file -t refs/tags/ai-workspace-migration/2026-11-16/main)"
  commit_in README.md "$(printf '%s\n# app' "$MARKER")"
  gate gate "$W/app" --test true
  rc_is 0
  sha="$(git -C "$(c)" rev-parse HEAD)"
  gate gate --merge "$W/app" "$sha"
  rc_is 0
  has "kept on the remote: feat/ai-workspace-migration"
  eq "developer on the remote" "$sha" "$(remote_sha developer)"
  eq "the branch stays on the remote" "$sha" "$(remote_sha feat/ai-workspace-migration)"
  gate release app
  rc_is 0
  eq "main on the remote" "$sha" "$(remote_sha main)"
  eq "local main" "$sha" "$(git -C "$R/projects/app" rev-parse main)"
  eq "the marker on main" "$MARKER" "$(git -C "$REMOTE" show main:README.md | head -n 1)"
  OUT="$(cd "$R" && bash scripts/aiwp-project-state.sh app)"
  has "projects/app: up to date (marker 0.1.0, workspace 0.1.0)"
}

test_a_later_normalization_branch_names_a_pending_migration() {
  norm_fixture feat/ai-workspace-migration-0-2-0
  commit_in README.md "$(printf '%s\n# app' "$MARKER")"
  gate gate "$W/app" --untested
  rc_is 1
  has "names no pending migration"
  # A project marked 0.1.0 in a workspace on 0.2.0 with the migration 0.2.0 pending.
  norm_fixture
  rm -rf "$R/tmp/work"
  printf '0.2.0\n' >"$R/VERSION"
  printf '# 0.2.0\n' >"$R/migrations/0.2.0.md"
  printf '%s\n# app\n' "$MARKER" >"$R/projects/app/README.md"
  git -C "$R/projects/app" add -A
  git -C "$R/projects/app" commit -q -m "marked 0.1.0"
  git -C "$R/projects/app" push -q origin developer
  (cd "$R" && bash scripts/aiwp-cmds.sh open "$W" app --branch feat/ai-workspace-migration-0-2-0 >/dev/null 2>&1)
  commit_in README.md "$(printf '<!-- AI-WORKSPACE-PROJECT 0.2.0 -->\n# app')"
  gate gate "$W/app" --untested
  rc_is 0
  has "normalization: judged on what feat/ai-workspace-migration-0-2-0 adds"
}

test_checkpoint_realigns_a_local_main_ahead_only_with_commits_the_remote_holds() {
  fixture
  local src="$R/projects/app" remote_main
  remote_main="$(remote_sha main)"
  # A local main one commit ahead of the remote's main, that commit already on the remote's developer: the state a
  # folder brought with --from can have (the work was merged into developer, main was never pushed).
  move_remote_developer merged.txt merged
  git -C "$src" fetch -q origin
  git -C "$src" branch -q -f --no-track main origin/developer
  gate checkpoint app --date 2026-11-16
  rc_is 0
  has "realigned: main of projects/app to origin/main"
  eq "main tag at the remote's main" "$remote_main" "$(git -C "$REMOTE" rev-parse 'refs/tags/ai-workspace-migration/2026-11-16/main^{commit}')"
  eq "local main back at the remote's main" "$remote_main" "$(git -C "$src" rev-parse main)"
  # A local main ahead with a commit no ref of the remote has: refused, named as ahead, nothing moved.
  git -C "$src" switch -q main
  printf 'local only\n' >"$src/local.txt"
  git -C "$src" add local.txt
  git -C "$src" commit -q -m "local only"
  local local_main
  local_main="$(git -C "$src" rev-parse main)"
  git -C "$src" switch -q developer
  gate checkpoint app --date 2026-11-17
  rc_is 1
  has "main of projects/app is 1 commit(s) ahead of the remote, with commits the remote does not have"
  eq "local main kept" "$local_main" "$(git -C "$src" rev-parse main)"
  eq "nothing pushed" none "$(remote_tag ai-workspace-migration/2026-11-17/main)"
  # Diverged: behind the remote too.
  git -C "$src" fetch -q origin
  rm -rf "$BASE/other-main"
  git clone -q -b main "$REMOTE" "$BASE/other-main"
  printf 'remote\n' >"$BASE/other-main/remote.txt"
  git -C "$BASE/other-main" add -A
  git -C "$BASE/other-main" commit -q -m remote
  git -C "$BASE/other-main" push -q origin main
  gate release app
  rc_is 1
  has "main of projects/app diverged from the remote (1 ahead, 1 behind)"
  eq "local main still kept" "$local_main" "$(git -C "$src" rev-parse main)"
}

test_sync_never_trusts_a_stale_remote_ref_nor_moves_a_checked_out_branch() {
  fixture
  local src="$R/projects/app" kept dev
  # A local main whose extra commit was only on a remote branch deleted since: the stale tracking ref does not count.
  rm -rf "$BASE/other-gone"
  git clone -q -b main "$REMOTE" "$BASE/other-gone"
  git -C "$BASE/other-gone" switch -q -c feature/gone
  printf 'gone\n' >"$BASE/other-gone/gone.txt"
  git -C "$BASE/other-gone" add -A
  git -C "$BASE/other-gone" commit -q -m gone
  git -C "$BASE/other-gone" push -q origin feature/gone
  git -C "$src" fetch -q origin
  git -C "$src" branch -q -f --no-track main origin/feature/gone
  kept="$(git -C "$src" rev-parse main)"
  git -C "$BASE/other-gone" push -q origin --delete feature/gone
  gate checkpoint app --date 2026-11-16
  rc_is 1
  has "main of projects/app is 1 commit(s) ahead of the remote, with commits the remote does not have"
  eq "main not moved" "$kept" "$(git -C "$src" rev-parse main)"
  ! git -C "$src" rev-parse -q --verify refs/remotes/origin/feature/gone >/dev/null; check "the stale tracking ref was pruned" $?
  # The checked-out developer ahead of the remote, even with a commit the remote holds elsewhere: refused, unmoved.
  git -C "$src" branch -q -f --no-track main origin/main
  # The remote's developer gains a commit that a second branch also holds; then developer goes back one commit.
  move_remote_developer side.txt side
  git -C "$src" fetch -q origin
  git -C "$src" push -q origin "refs/remotes/origin/developer:refs/heads/side"
  git -C "$src" fetch -q origin
  git -C "$src" merge -q --ff-only origin/developer
  dev="$(git -C "$src" rev-parse developer)"
  git -C "$BASE/other" reset -q --hard HEAD~1
  git -C "$BASE/other" push -q -f origin developer
  gate checkpoint app --date 2026-11-17
  rc_is 1
  has "developer of projects/app is checked out 1 commit(s) ahead of origin/developer"
  eq "developer not moved" "$dev" "$(git -C "$src" rev-parse developer)"
  eq "nothing pushed" none "$(remote_tag ai-workspace-migration/2026-11-17/developer)"
}

test_checkpoint_never_moves_a_tag_and_needs_a_clean_developer_with_a_remote() {
  fixture
  gate checkpoint app --date 2026-11-16
  rc_is 0
  local first
  first="$(remote_tag ai-workspace-migration/2026-11-16/developer)"
  gate checkpoint app --date 2026-11-16
  rc_is 0
  eq "same tag, pushed again" "$first" "$(remote_tag ai-workspace-migration/2026-11-16/developer)"
  move_remote_developer later.txt later
  gate checkpoint app --date 2026-11-16
  rc_is 1
  has "exists on another commit; a tag is never moved"
  eq "remote tag unchanged" "$first" "$(remote_tag ai-workspace-migration/2026-11-16/developer)"
  git -C "$R/projects/app" tag -d ai-workspace-migration/2026-11-16/developer >/dev/null
  gate checkpoint app --date 2026-11-16
  rc_is 1
  has "exists on the remote with another object"
  eq "remote tag still unchanged" "$first" "$(remote_tag ai-workspace-migration/2026-11-16/developer)"
  gate checkpoint app --date 16-11-2026
  rc_is 2
  gate checkpoint app --date 2026-11-17
  rc_is 0
  eq "the day's tag at the new head" "$(git -C "$BASE/other" rev-parse HEAD)" "$(git -C "$REMOTE" rev-parse 'refs/tags/ai-workspace-migration/2026-11-17/developer^{commit}')"
  git -C "$R/projects/app" switch -q main
  gate checkpoint app --date 2026-11-18
  rc_is 1
  has "is on main, not developer"
  eq "nothing pushed" none "$(remote_tag ai-workspace-migration/2026-11-18/main)"
  git -C "$R/projects/app" switch -q developer
  git -C "$R/projects/app" remote remove origin
  gate checkpoint app --date 2026-11-18
  rc_is 1
  has "has no remote"
}

test_release_refused_by_a_protected_main_leaves_main_and_opens_a_pull_request() {
  fixture
  commit_in feature.txt one
  gate gate "$W/app" --test true
  gate gate --merge "$W/app" "$(git -C "$(c)" rev-parse HEAD)"
  protect_main
  local main0
  main0="$(git -C "$R/projects/app" rev-parse main)"
  gate release app
  rc_is 1
  has "the remote refused the push of main"
  has "--pr-if-refused"
  eq "local main unchanged" "$main0" "$(git -C "$R/projects/app" rev-parse main)"
  eq "remote main unchanged" "$main0" "$(remote_sha main)"
  # The $* and $(...) belong to the stub: SC2016 does not apply.
  # shellcheck disable=SC2016
  printf '#!/usr/bin/env bash\necho "gh $* @ $(pwd -P)" >>"%s/gh.log"\necho https://example.com/acme/app/pull/1\n' "$BASE" >"$BASE/gh.sh"
  chmod +x "$BASE/gh.sh"
  : >"$BASE/gh.log"
  AIWP_GH="$BASE/gh.sh" gate release app --pr-if-refused
  rc_is 0
  has "pull request: https://example.com/acme/app/pull/1"
  grep -q "gh pr create --base main --head developer" "$BASE/gh.log"; check "gh opened the pull request" $?
  grep -q "@ $R/projects/app" "$BASE/gh.log"; check "from the project folder" $?
  eq "local main still unchanged" "$main0" "$(git -C "$R/projects/app" rev-parse main)"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$BASE/gh.sh"
  AIWP_GH="$BASE/gh.sh" gate release app --pr-if-refused
  rc_is 1
  has "the pull request could not be opened"
  gate release app --bogus
  rc_is 2
}

# A new commit on developer of projects/app, on the remote too, ready for a release.
developer_ahead() {
  printf '%s\n' "$1" >"$R/projects/app/$1.txt"
  git -C "$R/projects/app" add -A
  git -C "$R/projects/app" commit -q -m "add $1"
  git -C "$R/projects/app" push -q origin developer
}
local_tag() { git -C "$R/projects/app" rev-parse -q --verify "refs/tags/$1" 2>/dev/null || echo none; }
# A tag on the remote at a commit, pushed from a second clone, as another person would.
remote_tag_at() { # tag, commit
  rm -rf "$BASE/other"
  git clone -q "$REMOTE" "$BASE/other"
  git -C "$BASE/other" tag -a "$1" -m "$1" "$2"
  git -C "$BASE/other" push -q origin "refs/tags/$1"
}

test_release_tag_tags_the_released_main_and_pushes_only_that_tag() {
  fixture
  developer_ahead one
  local dev
  dev="$(git -C "$R/projects/app" rev-parse developer)"
  git -C "$R/projects/app" tag stray
  gate release app --tag v1.0.0
  rc_is 0
  has "released: main of projects/app"
  has "tagged: v1.0.0 at $(git -C "$R/projects/app" rev-parse --short "$dev")"
  has "pushed: v1.0.0"
  eq "remote main" "$dev" "$(remote_sha main)"
  eq "local main" "$dev" "$(git -C "$R/projects/app" rev-parse main)"
  eq "remote tag commit" "$dev" "$(git -C "$REMOTE" rev-parse -q --verify 'refs/tags/v1.0.0^{commit}')"
  eq "annotated" tag "$(git -C "$REMOTE" cat-file -t refs/tags/v1.0.0)"
  eq "same tag here and there" "$(local_tag v1.0.0)" "$(remote_tag v1.0.0)"
  eq "only that tag pushed" none "$(remote_tag stray)"
  local before
  before="$(remote_tag v1.0.0)"
  gate release app --tag v1.0.0 --pr-if-refused
  rc_is 0
  has "pushed: v1.0.0 (already on the remote)"
  eq "rerun keeps the tag" "$before" "$(remote_tag v1.0.0)"
  eq "rerun keeps the local tag" "$before" "$(local_tag v1.0.0)"
  # The tag only on the remote, on the released commit: the remote's tag object is taken, never a second one.
  git -C "$R/projects/app" tag -d v1.0.0 >/dev/null
  gate release app --tag v1.0.0
  rc_is 0
  eq "fetched the remote's tag" "$before" "$(local_tag v1.0.0)"
}

test_release_tag_on_another_commit_fails_before_main_moves() {
  fixture
  local main0
  main0="$(git -C "$R/projects/app" rev-parse main)"
  git -C "$R/projects/app" tag -a v1.0.0 -m v1.0.0 "$main0"
  remote_tag_at v2.0.0 "$main0"
  developer_ahead two
  gate release app --tag v1.0.0
  rc_is 1
  has "v1.0.0 exists on another commit; a tag is never moved"
  eq "local main unchanged" "$main0" "$(git -C "$R/projects/app" rev-parse main)"
  eq "remote main unchanged" "$main0" "$(remote_sha main)"
  eq "not pushed" none "$(remote_tag v1.0.0)"
  gate release app --tag v2.0.0
  rc_is 1
  has "v2.0.0 exists on the remote on another commit"
  eq "local main still unchanged" "$main0" "$(git -C "$R/projects/app" rev-parse main)"
  eq "remote main still unchanged" "$main0" "$(remote_sha main)"
  eq "no local v2.0.0" none "$(local_tag v2.0.0)"
  # The same name here and on the remote as two different tags on the released commit: refused, nothing moves.
  git -C "$R/projects/app" tag -a v3.0.0 -m mine developer
  remote_tag_at v3.0.0 "$(git -C "$R/projects/app" rev-parse developer)"
  gate release app --tag v3.0.0
  rc_is 1
  has "different tags"
  eq "remote main unchanged by v3.0.0" "$main0" "$(remote_sha main)"
  # A lightweight tag of the same name on the released commit: refused, never pushed as the release tag.
  git -C "$R/projects/app" tag v4.0.0 developer
  gate release app --tag v4.0.0
  rc_is 1
  has "lightweight tag"
  eq "remote main unchanged by v4.0.0" "$main0" "$(remote_sha main)"
  eq "v4.0.0 not pushed" none "$(remote_tag v4.0.0)"
}

test_release_tag_needs_a_valid_version_before_anything() {
  fixture
  developer_ahead three
  local main0
  main0="$(git -C "$R/projects/app" rev-parse main)"
  for bad in 1.0.0 v1.0 v1.0.0-rc1 "v1.0.0 " "" vX.Y.Z; do
    gate release app --tag "$bad"
    rc_is 2
  done
  has "--tag must be vX.Y.Z"
  gate release missing-repo --tag 1.0
  rc_is 2
  gate release app --tag
  rc_is 2
  gate release app --tag v1.0.0 --tag v1.0.1
  rc_is 2
  gate release app --pr-if-refused --pr-if-refused
  rc_is 2
  gate release app --tag v1.0.0 --bogus
  rc_is 2
  eq "local main unchanged" "$main0" "$(git -C "$R/projects/app" rev-parse main)"
  eq "remote main unchanged" "$main0" "$(remote_sha main)"
  eq "no tag" none "$(local_tag v1.0.0)"
}

test_release_tag_waits_for_the_pull_request() {
  fixture
  developer_ahead four
  protect_main
  local main0
  main0="$(git -C "$R/projects/app" rev-parse main)"
  gate release app --tag v1.0.0
  rc_is 1
  has "release app --pr-if-refused --tag v1.0.0"
  printf '#!/usr/bin/env bash\necho https://example.com/acme/app/pull/2\n' >"$BASE/gh.sh"
  chmod +x "$BASE/gh.sh"
  AIWP_GH="$BASE/gh.sh" gate release app --tag v1.0.0 --pr-if-refused
  rc_is 0
  has "pull request: https://example.com/acme/app/pull/2"
  has "no tag yet: v1.0.0 waits for the merge of the pull request"
  has "bash scripts/aiwp-cmds.sh release app --tag v1.0.0"
  hasnt_out "tagged:"
  eq "no local tag" none "$(local_tag v1.0.0)"
  eq "no remote tag" none "$(remote_tag v1.0.0)"
  eq "remote main unchanged" "$main0" "$(remote_sha main)"
}

test_release_tag_without_a_remote_is_local_and_a_refused_tag_push_says_how() {
  fixture
  developer_ahead five
  local dev
  dev="$(git -C "$R/projects/app" rev-parse developer)"
  # The remote refuses tags only: main is released, the tag stays local, and the message gives the push command.
  # The $1 belongs to the hook: SC2016 does not apply.
  # shellcheck disable=SC2016
  printf '#!/bin/sh\ncase "$1" in refs/tags/*) echo "no tags here" >&2; exit 1 ;; esac\nexit 0\n' >"$REMOTE/hooks/update"
  chmod +x "$REMOTE/hooks/update"
  gate release app --tag v1.0.0
  rc_is 1
  has "main was released, but the push of v1.0.0 failed: the tag is local only"
  has "git -C projects/app push origin refs/tags/v1.0.0"
  eq "remote main released" "$dev" "$(remote_sha main)"
  eq "local tag" "$dev" "$(git -C "$R/projects/app" rev-parse -q --verify 'refs/tags/v1.0.0^{commit}')"
  eq "no remote tag" none "$(remote_tag v1.0.0)"
  git -C "$R/projects/app" remote remove origin
  printf 'six\n' >"$R/projects/app/six.txt"
  git -C "$R/projects/app" add -A
  git -C "$R/projects/app" commit -q -m six
  dev="$(git -C "$R/projects/app" rev-parse developer)"
  gate release app --tag v1.1.0
  rc_is 0
  has "tagged: v1.1.0"
  has "no remote: v1.1.0 is local only"
  hasnt_out "pushed:"
  eq "local main" "$dev" "$(git -C "$R/projects/app" rev-parse main)"
  eq "annotated local tag" tag "$(git -C "$R/projects/app" cat-file -t refs/tags/v1.1.0)"
  eq "on the released main" "$dev" "$(git -C "$R/projects/app" rev-parse 'refs/tags/v1.1.0^{commit}')"
}

test_developer_switches_only_safely_and_creates_only_when_asked() {
  fixture
  git -C "$R/projects/app" switch -q main
  gate developer app
  rc_is 0
  has "switched: projects/app from main to developer"
  eq "on developer" developer "$(git -C "$R/projects/app" symbolic-ref --short HEAD)"
  git -C "$R/projects/app" switch -q -c feature/local
  printf 'x\n' >"$R/projects/app/local.txt"
  git -C "$R/projects/app" add -A
  git -C "$R/projects/app" commit -q -m local
  gate developer app
  rc_is 1
  has "with commits not on the remote"
  eq "still on the feature" feature/local "$(git -C "$R/projects/app" symbolic-ref --short HEAD)"
  printf 'y\n' >"$R/projects/app/dirty.txt"
  gate developer app
  rc_is 1
  has "has changes in its checkout"
  rm "$R/projects/app/dirty.txt"
  git -C "$R/projects/app" switch -q developer
  # A project whose remote has only main.
  git -C "$REMOTE" branch -D developer >/dev/null
  git -C "$R/projects/app" switch -q main
  git -C "$R/projects/app" branch -q -D developer feature/local
  gate developer app
  rc_is 1
  has "developer is not on the remote"
  eq "nothing created" none "$(remote_sha developer)"
  gate developer app --create
  rc_is 0
  has "created on the remote: developer, from main"
  eq "developer on the remote at main" "$(remote_sha main)" "$(remote_sha developer)"
  eq "on developer" developer "$(git -C "$R/projects/app" symbolic-ref --short HEAD)"
  git -C "$R/projects/app" remote remove origin
  gate developer app
  rc_is 1
  has "has no remote"
}

test_bring_from_a_local_folder_keeps_local_branches_and_points_origin_to_its_remote() {
  fixture
  local src="$BASE/old-$CURRENT"
  rm -rf "$src"
  git clone -q -b developer "$REMOTE" "$src"
  git -C "$src" switch -q -c feature/never-pushed
  printf 'wip\n' >"$src/wip.txt"
  git -C "$src" add -A
  git -C "$src" commit -q -m wip
  git -C "$src" tag local-tag
  # A local commit on a branch the remote has: brought, and named with its count, not as a branch the remote lacks.
  git -C "$src" switch -q developer
  printf 'local\n' >"$src/local.txt"
  git -C "$src" add local.txt
  git -C "$src" commit -q -m local
  git -C "$src" switch -q feature/never-pushed
  printf 'dirty\n' >>"$src/app.txt"
  printf 'new\n' >"$src/untracked.txt"
  git -C "$src" stash -q 2>/dev/null || true
  printf 'dirty again\n' >>"$src/app.txt"
  gate bring "$src" acme/billing-api
  rc_is 0
  has "brought: projects/acme/billing-api, on developer"
  has "origin: the source's remote"
  has "uncommitted in the source, not brought"
  has "app.txt"
  has "untracked.txt"
  has "1 stash(es) in the source"
  has "brought, not on the source's remote: developer (1 commit(s) the remote does not have) feature/never-pushed (not on the remote)"
  local dest="$R/projects/acme/billing-api"
  eq "origin is the real remote" "$REMOTE" "$(git -C "$dest" remote get-url origin)"
  eq "local branch kept" "$(git -C "$src" rev-parse feature/never-pushed)" "$(git -C "$dest" rev-parse feature/never-pushed)"
  git -C "$dest" rev-parse -q --verify refs/tags/local-tag >/dev/null; check "tags kept" $?
  eq "tracking refs are the remote's" "$(remote_sha developer)" "$(git -C "$dest" rev-parse origin/developer)"
  ! git -C "$dest" rev-parse -q --verify refs/remotes/origin/feature/never-pushed >/dev/null; check "no tracking ref of a local branch" $?
  eq "clean checkout" "" "$(git -C "$dest" status --porcelain)"
  eq "source untouched" "dirty again" "$(tail -n 1 "$src/app.txt")"
  gate bring "$src" acme/billing-api
  rc_is 1
  has "exists already"
  # Any layout: a project brought inside a repo is a repo inside that repo.
  gate bring "$src" acme/billing-api/inner
  rc_is 0
  has "brought: projects/acme/billing-api/inner"
  eq "a repo of its own inside the repo" "$dest/inner" "$(git -C "$dest/inner" rev-parse --show-toplevel)"
  gate bring "$R/projects/app" copy
  rc_is 1
  has "inside this workspace"
  gate bring "$src" Bad_Name
  rc_is 2
  git -C "$src" remote remove origin
  gate bring "$src" solo
  rc_is 0
  has "the source has no remote"
  ! git -C "$R/projects/solo" remote get-url origin >/dev/null 2>&1; check "no origin" $?
}

test_bring_from_a_url_checks_out_developer() {
  fixture
  gate bring "file://$REMOTE" from-url
  rc_is 0
  has "brought: projects/from-url, on developer"
  eq "origin" "file://$REMOTE" "$(git -C "$R/projects/from-url" remote get-url origin)"
  gate bring "file://$BASE/missing.git" nothing
  rc_is 1
  has "could not clone"
}

# Creates projects/$1 as a repo on developer with a bare remote, one committed file and, when given, a .gitignore $2.
nested_project() {
  local dir="$R/projects/$1" remote="$BASE/remote.$CURRENT.${1//\//-}.git"
  rm -rf "$remote"
  git init -q --bare -b main "$remote"
  git init -q -b main "$dir"
  printf '%s\n' "$1" >"$dir/readme.txt"
  [ -z "${2:-}" ] || printf '%s\n' "$2" >"$dir/.gitignore"
  git -C "$dir" add readme.txt ${2:+.gitignore}
  git -C "$dir" commit -q -m base
  git -C "$dir" switch -q -c developer
  git -C "$dir" remote add origin "$remote"
  git -C "$dir" push -q origin main developer
}

# A project root repo with two repos inside it (one it ignores, one it does not) and a repo of the same last folder
# name elsewhere: open names each clone after its whole path, the gate merges and release releases each at its depth,
# and the parent's checkout counts as clean with its nested repos, never with a stray file.
test_nested_repos_are_handled_at_their_depth() {
  fixture
  local w="2026-11-17-nested-change" rel name
  nested_project billing "$(printf 'billing-web/\n.env')"
  nested_project billing/billing-api ".env"
  nested_project billing/billing-web
  nested_project other/billing-api
  printf 'ROOT=1\n' >"$R/projects/billing/.env"
  printf 'API=1\n' >"$R/projects/billing/billing-api/.env"
  OUT="$(cd "$R" && bash scripts/aiwp-cmds.sh open "$w" billing billing/billing-api billing/billing-web other/billing-api 2>&1)"
  RC=$?
  rc_is 0
  for name in billing billing--billing-api billing--billing-web other--billing-api; do
    has "path: tmp/work/$w/$name"
  done
  has "attention: projects/billing/billing-api has no AI-WORKSPACE-PROJECT marker"
  eq "the root's own .env copied" "ROOT=1" "$(cat "$R/tmp/work/$w/billing/.env" 2>/dev/null)"
  [ ! -e "$R/tmp/work/$w/billing/billing-api" ]; check "the nested repo stays out of the root's clone" $?
  eq "the nested repo's .env in its own clone" "API=1" "$(cat "$R/tmp/work/$w/billing--billing-api/.env" 2>/dev/null)"
  eq "same last folder, two sources" "$R/projects/other/billing-api" "$(git -C "$R/tmp/work/$w/other--billing-api" config aiwp.source)"
  for rel in billing billing/billing-api billing/billing-web; do
    name="${rel//\//--}"
    printf 'change\n' >"$R/tmp/work/$w/$name/change.txt"
    git -C "$R/tmp/work/$w/$name" add change.txt
    git -C "$R/tmp/work/$w/$name" commit -q -m "change $rel" >/dev/null 2>&1
    gate gate "$w/$name" --test "test -f change.txt"
    rc_is 0
    has "gate: checks passed for"
    gate gate --merge "$w/$name" "$(git -C "$R/tmp/work/$w/$name" rev-parse HEAD)"
    rc_is 0
    eq "developer of projects/$rel" "$(git -C "$R/tmp/work/$w/$name" rev-parse HEAD)" "$(git -C "$R/projects/$rel" rev-parse developer)"
    [ -f "$R/projects/$rel/change.txt" ]; check "checkout of projects/$rel updated" $?
  done
  OUT="$(cd "$R" && bash scripts/aiwp-cmds.sh status "$w" 2>&1)"
  has "tmp/work/$w/billing--billing-api  branch=feat/nested-change"
  gate release billing/billing-api
  rc_is 0
  eq "main of the nested repo" "$(git -C "$R/projects/billing/billing-api" rev-parse developer)" "$(git -C "$R/projects/billing/billing-api" rev-parse main)"
  eq "the root does not ignore billing-api: git sees it" "?? billing-api/" "$(git -C "$R/projects/billing" status --porcelain)"
  printf 'stray\n' >"$R/projects/billing/stray.txt"
  gate release billing
  rc_is 1
  has "projects/billing has changes in its checkout"
  rm "$R/projects/billing/stray.txt"
  gate release billing
  rc_is 0
  eq "main of the root repo" "$(git -C "$R/projects/billing" rev-parse developer)" "$(git -C "$R/projects/billing" rev-parse main)"
  OUT="$(cd "$R" && bash scripts/aiwp-cmds.sh close "$w" 2>&1)"
  RC=$?
  rc_is 0
  has "closed: tmp/work/$w"
}

# --- Hotfix: a fix from main into production, then main merged down into developer ---------------------------------

HW="2026-11-17-hotfix-login-null"
hc() { echo "$R/tmp/work/$HW/app"; }
local_sha() { git -C "$R/projects/app" rev-parse -q --verify "refs/heads/$1" 2>/dev/null || echo none; }
remote_heads() { git -C "$REMOTE" for-each-ref --format='%(refname)' refs/heads | sort | tr '\n' ' '; }
# A commit in the hotfix clone (its hooks push it).
hcommit() { # file, content
  mkdir -p "$(dirname "$(hc)/$1")"
  printf '%s\n' "$2" >"$(hc)/$1"
  git -C "$(hc)" add -A
  git -C "$(hc)" commit -q -m "fix $1" >/dev/null 2>&1
}
# The fixture, developer one commit ahead of main (unreleased work, on the remote too), and a hotfix clone of main.
hotfix_fixture() {
  fixture
  developer_ahead unreleased
  (cd "$R" && bash scripts/aiwp-cmds.sh open "$HW" app --from-main >/dev/null 2>&1)
}
# The fixture with a fix already in main of the remote, not merged into developer.
hotfix_landed() {
  hotfix_fixture
  hcommit fix.txt fixed
  gate gate "$HW/app" --test "test -f fix.txt"
  gate hotfix "$HW/app" "$(git -C "$(hc)" rev-parse HEAD)"
}

test_hotfix_gate_against_main_then_into_main() {
  hotfix_fixture
  local dev0 main0 sha
  dev0="$(local_sha developer)"
  main0="$(local_sha main)"
  eq "the clone starts from main" "$main0" "$(git -C "$(hc)" rev-parse HEAD)"
  hcommit fix.txt fixed
  sha="$(git -C "$(hc)" rev-parse HEAD)"
  gate gate "$HW/app" --test "test -f fix.txt && test ! -f unreleased.txt"
  rc_is 0
  has "== 1/6 base: main of projects/app (hotfix: the checkout stays on developer)"
  has "gate: checks passed for $sha"
  has "bash scripts/aiwp-cmds.sh hotfix $HW/app $sha"
  hasnt_out "gate --merge"
  [ -f "$R/tmp/work/$HW/gate-app.md" ]; check "audit written" $?
  grep -q "Range: \`$main0..$sha\`" "$R/tmp/work/$HW/gate-app.md"; check "audit of main..fix" $?
  eq "checkout still on developer" developer "$(git -C "$R/projects/app" symbolic-ref --short HEAD)"
  eq "developer untouched" "$dev0" "$(local_sha developer)"
  eq "main untouched by the gate" "$main0" "$(remote_sha main)"
  gate gate --merge "$HW/app" "$sha"
  rc_is 1
  has "is a hotfix clone: its fix goes into main by bash scripts/aiwp-cmds.sh hotfix"
  eq "gate --merge left main" "$main0" "$(remote_sha main)"
  eq "gate --merge left developer" "$dev0" "$(remote_sha developer)"
  gate hotfix "$HW/app" "$sha"
  rc_is 0
  has "into main: $sha of projects/app"
  has "pushed: main"
  has "deleted from the remote: fix/login-null"
  has "bash scripts/aiwp-cmds.sh hotfix-tag app vX.Y.Z"
  has "bash scripts/aiwp-cmds.sh hotfix-down app"
  eq "remote main" "$sha" "$(remote_sha main)"
  eq "local main" "$sha" "$(local_sha main)"
  eq "remote developer untouched" "$dev0" "$(remote_sha developer)"
  eq "checkout on developer" developer "$(git -C "$R/projects/app" symbolic-ref --short HEAD)"
  eq "no tag" "" "$(git -C "$REMOTE" tag)"
  [ ! -f "$R/tmp/work/$HW/.gate-app" ]; check "record removed" $?
  OUT="$(cd "$R" && bash scripts/aiwp-cmds.sh close "$HW" 2>&1)"
  RC=$?
  rc_is 0
}

# AC-1: a branch that brought developer work in (a merge, a reset) is refused; a cherry-pick of the fix passes.
test_hotfix_gate_refuses_unreleased_developer_work() {
  hotfix_fixture
  git -C "$(hc)" fetch -q origin developer
  git -C "$(hc)" merge -q --no-edit FETCH_HEAD >/dev/null 2>&1
  gate gate "$HW/app" --test true
  rc_is 1
  has "refused: the branch holds 1 commit(s) of developer that main does not have"
  has "add unreleased"
  [ ! -f "$R/tmp/work/$HW/.gate-app" ]; check "no record" $?
  git -C "$(hc)" reset -q --hard origin/main
  git -C "$(hc)" reset -q --soft FETCH_HEAD
  git -C "$(hc)" reset -q --hard FETCH_HEAD
  gate gate "$HW/app" --test true
  rc_is 1
  has "commit(s) of developer that main does not have"
  git -C "$(hc)" reset -q --hard origin/main
  # -x: a new commit even within the same second (onto the same parent, a plain cherry-pick can be the very commit).
  git -C "$(hc)" cherry-pick -x "$(git -C "$R/projects/app" rev-parse developer)" >/dev/null 2>&1
  gate gate "$HW/app" --test "test -f unreleased.txt"
  rc_is 0
  has "gate: checks passed for"
}

# AC-4: without the gate's record, with a sha that moved, or with main moved, main does not change and gets no push.
test_hotfix_into_main_refuses_what_the_gate_did_not_check() {
  hotfix_fixture
  local main0 sha other
  main0="$(remote_sha main)"
  hcommit fix.txt fixed
  sha="$(git -C "$(hc)" rev-parse HEAD)"
  gate hotfix "$HW/app" "$sha"
  rc_is 1
  has "the gate did not pass for this clone"
  eq "no record: main unchanged" "$main0" "$(remote_sha main)"
  gate gate "$HW/app" --test true
  rc_is 0
  gate hotfix "$HW/app" "$(git -C "$(hc)" rev-parse HEAD~1)"
  rc_is 1
  has "is not the sha the gate checked"
  hcommit late.txt late
  gate hotfix "$HW/app" "$sha"
  rc_is 1
  has "the clone moved after the gate"
  eq "sha moved: main unchanged" "$main0" "$(remote_sha main)"
  git -C "$(hc)" reset -q --hard "$sha"
  printf 'dirty\n' >>"$(hc)/fix.txt"
  gate hotfix "$HW/app" "$sha"
  rc_is 1
  has "tracked changes after the gate"
  git -C "$(hc)" checkout -q -- fix.txt
  printf 'x\n' >"$R/projects/app/stray.txt"
  gate hotfix "$HW/app" "$sha"
  rc_is 1
  has "has changes in its checkout"
  rm "$R/projects/app/stray.txt"
  # Another hotfix reached main after the gate: run the gate again.
  rm -rf "$BASE/other"
  git clone -q -b main "$REMOTE" "$BASE/other"
  printf 'other\n' >"$BASE/other/other-fix.txt"
  git -C "$BASE/other" add -A
  git -C "$BASE/other" commit -q -m "other hotfix"
  git -C "$BASE/other" push -q origin main
  other="$(remote_sha main)"
  gate hotfix "$HW/app" "$sha"
  rc_is 1
  has "main moved after the gate: run the gate again"
  eq "main moved: not pushed" "$other" "$(remote_sha main)"
  eq "local main is the remote's" "$other" "$(local_sha main)"
  gate hotfix "$W/app" "$(git -C "$(c)" rev-parse HEAD)"
  rc_is 1
  has "is not a hotfix clone (open --from-main)"
  gate hotfix "$HW/app"
  rc_is 2
  gate hotfix "$HW/app" "$sha" --bogus
  rc_is 2
  gate hotfix "$HW/app" "$sha" extra
  rc_is 2
}

test_hotfix_refused_by_a_protected_main_opens_a_pull_request() {
  hotfix_fixture
  local main0 sha
  main0="$(remote_sha main)"
  hcommit fix.txt fixed
  sha="$(git -C "$(hc)" rev-parse HEAD)"
  gate gate "$HW/app" --test true
  protect_main
  gate hotfix "$HW/app" "$sha"
  rc_is 1
  has "the remote refused the push of main"
  has "bash scripts/aiwp-cmds.sh hotfix $HW/app $sha --pr-if-refused"
  eq "remote main unchanged" "$main0" "$(remote_sha main)"
  eq "local main unchanged" "$main0" "$(local_sha main)"
  # The $* and $(...) belong to the stub: SC2016 does not apply.
  # shellcheck disable=SC2016
  printf '#!/usr/bin/env bash\necho "gh $* @ $(pwd -P)" >>"%s/gh.log"\necho https://example.com/acme/app/pull/2\n' "$BASE" >"$BASE/gh.sh"
  chmod +x "$BASE/gh.sh"
  : >"$BASE/gh.log"
  AIWP_GH="$BASE/gh.sh" gate hotfix "$HW/app" "$sha" --pr-if-refused
  rc_is 0
  has "pull request: https://example.com/acme/app/pull/2"
  has "no tag yet: the tag waits for the merge of the pull request (a known limit)"
  grep -q "gh pr create --base main --head fix/login-null" "$BASE/gh.log"; check "gh opened fix -> main" $?
  grep -q "@ $R/projects/app" "$BASE/gh.log"; check "from the project folder" $?
  eq "local main still unchanged" "$main0" "$(local_sha main)"
  eq "fix branch kept for the pull request" "$sha" "$(remote_sha fix/login-null)"
  printf '#!/usr/bin/env bash\nexit 1\n' >"$BASE/gh.sh"
  AIWP_GH="$BASE/gh.sh" gate hotfix "$HW/app" "$sha" --pr-if-refused
  rc_is 1
  has "the pull request could not be opened"
}

test_hotfix_tag_only_while_main_waits_and_never_moved() {
  hotfix_fixture
  gate hotfix-tag app v1.0.1
  rc_is 1
  has "no hotfix pending in projects/app: main is already in developer"
  eq "no tag before the fix" none "$(remote_tag v1.0.1)"
  hcommit fix.txt fixed
  gate gate "$HW/app" --test true
  gate hotfix "$HW/app" "$(git -C "$(hc)" rev-parse HEAD)"
  local main1
  main1="$(remote_sha main)"
  for bad in 1.0.1 v1.0 v1.0.1-rc1 ""; do
    gate hotfix-tag app "$bad"
    rc_is 2
  done
  gate hotfix-tag app
  rc_is 2
  git -C "$R/projects/app" tag -a v1.0.0 -m v1.0.0 "$(local_sha developer)"
  gate hotfix-tag app v1.0.0
  rc_is 1
  has "v1.0.0 exists on another commit; a tag is never moved"
  git -C "$R/projects/app" tag v1.0.2 main
  gate hotfix-tag app v1.0.2
  rc_is 1
  has "lightweight tag"
  eq "lightweight never pushed" none "$(remote_tag v1.0.2)"
  remote_tag_at v1.0.3 "$(local_sha developer)"
  gate hotfix-tag app v1.0.3
  rc_is 1
  has "v1.0.3 exists on the remote on another commit"
  gate hotfix-tag app v1.0.1
  rc_is 0
  has "tagged: v1.0.1 at $(git -C "$R/projects/app" rev-parse --short main)"
  has "pushed: v1.0.1"
  has "next: bash scripts/aiwp-cmds.sh hotfix-down app"
  eq "tag on main" "$main1" "$(git -C "$REMOTE" rev-parse -q --verify 'refs/tags/v1.0.1^{commit}')"
  eq "annotated" tag "$(git -C "$REMOTE" cat-file -t refs/tags/v1.0.1)"
  eq "only that tag" none "$(remote_tag v1.0.0)"
  local before
  before="$(remote_tag v1.0.1)"
  gate hotfix-tag app v1.0.1
  rc_is 0
  has "pushed: v1.0.1 (already on the remote)"
  eq "kept" "$before" "$(remote_tag v1.0.1)"
  eq "main unchanged by the tag" "$main1" "$(remote_sha main)"
  gate hotfix-down app
  rc_is 0
  gate hotfix-tag app v1.0.4
  rc_is 1
  has "no hotfix pending"
}

# AC-6, clean: a standard merge commit of main into developer, pushed; no new branch and no test run.
test_hotfix_down_merges_main_into_developer() {
  hotfix_landed
  local dev0 main1 heads merge
  dev0="$(remote_sha developer)"
  main1="$(remote_sha main)"
  heads="$(remote_heads)"
  rm -f "$R/validate.log"
  gate hotfix-down app
  rc_is 0
  has "merged down: main ($(git -C "$R/projects/app" rev-parse --short "$main1")) into developer of projects/app"
  has "pushed: developer"
  merge="$(remote_sha developer)"
  eq "local developer is the pushed merge" "$merge" "$(local_sha developer)"
  eq "first parent: developer" "$dev0" "$(git -C "$REMOTE" rev-parse "$merge^1")"
  eq "second parent: main" "$main1" "$(git -C "$REMOTE" rev-parse "$merge^2")"
  eq "two parents" 3 "$(git -C "$REMOTE" rev-list --parents -n 1 "$merge" | wc -w | tr -d ' ')"
  eq "message" "Merge branch 'main' into developer" "$(git -C "$REMOTE" log -1 --format=%s "$merge")"
  eq "no new branch" "$heads" "$(remote_heads)"
  eq "main unchanged" "$main1" "$(remote_sha main)"
  [ ! -e "$R/validate.log" ]; check "no check run" $?
  [ -f "$R/projects/app/fix.txt" ] && [ -f "$R/projects/app/unreleased.txt" ]; check "checkout has both" $?
  eq "checkout clean" "" "$(git -C "$R/projects/app" status --porcelain)"
  gate hotfix-down app
  rc_is 0
  has "nothing to do: main of projects/app is already in developer"
  gate hotfix-down
  rc_is 2
  gate hotfix-down app extra
  rc_is 2
}

# AC-6, conflict: nothing changes and the way out is a fix/<slug>-developer clone through /merge; CHANGELOG.md is the
# expected conflict. That clone passes the gate while the hotfix waits, and its merge clears the wait (AC-7).
test_hotfix_down_conflict_changes_nothing_and_the_resolution_clone_clears_it() {
  fixture
  printf '# Changelog\n\n## 1.0.0 - 2026-11-01\n\n- first\n' >"$R/projects/app/CHANGELOG.md"
  git -C "$R/projects/app" add -A
  git -C "$R/projects/app" commit -q -m "changelog"
  git -C "$R/projects/app" push -q origin developer
  (cd "$R" && bash scripts/aiwp-cmds.sh release app >/dev/null 2>&1)
  printf '# Changelog\n\n## Unreleased\n\n- new feature\n\n## 1.0.0 - 2026-11-01\n\n- first\n' >"$R/projects/app/CHANGELOG.md"
  git -C "$R/projects/app" commit -q -am "unreleased entry"
  git -C "$R/projects/app" push -q origin developer
  (cd "$R" && bash scripts/aiwp-cmds.sh open "$HW" app --from-main >/dev/null 2>&1)
  printf '# Changelog\n\n## 1.0.1 - 2026-11-17\n\n- login no longer fails on a null name\n\n## 1.0.0 - 2026-11-01\n\n- first\n' >"$(hc)/CHANGELOG.md"
  hcommit fix.txt fixed
  gate gate "$HW/app" --test true
  gate hotfix "$HW/app" "$(git -C "$(hc)" rev-parse HEAD)"
  rc_is 0
  local dev0 main1
  dev0="$(remote_sha developer)"
  main1="$(remote_sha main)"
  gate hotfix-down app
  rc_is 1
  has "conflict merging main into developer of projects/app; nothing changed"
  has "  CHANGELOG.md"
  has "--branch fix/<slug>-developer"
  has "the Unreleased section of developer stays on top"
  eq "remote developer unchanged" "$dev0" "$(remote_sha developer)"
  eq "local developer unchanged" "$dev0" "$(local_sha developer)"
  eq "main unchanged" "$main1" "$(remote_sha main)"
  eq "checkout clean" "" "$(git -C "$R/projects/app" status --porcelain)"
  [ ! -e "$R/projects/app/.git/MERGE_HEAD" ]; check "no merge in progress" $?
  # The resolution: a clone of developer on fix/login-null-developer merges origin/main and resolves the conflict.
  local rw="2026-11-17-login-null-developer" rc_dir sha
  (cd "$R" && bash scripts/aiwp-cmds.sh open "$rw" app --branch fix/login-null-developer >/dev/null 2>&1)
  rc_dir="$R/tmp/work/$rw/app"
  git -C "$rc_dir" fetch -q origin main
  git -C "$rc_dir" merge -q --no-edit origin/main >/dev/null 2>&1
  printf '# Changelog\n\n## Unreleased\n\n- new feature\n\n## 1.0.1 - 2026-11-17\n\n- login no longer fails on a null name\n\n## 1.0.0 - 2026-11-01\n\n- first\n' >"$rc_dir/CHANGELOG.md"
  git -C "$rc_dir" add CHANGELOG.md
  git -C "$rc_dir" commit -q --no-edit >/dev/null 2>&1
  gate gate "$rw/app" --test "test -f fix.txt"
  rc_is 0
  has "hotfix pending: fix/login-null-developer holds main"
  sha="$(git -C "$rc_dir" rev-parse HEAD)"
  gate gate --merge "$rw/app" "$sha"
  rc_is 0
  git -C "$REMOTE" merge-base --is-ancestor "$main1" developer; check "developer holds main" $?
  eq "Unreleased stays on top" "## Unreleased" "$(git -C "$REMOTE" show developer:CHANGELOG.md | grep -m 1 '^## ')"
  OUT="$(cd "$R" && bash scripts/aiwp-project-state.sh app 2>&1)"
  hasnt_out "hotfix pending"
  gate hotfix-down app
  rc_is 0
  has "nothing to do"
}

# AC-7: while main waits to be merged into developer, the gate of a clone of developer and the release refuse with the
# reason; once hotfix-down pushed the merge, both work again.
test_a_pending_hotfix_blocks_developer_merges_and_the_release() {
  hotfix_fixture
  commit_in feature.txt one
  gate gate "$W/app" --test true
  rc_is 0
  local sha dev0
  sha="$(git -C "$(c)" rev-parse HEAD)"
  dev0="$(remote_sha developer)"
  hcommit fix.txt fixed
  gate gate "$HW/app" --test true
  gate hotfix "$HW/app" "$(git -C "$(hc)" rev-parse HEAD)"
  rc_is 0
  gate gate --merge "$W/app" "$sha"
  rc_is 1
  has "refused: a hotfix on main of projects/app is not merged into developer yet"
  has "bash scripts/aiwp-cmds.sh hotfix-down app"
  eq "developer unchanged" "$dev0" "$(remote_sha developer)"
  gate gate "$W/app" --test true
  rc_is 1
  has "attention: projects/app has a hotfix on main not merged into developer yet"
  has "refused: a hotfix on main of projects/app is not merged into developer yet"
  [ ! -f "$R/tmp/work/$W/.gate-app" ] || [ "$(cut -d' ' -f1 "$R/tmp/work/$W/.gate-app")" = "$sha" ]; check "no new record" $?
  gate release app --tag v1.1.0
  rc_is 1
  has "refused: a hotfix on main of projects/app is not merged into developer yet"
  eq "no release tag" none "$(remote_tag v1.1.0)"
  OUT="$(cd "$R" && bash scripts/aiwp-project-state.sh app 2>&1)"
  has "hotfix pending: main is not merged into developer"
  OUT="$(cd "$R" && bash scripts/aiwp-cmds.sh open 2026-11-17-next-change app 2>&1)"
  has "attention: projects/app has a hotfix on main not merged into developer yet"
  gate hotfix-down app
  rc_is 0
  OUT="$(cd "$R" && bash scripts/aiwp-project-state.sh app 2>&1)"
  hasnt_out "hotfix pending"
  gate gate "$W/app" --test "test -f fix.txt"
  rc_is 0
  hasnt_out "attention: projects/app has a hotfix"
  gate gate --merge "$W/app" "$(git -C "$(c)" rev-parse HEAD)"
  rc_is 0
  gate release app
  rc_is 0
  eq "released" "$(remote_sha developer)" "$(remote_sha main)"
}

# A repo with no remote: the same flow, every step local, and said.
test_hotfix_without_a_remote_stays_local() {
  fixture
  rm -rf "$R/tmp/work"
  git -C "$R/projects/app" remote remove origin
  developer_ahead_local() { printf 'u\n' >"$R/projects/app/u.txt"; git -C "$R/projects/app" add -A; git -C "$R/projects/app" commit -q -m unreleased; }
  developer_ahead_local
  OUT="$(cd "$R" && bash scripts/aiwp-cmds.sh open "$HW" app --from-main 2>&1)"
  has "attention: app has no remote"
  hcommit fix.txt fixed
  local sha
  sha="$(git -C "$(hc)" rev-parse HEAD)"
  gate gate "$HW/app" --test true
  rc_is 0
  gate hotfix "$HW/app" "$sha"
  rc_is 0
  has "no remote: main moved locally only"
  eq "local main" "$sha" "$(local_sha main)"
  eq "fix branch removed" none "$(local_sha fix/login-null)"
  OUT="$(cd "$R" && bash scripts/aiwp-project-state.sh --porcelain app 2>&1)"
  has "$(printf '\tdeveloper\tyes')"
  case "$OUT" in *"$(printf '\tyes')") check "hotfix yes" 0 ;; *) check "hotfix yes" 1 ;; esac
  gate release app
  rc_is 1
  has "hotfix-down app"
  gate hotfix-tag app v0.1.1
  rc_is 0
  has "no remote: v0.1.1 is local only"
  gate hotfix-down app
  rc_is 0
  has "no remote: developer merged locally only"
  git -C "$R/projects/app" merge-base --is-ancestor "$sha" developer; check "developer holds the fix" $?
}

test_usage() {
  fixture
  gate --help
  rc_is 0
  has "checkpoint <repo>"
  has "release <repo> [--pr-if-refused] [--tag vX.Y.Z]"
  has "hotfix <work>/<clone> <sha> [--pr-if-refused]"
  has "hotfix-tag <repo> vX.Y.Z"
  has "hotfix-down <repo>"
  gate bring onlyone
  rc_is 2
  gate developer app --bogus
  rc_is 2
  gate gate
  rc_is 2
  gate gate --merge "$W/app"
  rc_is 2
  gate nope
  rc_is 2
}

only=""
[ "${1:-}" != "--only" ] || only="${2:-}"
tests="$(declare -F | awk '{print $3}' | grep '^test_')"
[ -z "$only" ] || tests="$only"
for t in $tests; do
  CURRENT="$t"
  "$t"
  COUNT=$((COUNT + 1))
done
if [ "$FAILED" -eq 0 ]; then echo "ok: $COUNT tests"; else echo "failed: $FAILED checks"; exit 1; fi
