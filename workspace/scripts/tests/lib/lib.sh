#!/usr/bin/env bash
# Harness of the single-agent tests: isolated fixture repos, assertions, discovery of test_* functions.
# Every test runs in a subshell against its own repo through EDIT_QUEUE_ROOT, never the real workspace.
# shellcheck disable=SC2034  # Variables set here are read by the test files that source this one.
set -uo pipefail

# Under kcov (PS4 method) only the scripts under test need tracing; every bash it starts traces again
# through BASH_ENV. Not tracing the harness keeps its captured output away from kcov's parser, see kcov_resync.
{ set +x; } 2>/dev/null

export LC_ALL=C
unset CDPATH CLAUDE_CODE_SESSION_ID CLAUDE_PROJECT_DIR GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

QE_TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QE_REPO="$(cd "$QE_TESTS/../../.." && pwd)"
QE_TMP="${QUEUE_EDIT_TEST_TMP:-$QE_REPO/tmp/.data/session-tools-tests}"
mkdir -p "$QE_TMP"

# Records a note that is printed even when the test passes, such as a part that was skipped.
note() {
  echo "$*" >>"$QE_NOTES"
}

# Stops the current test with a message.
fail() {
  echo "FAIL: $*"
  exit 1
}

# Skips the current test, with its reason as the last line of the log.
skip_test() {
  echo "$*"
  exit 77
}

# Compares two values.
assert_eq() {
  [ "$1" = "$2" ] || fail "${3:-values differ}: expected [$1], got [$2]"
}

# Checks that a text holds a fixed string.
assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "${3:-text} does not contain [$2]: [$1]" ;;
  esac
}

# Checks that a text does not hold a fixed string.
assert_not_contains() {
  case "$1" in
    *"$2"*) fail "${3:-text} contains [$2]: [$1]" ;;
  esac
}

# Checks the exit code of the last call.
assert_exit() {
  [ "$RC" -eq "$1" ] || fail "expected exit $1, got $RC: $OUT"
}

# Checks how many lines of a file equal a fixed text.
assert_line_count() {
  local file="$1" line="$2" expected="$3" n
  n="$(grep -c -x -F -- "$line" "$file")"
  [ "$n" -eq "$expected" ] || fail "$file has [$line] $n times, expected $expected"
}

# Checks that a path exists.
assert_exists() {
  [ -e "$1" ] || fail "missing: $1"
}

# Checks that a path does not exist.
assert_missing() {
  [ ! -e "$1" ] || fail "should not exist: $1"
}

# Creates the isolated repo of a test and points the script under test at it.
new_fixture() {
  FIX_DIR="$(mktemp -d "$QE_TMP/fix.XXXXXX")"
  FIX="$FIX_DIR/repo"
  AUX="$FIX_DIR/aux"
  mkdir -p "$FIX/docs" "$FIX/scripts" "$FIX/projects/acme" "$AUX"
  git init -q "$FIX"
  git -C "$FIX" config user.name "Fictitious Person"
  git -C "$FIX" config user.email "person@example.test"
  fixture_files
  git -C "$FIX" add -A
  git -C "$FIX" commit -q -m "fixture"
  export EDIT_QUEUE_ROOT="$FIX"
}

# Writes the versioned files of the fixture repo, mirroring the workspace's ignore rules.
fixture_files() {
  printf '.history/\n/projects/*\n!/projects/README.md\n**/.env\n/tmp/\nignored.md\n' >"$FIX/.gitignore"
  printf '# Fixture\n\nIntro line\n' >"$FIX/README.md"
  printf '# Changes\n\n- first\n' >"$FIX/CHANGELOG.md"
  printf 'l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\n' >"$FIX/docs/lines.md"
  printf '| a | b |\n| 1 | 2 |\n| 3 | 4 |\n| 5 | 6 |\n' >"$FIX/docs/table.md"
  printf '{\n  "alpha": 1,\n  "beta": 2,\n  "gamma": 3\n}\n' >"$FIX/config.json"
  printf 'key: value\n' >"$FIX/settings.yaml"
  printf '#!/usr/bin/env bash\n' >"$FIX/scripts/run.sh"
  printf '# Projects\n\n| name |\n' >"$FIX/projects/README.md"
  printf '# History\n' >"$FIX/history.txt"
}

# Waits for background processes and removes the fixture; its path is always inside the test folder.
teardown_fixture() {
  [ -n "${FIX_DIR:-}" ] || return 0
  wait 2>/dev/null
  case "$FIX_DIR" in
    "$QE_TMP"/fix.*) rm -rf "$FIX_DIR" ;;
  esac
}

# kcov 43 counts single quotes across trace lines and has no notion of $'...'. A traced value holding a
# newline and an apostrophe, such as $'it\'s\n', leaves it waiting for a closing quote, and it ignores
# every later line, of every process, without any error: that is what took scope.sh to 52% in a full
# run. Tracing one 'it'\''s' always ends outside a quote, whatever the state before it.
kcov_resync() {
  [ -n "${KCOV_BASH_XTRACEFD:-}" ] || return 0
  (
    set -x
    : "it's"
  )
}

# Runs every test_* function of the file, each in a subshell with its own fixture, and prints the result.
# A test_defect_* proves a production defect still open: it fails until the defect is fixed, and the name
# loses the prefix then. QUEUE_EDIT_SKIP_DEFECTS=1 skips them, to read the state of everything else.
run_tests() {
  local t rc log passed=0 failed=0 skipped=0 names
  names="$(declare -F | awk '{ print $3 }' | grep '^test_')"
  QE_NOTES="$(mktemp "$QE_TMP/notes.XXXXXX")"
  for t in $names; do
    case "$t:${QUEUE_EDIT_SKIP_DEFECTS:-0}" in
      test_defect_*:1)
        skipped=$((skipped + 1))
        echo "skip $t: open defect, QUEUE_EDIT_SKIP_DEFECTS=1"
        continue
        ;;
    esac
    log="$(mktemp "$QE_TMP/log.XXXXXX")"
    (
      trap teardown_fixture EXIT
      new_fixture
      "$t"
    ) >"$log" 2>&1
    rc=$?
    case "$rc" in
      0)
        passed=$((passed + 1))
        [ "${QUEUE_EDIT_VERBOSE:-0}" -eq 0 ] || echo "ok   $t"
        case "$t" in
          test_defect_*) echo "note: $t passes now: rename it without test_defect_" ;;
        esac
        ;;
      77)
        skipped=$((skipped + 1))
        echo "skip $t: $(tail -n 1 "$log")"
        ;;
      *)
        failed=$((failed + 1))
        echo "FAIL $t"
        sed 's/^/     /' "$log"
        ;;
    esac
    rm -f "$log"
  done
  sed 's/^/note: /' "$QE_NOTES"
  rm -f "$QE_NOTES"
  echo "RESULT $passed $failed $skipped"
  [ "$failed" -eq 0 ]
}
