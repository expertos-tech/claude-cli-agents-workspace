#!/usr/bin/env bash
# Tests of tests/review-fixtures.sh and of the fixture set, with made-up reports: never calls the model. The fixtures
# themselves run against the reviewer only at the release (/caw-merge --main). Run: bash tests/test-review-fixtures.sh
# check takes the status of the test right before it on purpose: SC2319 does not apply.
# shellcheck disable=SC2319
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$HERE/.." && pwd -P)"
SCRIPT="$HERE/review-fixtures.sh"
BASE="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$BASE"' EXIT
FAILED=0
COUNT=0
OUT=""
RC=0
CURRENT=""
TOTAL="$(grep -c '^f[0-9][0-9] ' "$REPO/tests/review-fixtures/levels.txt")"

check() { # description, status (0 = ok)
  COUNT=$((COUNT + 1))
  if [ "$2" -ne 0 ]; then
    FAILED=$((FAILED + 1))
    echo "FAIL $CURRENT: $1 (rc=$RC out=[$OUT])"
  fi
}
has() { case "$OUT" in *"$1"*) check "has [$1]" 0 ;; *) check "missing [$1]" 1 ;; esac; }
hasnt() { case "$OUT" in *"$1"*) check "unexpected [$1]" 1 ;; *) check "no [$1]" 0 ;; esac; }
rc_is() { [ "$RC" -eq "$1" ]; check "rc $1" $?; }
run() {
  OUT="$(bash "$SCRIPT" "$@" 2>&1)"
  RC=$?
}

blocker_report() { printf 'VERDICT: REJECTED\nFINDINGS:\n- [BLOCKER] a/b.sh:1 — p — s — f\n- [WARNING] a/b.sh:2 — w — y — d\n' >"$1"; }
warning_report() { printf 'VERDICT: APPROVED_WITH_WARNINGS\nFINDINGS:\n- [WARNING] a/b.sh:2 — w — y — d\n' >"$1"; }
clean_report() { printf 'VERDICT: APPROVED\nFINDINGS:\n' >"$1"; }

# Writes, in <dir>, the report each fixture expects: a BLOCKER for a BLOCKER fixture, a warning for a WARNING one.
expected_reports() {
  local dir="$1" name level
  mkdir -p "$dir"
  while read -r name level _; do
    case "$name" in "" | "#"*) continue ;; esac
    if [ "$level" = BLOCKER ]; then blocker_report "$dir/$name.txt"; else warning_report "$dir/$name.txt"; fi
  done <"$REPO/tests/review-fixtures/levels.txt"
}

test_the_set_covers_each_hard_rule() {
  CURRENT="${FUNCNAME[0]}"
  local rules blockers warnings f
  # The rows of the table under "## Hard rules" of the product's security rules, header and separator left out.
  rules="$(awk '/^## /{on = ($0 == "## Hard rules")} on && /^\| / {n++} END {print n - 2}' "$REPO/workspace/rules/security.md")"
  blockers="$(grep -c '^f[0-9][0-9] BLOCKER ' "$REPO/tests/review-fixtures/levels.txt")"
  warnings="$(grep -c '^f[0-9][0-9] WARNING ' "$REPO/tests/review-fixtures/levels.txt")"
  [ "$rules" -ge 6 ]; check "the hard rules table read ($rules rows)" $?
  [ "$blockers" -eq "$rules" ]; check "one BLOCKER fixture per hard rule ($blockers for $rules)" $?
  [ "$warnings" -ge 3 ]; check "at least three WARNING fixtures ($warnings)" $?
  run list
  rc_is 0
  [ "$(printf '%s\n' "$OUT" | grep -c '^tests/review-fixtures/f[0-9][0-9]\.md$')" -eq $((blockers + warnings)) ]
  check "list prints every fixture" $?
  hasnt "BLOCKER"
  hasnt "WARNING"
  for f in "$REPO"/tests/review-fixtures/f[0-9][0-9].md; do
    grep -q '^## Request$' "$f" && grep -q '^## Diff$' "$f" && grep -q '^```diff$' "$f"
    check "$(basename "$f") holds a request and a diff" $?
    ! grep -qE 'BLOCKER|WARNING|levels\.txt' "$f"
    check "$(basename "$f") gives the reviewer no expected level" $?
  done
}

test_judge_passes_the_expected_levels() {
  CURRENT="${FUNCNAME[0]}"
  local dir="$BASE/ok" name
  expected_reports "$dir"
  run judge "$dir"
  rc_is 0
  has "PASS f01 expected=BLOCKER actual=BLOCKER"
  has "PASS f09 expected=WARNING actual=WARNING"
  hasnt "FAIL"
  has "result: $TOTAL/$TOTAL fixtures as expected"
  # A WARNING fixture with no finding at all passes too: it has no BLOCKER.
  name="$(grep -m1 '^f[0-9][0-9] WARNING ' "$REPO/tests/review-fixtures/levels.txt" | cut -d' ' -f1)"
  clean_report "$dir/$name.txt"
  run judge "$dir"
  rc_is 0
  has "PASS $name expected=WARNING actual=NONE"
  # "[BLOCKER]" in prose is no finding: only a line "- [BLOCKER] ..." is.
  printf 'VERDICT: APPROVED_WITH_WARNINGS\nNo [BLOCKER] found.\nFINDINGS:\n- [WARNING] a/b.sh:2 — w — y — d\n' >"$dir/$name.txt"
  run judge "$dir"
  rc_is 0
  has "PASS $name expected=WARNING actual=WARNING"
}

test_judge_fails_a_missed_or_wrong_level() {
  CURRENT="${FUNCNAME[0]}"
  local dir="$BASE/wrong"
  expected_reports "$dir"
  warning_report "$dir/f02.txt"
  blocker_report "$dir/f08.txt"
  rm "$dir/f05.txt"
  printf 'the reviewer stopped\n' >"$dir/f06.txt"
  run judge "$dir"
  rc_is 1
  has "FAIL f02 expected=BLOCKER actual=WARNING"
  has "FAIL f08 expected=WARNING actual=BLOCKER"
  has "FAIL f05 expected=BLOCKER actual=NO-REPORT"
  has "FAIL f06 expected=BLOCKER actual=NO-REPORT"
  has "PASS f01 expected=BLOCKER actual=BLOCKER"
  has "result: $((TOTAL - 4))/$TOTAL fixtures as expected"
}

test_usage() {
  CURRENT="${FUNCNAME[0]}"
  run --help
  rc_is 0
  has "Usage: bash tests/review-fixtures.sh"
  run
  rc_is 2
  run judge
  rc_is 2
  run judge "$BASE/none"
  rc_is 2
  run list extra
  rc_is 2
}

test_the_set_covers_each_hard_rule
test_judge_passes_the_expected_levels
test_judge_fails_a_missed_or_wrong_level
test_usage
if [ "$FAILED" -eq 0 ]; then echo "ok: $COUNT checks"; else echo "failed: $FAILED of $COUNT checks"; exit 1; fi
