#!/usr/bin/env bash
# Tests repo folders at any depth of projects/, history.sh --new-item and the custom layer items of init-repo.sh (POCs
# and tools of your own) in a throwaway root copy. Nothing may be written in the core (the root, tools/).
set -euo pipefail

export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE

# Prints the command reference.
usage() {
  cat <<'USAGE'
Usage: scripts/tests/test-projects-layout.sh [--help]

Tests repo folders at any depth of projects/, repos inside repos included, in init-repo.sh (and the marker it writes), history.sh
and scripts/lib/projects.sh, in a throwaway root copy. Exit codes: 0 all passed; 1 a test failed; 2 usage error.
USAGE
}

[ $# -eq 0 ] || case "$1" in
  --help | -h) usage; exit 0 ;;
  *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

real_scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/projects-layout.XXXXXX")" || exit 2
trap 'rm -rf "$tmp"' EXIT
passed=0
failed=0
RC=0
OUT=""

# Builds a fresh workspace root (no .git, as installed) with copies of the scripts under test and an empty projects
# index in the custom layer.
new_root() {
  R="$tmp/root.$1"
  mkdir -p "$R/scripts/lib" "$R/projects" "$R/tools"
  cp "$real_scripts/init-repo.sh" "$real_scripts/history.sh" "$R/scripts/"
  printf '0.1.0\n' >"$R/VERSION"
  cp "$real_scripts/lib/projects.sh" "$R/scripts/lib/"
  mkdir -p "$R/custom"
  printf '# Projects\n\n| Project | A | B |\n| --- | --- | --- |\n' >"$R/custom/projects.md"
  # As in an installed workspace: no repo at the root; custom/ is a repo of its own.
  git -C "$R/custom" init -q
}

# Runs a script of the current root, capturing exit code (RC) and output (OUT).
run() {
  local s="$1"
  shift
  RC=0
  OUT="$(cd "$R" && bash "scripts/$s.sh" "$@" 2>&1)" || RC=$?
}

# Checks the exit code and, when given, that the output holds a fixed text.
expect() {
  local label="$1" code="$2" text="${3:-}"
  if [ "$RC" -ne "$code" ]; then
    echo "FAIL: $label: expected exit $code, got $RC: $OUT"
    failed=$((failed + 1))
  elif [ -n "$text" ] && [[ "$OUT" != *"$text"* ]]; then
    echo "FAIL: $label: output lacks [$text]: $OUT"
    failed=$((failed + 1))
  else
    passed=$((passed + 1))
  fi
}

# Checks a path (-e) exists or is absent.
expect_path() {
  local label="$1" want="$2" path="$R/$3"
  if { [ "$want" = yes ] && [ -e "$path" ]; } || { [ "$want" = no ] && [ ! -e "$path" ]; }; then
    passed=$((passed + 1))
  else
    echo "FAIL: $label: expected $3 present=$want"
    failed=$((failed + 1))
  fi
}

# Makes a folder that looks like a git repo.
fake_repo() {
  mkdir -p "$R/$1/.git"
}

# init-repo.sh: --client forms.
test_init_client() {
  new_root a
  run init-repo --type project --client acme --name billing
  expect "client happy path" 0 "git init: projects/acme/billing"
  expect_path "nested repo" yes projects/acme/billing/.git
  expect_path "client not a repo" no projects/acme/.git
  expect_path "readme" yes projects/acme/billing/README.md
  if grep -q -F "| acme/billing |" "$R/custom/projects.md"; then passed=$((passed + 1)); else echo "FAIL: index row"; failed=$((failed + 1)); fi
  run init-repo --type project --client acme --name billing
  expect "idempotent" 0
  run init-repo --type project --client acme --name other
  expect "second project in client" 0
  git -C "$R/projects" init -q repo-client
  run init-repo --type project --client repo-client --name x
  expect "a client that is a repo holds a new repo" 0 "nested: projects/repo-client/x is a repo inside the repo projects/repo-client, which does not ignore it"
  expect_path "nested repo created" yes projects/repo-client/x/.git
  expect_row "nested row" repo-client/x
  local bad
  for bad in "../x" "a/b" "Acme" "a_b" "-a"; do
    run init-repo --type project --client "$bad" --name x
    expect "client [$bad]" 2 "kebab-case"
  done
  run init-repo --type project --client "" --name x
  expect "empty client" 2 "must not be empty"
  run init-repo --type poc --client acme --name x
  expect "client with poc" 2 "only with --type project"
}

