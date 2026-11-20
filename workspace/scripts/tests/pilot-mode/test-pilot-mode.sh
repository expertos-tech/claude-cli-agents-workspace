#!/usr/bin/env bash
# Tests of scripts/pilot-mode.sh: the default pilot mode of an installation (.claude/pilot-mode), the start context line
# of each default, /pilot turned off by custom/rules-config.json, and the writes of /pilot auto and /pilot assisted.
# A fake workspace root per test, never the real one.
# Run: bash scripts/tests/pilot-mode/test-pilot-mode.sh [--only <test_name>]
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(cd "$HERE/../.." && pwd)/pilot-mode.sh"
MANIFEST="$(cd "$HERE/../../.." && pwd)/rules/manifest.json"
BASE="$(mktemp -d)"
trap 'chmod -R u+w "$BASE" 2>/dev/null; rm -rf "$BASE"' EXIT
FAILED=0
OUT=""
RC=0
CURRENT=""
ROOT=""

LINE_ASSISTED="Pilot mode: assisted (the default of this installation). Read rules/assisted.md in full before your first reply and follow it."
LINE_AUTO="Pilot mode: auto (the default of this installation)."
LINE_OFF="Pilot mode: auto (/pilot is turned off in custom/rules-config.json)."

# A fresh workspace root: the manifest of the mandatory core, the skill pilot, an empty .claude/.
fixture() {
  ROOT="$BASE/$CURRENT"
  rm -rf "$ROOT"
  mkdir -p "$ROOT/rules/skills/pilot" "$ROOT/.claude"
  cp "$MANIFEST" "$ROOT/rules/manifest.json"
  printf -- '---\nname: pilot\n---\n\nbody\n' >"$ROOT/rules/skills/pilot/SKILL.md"
  printf '# AGENTS.md\n' >"$ROOT/AGENTS.md"
}

# Runs the script on the fixture root with the arguments given; sets OUT and RC.
run() {
  OUT="$(bash "$SCRIPT" "$@" --root "$ROOT" 2>&1)"
  RC=$?
}

# Writes the default file with the raw content $1 (printf format).
default_file() {
  # shellcheck disable=SC2059  # the content is the format on purpose: tests pass \n and odd bytes
  printf "$1" >"$ROOT/.claude/pilot-mode"
}

# Turns the skill pilot off in custom/rules-config.json.
pilot_off() {
  mkdir -p "$ROOT/custom"
  printf '{"core": {"skills": {"exclude": ["pilot"]}}}\n' >"$ROOT/custom/rules-config.json"
}

check() { # description, status (0 = ok)
  if [ "$2" -ne 0 ]; then
    FAILED=$((FAILED + 1))
    echo "FAIL $CURRENT: $1 (rc=$RC out=[$OUT])"
  fi
}
rc_is() { [ "$RC" -eq "$1" ]; check "rc $1" $?; }
out_is() { [ "$OUT" = "$1" ]; check "output is [$1]" $?; }
has() { case "$OUT" in *"$1"*) ;; *) check "missing [$1]" 1 ;; esac; }
content_is() { [ "$(cat "$1" 2>/dev/null)" = "$2" ]; check "content of $1 is [$2]" $?; }

# --- the start context line (AC-10): no file, auto, assisted, an unknown value, pilot turned off

test_context_with_no_file_is_assisted() {
  fixture
  run context
  rc_is 0
  out_is "$LINE_ASSISTED"
  rm -rf "$ROOT/.claude"
  run context
  rc_is 0
  out_is "$LINE_ASSISTED"
}

test_context_with_auto() {
  fixture
  default_file 'auto\n'
  run context
  rc_is 0
  out_is "$LINE_AUTO"
  # Spaces, a CR and no final line break are read the same.
  default_file '  auto \r\n'
  run context
  out_is "$LINE_AUTO"
  default_file 'auto'
  run context
  out_is "$LINE_AUTO"
}

test_context_with_assisted() {
  fixture
  default_file 'assisted\n'
  run context
  rc_is 0
  out_is "$LINE_ASSISTED"
}

