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
trap 'real_cleanup; rm -rf "$BASE"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE AIWP_TERMS_FILE
# No terms list of this machine reaches the tests: each scenario sets its own.
export AIWP_WORKSPACE="$BASE/no-workspace"
# A fake docker first on PATH for every test (REAL_PATH keeps the machine's): it records each call in DOCKER_LOG and
# answers from $DSTUB: containers/<project> (the compose folder; the container is c-<project>, web 80/tcp on host port
# 61500), res/<kind>.<project> (the lines of docker <kind> ls for that label), config.json (docker compose config).
REAL_PATH="$PATH"
mkdir -p "$BASE/bin"
export DOCKER_LOG="$BASE/docker.log" DSTUB="$BASE/dstub"
cat >"$BASE/bin/docker" <<'STUB'
#!/usr/bin/env bash
echo "docker $*" >>"$DOCKER_LOG"
label="com.docker.compose.project"
case "$*" in
  "version "*) [ -z "${DOCKER_DOWN:-}" ] || exit 1; echo 28.0 ;;
  "ps -aq --filter label=$label="*) p="${4##*=}"; [ ! -f "$DSTUB/containers/$p" ] || echo "c-$p" ;;
  "ps -aq --filter label=$label") for f in "$DSTUB"/containers/*; do [ -f "$f" ] && echo "c-${f##*/}"; done ;;
  "inspect "*)
    shift
    sep=""
    printf '['
    for id in "$@"; do
      p="${id#c-}"
      printf '%s{"Id":"%s","Config":{"Labels":{"%s":"%s","%s.working_dir":"%s","com.docker.compose.service":"web"}},"State":{"Running":true},"NetworkSettings":{"Ports":{"80/tcp":[{"HostIp":"0.0.0.0","HostPort":"61500"}]}}}' \
        "$sep" "$id" "$label" "$p" "$label" "$(cat "$DSTUB/containers/$p")"
      sep=","
    done
    printf ']\n'
    ;;
  "network ls --filter label=$label="* | "volume ls --filter label=$label="* | "image ls --filter label=$label="*)
    p="${4#label="$label"=}"
    [ ! -f "$DSTUB/res/$1.$p" ] || cat "$DSTUB/res/$1.$p"
    ;;
  compose*" config --format json"*) cat "$DSTUB/config.json" ;;
  compose*" up -d --build"*) echo "cwd $PWD" >>"$DOCKER_LOG" ;;
esac
exit 0
STUB
chmod +x "$BASE/bin/docker"
export PATH="$BASE/bin:$PATH"
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
  mkdir -p "$R/workspace/scripts"
  cp "$HERE/../workspace/scripts/agent-copy.py" "$R/workspace/scripts/agent-copy.py"
  rm -rf "$DSTUB" "$AIWP_WORKSPACE"
  mkdir -p "$DSTUB/containers" "$DSTUB/res"
  : >"$DOCKER_LOG"
  unset DOCKER_DOWN CAW_TEST_INSTALL INSTALL_RESULT
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
  has "bash tests/caw-work.sh push $W/claude-cli-agents-workspace"
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
  in_clone push -q --force-with-lease origin "HEAD:refs/heads/$B"
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
  hasnt "HEAD is not on"
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
  in_clone push -q origin HEAD:developer
  rc_not 0
  has "never pushes developer"
  eq "developer unchanged" "$dev" "$(remote_sha developer)"
  in_clone push -q origin HEAD:main
  rc_not 0
  has "never pushes main"
  eq "main unchanged" "$main" "$(remote_sha main)"
  git -C "$C" tag v9.9.9
  in_clone push -q origin v9.9.9
  rc_not 0
  has "never pushes a tag"
  eq "no tag on the remote" none "$(remote_sha tags/v9.9.9)"
  in_clone push -q origin HEAD:refs/notes/x
  rc_not 0
  has "branches only"
  # Another branch: pushed after the scan, and its deletion passes.
  in_clone push -q origin HEAD:refs/heads/chore/side
  rc_is 0
  eq "side branch pushed" "$(git -C "$C" rev-parse HEAD)" "$(remote_sha heads/chore/side)"
  in_clone push -q origin --delete chore/side
  rc_is 0
  eq "side branch deleted" none "$(remote_sha heads/chore/side)"
  in_clone push -q origin --delete developer
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