# init-repo.sh: one-level forms and the client-folder guard.
test_init_one_level() {
  new_root b
  run init-repo --type project --name solo
  expect "one-level project" 0 "git init: projects/solo"
  expect_path "repo" yes projects/solo/.git
  run init-repo --type tool --name tl
  expect "tool" 0 "created: custom/tools/tl/README.md"
  expect_path "tool folder in the custom layer" yes custom/tools/tl/README.md
  expect_path "tool index in the custom layer" yes custom/tools/README.md
  expect_path "nothing in the core tools/" no tools/tl
  if grep -q -F "| tl | tool |" "$R/custom/tools/README.md"; then passed=$((passed + 1)); else echo "FAIL: tool row"; failed=$((failed + 1)); fi
  run init-repo --type poc --name pc
  expect "poc" 0 "created: custom/pocs/pc/README.md"
  expect_path "poc folder in the custom layer" yes custom/pocs/pc/README.md
  expect_path "no poc in tools" no tools/pc
  mkdir -p "$R/projects/acme"
  fake_repo projects/acme/child
  cp "$R/custom/projects.md" "$tmp/index.before"
  run init-repo --type project --name acme
  expect "a grouping folder becomes the root repo of its project" 0 "git init: projects/acme"
  expect_path "root repo" yes projects/acme/.git
  expect_path "its readme" yes projects/acme/README.md
  expect_path "the repo below stays" yes projects/acme/child/.git
  expect_row "root repo row" acme
  mkdir -p "$R/projects/plain"
  run init-repo --type project --name plain
  expect "plain folder without child repos" 0
}

# init-repo.sh: the README of a new project and of a new POC starts with the marker of the workspace VERSION; a tool's
# does not; no readable VERSION creates nothing.
test_init_writes_the_marker() {
  new_root marker
  printf '0.3.1\n' >"$R/VERSION"
  run init-repo --type project --name marked
  expect "project" 0
  run init-repo --type poc --name marked-poc
  expect "poc" 0
  run init-repo --type tool --name marked-tool
  expect "tool" 0
  local f
  for f in projects/marked/README.md custom/pocs/marked-poc/README.md; do
    if [ "$(head -n 1 "$R/$f")" = "<!-- AI-WORKSPACE-PROJECT 0.3.1 -->" ]; then passed=$((passed + 1)); else echo "FAIL: marker of $f"; failed=$((failed + 1)); fi
  done
  if grep -q '^## How to test$' "$R/projects/marked/README.md"; then passed=$((passed + 1)); else echo "FAIL: How to test"; failed=$((failed + 1)); fi
  if ! grep -q AI-WORKSPACE-PROJECT "$R/custom/tools/marked-tool/README.md"; then passed=$((passed + 1)); else echo "FAIL: marker in a tool"; failed=$((failed + 1)); fi
  printf 'next\n' >"$R/VERSION"
  run init-repo --type project --name unversioned
  expect "no VERSION" 1 "VERSION of the workspace is missing"
  expect_path "nothing created" no projects/unversioned
}

# A .git that is a file (linked worktree or submodule) counts as a repo in init-repo.sh and history.sh.
test_git_file() {
  new_root e
  mkdir -p "$R/projects/wt" "$R/projects/gc/child"
  echo "gitdir: /elsewhere" >"$R/projects/wt/.git"
  echo "gitdir: /elsewhere" >"$R/projects/gc/child/.git"
  run init-repo --type project --name wt
  expect "init_git keeps .git file" 0
  if [ "$(cat "$R/projects/wt/.git")" = "gitdir: /elsewhere" ] && [ ! -e "$R/projects/wt/.git/HEAD" ]; then passed=$((passed + 1)); else echo "FAIL: .git file replaced"; failed=$((failed + 1)); fi
  run history show --target projects/gc
  expect "history of a folder in no repo, a .git file below" 0 "no history"
  run init-repo --type project --name gc
  expect "a folder with a .git file below becomes a repo" 0 "git init: projects/gc"
  mkdir -p "$R/projects/wt/docs"
  run history show --target projects/wt/docs
  expect "history inside a repo with a .git file" 2 "inside the repo projects/wt"
  run init-repo --type project --client wt --name x
  expect "a repo inside a repo with a .git file" 0 "nested: projects/wt/x is a repo inside the repo projects/wt"
  if [ "$(cat "$R/projects/wt/.git")" = "gitdir: /elsewhere" ]; then passed=$((passed + 1)); else echo "FAIL: outer .git file changed"; failed=$((failed + 1)); fi
  run history show --target projects/wt/x
  expect "history of the repo inside" 0 "no history"
  mkdir -p "$R/projects/wt2/kid"
  echo "gitdir: /elsewhere" >"$R/projects/wt2/.git"
  echo "gitdir: /elsewhere" >"$R/projects/wt2/kid/.git"
  run init-repo --type project --name wt2
  expect "repo with .git file holding a child repo" 0
  run history show --target projects/wt2
  expect "history of repo with .git file holding a child repo" 0
}

