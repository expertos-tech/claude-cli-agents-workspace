#!/usr/bin/env bash
# Tests of scripts/aiwp-project-state.sh in a throwaway workspace: projects with and without the marker, on developer,
# main or with no commit, POCs, the workspace's own repository, and the migrations that make a project out of date.
# Run: bash scripts/tests/aiwp-project-state/test-aiwp-project-state.sh [--only <test_name>]
# shellcheck disable=SC2319  # check takes the status of the test right before it, on purpose
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../.." && pwd)"
BASE="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$BASE"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 LC_ALL=C
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
FAILED=0
COUNT=0
OUT=""
RC=0
CURRENT=""
R=""
MARK="<!-- AI-WORKSPACE-PROJECT"

check() { # description, status (0 = ok)
  if [ "$2" -ne 0 ]; then
    FAILED=$((FAILED + 1))
    echo "FAIL $CURRENT: $1 (rc=$RC out=[$OUT])"
  fi
}
has() { case "$OUT" in *"$1"*) check "has [$1]" 0 ;; *) check "missing [$1]" 1 ;; esac; }
hasnt() { case "$OUT" in *"$1"*) check "unexpected [$1]" 1 ;; *) check "absent [$1]" 0 ;; esac; }
rc_is() { [ "$RC" -eq "$1" ]; check "rc $1" $?; }

# A workspace on version $1 with the migrations named after it ("0.1.0 0.2.0"), an empty projects/ and a custom/ repo.
fixture() {
  R="$BASE/ws.$CURRENT"
  rm -rf "$R"
  mkdir -p "$R/scripts/lib" "$R/projects" "$R/migrations" "$R/custom/pocs"
  cp "$SCRIPTS/aiwp-project-state.sh" "$R/scripts/"
  cp "$SCRIPTS/lib/projects.sh" "$R/scripts/lib/"
  printf '%s\n' "$1" >"$R/VERSION"
  local v
  for v in $2; do printf '# %s\n' "$v" >"$R/migrations/$v.md"; done
  printf '# migrations\n' >"$R/migrations/README.md"
  git init -q -b main "$R/custom"
}

# A project at projects/$1 whose README.md is $2 (a literal "-" for no README), committed on main and developer.
project() {
  local dir="$R/projects/$1"
  git init -q -b main "$dir"
  if [ "$2" = - ]; then printf 'x\n' >"$dir/app.txt"; else printf '%s\n' "$2" >"$dir/README.md"; fi
  git -C "$dir" add -A
  git -C "$dir" commit -q -m base
  git -C "$dir" branch developer
  git -C "$dir" switch -q developer
}

state() {
  OUT="$(cd "$R" && bash scripts/aiwp-project-state.sh "$@" 2>&1)"
  RC=$?
}

test_marker_missing_and_readme_without_marker() {
  fixture 0.1.0 0.1.0
  project no-readme -
  project plain "# plain"
  project second-line "$(printf '# title\n%s 0.1.0 -->' "$MARK")"
  project malformed "$MARK v0.1.0 -->"
  state
  rc_is 0
  has "projects/no-readme: not a workspace project: no marker in README.md of developer; developer exists; checkout on developer"
  has "projects/plain: not a workspace project"
  has "projects/second-line: not a workspace project"
  has "projects/malformed: not a workspace project"
  state --porcelain plain
  has "$(printf 'project\tplain\tprojects/plain\tnone\t-\t0.1.0\t-\tdeveloper\tyes\tdeveloper')"
}

test_marker_equal_is_up_to_date() {
  fixture 0.1.0 0.1.0
  project app "$(printf '%s 0.1.0 -->\n# app' "$MARK")"
  state app
  rc_is 0
  has "projects/app: up to date (marker 0.1.0, workspace 0.1.0)"
}

