#!/usr/bin/env bash
# Tests of tests/caw-work.sh in a throwaway repository: copies of tests/caw-work.sh and tests/lib/terms.sh in a repo
# with developer and main, a local bare remote, and a terms list holding an invented term. This repository is never
# touched. Run: bash tests/test-caw-work.sh [--only <test_name>]
# check takes the status of the test right before it on purpose: SC2319 does not apply. The tests run through a list
# built at run time: SC2329 does not apply.
# shellcheck disable=SC2319,SC2329
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BASE="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$BASE"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE AIWP_TERMS_FILE
# No terms list of this machine reaches the tests: each scenario sets its own.
export AIWP_WORKSPACE="$BASE/no-workspace"
TODAY="$(date +%Y-%m-%d)"
B="feat/sample-change"
W="$TODAY-sample-change"
FAILED=0
COUNT=0
OUT=""
RC=0
CURRENT=""
R=""
REMOTE=""
C=""

check() { # description, status (0 = ok)
  if [ "$2" -ne 0 ]; then
    FAILED=$((FAILED + 1))
    echo "FAIL $CURRENT: $1 (rc=$RC out=[$OUT])"
  fi
}
has() { case "$OUT" in *"$1"*) check "has [$1]" 0 ;; *) check "missing [$1]" 1 ;; esac; }
hasnt() { case "$OUT" in *"$1"*) check "unexpected [$1]" 1 ;; *) check "no [$1]" 0 ;; esac; }
rc_is() { [ "$RC" -eq "$1" ]; check "rc $1" $?; }
rc_not() { [ "$RC" -ne "$1" ]; check "rc not $1" $?; }
eq() { [ "$2" = "$3" ]; check "$1: expected [$2] got [$3]" $?; }

# Fresh root: tests/caw-work.sh and tests/lib/terms.sh copied, developer and main pushed to a bare remote, and a terms
# list with the invented term acmecorp in AIWP_TERMS_FILE.
fixture() {
  R="$BASE/root.$CURRENT"
  REMOTE="$BASE/remote.$CURRENT.git"
  rm -rf "$R" "$REMOTE"
  git init -q --bare -b main "$REMOTE"
  git init -q -b main "$R"
  mkdir -p "$R/tests/lib"
  cp "$HERE/caw-work.sh" "$R/tests/caw-work.sh"
  cp "$HERE/lib/terms.sh" "$R/tests/lib/terms.sh"
  printf 'tmp/\n' >"$R/.gitignore"
  printf '# sample\n' >"$R/README.md"
  git -C "$R" add -A
  git -C "$R" commit -q -m base
  git -C "$R" branch developer
  git -C "$R" switch -q developer
  git -C "$R" remote add origin "$REMOTE"
  git -C "$R" push -q origin main developer
  printf '\xEF\xBB\xBF# company terms of the tests\n\n  acmecorp  \n' >"$BASE/terms.$CURRENT.txt"
  export AIWP_TERMS_FILE="$BASE/terms.$CURRENT.txt"
  C="$R/tmp/work/$W/claude-cli-agents-workspace"
}

run() {
  OUT="$(cd "$R" && bash "$R/tests/caw-work.sh" "$@" 2>&1)"
  RC=$?
}

remote_sha() { git -C "$REMOTE" rev-parse -q --verify "${1#refs/}" 2>/dev/null || echo none; }
commit_in() { # file, content, [message]: commits in the clone; the hooks' output lands in OUT
  printf '%s\n' "$2" >"$C/$1"
  git -C "$C" add -- "$1"
  OUT="$(git -C "$C" commit -q -m "${3:-change $1}" 2>&1)"
  RC=$?
}
in_clone() { # git command in the clone; output in OUT
  OUT="$(git -C "$C" "$@" 2>&1)"
  RC=$?
}
# Takes the work branch into developer on the remote, as /caw-merge does from the root.
merge_into_developer() {
  git -C "$R" fetch -q origin
  git -C "$R" merge -q --no-edit "origin/$B" >/dev/null
  git -C "$R" push -q origin developer
}