# history.sh: valid and invalid targets, plus add, show and flush.
test_history() {
  new_root d
  fake_repo projects/repo1
  mkdir -p "$R/projects/repo1/docs" "$R/projects/acme/billing" "$R/projects/plain" "$R/projects/plain/sub" "$R/tools/tl" \
    "$R/custom/tools/mt" "$R/custom/pocs/pc"
  fake_repo projects/acme/billing
  local t
  for t in projects/repo1 projects/acme/billing custom/tools/mt custom/pocs/pc projects/plain projects/plain/sub projects/acme "projects/acme/"; do
    run history show --target "$t"
    expect "valid target [$t]" 0 "no history"
  done
  for t in . tools/tl custom/tools/mt/x custom custom/other/x projects/repo1/docs projects/missing projects/acme/missing "projects/a/b/c" "projects/Acme/x" "projects/../x" tools/tl/x other; do
    run history show --target "$t"
    expect "invalid target [$t]" 2
  done
  run history show --target projects/repo1/docs
  expect "subfolder message" 2 "inside the repo projects/repo1, not the root of a repo: use projects/repo1"
  run history add --target projects/acme/billing --request r --fact f --files x --author t
  expect "add nested" 0 "recorded: projects/acme/billing/history.txt"
  expect_path "history written" yes projects/acme/billing/history.txt
  run history show --target projects/acme/billing
  expect "show" 0 "REQUEST: r"
  run history add --target tools/tl --request r --fact f --files x --author t
  expect "the core tools/ is refused" 2 "custom/tools/<name>"
  expect_path "no history in the core tools/" no tools/tl/history.txt
  run history add --target . --request r --fact f --files x --author t
  expect "the root is refused" 2
  expect_path "no history at the root" no history.txt
  run history add --target custom/tools/mt --request r --fact f --files x --author t
  expect "a tool of yours keeps its history" 0 "recorded: custom/tools/mt/history.txt"
  run history flush
  expect "flush" 0 "flushed"
}

# history.sh add --new-item.
test_history_new_item() {
  new_root f
  run history add --target custom/tools/fresh --request r --fact f --files x --author t
  expect "without the flag a missing item is refused" 2 "target folder not found"
  expect_path "refusal creates nothing" no custom/tools/fresh
  run history add --target custom/tools/fresh --request r --fact f --files x --author t --new-item --dry-run
  expect "dry run" 0
  expect_path "dry run creates nothing" no custom/tools/fresh
  run history add --target custom/tools/fresh --request r --fact f --files x --author t --new-item
  expect "with the flag" 0 "recorded: custom/tools/fresh/history.txt"
  expect_path "folder created" yes custom/tools/fresh/history.txt
  run history add --target custom/tools/fresh --request r2 --fact f --files x --author t --new-item
  expect "existing item with the flag" 0 "recorded"
  run history add --target custom/pocs/newpoc --request r --fact f --files x --author t --new-item
  expect "a POC with the flag" 0 "recorded: custom/pocs/newpoc/history.txt"
  local t
  for t in . projects/newp projects/acme/newp tools/fresh custom/tools/Bad custom/tools/a/b; do
    run history add --target "$t" --request r --fact f --files x --author t --new-item
    expect "flag refused for [$t]" 2
  done
  expect_path "project target not created" no projects/newp
  expect_path "core tools/ target not created" no tools/fresh
}

# init-repo.sh: --checkout is gone (the workspace root is an installation, not a repo); a tool never lands in tools/.
test_init_no_checkout() {
  new_root h
  run init-repo --type tool --name tl --checkout "$tmp"
  expect "--checkout is unknown" 2 "unknown option"
  expect_path "nothing created" no custom/tools/tl
  rm -rf "$R/custom/.git"
  run init-repo --type tool --name tl
  expect "a tool needs the custom repo" 1 "custom/ is not a git repo of its own"
  expect_path "no tool written" no custom/tools
  expect_path "nothing in the core tools/" no tools/tl
}