test_run_refuses_ways_around_the_hooks() {
  fixture
  run open "$B"
  local dev main
  dev="$(remote_sha developer)"
  main="$(remote_sha main)"
  # A repository with no hooks inside the clone.
  git -C "$C" clone -q "$REMOTE" sub
  run run "$W" -- git --git-dir=sub/.git push "$REMOTE" HEAD:refs/heads/developer
  rc_is 1
  has "run uses the clone itself"
  run run "$W" -- env GIT_DIR=sub/.git git push origin HEAD:refs/heads/main
  rc_is 1
  has "a GIT_* variable"
  has "env: a wrapper"
  run run "$W" -- bash -c 'git push --no-veri origin HEAD:refs/heads/developer'
  rc_is 1
  mkdir -p "$BASE/home"
  # shellcheck disable=SC2016  # $HOME is for the inner shell, which must never run
  HOME="$BASE/home" run run "$W" -- bash -c 'touch "$HOME/x"'
  rc_is 1
  [ ! -e "$BASE/home/x" ]; check "nothing touched outside the clone" $?
  has "gives the interpreter its code"
  eq "developer unchanged" "$dev" "$(remote_sha developer)"
  eq "main unchanged" "$main" "$(remote_sha main)"
  local args
  while IFS= read -r args; do
    # shellcheck disable=SC2086  # each line is a command, split on purpose
    run run "$W" -- $args </dev/null
    [ "$RC" -eq 1 ]; check "refused: $args" $?
  done <<'LIST'
git push origin
git push -q origin HEAD:refs/heads/feat/sample-change
git send-pack origin
git http-push x
git -C sub status
git -Csub status
git -c user.name=x status
git -cuser.name=x status
git --work-tree=sub status
git --work-tree sub status
git --exec-path=bin status
git --config-env=core.editor=EDITOR status
git --namespace=x log
git --super-prefix=x status
git config user.name x
git config --unset caw.branch
git config alias.p push
git rebase -x true HEAD
git rebase --exec=true HEAD
git submodule foreach true
git bisect run true
git filter-branch HEAD
printf %s GIT_DIR=sub/.git
printf %s GIT_CONFIG_COUNT=1
env true
xargs true
nohup true
timeout 5 true
nice true
sudo true
parallel true
command true
stdbuf -o0 true
setsid true
find . -exec true ;
find . -execdir true ;
find . -ok true ;
eval true
source README.md
. README.md
bash -c true
bash -ec true
bash -lc true
sh -c true
zsh -c true
dash -c true
ksh -c true
fish -c true
fish --command true
bash
bash -s
bash -i README.md
bash --rcfile README.md
bash missing.sh
bash -- missing.sh
python3 -c pass
python3 -Ic pass
python -c pass
python3.12 -c pass
python3
python3 -
python3 -i s.py
python3 missing.py
node -e 1
node --eval=1
node --eval 1
node -p 1
node
deno eval 1
deno repl
bun -e 1
perl -e 1
perl -ne 1
ruby -E 1
ruby -e 1
php -r 1
php
LIST
}