test_older_marker_without_a_newer_migration_is_up_to_date() {
  fixture 0.3.0 0.1.0
  project app "$(printf '%s 0.1.0 -->\n# app' "$MARK")"
  state --porcelain app
  rc_is 0
  has "$(printf 'project\tapp\tprojects/app\tcurrent\t0.1.0\t0.3.0\t-')"
}

test_older_marker_with_newer_migrations_is_out_of_date() {
  fixture 0.4.0 "0.1.0 0.2.0 0.10.0 0.3.0"
  project app "$(printf '%s 0.1.0 -->\n# app' "$MARK")"
  state app
  rc_is 0
  has "projects/app: out of date: marker 0.1.0, workspace 0.4.0, pending migrations 0.2.0, 0.3.0"
  hasnt "0.10.0"
  state --porcelain app
  has "$(printf '\toutdated\t0.1.0\t0.4.0\t0.2.0,0.3.0\t')"
}

test_marker_above_the_workspace_is_newer() {
  fixture 0.1.0 0.1.0
  project app "$(printf '%s 0.2.0 -->' "$MARK")"
  state app
  has "marker 0.2.0 is newer than the workspace (0.1.0)"
}

test_the_marker_of_developer_counts_not_the_checkout() {
  fixture 0.1.0 0.1.0
  project app "# app"
  git -C "$R/projects/app" switch -q -c feature/x
  printf '%s 0.1.0 -->\n# app\n' "$MARK" >"$R/projects/app/README.md"
  git -C "$R/projects/app" commit -q -am "marker on a feature branch"
  state app
  has "projects/app: not a workspace project: no marker in README.md of developer; developer exists; checkout on feature/x"
  git -C "$R/projects/app" switch -q developer
  printf '%s 0.1.0 -->\n# app\n' "$MARK" >"$R/projects/app/README.md"
  state app
  has "projects/app: not a workspace project"
}

test_without_developer_main_counts_and_a_repo_with_no_commit_reads_the_folder() {
  fixture 0.1.0 0.1.0
  project app "$(printf '%s 0.1.0 -->' "$MARK")"
  git -C "$R/projects/app" switch -q main
  git -C "$R/projects/app" branch -q -D developer
  state app
  has "projects/app: up to date (marker 0.1.0, workspace 0.1.0); developer missing; checkout on main"
  git init -q -b main "$R/projects/fresh"
  printf '%s 0.1.0 -->\r\n# fresh\r\n' "$MARK" >"$R/projects/fresh/README.md"
  state --porcelain fresh
  has "$(printf '\tcurrent\t0.1.0\t0.1.0\t-\tfolder\tno\tmain')"
}

test_poc_reads_its_folder_readme() {
  fixture 0.2.0 "0.1.0 0.2.0"
  mkdir -p "$R/custom/pocs/cache-test" "$R/custom/pocs/old" "$R/custom/pocs/hidden"
  printf '%s 0.2.0 -->\n# cache-test (POC)\n' "$MARK" >"$R/custom/pocs/cache-test/README.md"
  printf '%s 0.1.0 -->\n' "$MARK" >"$R/custom/pocs/old/README.md"
  printf 'hidden/\n' >"$R/custom/pocs/.gitignore"
  state
  rc_is 0
  has "custom/pocs/cache-test: up to date (marker 0.2.0, workspace 0.2.0)"
  has "custom/pocs/old: out of date: marker 0.1.0, workspace 0.2.0, pending migrations 0.2.0"
  hasnt "custom/pocs/hidden"
  state --porcelain pocs/old
  has "$(printf 'poc\told\tcustom/pocs/old\toutdated\t0.1.0\t0.2.0\t0.2.0\tfile\t-\t-')"
  state custom/pocs/cache-test
  has "custom/pocs/cache-test: up to date"
  state custom/pocs/missing
  rc_is 1
  has "POC not found"
  state -- custom/pocs/hidden
  rc_is 1
  has "ignored by the custom layer"
  state hidden
  rc_is 1
  has "project not found: hidden"
}

