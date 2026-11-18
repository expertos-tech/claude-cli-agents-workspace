#!/usr/bin/env bash
# The review fixtures of tests/review-fixtures/: lists them, and judges the reviewer's report of each one against its
# expected level. Never calls the model: /caw-merge --main runs the reviewer on each fixture and saves the reports.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash tests/review-fixtures.sh list | judge <reports folder> | --help

The fixtures (tests/review-fixtures/f<nn>.md) are made-up changes: one per hard rule of workspace/rules/security.md
"Hard rules", expected BLOCKER, and some expected WARNING only (tests/review-fixtures/levels.txt). They prove that the
merge review still stops each hard rule and lets the rest through, at the release only: each run calls the model.

  list           one line per fixture: <path of the fixture> (the expected levels are never printed: they are not
                 for the reviewer)
  judge <dir>    reads <dir>/f<nn>.txt, the reviewer's report of each fixture in the format of .claude/rules/review.md,
                 and prints one line per fixture:
                   PASS|FAIL f<nn> expected=<BLOCKER|WARNING> actual=<BLOCKER|WARNING|NONE|NO-REPORT> — <what it stands for>
                 actual: BLOCKER when the report holds a "[BLOCKER]" finding, else WARNING when it holds a "[WARNING]"
                 one, else NONE; NO-REPORT when the file is missing, empty or holds no "VERDICT:" line. A BLOCKER
                 fixture passes with BLOCKER; a WARNING fixture passes with WARNING or NONE (no BLOCKER).
                 Then "result: <passed>/<total> fixtures as expected".

Exit codes: 0 every fixture as expected (list: listed); 1 a fixture not as expected, or the fixtures are malformed;
2 usage error.

Examples:
  bash tests/review-fixtures.sh list
  bash tests/review-fixtures.sh judge tmp/review-fixtures/20261118-120000
USAGE
}

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
dir="$repo/tests/review-fixtures"
levels="$dir/levels.txt"

# Prints "<fixture> <level> <what>" for each line of levels.txt; fails on a malformed line or a missing fixture file.
read_levels() {
  local name level what bad=0
  [ -r "$levels" ] || { echo "error: $levels not found" >&2; return 1; }
  while read -r name level what; do
    case "$name" in "" | "#"*) continue ;; esac
    if ! [[ "$name" =~ ^f[0-9]{2}$ ]] || { [ "$level" != BLOCKER ] && [ "$level" != WARNING ]; } || [ -z "$what" ]; then
      echo "error: malformed line of levels.txt: $name $level $what" >&2
      bad=1
      continue
    fi
    [ -f "$dir/$name.md" ] || { echo "error: no fixture file for $name: tests/review-fixtures/$name.md" >&2; bad=1; continue; }
    printf '%s %s %s\n' "$name" "$level" "$what"
  done <"$levels"
  return "$bad"
}

# Prints the level a report gives: BLOCKER, WARNING, NONE, or NO-REPORT.
report_level() {
  local file="$1"
  if [ ! -s "$file" ] || ! grep -q '^[[:space:]]*VERDICT:' "$file"; then
    echo NO-REPORT
  elif grep -q '\[BLOCKER\]' "$file"; then
    echo BLOCKER
  elif grep -q '\[WARNING\]' "$file"; then
    echo WARNING
  else
    echo NONE
  fi
}

cmd_list() {
  local out name
  out="$(read_levels)" || return 1
  while read -r name _; do
    printf 'tests/review-fixtures/%s.md\n' "$name"
  done <<<"$out"
}

cmd_judge() {
  local reports="$1" out name level what actual ok total=0 passed=0
  [ -d "$reports" ] || { echo "error: no reports folder: $reports" >&2; exit 2; }
  out="$(read_levels)" || return 1
  while read -r name level what; do
    total=$((total + 1))
    actual="$(report_level "$reports/$name.txt")"
    ok=FAIL
    if [ "$level" = BLOCKER ] && [ "$actual" = BLOCKER ]; then ok=PASS; fi
    if [ "$level" = WARNING ] && { [ "$actual" = WARNING ] || [ "$actual" = NONE ]; }; then ok=PASS; fi
    [ "$ok" = FAIL ] || passed=$((passed + 1))
    printf '%s %s expected=%s actual=%s — %s\n' "$ok" "$name" "$level" "$actual" "$what"
  done <<<"$out"
  echo "result: $passed/$total fixtures as expected"
  [ "$passed" -eq "$total" ]
}

case "${1:-}" in
  --help | -h) usage ;;
  list)
    [ $# -eq 1 ] || { echo "error: list takes no argument; see --help" >&2; exit 2; }
    cmd_list
    ;;
  judge)
    [ $# -eq 2 ] || { echo "error: usage: judge <reports folder>; see --help" >&2; exit 2; }
    cmd_judge "$2"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