test_run_allows_scripts_and_git_in_the_clone() {
  fixture
  run open "$B"
  printf 'echo ok-sh\n' >"$C/ok.sh"
  printf 'print("ok-py")\n' >"$C/s.py"
  run run "$W" -- bash ok.sh
  rc_is 0
  eq "bash script" ok-sh "$OUT"
  run run "$W" -- bash -euo pipefail ok.sh
  eq "bash with options" ok-sh "$OUT"
  run run "$W" -- sh ./ok.sh
  eq "sh script" ok-sh "$OUT"
  run run "$W" -- python3 s.py
  eq "python script" ok-py "$OUT"
  run run "$W" -- python3 -I s.py
  eq "python -I script" ok-py "$OUT"
  run run "$W" -- python3 -m platform
  rc_is 0
  run run "$W" -- bash tests/caw-work.sh --help
  rc_is 0
  has "Usage: bash tests/caw-work.sh"
  run run "$W" -- find . -name ok.sh
  rc_is 0
  has "./ok.sh"
  run run "$W" -- git status --short
  rc_is 0
  has "ok.sh"
  run run "$W" -- git add ok.sh s.py
  rc_is 0
  run run "$W" -- git commit -q -m "add the scripts"
  rc_is 0
  has "caw-work: pushed $B"
  eq "commit through run pushed" "$(git -C "$C" rev-parse HEAD)" "$(remote_sha "heads/$B")"
  run run "$W" -- git log --oneline -1
  has "add the scripts"
  run run "$W" -- git --no-pager log -1 --format=%s
  eq "git --no-pager" "add the scripts" "$OUT"
  run run "$W" -- git config --get caw.branch
  eq "git config read" "$B" "$OUT"
  run run "$W" -- git config caw.branch
  eq "git config single key" "$B" "$OUT"
  run run "$W" -- git commit -c HEAD --allow-empty -q
  rc_is 0
}

