#!/usr/bin/env bash
# Tests of scripts/check-workspace.sh (AC-24) and of scripts/validate.sh: the tmp/ and --path handling (AC-25, F8) and
# the tracked .env and local.settings.json files of the secrets check (test_secrets_*).
# Both run in a throwaway copy of the tree: validate.sh and the suites are stubbed to record their arguments,
# and docker is a fake on PATH. The real workspace is never touched.
# Run: bash scripts/tests/check-workspace/test-check-workspace.sh
# CHECK_WORKSPACE_TEST_TMP fixes the folder of the throwaway tree (kcov needs one stable path to merge hits).
set -uo pipefail
# Under kcov only the scripts under test are traced; the harness is not (see scripts/tests/lib/lib.sh).
{ set +x; } 2>/dev/null

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_SCRIPTS="$(cd "$HERE/../.." && pwd)"
unset CLAUDE_CODE_SESSION_ID GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE STUB_FAIL_SUITE STUB_VALIDATE_RC AIWP_TERMS_FILE
# The ledger has its own scenarios (test_ledger_*), which turn it on; the rest judge one run at a time.
export CHECK_LEDGER_DISABLE=1
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
if [ -n "${CHECK_WORKSPACE_TEST_TMP:-}" ]; then
  mkdir -p "$CHECK_WORKSPACE_TEST_TMP"
  BASE_DIR="$(cd "$CHECK_WORKSPACE_TEST_TMP" && pwd -P)"
else
  BASE_DIR="$(cd "$(mktemp -d)" && pwd -P)"
fi
trap 'rm -rf "$BASE_DIR"' EXIT
TREE="$BASE_DIR/work tree"
STUB_LOG="$BASE_DIR/stub.log"
FAKE_BIN="$BASE_DIR/fakebin"
export STUB_LOG
# The suites the gate must run, in order. The tree stubs exactly these.
EXPECTED_SUITES="tests/test-projects-layout.sh tests/check-workspace/test-check-workspace.sh tests/guard-subagent-model/test-guard-subagent-model.sh tests/guard-bash/test-guard-bash.sh tests/setup-claude/test-setup-claude.sh tests/heavy-run/test-heavy-run.sh tests/single-agent/test-single-agent.sh tests/aiwp-cmds/test-aiwp-cmds.sh tests/aiwp-gate/test-aiwp-gate.sh tests/aiwp-project-state/test-aiwp-project-state.sh tests/aiwp/test-aiwp.sh tests/sync-env/test-sync-env.sh"
# How many suites the gate has: a new suite changes one line of this file, not every count below.
SUITE_COUNT="$(echo "$EXPECTED_SUITES" | wc -w | tr -d ' ')"
PASS=0
FAILED=0
SKIPPED=0
OUT=""
RC=0
CURRENT=""

# kcov 43 loses track of quotes in traced values; tracing one balanced quote resynchronises it.
kcov_resync() {
  [ -n "${KCOV_BASH_XTRACEFD:-}" ] || return 0
  (
    set -x
    : "it's"
  )
}

# Records one assertion: $1 message, $2 status (0 = passed).
check() {
  if [ "$2" -eq 0 ]; then
    PASS=$((PASS + 1))
  else
    FAILED=$((FAILED + 1))
    echo "FAIL $CURRENT: $1 (rc=$RC out=[$OUT])"
  fi
}
eq() { [ "$2" = "$3" ]; check "$1: expected [$2] got [$3]" $?; }
has() { case "$OUT" in *"$2"*) check "$1" 0 ;; *) check "$1: missing [$2]" 1 ;; esac; }
lacks() { case "$OUT" in *"$2"*) check "$1: unexpected [$2]" 1 ;; *) check "$1" 0 ;; esac; }
rc_is() { [ "$RC" -eq "$1" ]; check "exit code $1" $?; }
ok() { local d="$1"; shift; "$@"; check "$d" $?; }
# Counts the lines of the stub log that start with $1 followed by a space.
log_count() { grep -c "^$1 " "$STUB_LOG" || true; }
# Prints the argument line of the last validate stub call. --files goes last and holds a temporary path: listed_files reads it.
validate_args() { grep '^validate ' "$STUB_LOG" | tail -n 1 | sed -e 's/^validate //' -e 's/ --files .*$//'; }
# Prints the --files list of the last validate stub call.
listed_files() { cat "$STUB_LOG.files" 2>/dev/null; }
# Prints a skipped test in the output and counts it: nothing is skipped silently.
skip() { SKIPPED=$((SKIPPED + 1)); echo "SKIP $CURRENT: $1"; }