# Checks the custom/projects.md of the current root holds a row for a relative path.
expect_row() {
  if grep -q -F "| $2 |" "$R/custom/projects.md"; then passed=$((passed + 1)); else echo "FAIL: $1: no row for $2"; failed=$((failed + 1)); fi
}

# A repo at any depth of projects/, its row with the relative path, and the flag validation of --parent and --client.
test_any_depth() {
  new_root i
  run init-repo --type project --name sample-client
  expect "a first-level folder becomes a repo" 0 "git init: projects/sample-client"
  expect_path "independent repo" yes projects/sample-client/.git
  expect_row "first level" sample-client
  run init-repo --type project --parent sample-group --name sample-service
  expect "second level with --parent" 0 "git init: projects/sample-group/sample-service"
  expect_path "repo" yes projects/sample-group/sample-service/.git
  expect_path "grouping folder stays plain" no projects/sample-group/.git
  expect_row "second level" sample-group/sample-service
  run init-repo --type project --parent sample-group/sample-area --name sample-service
  expect "third level" 0 "git init: projects/sample-group/sample-area/sample-service"
  expect_path "third-level repo" yes projects/sample-group/sample-area/sample-service/.git
  expect_row "third level" sample-group/sample-area/sample-service
  run init-repo --type project --parent sample-group/sample-area --name sample-service
  expect "idempotent at any depth" 0
  local bad
  for bad in "../x" "a//b" "a/" "/a" "Group" "a_b" "a/../b"; do
    run init-repo --type project --parent "$bad" --name x
    expect "parent [$bad]" 2 "kebab-case folders joined by /"
  done
  run init-repo --type project --parent "" --name x
  expect "empty parent" 2 "must not be empty"
  run init-repo --type project --parent a --client b --name x
  expect "parent and client together" 2 "not both"
  run init-repo --type poc --parent a --name x
  expect "parent with poc" 2 "--parent is valid only with --type project"
}

# Any layout: a repo inside a repo at the second and third level, a grouping folder that is no repo, a repo the parent
# ignores and one it does not; each is indexed, and a .git inside a hidden folder or node_modules is never a repo.
test_nested_repos() {
  new_root j
  run init-repo --type project --name sample-client
  printf 'ignored-child/\n' >>"$R/projects/sample-client/.gitignore"
  run init-repo --type project --parent sample-client --name nested
  expect "a repo inside a repo" 0 "git init: projects/sample-client/nested"
  expect "the parent does not ignore it" 0 "nested: projects/sample-client/nested is a repo inside the repo projects/sample-client, which does not ignore it"
  expect_path "nested repo" yes projects/sample-client/nested/.git
  expect_path "parent repo kept" yes projects/sample-client/.git
  expect_row "nested row" sample-client/nested
  run init-repo --type project --parent sample-client --name ignored-child
  expect "a repo the parent ignores" 0 "nested: projects/sample-client/ignored-child is a repo inside the repo projects/sample-client, which ignores it"
  run init-repo --type project --parent sample-client/nested/sub --name deep
  expect "three levels of repos, through a plain folder" 0 "inside the repo projects/sample-client/nested,"
  expect_path "third-level repo" yes projects/sample-client/nested/sub/deep/.git
  expect_path "the folder between stays plain" no projects/sample-client/nested/sub/.git
  expect_row "third-level row" sample-client/nested/sub/deep
  run init-repo --type project --parent sample-client/nested/sub --name deep
  expect "idempotent inside a repo" 0
  mkdir -p "$R/projects/g/a"
  fake_repo projects/g/a/s
  run init-repo --type project --parent g --name a
  expect "a grouping folder at the second level becomes a repo" 0 "git init: projects/g/a"
  expect_path "the repo below stays" yes projects/g/a/s/.git
  expect_path "the grouping folder above stays plain" no projects/g/.git
  if [[ "$OUT" == *nested:* ]]; then echo "FAIL: no repo above, yet a nested: line"; failed=$((failed + 1)); else passed=$((passed + 1)); fi
  fake_repo projects/plain/.cache/tool
  run init-repo --type project --name plain
  expect "a plain folder becomes a repo" 0 "git init: projects/plain"
  RC=0
  OUT="$(bash -c '. "$1/scripts/lib/projects.sh"; projects_repos "$1"' _ "$R" 2>&1)" || RC=$?
  local want
  want="$(printf '%s\n' projects/g/a projects/g/a/s projects/plain projects/sample-client projects/sample-client/ignored-child \
    projects/sample-client/nested projects/sample-client/nested/sub/deep)"
  if [ "$RC" -eq 0 ] && [ "$OUT" = "$want" ]; then passed=$((passed + 1)); else echo "FAIL: nested repos listed: [$OUT]"; failed=$((failed + 1)); fi
}