test_push_command() {
  fixture
  run open "$B"
  export AIWP_TERMS_FILE="$BASE/missing.txt"
  commit_in a.txt one
  has "NOT pushed"
  export AIWP_TERMS_FILE="$BASE/terms.$CURRENT.txt"
  run push "$W"
  rc_is 0
  has "caw-work: pushed $B"
  eq "pushed by push" "$(git -C "$C" rev-parse HEAD)" "$(remote_sha "heads/$B")"
  run push "$W/claude-cli-agents-workspace"
  rc_is 0
  commit_in b.txt acmecorp
  local pushed
  pushed="$(remote_sha "heads/$B")"
  run push "$W"
  rc_is 1
  has "refused: the lines above hold a company term"
  eq "a term is not pushed" "$pushed" "$(remote_sha "heads/$B")"
  git -C "$C" switch -q -c other
  run push "$W"
  rc_is 1
  has "HEAD is not on $B"
  run push
  rc_is 2
  run push bad
  rc_is 2
  run push 2026-01-01-missing
  rc_is 1
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

# Writes a tool of the clone: workspace/tools/<id>/compose.yaml (with $2 as its text) and an app file.
tool_in_clone() {
  mkdir -p "$C/workspace/tools/$1"
  printf '%s\n' "$2" >"$C/workspace/tools/$1/compose.yaml"
  printf 'print(1)\n' >"$C/workspace/tools/$1/app.py"
}

test_publish_routes_by_what_changed() {
  fixture
  run open "$B"
  run publish "$W"
  rc_is 0
  has "nothing to publish"
  mkdir -p "$C/docs" "$C/workspace/tools/acme-tool"
  printf '# doc\n' >"$C/docs/guide.md"
  printf '# tool\n' >"$C/workspace/tools/acme-tool/README.md"
  run publish "$W"
  rc_is 0
  has "nothing to publish"
  hasnt "test installation"
  # A tool: its copy in its own group, with the installed workspace's configuration.
  mkdir -p "$AIWP_WORKSPACE/custom/env" "$AIWP_WORKSPACE/custom/config/acme-tool"
  printf 'ACME_KEY=k\n' >"$AIWP_WORKSPACE/custom/env/acme-tool.env"
  tool_in_clone acme-tool 'services: {}'
  printf '{"name":"acme-tool","services":{"web":{"build":{"context":"."},"container_name":"acme-tool","ports":[{"target":80,"published":"8080","protocol":"tcp"}],"volumes":[{"type":"bind","source":"%s/workspace/custom/config/acme-tool/users.json","target":"/c","read_only":true}]}}}\n' "$C" >"$DSTUB/config.json"
  local g ov
  g="$(printf 'agent_%s-sample-change--acme-tool' "$(date +%m%d)")"
  ov="$R/tmp/work/$W/agent-acme-tool.compose.yaml"
  run publish "$W"
  rc_is 0
  has "copy: workspace/tools/acme-tool"
  has "group: $g"
  has "published: $g"
  has "port: web 80/tcp -> 6"
  hasnt "test installation"
  grep -q "^docker compose -p $g -f compose.yaml -f $ov --env-file $AIWP_WORKSPACE/custom/env/acme-tool.env up -d --build$" "$DOCKER_LOG"
  check "the tool's copy in its group, with the installed env file" $?
  grep -qx "cwd $C/workspace/tools/acme-tool" "$DOCKER_LOG"; check "from the clone's tool" $?
  grep -q "source: \"$AIWP_WORKSPACE/custom/config/acme-tool/users.json\"" "$ov"; check "configuration bind from the installed custom/" $?
  grep -q 'container_name: !reset null' "$ov"; check "fixed name dropped" $?
  # A machine tool with no compose file: nothing to publish for it.
  mkdir -p "$C/workspace/tools/acme-console"
  printf 'x\n' >"$C/workspace/tools/acme-console/main.go"
  run publish "$W"
  has "nothing to publish for workspace/tools/acme-console: it has no compose.yaml"
  # A script, a rule or the installer: a test installation.
  rm -rf "$C/workspace/tools"
  mkdir -p "$C/workspace/scripts"
  printf 'echo\n' >"$C/workspace/scripts/x.sh"
  cat >"$BASE/test-install.$CURRENT" <<'STUB'
#!/usr/bin/env bash
echo "test installation: $1/tmp/test-install/1"
echo "PASS manifest"
echo "workspace: $1/tmp/test-install/1/workspace"
echo "result: ${INSTALL_RESULT:-PASS}"
[ "${INSTALL_RESULT:-PASS}" = PASS ]
STUB
  chmod +x "$BASE/test-install.$CURRENT"
  export CAW_TEST_INSTALL="$BASE/test-install.$CURRENT"
  run publish "$W"
  rc_is 0
  has "  workspace: $C/tmp/test-install/1/workspace"
  has "  result: PASS"
  hasnt "PASS manifest"
  has "published: test installation"
  [ -f "$R/tmp/work/$W/agent-test-install.log" ]; check "log kept beside the clone" $?
  INSTALL_RESULT=FAIL run publish "$W"
  rc_is 1
  has "error: the test installation failed"
  rm -rf "$C/workspace/scripts"
  mkdir -p "$C/.claude/rules"
  printf 'x\n' >"$C/.claude/rules/x.md"
  run publish "$W"
  has "published: test installation"
  unset CAW_TEST_INSTALL
  run publish
  rc_is 2
  run publish 2026-01-01-missing
  rc_is 1
}

test_status_and_close_with_copy_groups() {
  fixture
  run open "$B"
  local g
  g="$(printf 'agent_%s-sample-change--acme-tool' "$(date +%m%d)")"
  echo "$C/workspace/tools/acme-tool" >"$DSTUB/containers/$g"
  echo "/elsewhere" >"$DSTUB/containers/agent_0101-other"
  echo "$C" >"$DSTUB/containers/claude-cli-agents-workspace"
  printf 'name: "%s"\n' "${g%-acme-tool}-down" >"$R/tmp/work/$W/agent-down.compose.yaml"
  run status "$W"
  rc_is 0
  has "copy: $g running 1/1 ports=web:80->61500"
  has "copy: ${g%-acme-tool}-down down ports=-"
  hasnt "agent_0101-other"
  DOCKER_DOWN=1 run status
  rc_is 0
  has "Docker: not reachable"
  # A refused close destroys nothing.
  printf 'x\n' >"$C/dirty.txt"
  run close "$W"
  rc_is 1
  hasnt "agent-down.compose.yaml"
  ! grep -q '^docker \(rm\|network rm\|volume rm\|image rm\)' "$DOCKER_LOG"; check "nothing destroyed" $?
  printf 'sha256:b %s-web:latest\n' "$g" >"$DSTUB/res/image.$g"
  run close "$W" --discard
  rc_is 0
  has "destroyed: $g (1 containers, 0 networks, 0 volumes, 1 images)"
  has "nothing to destroy: ${g%-acme-tool}-down"
  has "kept: claude-cli-agents-workspace (not a copy group)"
  ! grep -q 'rm.*\(c-claude-cli-agents-workspace\|agent_0101\)' "$DOCKER_LOG"; check "another project removed" $?
  [ ! -e "$R/tmp/work/$W" ]; check "folder removed" $?
}

# Real Docker, only names this test generates (the tool acme-t<random> and its agent_ group): a tool of the clone
# published as a copy, its configuration bound from the installed workspace, then destroyed by close. Skipped when
# Docker is not reachable or the base image is not on this machine (a test never downloads one).
REAL_GROUP=""
real_cleanup() {
  [ -n "$REAL_GROUP" ] || return 0
  PATH="$REAL_PATH" python3 -I "$HERE/../workspace/scripts/agent-copy.py" destroy "$REAL_GROUP" >/dev/null 2>&1
  REAL_GROUP=""
}

test_real_docker_publish_of_a_tool() {
  local image="${AIWP_TEST_BASE_IMAGE:-alpine:3.20}" rnd tool g id
  if ! PATH="$REAL_PATH" docker version >/dev/null 2>&1 || ! PATH="$REAL_PATH" docker image inspect "$image" >/dev/null 2>&1; then
    echo "SKIP $CURRENT: Docker not reachable or $image not on this machine"
    return 0
  fi
  fixture
  run open "$B"
  rnd="$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
  tool="acme-t$rnd"
  g="agent_$(date +%m%d)-sample-change--$tool"
  REAL_GROUP="$g"
  tool_in_clone "$tool" "name: acmet$rnd
services:
  web:
    build: .
    image: acmet$rnd-web:latest
    container_name: acmet$rnd-web
    ports: [\"127.0.0.1:8080:80\"]
    volumes:
      - \${ACME_CFG:-../../custom/config/$tool/cfg.txt}:/cfg.txt:ro"
  printf 'FROM %s\nCMD ["sh", "-c", "sleep 600"]\n' "$image" >"$C/workspace/tools/$tool/Dockerfile"
  mkdir -p "$AIWP_WORKSPACE/custom/config/$tool"
  printf 'from-installed\n' >"$AIWP_WORKSPACE/custom/config/$tool/cfg.txt"
  OUT="$(cd "$R" && PATH="$REAL_PATH" bash "$R/tests/caw-work.sh" publish "$W" 2>&1)"
  RC=$?
  rc_is 0
  has "published: $g"
  id="$(PATH="$REAL_PATH" docker ps -q --filter "label=com.docker.compose.project=$g")"
  [ -n "$id" ]; check "the copy runs" $?
  eq "configuration from the installed workspace" from-installed "$(PATH="$REAL_PATH" docker exec "$id" cat /cfg.txt 2>&1)"
  PATH="$REAL_PATH" docker exec "$id" env | grep -q '^AGENT_PORT_WEB_80=6'; check "port variable in the container" $?
  OUT="$(cd "$R" && PATH="$REAL_PATH" bash "$R/tests/caw-work.sh" status "$W" 2>&1)"
  has "copy: $g running 1/1 ports=web:80->6"
  OUT="$(cd "$R" && PATH="$REAL_PATH" bash "$R/tests/caw-work.sh" close "$W" --discard 2>&1)"
  RC=$?
  rc_is 0
  has "destroyed: $g"
  eq "group gone" "" "$(PATH="$REAL_PATH" docker ps -aq --filter "label=com.docker.compose.project=$g")$(PATH="$REAL_PATH" docker image ls -q --filter "label=com.docker.compose.project=$g")$(PATH="$REAL_PATH" docker network ls -q --filter "label=com.docker.compose.project=$g")"
  eq "no image of the tool's own name" "" "$(PATH="$REAL_PATH" docker image ls -q "acmet$rnd-web")"
  real_cleanup
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