# Fresh throwaway workspace tree on branch feature (cut from main), with validate.sh and every suite stubbed.
new_tree() {
  CURRENT="$1"
  local suite
  rm -rf "$TREE"
  mkdir -p "$TREE/scripts" "$TREE/docs/decisions" "$TREE/rules/agents"
  : >"$STUB_LOG"
  rm -f "$STUB_LOG.files"
  cp "$REAL_SCRIPTS/check-workspace.sh" "$TREE/scripts/check-workspace.sh"
  cp "$REAL_SCRIPTS/check-ledger.sh" "$TREE/scripts/check-ledger.sh"
  cat >"$TREE/scripts/validate.sh" <<'STUB'
#!/usr/bin/env bash
echo "validate $*" >>"$STUB_LOG"
while [ $# -gt 0 ]; do
  if [ "$1" = --files ]; then cp "$2" "$STUB_LOG.files"; fi
  shift
done
echo "stub validate output"
exit "${STUB_VALIDATE_RC:-0}"
STUB
  for suite in $EXPECTED_SUITES; do
    mkdir -p "$TREE/scripts/$(dirname "$suite")"
    cat >"$TREE/scripts/$suite" <<STUB
#!/usr/bin/env bash
echo "suite $suite" >>"\$STUB_LOG"
echo "stub suite output $suite"
[ "\${STUB_FAIL_SUITE:-}" != "$suite" ]
STUB
  done
  printf '# Decisions\n' >"$TREE/docs/decisions/README.md"
  printf '0001 first\n' >"$TREE/docs/decisions/0001-first.md"
  git -C "$TREE" init -q -b main
  git -C "$TREE" add -A
  git -C "$TREE" commit -q -m init
  git -C "$TREE" switch -q -c feature
}

# Writes a file (creating folders) without committing it.
put() { # path content
  mkdir -p "$TREE/$(dirname "$1")"
  printf '%s\n' "${2:-x}" >"$TREE/$1"
}

# Commits everything pending on the current branch.
commit_all() {
  git -C "$TREE" add -A
  git -C "$TREE" commit -q -m "${1:-change}"
}

# Runs the gate copy of the tree with the cwd in the tree, every check and every suite (--all).
cw() {
  OUT="$(cd "$TREE" && bash "$TREE/scripts/check-workspace.sh" --all "$@" 2>&1)"
  RC=$?
  kcov_resync
}

# Table row: a change gives exactly this validate --only list.
expect_list() { # label expected path...
  local label="$1" expected="$2"
  shift 2
  new_tree "list $label"
  local p
  for p in "$@"; do put "$p"; done
  cw
  rc_is 0
  eq "validate list for $label" "--only $expected" "$(validate_args)"
}

# ---------------------------------------------------------------- check-workspace.sh

test_AC24_usage() {
  new_tree usage
  cw --help
  rc_is 0
  has "help names the exit codes" "Exit codes: 0 every check passed; 1 a check failed; 2 usage error."
  has "help names the base default" "Default: main"
  cw -h
  rc_is 0
  cw --bogus
  rc_is 2
  has "unknown option" "unknown option: --bogus"
  cw --base
  rc_is 2
  has "--base needs a value" "--base needs a value"
  cw --base ""
  rc_is 2
  cw --base nope
  rc_is 2
  has "base must exist" "base not found: nope"
  cw --base main
  rc_is 0
  cw --verbose
  rc_is 0
}

test_AC24_not_a_checkout() {
  CURRENT="not a checkout"
  local plain="$BASE_DIR/plain"
  rm -rf "$plain"
  mkdir -p "$plain/scripts"
  cp "$REAL_SCRIPTS/check-workspace.sh" "$plain/scripts/check-workspace.sh"
  OUT="$(cd "$plain" && bash scripts/check-workspace.sh 2>&1)"
  RC=$?
  kcov_resync
  rc_is 2
  has "not a git checkout" "not a git checkout"
  rm -rf "$plain"
}

test_installed_workspace_checks_nothing() {
  CURRENT=installed_workspace
  local ws="$BASE_DIR/installed"
  rm -rf "$ws"
  mkdir -p "$ws/scripts" "$ws/.aiwp"
  printf '{}\n' >"$ws/.aiwp/manifest.json"
  cp "$REAL_SCRIPTS/check-workspace.sh" "$ws/scripts/check-workspace.sh"
  # Even inside another repository, the gate never judges it.
  git -C "$BASE_DIR" init -q 2>/dev/null
  OUT="$(cd "$ws" && bash scripts/check-workspace.sh --all 2>&1)"
  RC=$?
  kcov_resync
  rc_is 2
  has "one line" "an installed workspace has a read-only core and no git repository"
  eq "one line only" 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
  rm -rf "$ws" "$BASE_DIR/.git"
}

test_AC24_no_common_ancestor() {
  new_tree orphan
  git -C "$TREE" switch -q --orphan lone
  mkdir -p "$TREE/scripts"
  cp "$REAL_SCRIPTS/check-workspace.sh" "$TREE/scripts/check-workspace.sh"
  cp "$REAL_SCRIPTS/check-ledger.sh" "$TREE/scripts/check-ledger.sh"
  put lone.txt
  commit_all lone
  cw
  rc_is 1
  has "no merge-base" "no common ancestor"
  git -C "$TREE" switch -q feature
  cw
  rc_is 0
}

test_AC24_docs_only_runs_three_checks() {
  new_tree docs
  put docs/guide.md "# Guide"
  cw
  rc_is 0
  eq "AC-24 docs-only list" "--only secrets,markdown,mermaid" "$(validate_args)"
  eq "AC-24 docs-only runs no suite" 0 "$(log_count suite)"
  has "docs-only says suites were skipped" "SKIP suites (nothing under scripts/ changed)"
  has "decisions pass" "PASS decisions"
  has "settings pass" "PASS settings"
  has "validate pass" "PASS validate"
}

test_AC24_scripts_diff_adds_shell_and_suites() {
  new_tree scripts
  put scripts/tool.sh "echo hi"
  cw
  rc_is 0
  eq "AC-24 scripts list" "--only secrets,shell" "$(validate_args)"
  eq "AC-24 every suite ran" "$SUITE_COUNT" "$(log_count suite)"
  local want="" suite
  for suite in $EXPECTED_SUITES; do want="${want}suite $suite"$'\n'; done
  eq "AC-24 suites run in the listed order" "${want%$'\n'}" "$(grep '^suite ' "$STUB_LOG")"
  has "suites pass" "PASS suites"
  put docs/x.md "# x"
  cw
  eq "AC-24 scripts and docs list" "--only secrets,shell,markdown,mermaid" "$(validate_args)"
}

test_AC24_only_scripts_dir_runs_suites() {
  new_tree scripts-readme
  put scripts/README.md "# r"
  cw
  rc_is 0
  eq "a markdown under scripts/ still runs the suites" "$SUITE_COUNT" "$(log_count suite)"
  eq "and no shell check" "--only secrets,markdown,mermaid" "$(validate_args)"
}

test_AC24_validate_list_by_path() {
  expect_list nothing-changed secrets
  expect_list unrelated secrets other/data.txt
  expect_list markdown secrets,markdown,mermaid README.md
  expect_list mermaid-file secrets,markdown,mermaid docs/flow.mmd
  expect_list shell secrets,shell bin/run.sh
  expect_list dockerfile secrets,vuln,iac,dockerfile docker/some-image/Dockerfile.base
  expect_list dockerfile-outside-docker secrets,iac,dockerfile ci/Dockerfile
  expect_list docker-folder secrets,vuln,iac docker/compose.yaml
  expect_list python secrets,python bin/a.py
  expect_list typescript secrets,typescript web/a.ts
  expect_list tsx secrets,typescript web/b.tsx
  expect_list terraform secrets,terraform infra/main.tf
  expect_list coverage-folder secrets,coverage svc/.coveragerc svc/notes.txt
  expect_list everything secrets,vuln,iac,shell,dockerfile,markdown,mermaid,terraform,python,typescript docker/Dockerfile a.sh b.md c.py d.ts e.tf
}

test_AC24_coverage_needs_the_folder_with_coveragerc() {
  new_tree coverage-nested
  git -C "$TREE" switch -q main
  put svc/.coveragerc "[run]"
  put svc/pkg/mod.txt
  commit_all rc
  git -C "$TREE" switch -q feature
  git -C "$TREE" merge -q --no-edit main
  put svc/pkg/other.txt change
  cw
  eq "a nested path under a .coveragerc folder runs coverage" "--only secrets,coverage" "$(validate_args)"
  new_tree coverage-sibling
  git -C "$TREE" switch -q main
  put svc/.coveragerc "[run]"
  commit_all rc
  git -C "$TREE" switch -q feature
  git -C "$TREE" merge -q --no-edit main
  put other/file.txt
  cw
  eq "a path outside the folder does not" "--only secrets" "$(validate_args)"
  new_tree coverage-root
  git -C "$TREE" switch -q main
  put .coveragerc "[run]"
  commit_all rc
  git -C "$TREE" switch -q feature
  git -C "$TREE" merge -q --no-edit main
  put file.txt
  cw
  eq "a .coveragerc at the root covers a root file" "--only secrets,coverage" "$(validate_args)"
}

test_AC24_changed_paths_sources() {
  new_tree sources
  git -C "$TREE" switch -q main
  put old.py
  commit_all "old.py on main"
  git -C "$TREE" switch -q feature
  git -C "$TREE" merge -q --no-edit main
  put a.md "# a"
  commit_all md
  git -C "$TREE" switch -q main
  put main-only.sh
  commit_all "main moves on"
  git -C "$TREE" switch -q feature
  cw
  eq "committed on the branch counts; what only main changed does not (merge-base)" "--only secrets,markdown,mermaid" "$(validate_args)"
  put b.ts
  git -C "$TREE" add b.ts
  cw
  eq "staged counts" "--only secrets,markdown,mermaid,typescript" "$(validate_args)"
  git -C "$TREE" mv old.py moved.txt
  cw
  eq "a rename counts the old path too" "--only secrets,markdown,mermaid,python,typescript" "$(validate_args)"
  put c.tf
  cw
  eq "untracked counts" "--only secrets,markdown,mermaid,terraform,python,typescript" "$(validate_args)"
  new_tree sources-spaces
  put "dir with space/run.sh"
  cw
  eq "a path with spaces" "--only secrets,shell" "$(validate_args)"
}

test_AC24_base_option() {
  new_tree base
  git -C "$TREE" switch -q -c develop main
  put dev.md "# d"
  commit_all dev
  git -C "$TREE" switch -q feature
  git -C "$TREE" merge -q --no-edit develop
  put own.py
  commit_all own
  cw
  eq "default base is main" "--only secrets,markdown,mermaid,python" "$(validate_args)"
  cw --base develop
  rc_is 0
  eq "--base develop leaves only the branch's own change" "--only secrets,python" "$(validate_args)"
}

test_AC24_duplicate_decision_number_fails() {
  new_tree dup
  put docs/decisions/0002-second.md
  put docs/decisions/0010-tenth.md
  cw
  rc_is 0
  has "AC-24 distinct numbers pass" "PASS decisions"
  put docs/decisions/0002-other-second.md
  cw
  rc_is 1
  has "AC-24 duplicate number fails" "FAIL decisions"
  has "names the number" "duplicate decision number 2"
  has "names the first file" "0002-second.md"
  has "names the second file" "0002-other-second.md"
  has "says what to do" "renumber the record of the branch not yet merged"
  has "the other checks still ran" "PASS validate"
}

test_AC24_decision_number_ignores_padding_and_other_files() {
  new_tree dup-padding
  put docs/decisions/002-short.md
  put docs/decisions/0002-long.md
  cw
  rc_is 1
  has "002 and 0002 are the same number" "duplicate decision number 2"
  new_tree dup-others
  put docs/decisions/0003-a.md
  put docs/decisions/0003-a.txt
  put docs/decisions/notes.md
  cw
  rc_is 0
  new_tree dup-nofolder
  git -C "$TREE" rm -q -r docs/decisions
  commit_all nofolder
  cw
  rc_is 0
}

# AC-24: a folder with no record at all: the glob matches nothing, and that is no number.
test_AC24_an_empty_decisions_folder_passes() {
  new_tree dup-empty
  git -C "$TREE" rm -q -r docs/decisions
  commit_all emptyfolder
  mkdir -p "$TREE/docs/decisions"
  cw
  rc_is 0
  has "the check ran" "PASS decisions"
  lacks "no number made up" "duplicate decision number"
}

test_AC24_invalid_settings_fails() {
  new_tree settings
  put rules/agents/settings.json '{"hooks": {}}'
  cw
  rc_is 0
  has "AC-24 valid settings pass" "PASS settings"
  put rules/agents/settings.json '{"hooks": '
  cw
  rc_is 1
  has "AC-24 invalid settings fails" "FAIL settings"
  put rules/agents/settings.json 'null'
  cw
  rc_is 0
}

test_AC24_settings_only_checked_when_changed() {
  new_tree settings-unchanged
  put rules/agents/settings.json '{ broken'
  git -C "$TREE" switch -q main
  commit_all "broken on main"
  git -C "$TREE" switch -q feature
  git -C "$TREE" merge -q --no-edit main
  put docs/x.md "# x"
  cw
  rc_is 0
  has "an unchanged invalid settings.json is not this branch's problem" "PASS settings"
  git -C "$TREE" rm -q -f rules/agents/settings.json
  cw
  rc_is 1
  has "a deleted settings.json fails" "rules/agents/settings.json is missing"
}

# Builds a folder holding only the tools the gate needs, so a parser can be left out of PATH.
limited_path() { # folder tool...
  local dir="$1" t src
  shift
  rm -rf "$dir"
  mkdir -p "$dir"
  for t in bash env git sed awk grep sort uniq ls dirname mktemp rm tail cat head tr "$@"; do
    src="$(command -v "$t" 2>/dev/null)" || continue
    ln -s "$src" "$dir/$t"
  done
}

test_AC24_settings_parser_fallback() {
  new_tree settings-parser
  put rules/agents/settings.json '{ broken'
  local lp="$BASE_DIR/limited"
  if command -v python3 >/dev/null 2>&1; then
    limited_path "$lp" python3
    OUT="$(cd "$TREE" && PATH="$lp" bash "$TREE/scripts/check-workspace.sh" 2>&1)"
    RC=$?
    rc_is 1
    has "python3 fallback rejects invalid JSON" "FAIL settings"
    put rules/agents/settings.json '{}'
    OUT="$(cd "$TREE" && PATH="$lp" bash "$TREE/scripts/check-workspace.sh" 2>&1)"
    RC=$?
    rc_is 0
    has "python3 fallback accepts valid JSON" "PASS settings"
    put rules/agents/settings.json '{ broken'
  else
    skip "python3 not installed: its fallback is not exercised here"
  fi
  limited_path "$lp"
  OUT="$(cd "$TREE" && PATH="$lp" bash "$TREE/scripts/check-workspace.sh" 2>&1)"
  RC=$?
  kcov_resync
  rc_is 1
  has "no parser is a failure, not a silent pass" "neither jq nor python3 found"
  put docs/x.md "# x"
  git -C "$TREE" checkout -q -- rules/agents/settings.json 2>/dev/null || rm -f "$TREE/rules/agents/settings.json"
  OUT="$(cd "$TREE" && PATH="$lp" bash "$TREE/scripts/check-workspace.sh" 2>&1)"
  RC=$?
  has "with the file absent from the diff no parser is needed" "PASS settings"
  rm -rf "$lp"
}

test_AC24_validate_failure_fails_the_gate_and_the_rest_runs() {
  new_tree validate-fail
  put scripts/tool.sh "echo"
  STUB_VALIDATE_RC=1 cw
  rc_is 1
  has "validate failure fails" "FAIL validate"
  has "its output is indented under the failure" "  stub validate output"
  eq "the suites still ran" "$SUITE_COUNT" "$(log_count suite)"
  cw
  rc_is 0
}

test_AC24_missing_validate_script_fails() {
  new_tree no-validate
  rm "$TREE/scripts/validate.sh"
  cw
  rc_is 1
  has "missing validate.sh" "scripts/validate.sh is missing"
}

test_AC24_suite_failure_and_missing_suite() {
  new_tree suite-fail
  put scripts/tool.sh "echo"
  STUB_FAIL_SUITE=tests/heavy-run/test-heavy-run.sh cw
  rc_is 1
  has "a failing suite fails the gate" "FAIL suites"
  has "names the suite" "suite FAILED: scripts/tests/heavy-run/test-heavy-run.sh"
  eq "the other suites still ran" "$SUITE_COUNT" "$(log_count suite)"
  cw
  rc_is 0
  new_tree suite-missing
  put scripts/tool.sh "echo"
  rm "$TREE/scripts/tests/setup-claude/test-setup-claude.sh"
  cw
  rc_is 1
  has "a missing suite is a failure, never a silent skip" "suite missing: scripts/tests/setup-claude/test-setup-claude.sh"
  eq "the present suites ran" "$((SUITE_COUNT - 1))" "$(log_count suite)"
}

test_custom_terms_skip_without_the_custom_layer() {
  new_tree custom-terms-skip
  put docs/guide.md "Acme Corp guide"
  cw
  rc_is 0
  has "passes" "PASS custom-terms"
  has "says why" "SKIP custom-terms: no custom/core-terms.txt"
}

test_custom_terms_fail_on_a_term_in_the_core() {
  new_tree custom-terms-fail
  put custom/core-terms.txt "$(printf '# company\n\nacme\nwidget-[0-9]+\n')"
  put docs/guide.md "Built for ACME Corp"
  put rules/frontend.md "use widget-42 colors"
  put docs/clean.md "nothing here"
  cw
  rc_is 1
  has "fails" "FAIL custom-terms"
  has "names the file and line, any case" "docs/guide.md:1:Built for ACME Corp"
  has "a line is a regex" "rules/frontend.md:1:use widget-42 colors"
  lacks "a clean file is not listed" "docs/clean.md"
  lacks "the term list itself is not judged" "custom/core-terms.txt:"
  has "says what to do" "move them to custom/"
  has "the other checks still ran" "PASS validate"
}

# Commits everything pending on main, then puts feature back on top of it: what is committed this way is the base.
commit_on_main() {
  git -C "$TREE" switch -q main
  commit_all "${1:-base}"
  git -C "$TREE" switch -q -C feature main
}

test_custom_terms_judge_the_history_whole() {
  new_tree custom-terms-history
  put CHANGELOG.md "acme release"
  put tools/tool/CHANGELOG.md "acme entry"
  put tools/tool/history.txt "request: acme"
  put docs/decisions/0002-old.md "acme"
  commit_on_main
  put custom/core-terms.txt "acme"
  cw
  rc_is 1
  has "a committed changelog line fails, though the branch did not add it" "CHANGELOG.md:1:acme release"
  has "a tool changelog too" "tools/tool/CHANGELOG.md:1:acme entry"
  has "a history.txt too" "tools/tool/history.txt:1:request: acme"
  has "a decision record too" "docs/decisions/0002-old.md:1:acme"
  put tools/new/CHANGELOG.md "acme first entry"
  cw
  rc_is 1
  has "an untracked changelog is judged whole" "tools/new/CHANGELOG.md:1:acme first entry"
}

test_custom_terms_list_formatting() {
  new_tree custom-terms-format
  put docs/guide.md "Built for ACME Corp"
  printf '\xef\xbb\xbf  acme  \r\n' >"$TREE/custom/core-terms.txt" 2>/dev/null || { mkdir -p "$TREE/custom"; printf '\xef\xbb\xbf  acme  \r\n' >"$TREE/custom/core-terms.txt"; }
  cw
  rc_is 1
  has "a BOM and blanks around the term do not hide it" "docs/guide.md:1:Built for ACME Corp"
}

test_custom_terms_in_a_linked_worktree() {
  new_tree custom-terms-worktree
  printf '/custom/\n/tmp/\n' >"$TREE/.gitignore"
  commit_on_main
  put custom/core-terms.txt "acme"
  git -C "$TREE" worktree add -q -b feat/wt "$TREE/tmp/worktrees/ws/feat" main
  local wt="$TREE/tmp/worktrees/ws/feat"
  printf 'ACME corp\n' >"$wt/README.md"
  OUT="$(cd "$wt" && bash "$wt/scripts/check-workspace.sh" --all 2>&1)"
  RC=$?
  kcov_resync
  rc_is 1
  has "the worktree reads the list of the main checkout" "FAIL custom-terms"
  has "and names the line" "README.md:1:ACME corp"
}

test_custom_terms_judge_committed_and_untracked_files() {
  new_tree custom-terms-committed
  put custom/core-terms.txt "acme"
  put scripts/tool.sh "# acme"
  commit_all
  put tools/x/README.md "acme"
  cw
  rc_is 1
  has "a committed file" "scripts/tool.sh:1:# acme"
  has "an untracked file" "tools/x/README.md:1:acme"
}

test_custom_terms_empty_list_passes() {
  new_tree custom-terms-empty
  put custom/core-terms.txt "# only a comment"
  put docs/guide.md "acme"
  cw
  rc_is 0
  has "says the list is empty" "SKIP custom-terms: custom/core-terms.txt lists no term"
}

test_AC24_the_suite_list_matches_the_plan() {
  new_tree suite-list
  local listed
  listed="$(sed -n '/^SUITES="$/,/^"$/p' "$REAL_SCRIPTS/check-workspace.sh" | grep -v -e '^SUITES=' -e '^"$' | tr '\n' ' ' | sed 's/ $//')"
  eq "the SUITES list at the top of the script is the plan's" "$EXPECTED_SUITES" "$listed"
}

test_AC24_verbose_output() {
  new_tree verbose
  put docs/x.md "# x"
  cw
  lacks "quiet by default" "stub validate output"
  cw --verbose
  rc_is 0
  has "verbose prints the output of a passing check" "stub validate output"
  eq "verbose passes --verbose to validate" "--only secrets,markdown,mermaid --verbose" "$(validate_args)"
  put docs/decisions/0001-again.md
  cw --verbose
  rc_is 1
  has "verbose prints a failure in full" "renumber the record of the branch not yet merged"
  cw
  has "quiet prints a failure tail too" "  duplicate decision number 1"
}

test_AC24_runs_from_any_cwd() {
  new_tree cwd
  put docs/x.md "# x"
  OUT="$(cd / && bash "$TREE/scripts/check-workspace.sh" 2>&1)"
  RC=$?
  kcov_resync
  rc_is 0
  eq "the root is the parent of the script" "--only secrets,markdown,mermaid" "$(validate_args)"
}

# ---------------------------------------------------------------- independent audit (WP-8)
# Written from the plan, not from the code. A test that stays red here is a defect of the script, not of the test.

# Records a passed assertion when the last run did not exit 0.
rc_not_zero() {
  if [ "$RC" -ne 0 ]; then check "$1" 0; else check "$1" 1; fi
}

# Adds about 240 KB of untracked paths that sort after scripts/ and rules/: a diff larger than any pipe buffer.
put_big_diff() {
  local long1 long2 i dir
  long1="$(printf 'a%.0s' $(seq 1 240))"
  long2="$(printf 'b%.0s' $(seq 1 240))"
  dir="$TREE/zz/$long1/$long2"
  mkdir -p "$dir"
  for i in $(seq 1 500); do : >"$dir/f$i"; done
}

test_AC24_big_diff_does_not_hide_a_scripts_change() {
  new_tree big-scripts
  put scripts/tool.sh "echo hi"
  put_big_diff
  cw
  lacks "AC-24 a diff larger than a pipe still sees scripts/" "SKIP suites"
  eq "AC-24 every suite ran" "$SUITE_COUNT" "$(log_count suite)"
}

test_AC24_big_diff_does_not_hide_a_broken_settings() {
  new_tree big-settings
  put rules/agents/settings.json '{ broken'
  put_big_diff
  cw
  rc_is 1
  has "AC-24 a diff larger than a pipe still parses settings.json" "FAIL settings"
}

test_AC24_path_git_must_quote_still_counts() {
  new_tree quoted-scripts
  put 'scripts/we"ird.sh' "echo"
  cw
  eq "AC-24 a script with a quote in its name runs the suites" "$SUITE_COUNT" "$(log_count suite)"
  eq "AC-24 and the shell check" "--only secrets,shell" "$(validate_args)"
  new_tree quoted-tab
  put "$(printf 'scripts/ta\tb.md')" "# x"
  cw
  eq "AC-24 a tab in a path under scripts/" "$SUITE_COUNT" "$(log_count suite)"
  eq "AC-24 a tab in a markdown name" "--only secrets,markdown,mermaid" "$(validate_args)"
  new_tree quoted-backslash
  put 'odd\dir/run.sh' "echo"
  commit_all quoted
  cw
  rc_is 0
  eq "AC-24 a committed path with a backslash" "--only secrets,shell" "$(validate_args)"
  eq "AC-24 reaches validate by its plain name" 'odd\dir/run.sh' "$(listed_files)"
}

test_AC24_non_ascii_path_counts() {
  new_tree non-ascii
  put "scripts/ação.sh" "echo"
  cw
  rc_is 0
  eq "AC-24 a non-ASCII script runs the suites" "$SUITE_COUNT" "$(log_count suite)"
  eq "AC-24 and the shell check" "--only secrets,shell" "$(validate_args)"
}

# Puts a git on PATH that fails for one subcommand and otherwise runs the real one.
fake_git_failing() { # subcommand
  local real
  real="$(command -v git)"
  rm -rf "$FAKE_BIN"
  mkdir -p "$FAKE_BIN"
  # shellcheck disable=SC2016
  printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = "%s" ] && { echo "fake git failure" >&2; exit 128; }; done\nexec "%s" "$@"\n' "$1" "$real" >"$FAKE_BIN/git"
  chmod +x "$FAKE_BIN/git"
}