# History of a repo at the first and at the third level; folders inside it and grouping folders refused.
test_history_any_depth() {
  new_root k
  fake_repo projects/sample-client
  mkdir -p "$R/projects/sample-client/docs"
  fake_repo projects/g/a/s
  local t
  for t in projects/sample-client projects/g/a/s; do
    run history add --target "$t" --request r --fact f --files x --author t
    expect "history of [$t]" 0 "recorded: $t/history.txt"
  done
  for t in projects/sample-client/docs projects/g/a/s/x; do
    run history show --target "$t"
    expect "refused target [$t]" 2
  done
  run history show --target projects/g/a/s/x
  expect "inside a deep repo" 2 "inside the repo projects/g/a/s"
  for t in projects/g projects/g/a; do
    run history show --target "$t"
    expect "a grouping folder in no repo [$t]" 0 "no history"
  done
  # A repo inside a repo inside a repo: each keeps its own history; a folder belongs to the nearest repo.
  fake_repo projects/sample-client/inner
  fake_repo projects/sample-client/inner/core
  mkdir -p "$R/projects/sample-client/inner/core/src" "$R/projects/sample-client/inner/docs"
  for t in projects/sample-client/inner projects/sample-client/inner/core; do
    run history add --target "$t" --request r --fact f --files x --author t
    expect "history of the nested repo [$t]" 0 "recorded: $t/history.txt"
  done
  run history show --target projects/sample-client/inner/core/src
  expect "the nearest repo is named" 2 "inside the repo projects/sample-client/inner/core,"
  run history show --target projects/sample-client/inner/docs
  expect "the nearest repo, one level up" 2 "inside the repo projects/sample-client/inner,"
}

# The repo list of scripts/lib/projects.sh: any depth, sorted, repos inside repos included (15 levels too), never inside
# .git, a hidden folder, node_modules or a link.
test_projects_repos() {
  new_root l
  fake_repo projects/one
  fake_repo projects/one/vendor/inner
  fake_repo projects/one/node_modules/dep
  local deep=projects/d i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    deep="$deep/l$i"
    fake_repo "$deep"
  done
  fake_repo projects/g/two
  fake_repo projects/g/a/three
  fake_repo projects/.hidden/four
  mkdir -p "$R/projects/plain/empty"
  mkdir -p "$R/projects/wt"
  echo "gitdir: /elsewhere" >"$R/projects/wt/.git"
  ln -s "$R/projects/g" "$R/projects/link"
  ln -s "$R/projects/one" "$R/projects/link-to-repo"
  RC=0
  OUT="$(bash -c '. "$1/scripts/lib/projects.sh"; projects_repos "$1"' _ "$R" 2>&1)" || RC=$?
  local want
  want="$(printf '%s\n' projects/g/a/three projects/g/two projects/link-to-repo projects/one projects/one/vendor/inner projects/wt)"
  OUT="$(printf '%s\n' "$OUT" | grep -v '^projects/d/')"
  if [ "$RC" -eq 0 ] && [ "$OUT" = "$want" ]; then passed=$((passed + 1)); else echo "FAIL: projects_repos: [$OUT]"; failed=$((failed + 1)); fi
  OUT="$(bash -c '. "$1/scripts/lib/projects.sh"; projects_repos "$1"' _ "$R" | grep -c '^projects/d/')"
  if [ "$OUT" = 15 ]; then passed=$((passed + 1)); else echo "FAIL: 15 nested levels: $OUT"; failed=$((failed + 1)); fi
  OUT="$(bash -c '. "$1/scripts/lib/projects.sh"; projects_repo_of "$1" "$2"' _ "$R" "$deep/src/x")"
  if [ "$OUT" = "$deep" ]; then passed=$((passed + 1)); else echo "FAIL: nearest repo of a deep path: $OUT"; failed=$((failed + 1)); fi
  if ! bash -c '. "$1/scripts/lib/projects.sh"; projects_repo_of "$1" projects/g/a' _ "$R" >/dev/null; then
    passed=$((passed + 1)); else echo "FAIL: a grouping folder belongs to no repo"; failed=$((failed + 1)); fi
}