test_the_workspace_own_repository_is_recognized() {
  fixture 0.1.0 0.1.0
  project claude-cli-agents-workspace "# Claude CLI Agents Workspace"
  project fork "# fork"
  mkdir -p "$R/projects/fork/workspace/scripts"
  printf '0.1.0\n' >"$R/projects/fork/workspace/VERSION"
  printf '#!/usr/bin/env bash\n' >"$R/projects/fork/workspace/scripts/aiwp-cmds.sh"
  git -C "$R/projects/fork" add -A
  git -C "$R/projects/fork" commit -q -m layout
  project renamed "# renamed"
  git -C "$R/projects/renamed" remote add origin "https://example.com/acme/claude-cli-agents-workspace.git"
  state
  has "projects/claude-cli-agents-workspace: the workspace's own repository: never normalized"
  has "projects/fork: the workspace's own repository"
  has "projects/renamed: the workspace's own repository"
  state --porcelain fork
  has "$(printf '\tworkspace\t-\t')"
}

test_names_paths_and_nested_repos() {
  fixture 0.1.0 0.1.0
  mkdir -p "$R/projects/acme"
  project acme/billing-web "# billing"
  project other/billing-web "$(printf '%s 0.1.0 -->' "$MARK")"
  mkdir -p "$R/custom/pocs/billing-web"
  state billing-web
  rc_is 0
  has "projects/acme/billing-web: not a workspace project"
  has "projects/other/billing-web: up to date"
  has "custom/pocs/billing-web: not a workspace project: no marker in custom/pocs/billing-web/README.md"
  state projects/acme/billing-web/
  rc_is 0
  has "projects/acme/billing-web: not a workspace project"
  hasnt "projects/other"
  state nope
  rc_is 1
  has "project not found: nope"
  state ../escape
  rc_is 1
  state acme
  rc_is 1
}

# A project root repo with repos inside it, at the second and third level: each is listed and named at its depth.
test_repos_inside_repos_are_listed_at_their_depth() {
  fixture 0.1.0 0.1.0
  project billing "$(printf '%s 0.1.0 -->' "$MARK")"
  printf 'billing-web/\n' >"$R/projects/billing/.gitignore"
  project billing/billing-api "# api"
  project billing/billing-web "$(printf '%s 0.1.0 -->' "$MARK")"
  mkdir -p "$R/projects/billing/billing-api/libs"
  project billing/billing-api/libs/core "# core"
  state
  rc_is 0
  has "projects/billing: up to date"
  has "projects/billing/billing-api: not a workspace project"
  has "projects/billing/billing-web: up to date"
  has "projects/billing/billing-api/libs/core: not a workspace project"
  state --porcelain billing/billing-api/libs/core
  rc_is 0
  has "$(printf 'project\tcore\tprojects/billing/billing-api/libs/core\tnone')"
  state billing-web
  rc_is 0
  has "projects/billing/billing-web: up to date"
  state billing/billing-api/libs
  rc_is 1
}

test_usage_and_a_broken_version() {
  fixture 0.1.0 0.1.0
  state --help
  rc_is 0
  has "AI-WORKSPACE-PROJECT"
  state --bogus
  rc_is 2
  printf 'next\n' >"$R/VERSION"
  state
  rc_is 1
  has "VERSION of the workspace is missing or not x.y.z"
}

test_it_never_writes() {
  fixture 0.1.0 0.1.0
  project app "# app"
  local before after
  before="$(cd "$R" && find . -path ./custom/.git -prune -o -newer "$R/VERSION" -print | sort; ls -la "$R/projects/app/.git")"
  sleep 1
  state
  state --porcelain app
  after="$(cd "$R" && find . -path ./custom/.git -prune -o -newer "$R/VERSION" -print | sort; ls -la "$R/projects/app/.git")"
  [ "$before" = "$after" ]; check "nothing written in the workspace or the repo" $?
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