test_AC24_a_failing_diff_never_passes_on_an_empty_list() {
  new_tree diff-fails
  put scripts/tool.sh "echo"
  commit_all tool
  fake_git_failing diff
  OUT="$(cd "$TREE" && PATH="$FAKE_BIN:$PATH" bash "$TREE/scripts/check-workspace.sh" 2>&1)"
  RC=$?
  kcov_resync
  rc_not_zero "AC-24 the gate fails when git diff fails"
  new_tree ls-files-fails
  put scripts/tool.sh "echo"
  fake_git_failing ls-files
  OUT="$(cd "$TREE" && PATH="$FAKE_BIN:$PATH" bash "$TREE/scripts/check-workspace.sh" 2>&1)"
  RC=$?
  kcov_resync
  rc_not_zero "AC-24 the gate fails when git ls-files fails"
}

test_AC24_empty_settings_is_invalid_with_every_parser() {
  local lp="$BASE_DIR/limited" parser
  for parser in jq python3; do
    command -v "$parser" >/dev/null 2>&1 || {
      skip "$parser not installed"
      continue
    }
    limited_path "$lp" "$parser"
    new_tree "settings-empty-$parser"
    : >"$TREE/rules/agents/settings.json"
    OUT="$(cd "$TREE" && PATH="$lp" bash "$TREE/scripts/check-workspace.sh" 2>&1)"
    RC=$?
    rc_is 1
    has "AC-24 $parser: a zero-byte settings.json fails" "FAIL settings"
    new_tree "settings-blank-$parser"
    printf '  \n\n' >"$TREE/rules/agents/settings.json"
    OUT="$(cd "$TREE" && PATH="$lp" bash "$TREE/scripts/check-workspace.sh" 2>&1)"
    RC=$?
    rc_is 1
    has "AC-24 $parser: a blank settings.json fails" "FAIL settings"
    new_tree "settings-two-$parser"
    put rules/agents/settings.json '{} {}'
    OUT="$(cd "$TREE" && PATH="$lp" bash "$TREE/scripts/check-workspace.sh" 2>&1)"
    RC=$?
    rc_is 1
    has "AC-24 $parser: two documents fail" "FAIL settings"
    kcov_resync
  done
  rm -rf "$lp"
}

test_AC24_settings_odd_forms() {
  new_tree settings-dir
  put rules/agents/settings.json '{}'
  git -C "$TREE" switch -q main
  commit_all "settings on main"
  git -C "$TREE" switch -q feature
  git -C "$TREE" merge -q --no-edit main
  rm "$TREE/rules/agents/settings.json"
  put rules/agents/settings.json/inner "x"
  cw
  rc_is 1
  has "AC-24 a folder at that path is missing, not valid" "rules/agents/settings.json is missing"
  new_tree settings-dangling
  ln -s "$TREE/nowhere" "$TREE/rules/agents/settings.json"
  cw
  rc_is 1
  has "AC-24 a dangling link fails" "FAIL settings"
  new_tree settings-renamed
  put rules/agents/settings.json '{}'
  git -C "$TREE" switch -q main
  commit_all "settings on main"
  git -C "$TREE" switch -q feature
  git -C "$TREE" merge -q --no-edit main
  git -C "$TREE" mv rules/agents/settings.json rules/agents/other.json
  cw
  rc_is 1
  has "AC-24 renaming it away counts as removing it" "rules/agents/settings.json is missing"
}

test_AC24_decision_numbers_more_forms() {
  new_tree dup-spaces
  put "docs/decisions/0004-with space.md"
  put "docs/decisions/0004-other space.md"
  cw
  rc_is 1
  has "AC-24 duplicates with spaces in the names" "duplicate decision number 4"
  new_tree dup-letters
  put docs/decisions/12a-x.md
  put docs/decisions/12a-y.md
  cw
  rc_is 0
  has "not a number: not a record" "PASS decisions"
  new_tree dup-bigger
  put docs/decisions/0008-a.md
  put docs/decisions/0009-a.md
  put docs/decisions/0100-a.md
  cw
  rc_is 0
  has "08, 09 are decimal, never octal" "PASS decisions"
  new_tree dup-octal
  put docs/decisions/0008-a.md
  put docs/decisions/008-b.md
  cw
  rc_is 1
  has "008 and 0008" "duplicate decision number 8"
  new_tree dup-three
  put docs/decisions/0005-a.md
  put docs/decisions/0005-b.md
  put docs/decisions/0006-a.md
  put docs/decisions/0006-b.md
  cw
  rc_is 1
  has "first duplicate" "duplicate decision number 5"
  has "second duplicate" "duplicate decision number 6"
  new_tree dup-deleted
  git -C "$TREE" rm -q docs/decisions/0001-first.md
  put docs/decisions/0001-other.md
  cw
  rc_is 0
  has "a renumbered record is no duplicate" "PASS decisions"
}

test_AC24_decision_number_case_variant_fails() {
  new_tree dup-case
  put docs/decisions/0001-other.MD
  cw
  rc_is 1
  has "AC-24 .MD is a record too" "duplicate decision number 1"
}

test_AC24_gate_in_a_linked_worktree() {
  new_tree linked
  local wt="$BASE_DIR/linked wt"
  rm -rf "$wt"
  git -C "$TREE" worktree add -q -b prompt "$wt" main
  mkdir -p "$wt/docs"
  printf '# x\n' >"$wt/docs/x.md"
  OUT="$(cd "$wt" && bash "$wt/scripts/check-workspace.sh" 2>&1)"
  RC=$?
  kcov_resync
  rc_is 0
  eq "AC-24 a worktree's own diff" "--only secrets,markdown,mermaid" "$(validate_args)"
  printf 'x\n' >"$wt/docs/decisions/0001-again.md"
  OUT="$(cd "$wt" && bash "$wt/scripts/check-workspace.sh" 2>&1)"
  RC=$?
  rc_is 1
  has "AC-24 the worktree's own decision records" "duplicate decision number 1"
  git -C "$TREE" worktree remove --force "$wt"
}

test_AC24_base_as_sha_tag_and_invalid_forms() {
  new_tree base-forms
  git -C "$TREE" tag v1 main
  put a.md "# a"
  commit_all a
  put b.py
  commit_all b
  cw --base v1
  rc_is 0
  eq "a tag" "--only secrets,markdown,mermaid,python" "$(validate_args)"
  cw --base "$(git -C "$TREE" rev-parse HEAD^)"
  rc_is 0
  eq "a sha" "--only secrets,python" "$(validate_args)"
  cw --base=main
  rc_is 2
  cw --base "main..feature"
  rc_is 2
  cw --base "-x"
  rc_is 2
  local blob
  blob="$(git -C "$TREE" rev-parse HEAD:a.md)"
  cw --base "$blob"
  rc_is 2
  has "a blob is not a commit" "base not found"
}

test_AC24_help_needs_no_checkout() {
  CURRENT="help without a checkout"
  local plain="$BASE_DIR/plain help"
  rm -rf "$plain"
  mkdir -p "$plain/scripts"
  cp "$REAL_SCRIPTS/check-workspace.sh" "$plain/scripts/check-workspace.sh"
  OUT="$(bash "$plain/scripts/check-workspace.sh" --help 2>&1)"
  RC=$?
  kcov_resync
  rc_is 0
  has "help" "Usage: scripts/check-workspace.sh"
  OUT="$(bash "$plain/scripts/check-workspace.sh" --nope 2>&1)"
  RC=$?
  kcov_resync
  rc_is 2
  rm -rf "$plain"
}

test_AC24_missing_tools_fail_closed() {
  new_tree no-git
  local lp="$BASE_DIR/limited"
  limited_path "$lp"
  rm -f "$lp/git"
  OUT="$(cd "$TREE" && PATH="$lp" bash "$TREE/scripts/check-workspace.sh" 2>&1)"
  RC=$?
  kcov_resync
  rc_is 2
  has "git is required" "git not found"
  limited_path "$lp"
  rm -f "$lp/mktemp"
  OUT="$(cd "$TREE" && PATH="$lp" bash "$TREE/scripts/check-workspace.sh" 2>&1)"
  RC=$?
  kcov_resync
  rc_not_zero "no folder for the logs: never a pass"
  lacks "and no check claims it passed" "PASS"
  rm -rf "$lp"
}

test_AC24_failure_output_is_capped_at_30_lines() {
  new_tree long-failure
  cat >"$TREE/scripts/validate.sh" <<'STUB'
#!/usr/bin/env bash
for i in $(seq 1 40); do echo "line-$i-end"; done
exit 1
STUB
  put docs/x.md "# x"
  cw
  rc_is 1
  has "the last line of the failure" "line-40-end"
  has "the 30th from the end" "line-11-end"
  lacks "not the 31st from the end" "line-10-end"
  cw --verbose
  has "--verbose prints all of it" "line-1-end"
}

test_AC24_odd_names_do_not_break_the_list() {
  new_tree dash-name
  printf '# x\n' >"$TREE/-x.md"
  cw
  rc_is 0
  eq "a name starting with a dash" "--only secrets,markdown,mermaid" "$(validate_args)"
  new_tree star-name
  put 'docs/*.md' "# x"
  cw
  rc_is 0
  eq "a glob in a name is literal" "--only secrets,markdown,mermaid" "$(validate_args)"
  new_tree deleted-script
  git -C "$TREE" rm -q scripts/validate.sh
  put scripts/stub.txt x
  cp "$REAL_SCRIPTS/check-workspace.sh" "$TREE/scripts/check-workspace.sh"
  cp "$REAL_SCRIPTS/check-ledger.sh" "$TREE/scripts/check-ledger.sh"
  cw
  rc_is 1
  has "a gate with validate.sh deleted fails" "scripts/validate.sh is missing"
  new_tree deleted-only
  git -C "$TREE" rm -q docs/decisions/README.md
  commit_all removed
  cw
  rc_is 0
  eq "a deleted markdown still counts" "--only secrets,markdown,mermaid" "$(validate_args)"
}

# ---------------------------------------------------------------- validate.sh (AC-25)

test_AC25_root_config_allowlists_only_the_top_level_tmp() {
  CURRENT="gitleaks root config"
  local regex probe
  regex="$(sed -n "s/^paths = \['''\(.*\)'''\]\$/\1/p" "$REAL_SCRIPTS/../docker/config/gitleaks-root.toml")"
  ok "control: the config holds one path pattern" test -n "$regex"
  for probe in tmp/worktrees/r/b/key /work/tmp/worktrees/r/b/key; do
    printf '%s\n' "$probe" | grep -Eq "$regex"
    check "AC-25 $probe is ignored by the root scan" $?
  done
  for probe in docs/tmp/key /work/docs/tmp/key tools/p/tmp/key tmpfile; do
    if printf '%s\n' "$probe" | grep -Eq "$regex"; then check "AC-25 $probe is still scanned" 1; else check "AC-25 $probe is still scanned" 0; fi
  done
}

# Decisions of the exclusions in validate.sh and gitleaks.toml, each with its test below:
# - coverage: a .coveragerc under tools/ is skipped, one elsewhere runs: test_AC25_coverage_skips_pocs_and_tools
# - files() and listed_files(): the console's generated dist is pruned with and without --path, the same path in
#   another tool is not, node_modules and .data are pruned, and a root scan skips projects/:
#   test_AC25_generated_and_local_folders_are_skipped
# - generated_skip_dir(): the Trivy entry per target: test_AC25_trivy_skip_is_relative_to_the_target
# - gitleaks allowlist: the console's dist and node_modules are ignored, another dist is scanned:
#   test_AC25_gitleaks_allowlist_for_generated_output
test_AC25_coverage_skips_pocs_and_tools() {
  new_validate_tree coverage-pocs
  mkdir -p "$TREE/tools/poc" "$TREE/docs/cov"
  : >"$TREE/tools/poc/.coveragerc"
  : >"$TREE/docs/cov/.coveragerc"
  vl --only coverage
  rc_is 0
  log_has "AC-25 coverage runs a folder outside tools" "--workdir /work/docs/cov"
  log_lacks "AC-25 and skips one under tools" "tools/poc"
}

test_AC25_generated_and_local_folders_are_skipped() {
  new_validate_tree generated
  local kept=tools/other/internal/webui/dist generated=tools/container-console-docker-ce/internal/webui/dist
  mkdir -p "$TREE/$generated" "$TREE/$kept" "$TREE/docs/node_modules/d" "$TREE/docs/.data" "$TREE/projects/p"
  : >"$TREE/$generated/gen.sh"
  : >"$TREE/$kept/kept.sh"
  : >"$TREE/docs/node_modules/d/dep.sh"
  : >"$TREE/docs/.data/local.sh"
  : >"$TREE/projects/p/own.sh"
  vl --only shell
  rc_is 0
  log_has "AC-25 the same path in another tool is checked" "/work/$kept/kept.sh"
  log_lacks "AC-25 the console's generated output is skipped" "gen.sh"
  log_lacks "AC-25 node_modules is skipped" "dep.sh"
  log_lacks "AC-25 .data is skipped" "local.sh"
  log_lacks "AC-25 a root scan skips projects/" "own.sh"
  local path
  for path in tools tools/container-console-docker-ce; do
    : >"$STUB_LOG"
    vl --only shell --path "$path"
    rc_is 0
    log_lacks "AC-25 --path $path skips the console's generated output" "gen.sh"
  done
  : >"$STUB_LOG"
  vl --only shell --path tools
  log_has "AC-25 and --path tools still checks another tool" "$kept/kept.sh"
  local list="$BASE_DIR/generated.list"
  printf '%s\n' "$generated/gen.sh" "$kept/kept.sh" >"$list"
  : >"$STUB_LOG"
  vl --only shell --files "$list"
  rc_is 0
  log_has "AC-25 --files judges the same path in another tool" "$kept/kept.sh"
  log_lacks "AC-25 and skips the console's generated output" "gen.sh"
}