test_open_pushes_a_branch_with_hooks() {
  fixture
  run open "$B"
  rc_is 0
  has "pushed: $B"
  has "path: tmp/work/$W/claude-cli-agents-workspace"
  eq "branch" "$B" "$(git -C "$C" symbolic-ref --short HEAD)"
  eq "starts at origin/developer" "$(remote_sha developer)" "$(git -C "$C" rev-parse HEAD)"
  eq "branch on the remote" "$(git -C "$C" rev-parse HEAD)" "$(remote_sha "heads/$B")"
  eq "origin is the root's origin" "$REMOTE" "$(git -C "$C" remote get-url origin)"
  eq "branch recorded" "$B" "$(git -C "$C" config caw.branch)"
  eq "upstream" "origin/$B" "$(git -C "$C" rev-parse --abbrev-ref '@{upstream}')"
  eq "no other local branch" "$B" "$(git -C "$C" for-each-ref --format='%(refname:short)' refs/heads)"
  eq "hooks path is the clone's own" "$C/.git/hooks" "$(git -C "$C" config core.hooksPath)"
  local h
  for h in post-commit post-merge post-rewrite pre-push; do
    [ -x "$C/.git/hooks/$h" ]; check "hook $h" $?
    grep -qF "$R/tests/caw-work.sh" "$C/.git/hooks/$h"; check "hook $h calls the script by its absolute path" $?
  done
  eq "root untouched" "" "$(git -C "$R" status --porcelain)"
  eq "root branches" "developer main" "$(git -C "$R" for-each-ref --format='%(refname:short)' refs/heads | tr '\n' ' ' | sed 's/ $//')"
  run open "$B"
  rc_is 0
  has "(already open)"
  # A clone of the same branch opened another day is reused where it is.
  mv "$R/tmp/work/$W" "$R/tmp/work/2026-01-01-sample-change"
  run open "$B"
  rc_is 0
  has "path: tmp/work/2026-01-01-sample-change/claude-cli-agents-workspace (already open)"
  [ ! -e "$R/tmp/work/$W" ]; check "no second clone" $?
}

test_open_refuses_bad_names() {
  fixture
  run open developer
  rc_is 2
  run open main
  rc_is 2
  run open feature/sample
  rc_is 2
  run open feat/Bad_Slug
  rc_is 2
  run open feat/main
  rc_is 2
  run open fix/developer
  rc_is 2
  run open
  rc_is 2
  git -C "$R" tag feat/tagged
  run open feat/tagged
  rc_is 1
  has "is the name of a tag"
  # A tag only on the remote is refused too.
  git -C "$R" tag fix/remote-tag
  git -C "$R" push -q origin fix/remote-tag
  git -C "$R" tag -d fix/remote-tag >/dev/null
  run open fix/remote-tag
  rc_is 1
  has "tag on origin"
  # A branch already on the remote with no clone here.
  git -C "$R" push -q origin developer:refs/heads/docs/elsewhere
  run open docs/elsewhere
  rc_is 1
  has "on origin already"
  [ -z "$(ls -A "$R/tmp/work" 2>/dev/null)" ]; check "nothing created" $?
  # Another branch with the same slug, the same day.
  run open "$B"
  rc_is 0
  run open fix/sample-change
  rc_is 1
  has "is open already for $B"
}

test_open_needs_an_origin() {
  fixture
  git -C "$R" remote remove origin
  run open "$B"
  rc_is 1
  has "no origin remote"
  [ ! -e "$R/tmp/work/$W" ]; check "nothing created" $?
}

test_every_commit_is_pushed() {
  fixture
  run open "$B"
  commit_in a.txt one
  rc_is 0
  has "caw-work: pushed $B"
  eq "remote has the commit" "$(git -C "$C" rev-parse HEAD)" "$(remote_sha "heads/$B")"
  eq "tracking ref follows" "$(git -C "$C" rev-parse HEAD)" "$(git -C "$C" rev-parse "origin/$B")"
}