test_context_with_an_unknown_value_is_assisted() {
  fixture
  local value
  for value in 'manual\n' 'AUTO\n' 'auto mode\n' '\n' '' 'off\nauto\n'; do
    default_file "$value"
    run context
    rc_is 0
    out_is "$LINE_ASSISTED"
  done
  # A link is never read, wherever it points.
  printf 'auto\n' >"$BASE/elsewhere-$CURRENT"
  rm -f "$ROOT/.claude/pilot-mode"
  ln -s "$BASE/elsewhere-$CURRENT" "$ROOT/.claude/pilot-mode"
  run context
  out_is "$LINE_ASSISTED"
  # A folder in its place.
  rm -f "$ROOT/.claude/pilot-mode"
  mkdir "$ROOT/.claude/pilot-mode"
  run context
  rc_is 0
  out_is "$LINE_ASSISTED"
}

test_context_with_pilot_turned_off_is_auto() {
  fixture
  pilot_off
  run context
  rc_is 0
  out_is "$LINE_OFF"
  default_file 'assisted\n'
  run context
  out_is "$LINE_OFF"
  default_file 'auto\n'
  run context
  out_is "$LINE_OFF"
  # A configuration that cannot be used turns nothing off (setup-claude.sh then loads the whole core, /pilot too).
  printf '{"core": {"skills": {"exclude": ["pilot"]' >"$ROOT/custom/rules-config.json"
  default_file 'assisted\n'
  run context
  rc_is 0
  out_is "$LINE_ASSISTED"
  # Another skill turned off: /pilot is still there.
  printf '{"core": {"skills": {"exclude": ["frontend"]}}}\n' >"$ROOT/custom/rules-config.json"
  run context
  out_is "$LINE_ASSISTED"
}

test_context_never_fails() {
  fixture
  default_file 'auto\n'
  chmod 000 "$ROOT/.claude/pilot-mode"
  run context
  rc_is 0
  [ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 1 ]; check "one line" $?
  chmod 644 "$ROOT/.claude/pilot-mode"
}

# --- show

test_show_names_the_default_and_where_it_comes_from() {
  fixture
  run
  rc_is 0
  out_is "default: assisted (no .claude/pilot-mode)"
  default_file 'auto\n'
  run show
  out_is "default: auto (.claude/pilot-mode)"
  default_file 'assisted\n'
  run show
  out_is "default: assisted (.claude/pilot-mode)"
  default_file 'manual\n'
  run show
  out_is "default: assisted (.claude/pilot-mode holds a value it does not know)"
  pilot_off
  run show
  out_is "default: auto (/pilot is turned off in custom/rules-config.json)"
}

# --- set: /pilot auto and /pilot assisted write the default (AC-2); /pilot manual never does (AC-3)

test_set_auto_then_assisted() {
  fixture
  run set auto
  rc_is 0
  out_is "written: .claude/pilot-mode (auto)"
  content_is "$ROOT/.claude/pilot-mode" auto
  run context
  out_is "$LINE_AUTO"
  run set assisted
  rc_is 0
  out_is "written: .claude/pilot-mode (assisted)"
  content_is "$ROOT/.claude/pilot-mode" assisted
  run context
  out_is "$LINE_ASSISTED"
  [ -z "$(find "$ROOT/.claude" -name '.pilot-mode.*')" ]; check "no temporary file left" $?
}

test_set_manual_or_an_unknown_mode_changes_nothing() {
  fixture
  default_file 'auto\n'
  local mode
  for mode in manual Auto off ""; do
    run set "$mode"
    rc_is 2
    content_is "$ROOT/.claude/pilot-mode" auto
  done
  run set manual
  has "manual is a choice of one session"
  run context
  out_is "$LINE_AUTO"
  rm -f "$ROOT/.claude/pilot-mode"
  run set manual
  rc_is 2
  [ ! -e "$ROOT/.claude/pilot-mode" ]; check "manual writes no file" $?
}