# Checks that both Trivy commands of the last run skip exactly this entry, followed by this text.
trivy_skip_is() {
  local cmd line
  for cmd in "trivy fs" "trivy config"; do
    line="$(grep -F "$cmd" "$STUB_LOG" | tail -n 1)"
    case "$line" in
      *"**/node_modules,$2"*) check "AC-25 $1: $cmd" 0 ;;
      *) check "AC-25 $1: $cmd missing [$2] in [$line]" 1 ;;
    esac
  done
}

test_AC25_trivy_skip_is_relative_to_the_target() {
  new_validate_tree trivy-skip
  local dist=tools/container-console-docker-ce/internal/webui/dist worktree=tmp/worktrees/r/b
  mkdir -p "$TREE/$dist" "$TREE/$worktree/$dist" "$TREE/docs"
  vl --only vuln,iac
  rc_is 0
  trivy_skip_is "a root scan names the whole path" "**/$dist,tmp,projects,custom"
  local case_line path entry
  for case_line in \
    "tools|container-console-docker-ce/internal/webui/dist " \
    "tools/container-console-docker-ce|internal/webui/dist " \
    "$worktree/tools|container-console-docker-ce/internal/webui/dist " \
    "$worktree/tools/container-console-docker-ce|internal/webui/dist " \
    "$worktree|**/$dist " \
    "docs|**/$dist "; do
    path="${case_line%%|*}"
    entry="${case_line#*|}"
    : >"$STUB_LOG"
    vl --only vuln,iac --path "$path"
    rc_is 0
    trivy_skip_is "--path $path" "$entry"
  done
}

test_AC25_gitleaks_allowlist_for_generated_output() {
  CURRENT="gitleaks generated output allowlist"
  local regex probe
  regex="$(sed -n "s/^paths = \['''\(.*node_modules.*\)'''\]\$/\1/p" "$REAL_SCRIPTS/../docker/config/gitleaks.toml" | sed "s/''', '''/|/")"
  ok "control: the config holds the generated output patterns" test -n "$regex"
  for probe in /work/tools/container-console-docker-ce/internal/webui/dist/a.js /work/web/node_modules/d/a.js; do
    printf '%s\n' "$probe" | grep -Eq "$regex"
    check "AC-25 $probe is ignored" $?
  done
  for probe in /work/tools/other/internal/webui/dist/a.js /work/projects/p/internal/webui/dist/a.js; do
    if printf '%s\n' "$probe" | grep -Eq "$regex"; then check "AC-25 $probe is still scanned" 1; else check "AC-25 $probe is still scanned" 0; fi
  done
}

test_AC25_nested_tmp_is_not_the_top_level_one() {
  new_validate_tree nested-tmp
  mkdir -p "$TREE/docs/tmp"
  # shellcheck disable=SC2016
  printf '# a\n\n```mermaid\ngraph TD\n```\n' >"$TREE/docs/tmp/a.md"
  : >"$TREE/docs/tmp/run.sh"
  vl --only mermaid
  rc_is 0
  log_has "AC-25 the root scan renders a diagram under a nested tmp/" "-i /work/docs/tmp/a.md"
  : >"$STUB_LOG"
  vl --only shell
  rc_is 0
  log_has "AC-25 and shell-checks a script there" "/work/docs/tmp/run.sh"
}

test_AC25_target_spellings() {
  new_validate_tree spellings
  mkdir -p "$TREE/tmp/worktrees/r/b"
  vl --only secrets --path ./tmp/worktrees/r/b/
  rc_is 0
  log_has "AC-25 ./ and a trailing / still name the worktree" "dir /work/tmp/worktrees/r/b --no-banner"
  log_lacks "AC-25 and keep the normal config" "gitleaks-root.toml"
  : >"$STUB_LOG"
  vl --only secrets --path tmp
  rc_is 0
  log_lacks "AC-25 tmp itself is not a root scan" "gitleaks-root.toml"
  : >"$STUB_LOG"
  vl --only secrets --path .
  rc_is 0
  log_has "AC-25 . is the root scan" "gitleaks-root.toml"
  vl --only secrets --path tmp/worktrees/../x
  rc_is 2
  vl --only secrets --path tmp/worktrees/r/nope
  rc_is 2
}

# Tree with validate.sh, a fake docker on PATH that logs its arguments, and the given files.
new_validate_tree() {
  CURRENT="$1"
  rm -rf "$TREE" "$FAKE_BIN"
  mkdir -p "$TREE/scripts" "$TREE/docker" "$FAKE_BIN"
  : >"$STUB_LOG"
  cp "$REAL_SCRIPTS/validate.sh" "$TREE/scripts/validate.sh"
  cp "$REAL_SCRIPTS/check-ledger.sh" "$TREE/scripts/check-ledger.sh"
  mkdir -p "$TREE/scripts/lib"
  cp "$REAL_SCRIPTS/lib/env.sh" "$TREE/scripts/lib/env.sh"
  cat >"$FAKE_BIN/docker" <<'STUB'
#!/usr/bin/env bash
echo "docker $*" >>"$STUB_LOG"
echo "fake docker output"
exit "${STUB_DOCKER_RC:-0}"
STUB
  chmod +x "$FAKE_BIN/docker"
}

# Runs the validate.sh of the tree with the fake docker.
vl() {
  OUT="$(cd "$TREE" && PATH="$FAKE_BIN:$PATH" bash "$TREE/scripts/validate.sh" "$@" 2>&1)"
  RC=$?
  kcov_resync
}

# The docker lines of the log, joined for substring checks.
docker_log() { cat "$STUB_LOG"; }
log_has() { case "$(docker_log)" in *"$2"*) check "$1" 0 ;; *) check "$1: missing [$2] in [$(docker_log)]" 1 ;; esac; }
log_lacks() { case "$(docker_log)" in *"$2"*) check "$1: unexpected [$2] in [$(docker_log)]" 1 ;; *) check "$1" 0 ;; esac; }

test_AC25_secrets_config_by_target() {
  new_validate_tree secrets-config
  mkdir -p "$TREE/tmp/worktrees/r/b" "$TREE/projects/x"
  vl --only secrets
  rc_is 0
  log_has "AC-25 root scan uses the root config" "dir /work --no-banner --redact --config /work/docker/config/gitleaks-root.toml"
  : >"$STUB_LOG"
  vl --only secrets --path tmp/worktrees/r/b
  rc_is 0
  log_has "AC-25 a worktree is scanned" "dir /work/tmp/worktrees/r/b --no-banner"
  log_has "AC-25 with the normal config" "--config /work/docker/config/gitleaks.toml"
  log_lacks "AC-25 and not the root one" "gitleaks-root.toml"
  : >"$STUB_LOG"
  vl --only secrets --path projects/x
  log_has "a project keeps the normal config" "--config /work/docker/config/gitleaks.toml"
  log_lacks "and not the root one" "gitleaks-root.toml"
  : >"$STUB_LOG"
  vl --only secrets --path ./
  log_has "--path ./ is the root scan" "gitleaks-root.toml"
}

test_AC25_vuln_and_iac_skip_tmp_only_at_the_root() {
  new_validate_tree skip-dirs
  mkdir -p "$TREE/tmp/worktrees/r/b" "$TREE/projects/x"
  local vuln_old="--skip-dirs refs,.history,**/.data,**/node_modules,**/tools/container-console-docker-ce/internal/webui/dist --skip-files **/.env /work/projects/x"
  local iac_old="--skip-dirs .history,**/.data,**/node_modules,**/tools/container-console-docker-ce/internal/webui/dist /work/projects/x"
  vl --only vuln,iac
  log_has "AC-25 root vuln skips tmp and projects" "--skip-dirs refs,.history,**/.data,**/node_modules,**/tools/container-console-docker-ce/internal/webui/dist,tmp,projects,custom --skip-files **/.env /work"
  log_has "AC-25 root iac skips tmp and projects" "--skip-dirs .history,**/.data,**/node_modules,**/tools/container-console-docker-ce/internal/webui/dist,tmp,projects,custom /work"
  : >"$STUB_LOG"
  vl --only vuln,iac --path projects/x
  log_has "a project's vuln line is unchanged" "$vuln_old"
  log_has "a project's iac line is unchanged" "$iac_old"
  : >"$STUB_LOG"
  vl --only vuln,iac --path tmp/worktrees/r/b
  log_lacks "AC-25 a worktree scan does not skip tmp" ",tmp"
  log_has "AC-25 and scans the worktree" "/work/tmp/worktrees/r/b"
}

test_AC25_mermaid_ignores_tmp_at_the_root() {
  new_validate_tree mermaid
  mkdir -p "$TREE/docs" "$TREE/tmp/worktrees/r/b"
  # shellcheck disable=SC2016
  printf '# a\n\n```mermaid\ngraph TD\n```\n' >"$TREE/docs/a.md"
  # shellcheck disable=SC2016
  printf '# c\n\n```mermaid\ngraph TD\n```\n' >"$TREE/tmp/worktrees/r/b/c.md"
  vl --only mermaid
  rc_is 0
  has "mermaid passes" "PASS mermaid"
  log_has "AC-25 root scan renders its own diagram" "-i /work/docs/a.md"
  log_lacks "AC-25 and not the one under tmp/" "tmp/worktrees"
  : >"$STUB_LOG"
  vl --only mermaid --path tmp/worktrees/r/b
  log_has "AC-25 the worktree target renders its diagram" "-i /work/tmp/worktrees/r/b/c.md"
  : >"$STUB_LOG"
  vl --only mermaid --path docs
  log_has "another folder is unchanged" "-i /work/docs/a.md"
}

test_AC25_owned_checks_skip_worktrees() {
  new_validate_tree owned
  mkdir -p "$TREE/tmp/worktrees/r/b" "$TREE/tools/p" "$TREE/projects/x"
  : >"$TREE/tmp/worktrees/r/b/x.py"
  : >"$TREE/tmp/worktrees/r/b/y.ts"
  : >"$TREE/tmp/worktrees/r/b/.coveragerc"
  : >"$TREE/tmp/worktrees/r/b/run.sh"
  : >"$TREE/tools/p/z.py"
  : >"$TREE/projects/x/w.py"
  vl --only python,typescript,coverage --path tmp/worktrees/r/b
  rc_is 0
  has "AC-25 python skipped in a worktree" "SKIP python (no targets)"
  has "AC-25 typescript skipped in a worktree" "SKIP typescript (no targets)"
  has "AC-25 coverage skipped in a worktree" "SKIP coverage (no targets)"
  log_lacks "AC-25 nothing ran in the worktree" "x.py"
  vl --only python --path projects/x
  has "as under projects/" "SKIP python (no targets)"
  mkdir -p "$TREE/tmp/work/2026-11-16-x/app"
  : >"$TREE/tmp/work/2026-11-16-x/app/v.py"
  vl --only python,coverage --path tmp/work/2026-11-16-x/app
  has "a clone of tmp/work/ is project code too" "SKIP python (no targets)"
  log_lacks "nothing ran in the clone" "v.py"
  : >"$STUB_LOG"
  vl --only python
  rc_is 0
  has "control: the root scan still lints an owned file" "PASS python"
  log_has "control: the file reached ruff" "/work/tools/p/z.py"
  log_lacks "control: not the worktree file" "tmp/worktrees"
  log_lacks "control: not the project file" "projects/x"
}

test_AC25_shell_still_runs_in_a_worktree() {
  new_validate_tree shell
  mkdir -p "$TREE/tmp/worktrees/r/b" "$TREE/tmp/other"
  : >"$TREE/tmp/worktrees/r/b/run.sh"
  : >"$TREE/tmp/other/skipped.sh"
  : >"$TREE/root.sh"
  vl --only shell --path tmp/worktrees/r/b
  rc_is 0
  log_has "AC-25 a worktree is shell-checked like a project" "/work/tmp/worktrees/r/b/run.sh"
  : >"$STUB_LOG"
  vl --only shell
  log_has "root scan checks root.sh" "/work/root.sh"
  log_lacks "root scan ignores tmp/ (as before)" "/work/tmp/"
}

test_AC25_validate_usage_unchanged() {
  new_validate_tree usage
  vl --path /abs
  rc_is 2
  vl --path nope
  rc_is 2
  vl --only bogus
  rc_is 2
  vl --help
  rc_is 0
  has "help documents the worktree target" "--path tmp/worktrees/<repo>/<branch>"
  STUB_DOCKER_RC=1 vl --only secrets
  rc_is 1
  has "a failing tool fails the check" "FAIL secrets"
}

# ---------------------------------------------------------------- validate.sh secrets: tracked .env and local.settings.json
# docker/config/gitleaks.toml allowlists both names, so the scan never sees one: a tracked one fails the check by itself.

# Records whether the output holds exactly this line.
has_line() {
  if printf '%s\n' "$OUT" | grep -qxF -- "$2"; then check "$1" 0; else check "$1: missing line [$2]" 1; fi
}