test_a_term_in_a_file_is_not_pushed() {
  fixture
  run open "$B"
  local pushed
  pushed="$(remote_sha "heads/$B")"
  commit_in notes.txt "made for ACMECORP inc"
  rc_is 0
  has "notes.txt:1:made for ACMECORP inc"
  has "refused: the lines above hold a company term"
  has "NOT pushed"
  eq "remote unchanged" "$pushed" "$(remote_sha "heads/$B")"
  eq "commit stays" "change notes.txt" "$(git -C "$C" log -1 --format=%s)"
  # Removing it in a later commit is not enough: the first one would still leave.
  commit_in notes.txt "made for a customer"
  has "refused: the lines above hold a company term"
  eq "still not pushed" "$pushed" "$(remote_sha "heads/$B")"
  # Rewriting the commits not on the remote is: the push is a fast-forward.
  git -C "$C" reset -q --soft "$pushed"
  OUT="$(git -C "$C" commit -q -m "add notes" 2>&1)"
  has "caw-work: pushed $B"
  eq "pushed after the rewrite" "$(git -C "$C" rev-parse HEAD)" "$(remote_sha "heads/$B")"
}

test_a_term_in_a_message_is_not_pushed() {
  fixture
  run open "$B"
  local pushed
  pushed="$(remote_sha "heads/$B")"
  commit_in b.txt b "fix the acmecorp export"
  has ":message:1:fix the acmecorp export"
  has "NOT pushed"
  eq "remote unchanged" "$pushed" "$(remote_sha "heads/$B")"
  # An amend of a commit not on the remote is fine.
  OUT="$(git -C "$C" commit -q --amend -m "fix the export" 2>&1)"
  has "caw-work: pushed $B"
  eq "amend pushed" "$(git -C "$C" rev-parse HEAD)" "$(remote_sha "heads/$B")"
}

test_rewriting_pushed_commits_is_refused() {
  fixture
  run open "$B"
  commit_in a.txt one
  local pushed
  pushed="$(remote_sha "heads/$B")"
  printf 'two\n' >>"$C/a.txt"
  OUT="$(git -C "$C" commit -q -am amended --amend 2>&1)"
  has "force push"
  has "git reset --soft ${pushed:0:12}"
  has "NOT pushed"
  eq "remote unchanged by the amend" "$pushed" "$(remote_sha "heads/$B")"
  in_clone push -q --force origin "HEAD:refs/heads/$B"
  rc_not 0
  has "that is a force push"
  eq "remote unchanged by --force" "$pushed" "$(remote_sha "heads/$B")"
  run run "$W" -- git push -q --force-with-lease origin "HEAD:refs/heads/$B"
  rc_not 0
  has "that is a force push"
  eq "remote unchanged by a lease" "$pushed" "$(remote_sha "heads/$B")"
}

test_rebase_pushes_at_the_end() {
  fixture
  run open "$B"
  # Two commits left unpushed: the terms list names no file, so the hooks refuse.
  export AIWP_TERMS_FILE="$BASE/missing.txt"
  commit_in b.txt b
  has "AIWP_TERMS_FILE names no file"
  commit_in c.txt c
  export AIWP_TERMS_FILE="$BASE/terms.$CURRENT.txt"
  OUT="$(GIT_SEQUENCE_EDITOR=true git -C "$C" rebase -q -i --force-rebase HEAD~2 2>&1)"
  RC=$?
  rc_is 0
  hasnt "HEAD is on"
  has "caw-work: pushed $B"
  eq "the rebase is pushed at the end" "$(git -C "$C" rev-parse HEAD)" "$(remote_sha "heads/$B")"
}

test_a_merge_is_pushed() {
  fixture
  run open "$B"
  commit_in a.txt one
  printf 'news\n' >"$R/news.txt"
  git -C "$R" add news.txt
  git -C "$R" commit -q -m news
  git -C "$R" push -q origin developer
  in_clone fetch -q origin
  in_clone merge -q --no-edit origin/developer
  has "caw-work: pushed $B"
  eq "merge pushed" "$(git -C "$C" rev-parse HEAD)" "$(remote_sha "heads/$B")"
}