# init-repo.sh: a POC that custom/pocs/.gitignore excludes is refused, with nothing written.
test_init_ignored_poc() {
  new_root ignored
  mkdir -p "$R/custom/pocs"
  printf 'excluded-poc/\n' >"$R/custom/pocs/.gitignore"
  run init-repo --type poc --name excluded-poc
  expect "ignored poc refused" 1 "is ignored and outside this workspace"
  expect_path "no folder written" no custom/pocs/excluded-poc
  run init-repo --type poc --name kept-poc
  expect "a poc not ignored is created" 0
  expect_path "its folder" yes custom/pocs/kept-poc/README.md
}

# init-repo.sh: a POC needs the custom layer as a repo of its own; a plain custom/ folder would make git read the
# ignore rules of the workspace repo, which ignores custom/ whole.
test_init_poc_needs_the_custom_repo() {
  new_root pocrepo
  rm -rf "$R/custom/.git"
  run init-repo --type poc --name lone
  expect "custom/ not a repo" 1 "custom/ is not a git repo of its own"
  expect_path "nothing written" no custom/pocs
  rm -rf "$R/custom"
  run init-repo --type poc --name lone
  expect "no custom/" 1 "custom/ not found"
}

# init-repo.sh: a new index row goes right below the last row of the first table, text after it stays, and a second
# run with the same name adds nothing (never at the end of the file, after the closing paragraph).
test_init_index_row_below_table() {
  new_root index
  mkdir -p "$R/custom/tools"
  printf '# idx\n\n| Item | Type | Goal |\n| --- | --- | --- |\n| old | tool | x |\n\nClosing paragraph.\n' \
    >"$R/custom/tools/README.md"
  printf '# Projects\n\n| Name | A | B |\n| --- | --- | --- |\n| p0 | | |\n\n## Ports\n\n| Port | Owner |\n| --- | --- |\n| 1 | p0 |\n' \
    >"$R/custom/projects.md"
  run init-repo --type tool --name tl
  expect "tool indexed" 0 "indexed: custom/tools/README.md"
  run init-repo --type poc --name pc
  run init-repo --type tool --name tl
  expect "second run" 0
  if [[ "$OUT" == *indexed* ]]; then echo "FAIL: second run indexed again: $OUT"; failed=$((failed + 1)); else passed=$((passed + 1)); fi
  run init-repo --type project --name np
  expect "project indexed" 0 "indexed: custom/projects.md"
  local want
  want="$(printf '# idx\n\n| Item | Type | Goal |\n| --- | --- | --- |\n| old | tool | x |\n| tl | tool | |\n\nClosing paragraph.')"
  if grep -q -F "| pc | poc |" "$R/custom/pocs/README.md"; then passed=$((passed + 1)); else echo "FAIL: poc row in custom/pocs/README.md"; failed=$((failed + 1)); fi
  if [ "$(cat "$R/custom/tools/README.md")" = "$want" ]; then passed=$((passed + 1)); else
    echo "FAIL: tools index:"; cat "$R/custom/tools/README.md"; failed=$((failed + 1)); fi
  want="$(printf '# Projects\n\n| Name | A | B |\n| --- | --- | --- |\n| p0 | | |\n| np | | |\n\n## Ports\n\n| Port | Owner |\n| --- | --- |\n| 1 | p0 |')"
  if [ "$(cat "$R/custom/projects.md")" = "$want" ]; then passed=$((passed + 1)); else
    echo "FAIL: projects index:"; cat "$R/custom/projects.md"; failed=$((failed + 1)); fi
}

# init-repo.sh: without the custom layer the project is still created, and the missing row is said, never silent.
test_init_project_without_custom_layer() {
  new_root nocustom
  rm -rf "$R/custom"
  run init-repo --type project --name lone
  expect "project without custom layer" 0 "git init: projects/lone"
  expect "says the row is missing" 0 "attention: custom/projects.md not found: add the row of lone"
  expect_path "no custom folder created" no custom
}

test_init_client
test_init_one_level
test_history_new_item
test_init_no_checkout
test_init_writes_the_marker
test_history
test_git_file
test_any_depth
test_nested_repos
test_history_any_depth
test_projects_repos
test_init_ignored_poc
test_init_poc_needs_the_custom_repo
test_init_index_row_below_table
test_init_project_without_custom_layer
echo "projects-layout: passed=$passed failed=$failed"
[ "$failed" -eq 0 ]