test_secrets_fail_on_a_tracked_env_file() {
  new_validate_tree tracked-env
  git -C "$TREE" init -q -b main
  mkdir -p "$TREE/svc/api"
  : >"$TREE/.env.example"
  : >"$TREE/svc/env"
  : >"$TREE/svc/my.env"
  : >"$TREE/svc/local.settings.json.bak"
  commit_all lookalikes
  : >"$TREE/svc/.env"
  : >"$TREE/svc/api/local.settings.json"
  vl --only secrets
  rc_is 0
  has "untracked files of those names and tracked lookalikes pass" "PASS secrets"
  git -C "$TREE" add svc/.env
  vl --only secrets
  rc_is 1
  has "a staged .env fails" "FAIL secrets"
  has_line "names it" "  tracked by git: svc/.env"
  has "says why in one line" "is never scanned (docker/config/gitleaks.toml allowlists both names)"
  lacks "not the untracked one" "tracked by git: svc/api/local.settings.json"
  log_has "the scan still ran" " gitleaks dir /work "
  commit_all env
  : >"$TREE/.env"
  git -C "$TREE" add .env svc/api/local.settings.json
  STUB_DOCKER_RC=1 vl --only secrets
  rc_is 1
  has "a failing scan prints its own output" "fake docker output"
  has_line "and the tracked files after it: at the root" "  tracked by git: .env"
  has_line "committed" "  tracked by git: svc/.env"
  has_line "nested" "  tracked by git: svc/api/local.settings.json"
  lacks "never a lookalike" ".env.example"
  vl --only shell,markdown
  rc_is 0
  lacks "only the secrets check looks" "tracked by git"
}

test_secrets_tracked_env_follows_the_target() {
  new_validate_tree tracked-env-path
  git -C "$TREE" init -q -b main
  printf '/projects/\n' >"$TREE/.gitignore"
  mkdir -p "$TREE/tools/p" "$TREE/docs" "$TREE/projects/x/sub"
  : >"$TREE/tools/p/.env"
  commit_all poc
  git init -q -b main "$TREE/projects/x"
  : >"$TREE/projects/x/sub/local.settings.json"
  git -C "$TREE/projects/x" add -A
  vl --only secrets --path docs
  rc_is 0
  has "a target with none passes" "PASS secrets"
  vl --only secrets --path tools/p
  rc_is 1
  has_line "a folder of the workspace repo, by its workspace path" "  tracked by git: tools/p/.env"
  vl --only secrets --path projects/x
  rc_is 1
  has_line "a project is asked in its own repo" "  tracked by git: projects/x/sub/local.settings.json"
  vl --only secrets --path projects
  rc_is 1
  has_line "a folder that groups repos asks each repo inside it" "  tracked by git: projects/x/sub/local.settings.json"
  lacks "and only what is inside it" "tracked by git: tools"
  vl --only secrets
  rc_is 1
  has_line "the root scan sees the workspace repo" "  tracked by git: tools/p/.env"
  lacks "and leaves a project's repo to its own run" "tracked by git: projects/x"
}

test_secrets_tracked_custom_env_file_fails() {
  new_validate_tree tracked-custom-env
  mkdir -p "$TREE/custom/env" "$TREE/projects/x/env"
  git init -q -b main "$TREE/custom"
  : >"$TREE/custom/env/docker.env"
  : >"$TREE/custom/env/README.md"
  git -C "$TREE/custom" add -f env
  git init -q -b main "$TREE/projects/x"
  : >"$TREE/projects/x/env/prod.env"
  git -C "$TREE/projects/x" add -A
  vl --only secrets --path custom
  rc_is 1
  has_line "a filled env file tracked by the custom layer" "  tracked by git: custom/env/docker.env"
  vl --only secrets --path custom/env
  rc_is 1
  has_line "also with the env folder as the target" "  tracked by git: custom/env/docker.env"
  lacks "only the .env files" "tracked by git: custom/env/README.md"
  vl --only secrets --path projects/x
  rc_is 0
  lacks "env/*.env is the custom layer's rule only" "tracked by git: projects/x/env/prod.env"
  local list="$BASE_DIR/custom-env.list"
  printf 'custom/env/docker.env\ncustom/env/README.md\n' >"$list"
  vl --only secrets --files "$list"
  rc_is 1
  has_line "a listed tracked filled env file fails" "  tracked by git: custom/env/docker.env"
  lacks "and only that one" "tracked by git: custom/env/README.md"
  printf 'projects/x/env/prod.env\n' >"$list"
  vl --only secrets --files "$list"
  lacks "a project's env/*.env is not a filled env file" "tracked by git: projects/x/env/prod.env"
}

test_secrets_tracked_env_is_skipped_outside_git() {
  new_validate_tree tracked-env-no-git
  : >"$TREE/.env"
  vl --only secrets
  rc_is 0
  has "not a git repo: nothing is tracked" "PASS secrets"
  lacks "and nothing is said" "tracked by git"
  git -C "$TREE" init -q -b main
  git -C "$TREE" add .env
  vl --only secrets
  rc_is 1
  has_line "control: in a repo it fails" "  tracked by git: .env"
  local lp="$BASE_DIR/limited"
  limited_path "$lp"
  rm -f "$lp/git"
  OUT="$(cd "$TREE" && PATH="$FAKE_BIN:$lp" bash "$TREE/scripts/validate.sh" --only secrets 2>&1)"
  RC=$?
  kcov_resync
  rc_is 0
  has "without git there is nobody to ask: the scan alone decides" "PASS secrets"
  rm -rf "$lp"
}

test_secrets_tracked_env_with_files_judges_only_the_list() {
  new_validate_tree tracked-env-files
  git -C "$TREE" init -q -b main
  printf '.history/\n/projects/\n' >"$TREE/.gitignore"
  mkdir -p "$TREE/a" "$TREE/b" "$TREE/projects/x"
  : >"$TREE/.env"
  : >"$TREE/a/.env"
  : >"$TREE/a/.env.example"
  : >"$TREE/a/notes.md"
  : >"$TREE/b/local.settings.json"
  commit_all tracked
  : >"$TREE/b/.env"
  git init -q -b main "$TREE/projects/x"
  : >"$TREE/projects/x/.env"
  git -C "$TREE/projects/x" add .env
  local list="$BASE_DIR/files.list"
  printf 'a/notes.md\na/.env.example\nb/.env\n' >"$list"
  vl --only secrets --files "$list"
  rc_is 0
  has "tracked ones outside the list, a listed untracked one and a lookalike pass" "PASS secrets"
  printf 'a/notes.md\na/.env\n' >"$list"
  vl --only secrets --files "$list"
  rc_is 1
  has_line "a listed tracked one fails" "  tracked by git: a/.env"
  lacks "one outside the list is not judged" "tracked by git: b/local.settings.json"
  log_has "the copy of the list is still scanned" " gitleaks dir /work/.history/validate-secrets."
  : >"$STUB_LOG"
  vl --only secrets --path b --files "$list"
  rc_is 0
  has "a list with nothing inside the target has nothing to judge" "SKIP secrets (no targets)"
  printf '.env\nb/local.settings.json\nprojects/x/.env\n' >"$list"
  vl --only secrets --files "$list"
  rc_is 1
  has_line "a listed one at the root" "  tracked by git: .env"
  has_line "the other name" "  tracked by git: b/local.settings.json"
  has_line "one tracked by a project's own repo" "  tracked by git: projects/x/.env"
  vl --only secrets --path b --files "$list"
  rc_is 1
  has_line "with a target: the listed one inside it" "  tracked by git: b/local.settings.json"
  lacks "and only that" "tracked by git: .env"
  rm -f "$list"
}

# The gate judges the changed files: a .env the branch adds to git fails it, also under tools/.
test_gate_fails_on_a_tracked_env_file() {
  new_judging_tree gate-tracked-env
  put svc/.env "KEY=value"
  cwj
  rc_is 0
  has "control: an untracked one is not git's yet" "PASS validate"
  git -C "$TREE" add svc/.env
  cwj
  rc_is 1
  has "a .env added to git fails the gate" "FAIL validate"
  has "and names it" "tracked by git: svc/.env"
  git -C "$TREE" rm -q --cached svc/.env
  rm "$TREE/svc/.env"
  put tools/p/local.settings.json '{}'
  git -C "$TREE" add tools/p/local.settings.json
  cwj
  rc_is 1
  has "a POC is not lint-gated, but its tracked local file fails too" "tracked by git: tools/p/local.settings.json"
}

# ---------------------------------------------------------------- lint judges the diff

# Tree whose gate runs the real validate.sh on a fake docker that judges like a linter: a listed file holding DEFECT
# fails. gitleaks fails on each file holding LEAKED in the folder it scans, or always with STUB_SECRETS_RC. Every call
# is logged. Already on main, so validate.sh is not in the diff.
new_judging_tree() {
  new_tree "$1"
  git -C "$TREE" switch -q main
  cp "$REAL_SCRIPTS/validate.sh" "$TREE/scripts/validate.sh"
  cp "$REAL_SCRIPTS/check-ledger.sh" "$TREE/scripts/check-ledger.sh"
  mkdir -p "$TREE/docker" "$TREE/scripts/lib"
  cp "$REAL_SCRIPTS/lib/env.sh" "$TREE/scripts/lib/env.sh"
  commit_all "real validate"
  git -C "$TREE" switch -q feature
  git -C "$TREE" merge -q --ff-only main
  rm -rf "$FAKE_BIN"
  mkdir -p "$FAKE_BIN"
  cat >"$FAKE_BIN/docker" <<'STUB'
#!/usr/bin/env bash
echo "docker $*" >>"$STUB_LOG"
rc=0
case "$*" in
  *" gitleaks "*)
    [ "${STUB_SECRETS_RC:-0}" -eq 0 ] || exit "$STUB_SECRETS_RC"
    for a in "$@"; do
      case "$a" in /work | /work/*) ;; *) continue ;; esac
      d="$FAKE_TREE${a#/work}"
      [ -d "$d" ] || continue
      while IFS= read -r hit; do
        echo "leak in /work${hit#"$FAKE_TREE"}"
        rc=1
      done < <(grep -rl LEAKED -- "$d")
    done
    exit "$rc"
    ;;
esac
for a in "$@"; do
  case "$a" in
    /work/*)
      f="$FAKE_TREE/${a#/work/}"
      if [ -f "$f" ] && grep -q DEFECT -- "$f"; then
        echo "defect in $a"
        rc=1
      fi
      ;;
  esac
done
exit "$rc"
STUB
  chmod +x "$FAKE_BIN/docker"
  export FAKE_TREE="$TREE"
}

# Commits the given paths on main with a defect and brings them to the branch: defects outside the diff.
old_defects() {
  local p
  git -C "$TREE" switch -q main
  for p in "$@"; do put "$p" DEFECT; done
  commit_all "defects already on main"
  git -C "$TREE" switch -q feature
  git -C "$TREE" merge -q --no-edit main
}

# Runs the gate of the tree on the fake docker.
cwj() {
  : >"$STUB_LOG"
  OUT="$(cd "$TREE" && PATH="$FAKE_BIN:$PATH" bash "$TREE/scripts/check-workspace.sh" "$@" 2>&1)"
  RC=$?
  kcov_resync
}

# The real case: MD031 at tools/container-console-docker-ce/docs/testes-manuais.md:65, already on main.
test_AC24_a_defect_outside_the_diff_does_not_fail_the_gate() {
  new_judging_tree lint-real-shape
  old_defects tools/container-console-docker-ce/docs/testes-manuais.md docs/old.md
  put docs/new.md "# clean"
  cwj
  rc_is 0
  has "AC-24 a defective .md outside the diff plus a changed clean .md passes" "PASS validate"
  log_has "AC-24 the changed file is judged" "markdownlint /work/docs/new.md"
  log_lacks "AC-24 the old defect is not" "old.md"
  log_lacks "AC-24 nor the POC one" "testes-manuais"
  log_has "AC-24 secrets judge a copy of the changed files" " gitleaks dir /work/.history/validate-secrets."
  OUT="$(cd "$TREE" && PATH="$FAKE_BIN:$PATH" bash scripts/validate.sh --only markdown 2>&1)"
  RC=$?
  kcov_resync
  rc_is 1
  has "control: the full scan does see the old defect" "defect in /work/docs/old.md"
  put docs/bad.md DEFECT
  cwj
  rc_is 1
  has "AC-24 a changed defective .md fails" "FAIL validate"
  has "AC-24 and names it" "defect in /work/docs/bad.md"
  rm "$TREE/docs/bad.md"
  printf 'more\n' >>"$TREE/docs/old.md"
  cwj
  rc_is 1
  has "AC-24 an old defect in a file the branch changes is its problem" "defect in /work/docs/old.md"
}

# Secrets judge the diff like the lint checks: the real case was a finding in another repo under projects/.
test_AC24_secrets_judge_only_the_changed_files() {
  new_judging_tree secrets-diff
  git -C "$TREE" switch -q main
  put docs/old.md LEAKED
  put tools/p/old.sh LEAKED
  commit_all "secrets already on main"
  git -C "$TREE" switch -q feature
  git -C "$TREE" merge -q --no-edit main
  put "docs/new file.md" "# clean"
  cwj
  rc_is 0
  has "AC-24 a secret outside the diff does not fail the gate" "PASS validate"
  log_has "control: the secrets scan ran" " gitleaks dir /work/.history/validate-secrets."
  put "docs/new file.md" LEAKED
  cwj
  rc_is 1
  has "AC-24 a secret in a changed file fails" "FAIL validate"
  has "AC-24 and names the real file" "leak in /work/docs/new file.md"
  lacks "AC-24 not the unchanged file" "old.md"
  lacks "AC-24 nor the path of the copy" "validate-secrets"
  ok "AC-24 the copy is removed after the scan" test -z "$(ls -A "$TREE/.history" 2>/dev/null)"
  put "docs/new file.md" "# clean"
  put tools/p/new.sh LEAKED
  cwj
  rc_is 1
  has "AC-24 a secret in a changed POC file still fails" "leak in /work/tools/p/new.sh"
  lacks "AC-24 and not the unchanged POC file" "old.sh"
  OUT="$(cd "$TREE" && PATH="$FAKE_BIN:$PATH" bash scripts/validate.sh --only secrets 2>&1)"
  RC=$?
  kcov_resync
  rc_is 1
  has "control: without --files the whole checkout is scanned" "leak in /work/docs/old.md"
}

test_AC24_each_lint_check_judges_only_the_changed_files() {
  local row name tool
  for row in shell:bin/run.sh:shellcheck dockerfile:ci/Dockerfile.app:hadolint markdown:docs/a.md:markdownlint \
    mermaid:docs/flow.mmd:mermaid python:bin/a.py:ruff typescript:web/a.ts:biome typescript:web/b.tsx:biome; do
    name="${row#*:}"
    tool="${name#*:}"
    name="${name%:*}"
    new_judging_tree "lint-$tool"
    old_defects "old/${name##*/}"
    put "$name" clean
    cwj --verbose
    rc_is 0
    has "[$name] the check runs" "PASS ${row%%:*}"
    log_has "[$name] the changed file reaches $tool" "/work/$name"
    log_lacks "[$name] the old defect does not" "/work/old/"
    put "$name" DEFECT
    cwj
    rc_is 1
    has "[$name] a changed defect fails" "defect in /work/$name"
  done
}