test_protected_refs_are_refused() {
  fixture
  run open "$B"
  commit_in a.txt one
  local dev main
  dev="$(remote_sha developer)"
  main="$(remote_sha main)"
  run run "$W" -- git push -q origin HEAD:developer
  rc_not 0
  has "never pushes developer"
  eq "developer unchanged" "$dev" "$(remote_sha developer)"
  run run "$W" -- git push -q origin HEAD:main
  rc_not 0
  has "never pushes main"
  eq "main unchanged" "$main" "$(remote_sha main)"
  git -C "$C" tag v9.9.9
  run run "$W" -- git push -q origin v9.9.9
  rc_not 0
  has "never pushes a tag"
  eq "no tag on the remote" none "$(remote_sha tags/v9.9.9)"
  run run "$W" -- git push -q origin HEAD:refs/notes/x
  rc_not 0
  has "branches only"
  # Another branch: pushed after the scan, and its deletion passes.
  run run "$W" -- git push -q origin HEAD:refs/heads/chore/side
  rc_is 0
  eq "side branch pushed" "$(git -C "$C" rev-parse HEAD)" "$(remote_sha heads/chore/side)"
  run run "$W" -- git push -q origin --delete chore/side
  rc_is 0
  eq "side branch deleted" none "$(remote_sha heads/chore/side)"
  run run "$W" -- git push -q origin --delete developer
  rc_not 0
  eq "developer not deleted" "$dev" "$(remote_sha developer)"
}

test_no_terms_list_skips_the_scan() {
  fixture
  run open "$B"
  unset AIWP_TERMS_FILE
  commit_in a.txt "acmecorp"
  has "SKIP terms scan: no terms list"
  has "caw-work: pushed $B"
  eq "pushed" "$(git -C "$C" rev-parse HEAD)" "$(remote_sha "heads/$B")"
  # A list with no term skips too; the AIWP_WORKSPACE lookup is used.
  mkdir -p "$AIWP_WORKSPACE/custom"
  printf '# none\n' >"$AIWP_WORKSPACE/custom/core-terms.txt"
  commit_in b.txt b
  has "SKIP terms scan: the terms list holds no term"
  rm -rf "$AIWP_WORKSPACE"
}

test_run_refuses_paths_outside_the_clone() {
  fixture
  run open "$B"
  run run "$W" -- touch marker ../../escape
  rc_is 1
  has "../../escape: a path outside the clone"
  [ ! -e "$C/marker" ] && [ ! -e "$R/tmp/escape" ]; check "nothing ran" $?
  run run "$W" -- cat "$BASE/terms.$CURRENT.txt"
  rc_is 1
  has "a path outside the clone"
  run run "$W" -- ls "~"
  rc_is 1
  has "under ~"
  run run "$W" -- ls ~/x
  rc_is 1
  run run "$W" -- git --git-dir=/etc status
  rc_is 1
  run run "$W" -- env "HOME=$BASE" true
  rc_is 1
  ln -s "$BASE" "$C/link"
  run run "$W" -- cat link/x
  rc_is 1
  has "link/x: a path outside the clone"
  rm "$C/link"
  run run "$W" -- git commit --no-verify -m x
  rc_is 1
  has "--no-verify would skip"
  run run "$W" -- git push --no-verif origin
  rc_is 1
  run run "$W" -- bash -c "git push --no-verify"
  rc_is 1
  run run "$W" -- git -c core.hooksPath=/dev/null commit -m x
  rc_is 1
  has "core.hooksPath would skip"
  run run "$W" -- git config core.hookspath x
  rc_is 1
  eq "hooks path unchanged" "$C/.git/hooks" "$(git -C "$C" config core.hooksPath)"
  run run nope -- true
  rc_is 2
  run run 2026-01-01-missing -- true
  rc_is 1
  run run "$W" true
  rc_is 2
}