test_set_creates_the_folder_and_replaces_a_link() {
  fixture
  rm -rf "$ROOT/.claude"
  run set auto
  rc_is 0
  content_is "$ROOT/.claude/pilot-mode" auto
  # A link at the file is replaced, never followed.
  printf 'keep\n' >"$BASE/target-$CURRENT"
  rm -f "$ROOT/.claude/pilot-mode"
  ln -s "$BASE/target-$CURRENT" "$ROOT/.claude/pilot-mode"
  run set assisted
  rc_is 0
  [ ! -L "$ROOT/.claude/pilot-mode" ]; check "the link is replaced by a file" $?
  content_is "$ROOT/.claude/pilot-mode" assisted
  content_is "$BASE/target-$CURRENT" keep
}

# Regression: mv -f onto a link to a folder moved the file into that folder and still printed "written".
test_set_replaces_a_link_to_a_folder_and_refuses_a_folder() {
  fixture
  mkdir -p "$BASE/dir-$CURRENT" "$ROOT/.claude"
  rm -f "$ROOT/.claude/pilot-mode"
  ln -s "$BASE/dir-$CURRENT" "$ROOT/.claude/pilot-mode"
  run set auto
  rc_is 0
  local status=0
  [ ! -L "$ROOT/.claude/pilot-mode" ] || status=1
  check "the link to a folder is replaced by a file" "$status"
  content_is "$ROOT/.claude/pilot-mode" auto
  status=0
  [ -z "$(ls -A "$BASE/dir-$CURRENT")" ] || status=1
  check "nothing is written inside the linked folder" "$status"
  rm -f "$ROOT/.claude/pilot-mode"
  mkdir "$ROOT/.claude/pilot-mode"
  run set assisted
  rc_is 1
  has "is a folder; nothing written"
  status=0
  [ -z "$(ls -A "$ROOT/.claude/pilot-mode")" ] || status=1
  check "nothing is written inside the folder" "$status"
}

test_set_with_pilot_turned_off_writes_and_says_so() {
  fixture
  pilot_off
  run set assisted
  rc_is 0
  has "written: .claude/pilot-mode (assisted)"
  has "note: /pilot is turned off in custom/rules-config.json"
  run context
  out_is "$LINE_OFF"
}

test_set_in_a_folder_that_cannot_be_written_fails() {
  fixture
  [ "$(id -u)" -ne 0 ] || return 0
  default_file 'assisted\n'
  chmod 555 "$ROOT/.claude"
  run set auto
  rc_is 1
  has "error: cannot write"
  chmod 755 "$ROOT/.claude"
  content_is "$ROOT/.claude/pilot-mode" assisted
}

# --- usage

test_usage_errors_and_help() {
  fixture
  run --help
  rc_is 0
  has "Usage: scripts/pilot-mode.sh"
  has "$LINE_ASSISTED"
  has "$LINE_AUTO"
  has "$LINE_OFF"
  run set
  rc_is 2
  run show context
  rc_is 2
  run unknown
  rc_is 2
  OUT="$(bash "$SCRIPT" context --root "$BASE/missing-$CURRENT" 2>&1)"
  RC=$?
  rc_is 2
  has "error: --root is not a folder"
}

only=""
if [ "${1:-}" = "--only" ]; then
  [ $# -ge 2 ] || { echo "error: --only needs a test name" >&2; exit 2; }
  only="$2"
elif [ $# -gt 0 ]; then
  echo "usage: $0 [--only <test_name>]" >&2
  exit 2
fi
tests="$(declare -F | awk '{print $3}' | grep '^test_')"
[ -z "$only" ] || { echo "$tests" | grep -qx "$only" || { echo "error: no such test: $only" >&2; exit 2; }; tests="$only"; }
count=0
for t in $tests; do
  CURRENT="$t"
  "$t"
  count=$((count + 1))
done
if [ "$FAILED" -eq 0 ]; then echo "ok: $count tests"; else echo "failed: $FAILED checks"; exit 1; fi