test_AC24_a_diagram_outside_the_diff_is_not_rendered() {
  new_judging_tree lint-diagram
  git -C "$TREE" switch -q main
  # shellcheck disable=SC2016
  printf '# o\n\n```mermaid\nDEFECT\n```\n' >"$TREE/docs/old-diagram.md"
  commit_all "old diagram"
  git -C "$TREE" switch -q feature
  git -C "$TREE" merge -q --no-edit main
  put docs/plain.md "# no diagram"
  cwj
  rc_is 0
  log_lacks "AC-24 the old diagram is not rendered" "old-diagram"
  log_lacks "AC-24 a changed file with no diagram neither" "-i /work/docs/plain.md"
  # shellcheck disable=SC2016
  printf '# n\n\n```mermaid\nDEFECT\n```\n' >"$TREE/docs/new-diagram.md"
  cwj
  rc_is 1
  log_has "AC-24 a changed diagram is rendered" "-i /work/docs/new-diagram.md"
}

test_AC24_poc_paths_are_never_lint_gated() {
  new_tree poc-only
  put tools/p/README.md "# p"
  put tools/p/run.sh "echo hi"
  put tools/p/Dockerfile "FROM x"
  put tools/p/main.tf "x"
  put tools/p/a.ts "x"
  put tools/p/.coveragerc "[run]"
  cw
  rc_is 0
  eq "AC-24 a diff entirely under tools/ runs only secrets" "--only secrets" "$(validate_args)"
  eq "AC-24 and judges no file" "" "$(listed_files)"
  has "AC-24 the parse step runs" "PASS parse"
  has "AC-24 no suite" "SKIP suites"
  new_tree poc-mixed
  put tools/p/README.md "# p"
  put docs/x.md "# x"
  cw
  rc_is 0
  eq "a mixed diff: what is outside" "--only secrets,markdown,mermaid" "$(validate_args)"
  eq "only the path outside is judged" "docs/x.md" "$(listed_files)"
  new_tree poc-lookalikes
  put tools-old/a.md "# a"
  put docs/tools/b.md "# b"
  put Pocs-And-Tools/c.md "# c"
  cw
  rc_is 0
  eq "lookalikes are gated: the list" "--only secrets,markdown,mermaid" "$(validate_args)"
  eq "lookalikes are gated: the files" 3 "$(listed_files | wc -l | tr -d ' ')"
  lacks "and no parse step" "parse"
  new_judging_tree poc-real
  old_defects docs/old.md
  put tools/p/README.md DEFECT
  put tools/p/run.sh DEFECT
  cwj
  rc_is 0
  log_lacks "AC-24 a POC defect reaches no linter" "tools"
  log_has "AC-24 secrets run" " gitleaks dir /work/.history/validate-secrets."
  STUB_SECRETS_RC=1 cwj
  rc_is 1
  has "AC-24 a secret in a POC still fails" "FAIL validate"
}

test_AC24_poc_files_must_parse() {
  new_tree poc-parse
  put tools/p/bad.sh "if then"
  cw
  rc_is 1
  has "a shell script that does not parse fails" "FAIL parse"
  has "and names it" "does not parse: tools/p/bad.sh"
  rm "$TREE/tools/p/bad.sh"
  put tools/p/bad.json '{ broken'
  cw
  rc_is 1
  has "a JSON that does not parse fails" "does not parse: tools/p/bad.json"
  put tools/p/bad.json '{}'
  put tools/p/tsconfig.json '{ // comments are allowed here
}'
  put tools/p/notes.txt 'if then'
  put tools/p/good.sh 'echo ok'
  cw
  rc_is 0
  has "valid files, tsconfig and other types pass" "PASS parse"
  if command -v python3 >/dev/null 2>&1; then
    put tools/p/bad.py 'def ('
    cw
    rc_is 1
    has "a Python file that does not parse fails" "does not parse: tools/p/bad.py"
    put tools/p/bad.py 'x = 1'
    cw
    rc_is 0
  else
    skip "python3 not installed: its parse is not exercised here"
  fi
  new_tree poc-parse-deleted
  git -C "$TREE" switch -q main
  put tools/p/gone.sh 'echo'
  commit_all "poc on main"
  git -C "$TREE" switch -q feature
  git -C "$TREE" merge -q --no-edit main
  git -C "$TREE" rm -q tools/p/gone.sh
  mkdir -p "$TREE/tools/p"
  ln -s "$TREE/nowhere" "$TREE/tools/p/link.sh"
  cw
  rc_is 0
  has "a deleted file and a link have nothing to parse" "PASS parse"
}

test_AC24_an_empty_changed_list_is_said_out_loud() {
  new_judging_tree empty-list
  old_defects docs/old.md
  cwj
  rc_is 0
  has "AC-24 no changed path is not silent" "NOTE no changed paths against main"
  has "AC-24 secrets have no changed file to judge" "SKIP secrets (no targets)"
  log_lacks "AC-24 so no scan ran" "gitleaks"
  log_lacks "AC-24 and no lint" "markdownlint"
  put docs/x.md "# x"
  cwj
  lacks "a diff has no such note" "NOTE no changed paths"
  fake_git_failing diff
  OUT="$(cd "$TREE" && PATH="$FAKE_BIN:$PATH" bash "$TREE/scripts/check-workspace.sh" 2>&1)"
  RC=$?
  kcov_resync
  rc_not_zero "AC-24 a failing diff is an error, never an empty list"
  lacks "AC-24 and no check passed" "PASS"
}

test_AC24_the_list_holds_the_changed_files_still_on_disk() {
  new_tree list-contents
  git -C "$TREE" switch -q main
  put docs/gone.md "# g"
  put docs/old-name.md "# o"
  commit_all "on main"
  git -C "$TREE" switch -q feature
  git -C "$TREE" merge -q --no-edit main
  git -C "$TREE" rm -q docs/gone.md
  git -C "$TREE" mv docs/old-name.md docs/new-name.md
  put "docs/with space.md" "# s"
  put 'docs/we"ird.md' "# w"
  put "$(printf 'docs/ta\tb.md')" "# t"
  ln -s "$TREE/nowhere" "$TREE/docs/link.md"
  cw
  rc_is 0
  eq "AC-24 a deleted markdown still asks for the check" "--only secrets,markdown,mermaid" "$(validate_args)"
  eq "AC-24 what is on disk, by its plain name" "$(printf 'docs/new-name.md\ndocs/ta\tb.md\ndocs/we"ird.md\ndocs/with space.md')" "$(listed_files | sort)"
  new_tree list-deleted-only
  git -C "$TREE" rm -q docs/decisions/README.md
  commit_all removed
  cw
  rc_is 0
  eq "AC-24 nothing to judge is an empty list" "" "$(listed_files)"
  new_judging_tree list-real-deleted
  git -C "$TREE" rm -q docs/decisions/README.md
  commit_all removed
  cwj --verbose
  rc_is 0
  has "AC-24 a check left with nothing says SKIP" "SKIP markdown (no targets)"
  new_tree list-newline
  put "$(printf 'docs/new\nline.md')" "# n"
  cw
  rc_is 1
  has "AC-24 a name a line cannot carry is a failure, never unjudged" "holds a newline"
  eq "and validate does not run" "" "$(validate_args)"
}