test_run_accepts_paths_inside_the_clone() {
  fixture
  run open "$B"
  run run "$W" -- pwd
  rc_is 0
  eq "cwd" "$C" "$OUT"
  run run "$W/claude-cli-agents-workspace" -- cat ./README.md
  rc_is 0
  has "# sample"
  mkdir -p "$C/sub"
  run run "$W" -- cp /dev/null "$C/sub/../empty.txt"
  rc_is 0
  [ -f "$C/empty.txt" ]; check "absolute path inside" $?
  run run "$W" -- printf '%s\n' --opt=sub/x NAME=README.md origin/developer..HEAD
  rc_is 0
  has "--opt=sub/x"
  run run "$W" -- printenv AIWP_TERMS_FILE
  eq "a set AIWP_TERMS_FILE stays" "$BASE/terms.$CURRENT.txt" "$OUT"
  unset AIWP_TERMS_FILE
  mkdir -p "$AIWP_WORKSPACE/custom"
  printf 'acmecorp\n' >"$AIWP_WORKSPACE/custom/core-terms.txt"
  run run "$W" -- printenv AIWP_TERMS_FILE
  eq "the root's terms list exported" "$AIWP_WORKSPACE/custom/core-terms.txt" "$OUT"
  rm -rf "$AIWP_WORKSPACE"
}

test_status() {
  fixture
  run status
  has "no clone under tmp/work/"
  run open "$B"
  run status "$W"
  rc_is 0
  has "tmp/work/$W/claude-cli-agents-workspace  branch=$B ahead=0 not-pushed=0 uncommitted=0 in-developer=yes"
  commit_in a.txt one
  printf 'x\n' >"$C/dirty.txt"
  commit_in b.txt "acmecorp"
  run status
  has "branch=$B ahead=2 not-pushed=1 uncommitted=1 in-developer=no"
  run status bad
  rc_is 2
}

test_close_refuses_what_would_be_lost() {
  fixture
  run open "$B"
  commit_in a.txt one
  printf 'x\n' >"$C/dirty.txt"
  run close "$W"
  rc_is 1
  has "files changed and not committed"
  has "$B is not in origin/developer"
  rm "$C/dirty.txt"
  printf 'y\n' >>"$C/a.txt"
  git -C "$C" stash -q
  run close "$W"
  rc_is 1
  has "a stash"
  git -C "$C" stash drop -q
  commit_in b.txt "acmecorp"
  run close "$W"
  rc_is 1
  has "commits not on the remote"
  printf 'notes\n' >"$R/tmp/work/$W/notes.txt"
  run close "$W"
  has "notes.txt: not a clone made by open"
  [ -d "$C" ]; check "clone kept" $?
  run close bad
  rc_is 2
  run close "$W" --force
  rc_is 2
  run close 2026-01-01-missing
  rc_is 1
}

test_close_after_the_merge_deletes_the_remote_branch() {
  fixture
  run open "$B"
  commit_in a.txt one
  merge_into_developer
  run close "$W"
  rc_is 0
  has "deleted on origin: $B"
  has "closed: tmp/work/$W"
  [ ! -e "$R/tmp/work/$W" ]; check "folder removed" $?
  eq "remote branch deleted" none "$(remote_sha "heads/$B")"
  eq "developer kept" "$(git -C "$R" rev-parse developer)" "$(remote_sha developer)"
}

test_close_discard() {
  fixture
  run open "$B"
  commit_in a.txt one
  commit_in b.txt "acmecorp"
  local pushed
  pushed="$(remote_sha "heads/$B")"
  run close "$W" --discard
  rc_is 0
  has "discarded: tmp/work/$W"
  [ ! -e "$R/tmp/work/$W" ]; check "folder removed" $?
  eq "remote branch stays" "$pushed" "$(remote_sha "heads/$B")"
}

test_usage() {
  fixture
  run --help
  rc_is 0
  has "Usage: bash tests/caw-work.sh"
  has "open <type>/<slug>"
  has "run <work>[/<clone>] -- <command>..."
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