# Runs the validate.sh of the tree with a deadline of 5 s: RC=124 when it had to be killed, so a hang fails instead
# of stopping the suite. Output is not kept.
vl_bounded() {
  (cd "$TREE" && PATH="$FAKE_BIN:$PATH" exec bash "$TREE/scripts/validate.sh" "$@") >/dev/null 2>&1 &
  local pid=$! i=0
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 50 ]; do
    sleep 0.1
    i=$((i + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    RC=124
  else
    wait "$pid"
    RC=$?
  fi
  kcov_resync
}

test_AC25_validate_files_flag_usage() {
  new_validate_tree files-usage
  : >"$TREE/a.md"
  local list="$BASE_DIR/files.list"
  vl --only markdown --files
  rc_is 2
  vl --only markdown --files ""
  rc_is 2
  has "says so" "--files needs a value"
  vl --only markdown --files "$BASE_DIR/nowhere.list"
  rc_is 2
  has "a missing list" "--files is not a file"
  rm -f "$list"
  mkfifo "$list"
  vl_bounded --only markdown --files "$list"
  rc_is 2
  rm -f "$list"
  local bad
  for bad in /etc/hosts ../a.md a/../a.md nope.md; do
    printf '%s\n' "$bad" >"$list"
    vl --only markdown --files "$list"
    rc_is 2
    has "[$bad] is refused" "--files entry"
  done
  eq "no tool ran on a bad list" "" "$(docker_log)"
  vl --help
  has "help documents the flag" "--files <path-file>"
  rm -f "$list"
}

test_AC25_validate_files_scopes_the_lint_checks() {
  new_validate_tree files-scope
  mkdir -p "$TREE/docs" "$TREE/tools" "$TREE/web" "$TREE/ci"
  : >"$TREE/docs/in.md"
  : >"$TREE/docs/out.md"
  : >"$TREE/tools/in.sh"
  : >"$TREE/tools/out.sh"
  : >"$TREE/tools/in.py"
  : >"$TREE/tools/out.py"
  : >"$TREE/web/in.ts"
  : >"$TREE/web/out.ts"
  : >"$TREE/web/in.tsx"
  : >"$TREE/ci/Dockerfile.in"
  : >"$TREE/ci/Dockerfile.out"
  : >"$TREE/docs/in.mmd"
  : >"$TREE/docs/out.mmd"
  local list="$BASE_DIR/files.list"
  printf 'docs/in.md\ntools/in.sh\ntools/in.py\nweb/in.ts\nweb/in.tsx\nci/Dockerfile.in\ndocs/in.mmd\n' >"$list"
  vl --only shell,dockerfile,markdown,mermaid,python,typescript --files "$list"
  rc_is 0
  local f
  for f in docs/in.md tools/in.sh tools/in.py web/in.ts web/in.tsx ci/Dockerfile.in docs/in.mmd; do
    log_has "[$f] judged" "/work/$f"
  done
  for f in docs/out.md tools/out.sh tools/out.py web/out.ts ci/Dockerfile.out docs/out.mmd; do
    log_lacks "[$f] is outside the list" "/work/$f"
  done
  : >"$STUB_LOG"
  vl --only shell,dockerfile,markdown,python,typescript
  rc_is 0
  log_has "without the flag: the whole target, as today" "/work/docs/out.md"
  log_has "without the flag: shell too" "/work/tools/out.sh"
  log_has "without the flag: python too" "/work/tools/out.py"
  printf 'docs/in.md' >"$list"
  : >"$STUB_LOG"
  vl --only markdown --files "$list"
  log_has "a last line with no newline counts" "/work/docs/in.md"
}

test_AC25_validate_files_with_nothing_to_judge_says_skip() {
  new_validate_tree files-empty
  mkdir -p "$TREE/docs"
  : >"$TREE/docs/a.md"
  : >"$TREE/run.sh"
  local list="$BASE_DIR/files.list"
  : >"$list"
  vl --only secrets,shell,dockerfile,markdown,mermaid,python,typescript --files "$list"
  rc_is 0
  local c
  for c in secrets shell dockerfile markdown mermaid python typescript; do
    has "$c says SKIP" "SKIP $c (no targets)"
  done
  eq "no tool ran" "" "$(docker_log)"
  ok "and secrets left no copy behind" test ! -e "$TREE/.history"
  printf 'docs/a.md\n' >"$list"
  vl --only shell --files "$list"
  has "a list with nothing of its kind too" "SKIP shell (no targets)"
  printf 'run.sh\n' >"$list"
  vl --only secrets --path docs --files "$list"
  rc_is 0
  has "a list with nothing inside the target: secrets says SKIP" "SKIP secrets (no targets)"
  eq "and scans nothing" "" "$(docker_log)"
  : >"$STUB_LOG"
  vl --only shell,markdown
  has "without the flag the old summary stays" "PASS shell"
  log_has "and the whole target runs" "/work/run.sh"
}

test_AC25_validate_files_keeps_the_exclusions_and_the_target() {
  new_validate_tree files-exclusions
  local p list="$BASE_DIR/files.list"
  : >"$list"
  for p in tmp/worktrees/r/b/a.sh projects/x/b.sh node_modules/c.sh docs/node_modules/d.sh refs/e.sh .history/f.sh \
    .claude/g.sh docs/.data/h.sh tools/container-console-docker-ce/internal/webui/dist/i.sh ok/kept.sh; do
    mkdir -p "$TREE/$(dirname "$p")"
    : >"$TREE/$p"
    printf '%s\n' "$p" >>"$list"
  done
  vl --only shell --files "$list"
  rc_is 0
  log_has "an ordinary file stays" "/work/ok/kept.sh"
  eq "what the full scan prunes is pruned here too" 1 "$(grep -o '/work/[^ ]*\.sh' "$STUB_LOG" | wc -l | tr -d ' ')"
  log_lacks "no project file" "projects/x"
  : >"$STUB_LOG"
  vl --only shell --path tmp/worktrees/r/b --files "$list"
  log_has "a target keeps what is inside it" "/work/tmp/worktrees/r/b/a.sh"
  log_lacks "and only that" "kept.sh"
  : >"$STUB_LOG"
  printf 'projects/x/b.py\n' >"$list"
  : >"$TREE/projects/x/b.py"
  vl --only python --files "$list"
  has "a project file is not the workspace's to lint" "SKIP python (no targets)"
  : >"$STUB_LOG"
  vl --only python --path projects/x --files "$list"
  has "not even when targeted" "SKIP python (no targets)"
}

test_AC25_validate_files_leaves_the_other_checks_on_the_whole_target() {
  new_validate_tree files-others
  mkdir -p "$TREE/infra" "$TREE/svc"
  printf 'provider "x" {}\n' >"$TREE/infra/main.tf"
  : >"$TREE/svc/.coveragerc"
  : >"$TREE/a.md"
  local list="$BASE_DIR/files.list" with without
  printf 'a.md\n' >"$list"
  vl --only vuln,iac,terraform,coverage
  rc_is 0
  without="$(sed 's/ *$//' "$STUB_LOG")"
  : >"$STUB_LOG"
  vl --only vuln,iac,terraform,coverage --files "$list"
  rc_is 0
  with="$(sed 's/ *$//' "$STUB_LOG")"
  ok "control: they ran" test -n "$without"
  eq "AC-24 the same calls with and without the flag" "$without" "$with"
  log_has "terraform found the module" "-chdir=/work/infra"
  log_has "coverage found its folder" "/work/svc"
}

# ---------------------------------------------------------------- F8: validate.sh --path absolute inside the workspace

test_F8_absolute_path_inside_the_workspace_is_that_folder() {
  new_validate_tree abs-inside
  mkdir -p "$TREE/tmp/worktrees/r/b"
  : >"$TREE/tmp/worktrees/r/b/run.sh"
  vl --only secrets,shell --path "$TREE/tmp/worktrees/r/b"
  rc_is 0
  log_has "F8 the worktree is scanned where it is mounted" "dir /work/tmp/worktrees/r/b --no-banner"
  log_has "F8 with the normal config" "--config /work/docker/config/gitleaks.toml"
  log_has "F8 and its files are judged" "/work/tmp/worktrees/r/b/run.sh"
  log_lacks "F8 no host path reaches the tool" "$TREE/tmp"
  : >"$STUB_LOG"
  vl --only secrets --path "$TREE/tmp/worktrees/r/b/"
  rc_is 0
  log_has "F8 a trailing slash" "dir /work/tmp/worktrees/r/b --no-banner"
  : >"$STUB_LOG"
  vl --only secrets --path "$TREE"
  rc_is 0
  log_has "F8 the root itself is the root scan" "gitleaks-root.toml"
  log_has "F8 mounted as the root" "dir /work --no-banner"
  : >"$STUB_LOG"
  vl --only secrets --path "$TREE/tmp/worktrees/r/b/."
  rc_is 0
  log_has "F8 a dot at the end" "dir /work/tmp/worktrees/r/b --no-banner"
}

test_F8_absolute_path_through_a_link_to_the_workspace() {
  new_validate_tree abs-link
  mkdir -p "$TREE/tmp/worktrees/r/b"
  local link="$BASE_DIR/link to tree"
  rm -f "$link"
  ln -s "$TREE" "$link"
  vl --only secrets --path "$link/tmp/worktrees/r/b"
  rc_is 0
  log_has "F8 another spelling of the same folder, as /tmp on macOS" "dir /work/tmp/worktrees/r/b --no-banner"
  rm -f "$link"
}

test_F8_absolute_path_works_with_files() {
  new_validate_tree abs-files
  mkdir -p "$TREE/tmp/worktrees/r/b"
  : >"$TREE/tmp/worktrees/r/b/in.sh"
  : >"$TREE/out.sh"
  local list="$BASE_DIR/files.list"
  printf 'tmp/worktrees/r/b/in.sh\nout.sh\n' >"$list"
  vl --only shell --path "$TREE/tmp/worktrees/r/b" --files "$list"
  rc_is 0
  log_has "F8 a listed file inside the target" "/work/tmp/worktrees/r/b/in.sh"
  log_lacks "F8 not one outside it" "/work/out.sh"
}

test_F8_outside_the_workspace_stays_refused() {
  new_validate_tree abs-outside
  mkdir -p "$TREE/tmp/worktrees/r/b" "$BASE_DIR/elsewhere" "$TREE-sibling"
  ln -s "$BASE_DIR/elsewhere" "$TREE/tmp/out-link"
  local bad
  for bad in "$BASE_DIR/elsewhere" "$BASE_DIR" "$TREE-sibling" "$TREE/tmp/out-link" /; do
    vl --only secrets --path "$bad"
    rc_is 2
    has "F8 outside: $bad" "--path is outside the workspace"
    eq "F8 no tool ran for $bad" "" "$(docker_log)"
  done
  for bad in "$TREE/tmp/.." "$TREE/tmp/../tmp" "$TREE/../elsewhere" ../x x/.. x/../y ./..; do
    vl --only secrets --path "$bad"
    rc_is 2
    has "F8 '..' refused: $bad" "must not hold '..'"
    eq "F8 no tool ran for $bad" "" "$(docker_log)"
  done
  vl --only secrets --path "$TREE/nope"
  rc_is 2
  has "F8 a missing folder inside" "folder not found"
  vl --only secrets --path "$BASE_DIR/nope"
  rc_is 2
  has "F8 a missing folder outside" "folder not found"
  : >"$TREE/a-file"
  vl --only secrets --path "$TREE/a-file"
  rc_is 2
  has "F8 a file is no folder" "folder not found"
  eq "control: nothing ran" "" "$(docker_log)"
  rm -rf "$TREE-sibling" "$BASE_DIR/elsewhere"
}

test_F8_help_says_it() {
  new_validate_tree abs-help
  vl --help
  has "F8 help" "absolute inside it"
}

# ---------------------------------------------------------------- selection, stop and ledger (decision 0046)

# Runs the gate as a branch does: selection and stop on, ledger on.
branch_gate() {
  OUT="$(cd "$TREE" && CHECK_LEDGER_DISABLE="" bash "$TREE/scripts/check-workspace.sh" "$@" 2>&1)"
  RC=$?
}

test_gate_runs_only_the_suite_of_what_changed() {
  new_tree selection
  put scripts/heavy-run.sh
  branch_gate
  rc_is 0
  eq "only the suite of the changed script ran" "1" "$(grep -c '^suite ' "$STUB_LOG")"
  eq "and it is that one" "1" "$(grep -c '^suite tests/heavy-run/' "$STUB_LOG")"
  has "the others say why they did not run" "SKIP suite scripts/tests/setup-claude/test-setup-claude.sh"
  has "the time of the check is printed" "PASS suites ("
  new_tree selection-no-suite
  put scripts/sonar.sh
  branch_gate
  eq "a script with no suite runs none" "0" "$(grep -c '^suite ' "$STUB_LOG")"
  new_tree selection-gate
  printf '# changed\n' >>"$TREE/scripts/validate.sh"
  branch_gate
  eq "a gate script runs only the suite that depends on it" "1" "$(grep -c '^suite ' "$STUB_LOG")"
  eq "the gate's own suite" "1" "$(grep -c '^suite tests/check-workspace/' "$STUB_LOG")"
  has "an unrelated suite is skipped" "SKIP suite scripts/tests/heavy-run/test-heavy-run.sh"
  new_tree selection-lib
  put scripts/lib/projects.sh
  branch_gate
  eq "a shared library runs the suites of the scripts that source it, or call one that does" "4" "$(grep -c '^suite ' "$STUB_LOG")"
  eq "the projects layout suite" "1" "$(grep -c '^suite tests/test-projects-layout.sh' "$STUB_LOG")"
  eq "and the single-agent suite" "1" "$(grep -c '^suite tests/single-agent/' "$STUB_LOG")"
  eq "and the project state suite" "1" "$(grep -c '^suite tests/aiwp-project-state/' "$STUB_LOG")"
  eq "and the gate suite (bring)" "1" "$(grep -c '^suite tests/aiwp-gate/' "$STUB_LOG")"
  new_tree selection-test-lib
  put scripts/tests/lib/lib.sh
  branch_gate
  eq "the shared test library runs the suite that sources it" "1" "$(grep -c '^suite ' "$STUB_LOG")"
  eq "the single-agent suite" "1" "$(grep -c '^suite tests/single-agent/' "$STUB_LOG")"
  new_tree selection-guard
  put scripts/guard-subagent-model.sh
  branch_gate
  eq "the guard runs its suite" "1" "$(grep -c '^suite tests/guard-subagent-model/' "$STUB_LOG")"
  eq "and no other" "1" "$(grep -c '^suite ' "$STUB_LOG")"
  new_tree selection-settings
  put rules/agents/settings.json '{"hooks":{}}'
  branch_gate
  rc_is 0
  eq "settings.json alone runs the subagent guard suite" "1" "$(grep -c '^suite tests/guard-subagent-model/' "$STUB_LOG")"
  eq "and the bash guard suite" "1" "$(grep -c '^suite tests/guard-bash/' "$STUB_LOG")"
  eq "and the single-agent suite" "1" "$(grep -c '^suite tests/single-agent/' "$STUB_LOG")"
  eq "and the aiwp suite (the release notice hook)" "1" "$(grep -c '^suite tests/aiwp/' "$STUB_LOG")"
  eq "and no other" "4" "$(grep -c '^suite ' "$STUB_LOG")"
  branch_gate
  has "same settings.json" "CACHED suite scripts/tests/guard-subagent-model/test-guard-subagent-model.sh"
  put rules/agents/settings.json '{"hooks":{"a":1}}'
  branch_gate
  eq "a changed settings.json runs them again" "8" "$(grep -c '^suite ' "$STUB_LOG")"
}

test_gate_stops_at_the_first_failure() {
  new_tree stop-validate
  put scripts/heavy-run.sh
  STUB_VALIDATE_RC=1 branch_gate
  rc_is 1
  eq "validate failed: no suite ran" "0" "$(grep -c '^suite ' "$STUB_LOG")"
  STUB_VALIDATE_RC=1 branch_gate --all
  eq "--all still runs them" "$SUITE_COUNT" "$(grep -c '^suite ' "$STUB_LOG")"
  new_tree stop-suite
  put scripts/heavy-run.sh
  STUB_FAIL_SUITE=tests/heavy-run/test-heavy-run.sh branch_gate
  rc_is 1
  has "a failed suite says how to run it alone" "run it alone: bash scripts/tests/heavy-run/test-heavy-run.sh"
}

test_floor_skips_the_suites() {
  new_tree floor
  put scripts/heavy-run.sh
  branch_gate --floor
  rc_is 0
  eq "no suite ran" "0" "$(log_count suite)"
  has "the skip says why" "SKIP suites (--floor"
  has "the other checks still ran" "PASS validate"
  branch_gate
  ok "without --floor the suite runs" test "$(log_count suite)" -gt 0
  cw --help
  has "the help names the option" "--floor"
}

test_ledger_runs_a_suite_once_per_state() {
  new_tree ledger-suite
  put scripts/heavy-run.sh
  STUB_FAIL_SUITE=tests/heavy-run/test-heavy-run.sh branch_gate
  rc_is 1
  branch_gate
  rc_is 0
  eq "a failure is not recorded: it runs again" "2" "$(grep -c '^suite ' "$STUB_LOG")"
  branch_gate
  rc_is 0
  has "same inputs" "CACHED suite scripts/tests/heavy-run/test-heavy-run.sh"
  eq "do not run again" "2" "$(grep -c '^suite ' "$STUB_LOG")"
  put scripts/heavy-run.sh "changed"
  branch_gate
  eq "a changed input runs it" "3" "$(grep -c '^suite ' "$STUB_LOG")"
  branch_gate --no-cache
  eq "--no-cache runs it" "4" "$(grep -c '^suite ' "$STUB_LOG")"
  printf '# changed gate\n' >>"$TREE/scripts/check-workspace.sh"
  branch_gate
  lacks "a changed gate script passes nothing from the ledger" "CACHED suite"
}

# With --files the key of a check is the content of the listed files; for secrets also which of them git tracks.
test_ledger_sees_a_listed_env_file_become_tracked() {
  new_validate_tree ledger-tracked-env
  printf '.history/\n' >"$TREE/.gitignore"
  put svc/.env "KEY=value"
  git -C "$TREE" init -q -b main
  git -C "$TREE" add .gitignore
  git -C "$TREE" commit -q -m init
  local list="$BASE_DIR/files.list"
  printf 'svc/.env\n' >"$list"
  CHECK_LEDGER_DISABLE="" vl --only secrets --files "$list"
  rc_is 0
  CHECK_LEDGER_DISABLE="" vl --only secrets --files "$list"
  has "same list, same content, still untracked" "CACHED secrets"
  git -C "$TREE" add svc/.env
  CHECK_LEDGER_DISABLE="" vl --only secrets --files "$list"
  rc_is 1
  has "tracked now: the old pass is not reused" "FAIL secrets"
  rm -f "$list"
}

test_ledger_keeps_a_validate_pass_while_the_folder_holds() {
  new_validate_tree ledger-validate
  put docs/a.md
  printf '.history/\n' >"$TREE/.gitignore"
  git -C "$TREE" init -q -b main
  git -C "$TREE" add -A
  git -C "$TREE" commit -q -m init
  CHECK_LEDGER_DISABLE="" vl --only secrets
  rc_is 0
  CHECK_LEDGER_DISABLE="" vl --only secrets
  has "same folder" "CACHED secrets"
  eq "the tool ran once" "1" "$(grep -c '^docker ' "$STUB_LOG")"
  put docs/a.md "changed"
  CHECK_LEDGER_DISABLE="" vl --only secrets
  has "a changed file runs it" "PASS secrets"
  STUB_DOCKER_RC=1 CHECK_LEDGER_DISABLE="" vl --only markdown
  rc_is 1
  STUB_DOCKER_RC=0 CHECK_LEDGER_DISABLE="" vl --only markdown
  has "a failure is not recorded" "PASS markdown"
  rm -rf "$TREE/.git"
  CHECK_LEDGER_DISABLE="" vl --only secrets
  CHECK_LEDGER_DISABLE="" vl --only secrets
  has "outside git nothing is cached" "PASS secrets"
}

# ---------------------------------------------------------------- a product in a subfolder of its repo

# Fresh throwaway repo whose product sits in workspace/ (the layout of the public repo), with a README.md and a
# maintainers/ folder of its own at the repo root, outside the product. TREE stays the product folder.
new_nested_tree() {
  new_tree "$1"
  local repo="$BASE_DIR/nested repo"
  rm -rf "$repo" "$TREE/.git"
  mkdir -p "$repo/maintainers"
  printf '# Repo\n' >"$repo/README.md"
  printf '# Release\n' >"$repo/maintainers/release.md"
  mv "$TREE" "$repo/workspace"
  git -C "$repo" init -q -b main
  git -C "$repo" add -A
  git -C "$repo" commit -q -m init
  git -C "$repo" switch -q -c feature
  TREE="$repo/workspace"
  NESTED="$repo"
}

# Puts TREE back on the plain throwaway tree after a nested test.
end_nested_tree() {
  rm -rf "$NESTED"
  TREE="$BASE_DIR/work tree"
}

test_nested_changed_paths_are_relative_to_the_product() {
  new_nested_tree nested-paths
  put docs/guide.md "# Guide"
  put scripts/new.py
  commit_all
  put rules/x.sh
  printf 'outside\n' >>"$NESTED/README.md"
  printf '# Notes\n' >"$NESTED/maintainers/notes.md"
  printf 'x\n' >"$NESTED/root.sh"
  cw
  rc_is 0
  eq "the product's own paths, product-relative" "--only secrets,shell,markdown,mermaid,python" "$(validate_args)"
  OUT="$(listed_files)"
  has "a committed file, product-relative" "docs/guide.md"
  has "an untracked file, product-relative" "rules/x.sh"
  lacks "no path keeps the repo prefix" "workspace/"
  lacks "a change outside the product is not the gate's" "README.md"
  lacks "the repo's maintainers/ is not the product" "maintainers/"
  lacks "an untracked file outside the product is not the gate's" "root.sh"
  eq "every suite ran" "$SUITE_COUNT" "$(log_count suite)"
  end_nested_tree
}

test_nested_decisions_and_settings() {
  new_nested_tree nested-decisions
  put docs/decisions/0001-again.md
  cw
  rc_is 1
  has "the product's decision records" "duplicate decision number 1"
  rm "$TREE/docs/decisions/0001-again.md"
  printf '{}\n{}\n' >"$TREE/rules/agents/settings.json"
  cw
  rc_is 1
  has "a changed settings file, seen through the repo prefix" "FAIL settings"
  end_nested_tree
}

test_nested_custom_terms() {
  new_nested_tree nested-terms
  commit_on_main
  local terms="$BASE_DIR/terms.txt"
  printf 'acme\n' >"$terms"
  printf 'acme outside the product\n' >"$NESTED/maintainers/acme.md"
  AIWP_TERMS_FILE="$terms" cw
  rc_is 0
  has "the paths outside the product pass" "PASS custom-terms"
  put CHANGELOG.md "acme release"
  commit_on_main
  put docs/guide.md "ACME guide"
  AIWP_TERMS_FILE="$terms" cw
  rc_is 1
  has "a committed history line, product-relative" "CHANGELOG.md:1:acme release"
  lacks "no history path keeps the repo prefix" "workspace/CHANGELOG.md"
  has "a product file, product-relative" "docs/guide.md:1:ACME guide"
  lacks "no file outside the product" "maintainers/acme.md"
  rm -f "$terms"
  end_nested_tree
}

test_nested_custom_terms_in_a_linked_worktree() {
  new_nested_tree nested-terms-worktree
  printf '/custom/\n/tmp/\n' >"$TREE/.gitignore"
  commit_on_main
  put custom/core-terms.txt "acme"
  local wt="$BASE_DIR/nested wt"
  rm -rf "$wt"
  git -C "$NESTED" worktree add -q -b feat/wt "$wt" main
  printf 'ACME corp\n' >"$wt/workspace/README.md"
  OUT="$(cd "$wt" && bash "$wt/workspace/scripts/check-workspace.sh" --all 2>&1)"
  RC=$?
  kcov_resync
  rc_is 1
  has "the worktree reads the list at the same place in the main checkout" "README.md:1:ACME corp"
  git -C "$NESTED" worktree remove --force "$wt"
  end_nested_tree
}

test_custom_terms_from_AIWP_TERMS_FILE() {
  new_tree terms-env
  put custom/core-terms.txt "other"
  put docs/guide.md "Built for ACME Corp"
  local terms="$BASE_DIR/terms.txt"
  printf '# list\nacme\n' >"$terms"
  AIWP_TERMS_FILE="$terms" cw
  rc_is 1
  has "the named list wins over custom/" "docs/guide.md:1:Built for ACME Corp"
  printf '# only a comment\n' >"$terms"
  AIWP_TERMS_FILE="$terms" cw
  rc_is 0
  has "an empty named list skips" "lists no term"
  AIWP_TERMS_FILE="$BASE_DIR/missing.txt" cw
  rc_is 1
  has "a named list that is missing fails" "AIWP_TERMS_FILE names no file"
  rm -f "$terms"
}

# Writes i18n/<locale>/<doc> in the nested repo for each locale given (default: pt-BR and es), with the source line of
# the English file as it is now, then a blank line and a body.
translate() { # doc [locale...]
  local doc="$1" hash loc
  shift
  [ $# -gt 0 ] || set -- pt-BR es
  hash="$(sha256sum <"$NESTED/$doc" | awk '{ print $1 }')"
  for loc in "$@"; do
    mkdir -p "$NESTED/i18n/$loc/$(dirname "$doc")"
    printf '<!-- source: %s sha256:%s -->\n\n# Translated\n' "$doc" "$hash" >"$NESTED/i18n/$loc/$doc"
  done
}

# Nested repo with i18n/ and one document of each kind in scope, all translated, plus files out of scope.
new_i18n_tree() {
  new_nested_tree "$1"
  put README.md "# Product"
  put docs/guide.md "# Guide"
  put docs/sub/deep.md "# Deep"
  put tools/t/README.md "# Tool"
  put tools/t/docs/ops.md "# Ops"
  put tools/t/web/README.md "# Web"
  put tools/t/notes/other.md "# Not a doc"
  put CHANGELOG.md "# Changelog"
  put docs/decisions/0002-second.md "# Second"
  local d
  for d in README.md workspace/README.md workspace/docs/guide.md workspace/docs/sub/deep.md workspace/tools/t/README.md \
    workspace/tools/t/docs/ops.md workspace/tools/t/web/README.md; do
    translate "$d"
  done
}

test_i18n_skips_without_the_folder() {
  new_tree i18n-plain
  cw
  rc_is 0
  has "a plain checkout skips" "SKIP i18n: no i18n/ at the repo root"
  new_nested_tree i18n-nested-none
  put docs/guide.md "# Guide"
  cw
  rc_is 0
  has "a repo with no i18n/ skips" "SKIP i18n: no i18n/ at the repo root"
  end_nested_tree
}

test_i18n_passes_when_every_document_is_translated() {
  new_i18n_tree i18n-pass
  cw
  rc_is 0
  has "passes" "PASS i18n"
  lacks "nothing out of scope is asked" "missing translation"
  commit_all
  cw
  rc_is 0
  has "committed files pass too" "PASS i18n"
  end_nested_tree
}

test_i18n_fails_on_a_missing_translation() {
  new_i18n_tree i18n-missing
  rm "$NESTED/i18n/es/workspace/docs/guide.md" "$NESTED/i18n/pt-BR/README.md"
  put docs/new.md "# New"
  cw
  rc_is 1
  has "fails" "FAIL i18n"
  has "a product document" "missing translation: i18n/es/workspace/docs/guide.md (of workspace/docs/guide.md)"
  has "the root README" "missing translation: i18n/pt-BR/README.md (of README.md)"
  has "an untracked new document, in both locales" "missing translation: i18n/pt-BR/workspace/docs/new.md"
  has "and es" "missing translation: i18n/es/workspace/docs/new.md"
  lacks "a translated one is fine" "i18n/pt-BR/workspace/docs/guide.md (of"
  end_nested_tree
}

test_i18n_fails_without_the_source_line() {
  new_i18n_tree i18n-no-source
  printf '# Guia\n' >"$NESTED/i18n/pt-BR/workspace/docs/guide.md"
  sed -i.bak 's#source: workspace/tools/t/README.md#source: workspace/tools/t/README#' "$NESTED/i18n/es/workspace/tools/t/README.md"
  rm -f "$NESTED/i18n/es/workspace/tools/t/README.md.bak"
  : >"$NESTED/i18n/es/workspace/docs/sub/deep.md"
  cw
  rc_is 1
  has "no header" "no source line: i18n/pt-BR/workspace/docs/guide.md (line 1 must be exactly: <!-- source: workspace/docs/guide.md sha256:"
  has "a header naming another path" "no source line: i18n/es/workspace/tools/t/README.md"
  has "an empty file" "no source line: i18n/es/workspace/docs/sub/deep.md"
  end_nested_tree
}

test_i18n_fails_on_an_outdated_hash() {
  new_i18n_tree i18n-outdated
  printf 'a new paragraph\n' >>"$TREE/docs/guide.md"
  printf 'changed\n' >>"$NESTED/README.md"
  cw
  rc_is 1
  has "a changed product document" "outdated translation: i18n/pt-BR/workspace/docs/guide.md"
  has "both locales" "outdated translation: i18n/es/workspace/docs/guide.md"
  has "the root README" "outdated translation: i18n/es/README.md"
  translate workspace/docs/guide.md
  translate README.md
  cw
  rc_is 0
  has "a new hash passes" "PASS i18n"
  end_nested_tree
}

test_i18n_fails_on_an_orphan_translation() {
  new_i18n_tree i18n-orphan
  rm "$TREE/tools/t/docs/ops.md"
  mkdir -p "$NESTED/i18n/fr/workspace"
  printf 'x\n' >"$NESTED/i18n/fr/workspace/README.md"
  mkdir -p "$NESTED/i18n/es/workspace/docs/decisions"
  printf 'x\n' >"$NESTED/i18n/es/workspace/docs/decisions/0001-first.md"
  printf 'about the translations\n' >"$NESTED/i18n/README.md"
  cw
  rc_is 1
  has "its source is gone" "orphan translation: i18n/pt-BR/workspace/tools/t/docs/ops.md (no document workspace/tools/t/docs/ops.md needs it"
  has "in both locales" "orphan translation: i18n/es/workspace/tools/t/docs/ops.md"
  has "a decision record is never translated" "orphan translation: i18n/es/workspace/docs/decisions/0001-first.md"
  lacks "another locale of a real document is no orphan" "i18n/fr/workspace/README.md"
  lacks "a file right under i18n/ is no translation" "i18n/README.md"
  end_nested_tree
}

# Writes file $1, relative to the nested repo root, with content $2.
put_root() { # path content
  mkdir -p "$NESTED/$(dirname "$1")"
  printf '%s\n' "${2:-x}" >"$NESTED/$1"
}

test_i18n_requires_the_repository_documents() {
  new_i18n_tree i18n-repo-docs
  put_root maintainers/plans/README.md "# Plans"
  put_root docs/guide.md "# Project guide"
  put_root docs/decisions/0001-first.md "# First"
  put_root node_modules/pkg/README.md "# Package"
  put_root web/node_modules/pkg/README.md "# Package"
  put node_modules/pkg/README.md "# Package"
  put_root .claude/README.md "# Settings"
  put_root tmp/README.md "# Scratch"
  cw
  rc_is 1
  has "fails" "FAIL i18n"
  has "a nested README outside the product" "missing translation: i18n/pt-BR/maintainers/plans/README.md (of maintainers/plans/README.md)"
  has "in both locales" "missing translation: i18n/es/maintainers/plans/README.md"
  has "a root docs/ document" "missing translation: i18n/es/docs/guide.md (of docs/guide.md)"
  lacks "a root decision record is not asked" "docs/decisions/0001-first.md"
  lacks "node_modules/ at any depth is not asked" "node_modules"
  lacks ".claude/ is not asked" ".claude/README.md"
  lacks "tmp/ is not asked" "tmp/README.md"
  lacks "a non-README outside docs/ is not asked" "maintainers/release.md"
  translate maintainers/plans/README.md
  translate docs/guide.md
  cw
  rc_is 0
  has "translated, it passes" "PASS i18n"
  end_nested_tree
}

test_i18n_fails_on_an_orphan_of_a_root_document() {
  new_i18n_tree i18n-root-orphan
  put_root docs/guide.md "# Project guide"
  translate docs/guide.md
  cw
  rc_is 0
  has "translated, it passes" "PASS i18n"
  rm "$NESTED/docs/guide.md"
  cw
  rc_is 1
  has "its source is gone" "orphan translation: i18n/pt-BR/docs/guide.md (no document docs/guide.md needs it"
  has "in both locales" "orphan translation: i18n/es/docs/guide.md"
  end_nested_tree
}

# Tree with one missing, one outdated and one orphan translation.
i18n_pending_tree() {
  new_i18n_tree "$1"
  rm "$NESTED/i18n/es/workspace/docs/guide.md"
  printf 'changed\n' >>"$NESTED/README.md"
  mkdir -p "$NESTED/i18n/pt-BR/workspace/docs"
  printf 'x\n' >"$NESTED/i18n/pt-BR/workspace/docs/gone.md"
}

test_i18n_pending_reports_and_passes() {
  i18n_pending_tree i18n-pending
  cw --i18n-pending
  rc_is 0
  has "passes with the count" "PASS i18n (4 pending translations)"
  has "a missing one is pending" "  pending: missing translation: i18n/es/workspace/docs/guide.md (of workspace/docs/guide.md)"
  has "an outdated one is pending" "  pending: outdated translation: i18n/pt-BR/README.md"
  has "in both locales" "  pending: outdated translation: i18n/es/README.md"
  has "an orphan is pending" "  pending: orphan translation: i18n/pt-BR/workspace/docs/gone.md"
  lacks "no failure" "FAIL i18n"
  cw
  rc_is 1
  has "without the option it fails as before" "FAIL i18n"
  has "with the same message" "  missing translation: i18n/es/workspace/docs/guide.md"
  lacks "and no pending line" "pending:"
  end_nested_tree
}

test_i18n_pending_without_findings_has_no_count() {
  new_i18n_tree i18n-pending-clean
  cw --i18n-pending
  rc_is 0
  has "passes" "PASS i18n ("
  lacks "no count when nothing is pending" "pending translations"
  end_nested_tree
}

test_i18n_pending_is_never_reused_by_a_strict_run() {
  i18n_pending_tree i18n-pending-ledger
  branch_gate --i18n-pending
  rc_is 0
  has "the pending run passes" "PASS i18n (4 pending translations)"
  branch_gate
  rc_is 1
  has "a strict run on the same inputs still fails" "FAIL i18n"
  lacks "nothing served from the ledger for i18n" "CACHED i18n"
  end_nested_tree
}

# --only <test_name> runs one test; a failed test prints the command that runs it alone.
# --deep also runs the extreme cases, diffs larger than a pipe (rules/quality.md "Tests").
ONLY=""
if [ "${1:-}" = "--only" ]; then ONLY="${2:-}"; fi
for t in $(declare -F | awk '{ print $3 }' | grep '^test_'); do
  if [ -n "$ONLY" ] && [ "$t" != "$ONLY" ]; then continue; fi
  if [ -z "$ONLY" ] && [ "${1:-}" != "--deep" ]; then
    case "$t" in test_AC24_big_diff_*) continue ;; esac
  fi
  CURRENT="$t"
  failed_before="$FAILED"
  "$t"
  if [ "$FAILED" -ne "$failed_before" ]; then echo "run it alone: bash ${BASH_SOURCE[0]} --only $t"; fi
done
echo "RESULT passed=$PASS failed=$FAILED skipped=$SKIPPED"
[ "$FAILED" -eq 0 ]
