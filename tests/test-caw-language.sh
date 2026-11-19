#!/usr/bin/env bash
# Tests of tests/caw-language.py (the SessionStart hook of the maintenance session that asks for the preferred
# language) on throwaway folders in a temporary directory, removed on exit: each scenario points CLAUDE_PROJECT_DIR,
# CLAUDE_CONFIG_DIR and HOME at folders of its own, so the real user settings and the real
# .claude/settings.local.json of this repository are never read; it runs the hook, then asserts its status, that it
# printed nothing on stderr, and that its output is empty or the SessionStart JSON that asks for the language.
# The tests run through a list built at run time: SC2329 does not apply. "$CLAUDE_PROJECT_DIR" in single quotes is the
# hook's command written as is in the settings, never an expansion: SC2016 does not apply.
# shellcheck disable=SC2329,SC2016
set -uo pipefail

usage() {
  cat <<'USAGE'
Usage: tests/test-caw-language.sh [--only <test_name>] [--help]

Runs the scenarios of tests/caw-language.py: a "language" in .claude/settings.local.json of CLAUDE_PROJECT_DIR, in
$CLAUDE_CONFIG_DIR/settings.json or, with no CLAUDE_CONFIG_DIR, in $HOME/.claude/settings.json makes the hook print
nothing; none set, it prints the SessionStart JSON whose context asks for the language first and says where to save
it; a malformed, unreadable or non-UTF-8 settings file (local or user), a value that is not a non-empty string, a
missing CLAUDE_PROJECT_DIR, a missing HOME and any stdin still exit 0 with nothing on stderr; .claude/settings.json of
this repository (read only) registers the hook on startup|resume|clear|compact. Prints one FAIL line per failed
assertion and "ok: <n> tests" at the end.

Exit codes: 0 every test passed; 1 a test failed; 2 usage error.

Examples:
  bash tests/test-caw-language.sh
  bash tests/test-caw-language.sh --only test_set_local
USAGE
}

ONLY=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help | -h) usage; exit 0 ;;
    --only)
      [ "$#" -ge 2 ] && [ -n "$2" ] || { echo "error: --only needs a test name" >&2; exit 2; }
      ONLY="$2"
      shift 2
      ;;
    *) echo "error: unknown argument: $1" >&2; exit 2 ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO="$(cd "$HERE/.." && pwd -P)"
HOOK="$HERE/caw-language.py"
[ -f "$HOOK" ] || { echo "error: tests/caw-language.py not found" >&2; exit 2; }
BASE="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$BASE"' EXIT
FAILED=0
COUNT=0
OUT=""
RAW=""
ERR=""
RC=0
CURRENT=""
# The folders of the current test: the project (CLAUDE_PROJECT_DIR), the user config (CLAUDE_CONFIG_DIR) and HOME.
P=""
U=""
H=""
ASK="ask the person their preferred language of communication"

# Creates fresh, empty project, user config and home folders for the current test, and sets P, U and H.
fresh() {
  rm -rf "${BASE:?}/$CURRENT"
  P="$BASE/$CURRENT/project"
  U="$BASE/$CURRENT/config"
  H="$BASE/$CURRENT/home"
  mkdir -p "$P/.claude" "$U" "$H/.claude"
}

# Writes <content> to the file <file>.
put() { printf '%s\n' "$2" >"$1"; }

# Runs the hook with <stdin> as its input and the environment <assignments...> (NAME=value; P, U and H are not set
# unless given), never the caller's CLAUDE_PROJECT_DIR, CLAUDE_CONFIG_DIR or HOME. Keeps its status in RC, its stderr
# in ERR, its stdout in RAW, and the additionalContext of its JSON in OUT (empty when it printed nothing). An output
# that is neither empty nor the SessionStart JSON fails the test.
hook() {
  local stdin="$1"
  shift
  RAW="$(printf '%s' "$stdin" |
    env -u CLAUDE_PROJECT_DIR -u CLAUDE_CONFIG_DIR -u HOME "$@" python3 -I -B "$HOOK" 2>"$BASE/stderr")"
  RC=$?
  ERR="$(cat "$BASE/stderr")"
  OUT=""
  [ -n "$RAW" ] || return 0
  OUT="$(printf '%s' "$RAW" | python3 -I -B -c '
import json, sys
data = json.load(sys.stdin)
out = data["hookSpecificOutput"]
assert set(data) == {"hookSpecificOutput"} and set(out) == {"hookEventName", "additionalContext"}
assert out["hookEventName"] == "SessionStart"
sys.stdout.write(out["additionalContext"])
' 2>/dev/null)" || {
    OUT=""
    fail "the output is not the SessionStart JSON: ${RAW:0:200}"
  }
}

# Runs the hook with the project, the user config and the home of the current test, and an empty stdin.
hook_all() { hook "" "CLAUDE_PROJECT_DIR=$P" "CLAUDE_CONFIG_DIR=$U" "HOME=$H"; }

# Records a failed assertion of the current test with <message>.
fail() {
  echo "FAIL $CURRENT: $1"
  FAILED=$((FAILED + 1))
}

# Asserts the last run returned <rc>.
status_is() { [ "$RC" -eq "$1" ] || fail "expected status $1, got $RC"; }

# Asserts the last run printed nothing on stderr (no traceback).
quiet() { [ -z "$ERR" ] || fail "stderr: ${ERR:0:300}"; }

# Asserts the context of the last run holds the fixed string <text>.
has() { printf '%s\n' "$OUT" | grep -qF -- "$1" || fail "context lacks: $1"; }

# Asserts the last run exited 0, quietly, and printed nothing: a language is set. <why> names the case.
silent() {
  status_is 0
  quiet
  [ -z "$RAW" ] || fail "$1: expected no output, got: ${RAW:0:200}"
}

# Asserts the last run exited 0, quietly, with the context that asks for the language. <why> names the case.
asks() {
  status_is 0
  quiet
  printf '%s\n' "$OUT" | grep -qF -- "$ASK" || fail "$1: the context does not ask for the language: ${RAW:0:200}"
}

test_unset() {
  fresh
  hook_all
  asks "no settings file"
  has "In your first reply, before anything else"
  has 'the key `language` in `.claude/settings.local.json` of the repository root'
  has "keep every other key"
  has "at most 40 characters of letters, spaces, hyphens and parentheses"
  has "reply in that language"
  put "$P/.claude/settings.local.json" '{"permissions": {"allow": []}}'
  put "$U/settings.json" '{"model": "opus"}'
  hook_all
  asks "settings files without a language"
}

test_set_local() {
  fresh
  put "$P/.claude/settings.local.json" '{"language": "portuguese", "permissions": {"allow": []}}'
  hook_all
  silent "language in the local settings"
}

test_set_user_config_dir() {
  fresh
  put "$U/settings.json" '{"language": "spanish"}'
  hook_all
  silent "language in \$CLAUDE_CONFIG_DIR/settings.json"
}

test_set_user_home() {
  fresh
  put "$H/.claude/settings.json" '{"language": "spanish"}'
  hook "" "CLAUDE_PROJECT_DIR=$P" "HOME=$H"
  silent "language in \$HOME/.claude/settings.json, no CLAUDE_CONFIG_DIR"
  hook "" "CLAUDE_PROJECT_DIR=$P" "CLAUDE_CONFIG_DIR=" "HOME=$H"
  silent "language in \$HOME/.claude/settings.json, CLAUDE_CONFIG_DIR empty"
}

test_config_dir_replaces_home() {
  fresh
  put "$H/.claude/settings.json" '{"language": "spanish"}'
  hook_all
  asks "CLAUDE_CONFIG_DIR set: \$HOME/.claude is not the user settings"
}

test_malformed_local() {
  fresh
  put "$P/.claude/settings.local.json" '{ "language": "portuguese",'
  hook_all
  asks "malformed local settings"
  put "$U/settings.json" '{"language": "spanish"}'
  hook_all
  silent "malformed local settings, language in the user settings"
}

test_malformed_user() {
  fresh
  put "$U/settings.json" 'not json at all'
  hook_all
  asks "malformed user settings"
  put "$P/.claude/settings.local.json" '{"language": "portuguese"}'
  hook_all
  silent "malformed user settings, language in the local settings"
  rm "$P/.claude/settings.local.json"
  put "$H/.claude/settings.json" '['
  hook "" "CLAUDE_PROJECT_DIR=$P" "HOME=$H"
  asks "malformed \$HOME/.claude/settings.json"
}

test_unreadable() {
  fresh
  mkdir "$P/.claude/settings.local.json"
  printf '{"language": "\377\376"}\n' >"$U/settings.json"
  hook_all
  asks "a folder as the local settings, a non-UTF-8 user settings"
  printf '' >"$H/.claude/settings.json"
  hook "" "CLAUDE_PROJECT_DIR=$P" "HOME=$H"
  asks "an empty user settings file"
}

test_not_a_string() {
  local value
  fresh
  for value in '1' 'null' 'true' '""' '"   "' '["portuguese"]' '{"name": "portuguese"}'; do
    put "$P/.claude/settings.local.json" "{\"language\": $value}"
    put "$U/settings.json" "{\"language\": $value}"
    hook_all
    asks "language $value"
  done
  put "$P/.claude/settings.local.json" '["language", "portuguese"]'
  put "$U/settings.json" '"portuguese"'
  hook_all
  asks "settings that are not a JSON object"
}

test_missing_project_dir() {
  fresh
  hook "" "CLAUDE_CONFIG_DIR=$U" "HOME=$H"
  asks "no CLAUDE_PROJECT_DIR, no user language"
  hook "" "CLAUDE_PROJECT_DIR=" "CLAUDE_CONFIG_DIR=$U" "HOME=$H"
  asks "empty CLAUDE_PROJECT_DIR, no user language"
  put "$U/settings.json" '{"language": "spanish"}'
  hook "" "CLAUDE_CONFIG_DIR=$U" "HOME=$H"
  silent "no CLAUDE_PROJECT_DIR, language in the user settings"
  hook "" "CLAUDE_PROJECT_DIR=$BASE/$CURRENT/none" "CLAUDE_CONFIG_DIR=$U" "HOME=$H"
  silent "CLAUDE_PROJECT_DIR not a folder, language in the user settings"
}

test_missing_home() {
  fresh
  hook "" "CLAUDE_PROJECT_DIR=$P"
  asks "no HOME, no CLAUDE_CONFIG_DIR"
  hook ""
  asks "no variable at all"
}

test_stdin() {
  local stdin
  fresh
  for stdin in '' '{"source": "compact", "hook_event_name": "SessionStart"}' '{ not json' "$(printf '\377\376')"; do
    hook "$stdin" "CLAUDE_PROJECT_DIR=$P" "CLAUDE_CONFIG_DIR=$U" "HOME=$H"
    asks "stdin ${stdin:0:20}"
  done
  put "$P/.claude/settings.local.json" '{"language": "portuguese"}'
  hook '{"source": "resume"}' "CLAUDE_PROJECT_DIR=$P" "CLAUDE_CONFIG_DIR=$U" "HOME=$H"
  silent "stdin resume, language set"
}

test_registered() {
  OUT="$(python3 -I -B -c '
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    settings = json.load(handle)
command = sys.argv[2]
for entry in settings["hooks"]["SessionStart"]:
    for hook in entry.get("hooks", []):
        if hook.get("type") == "command" and hook.get("command") == command:
            needed = {"startup", "resume", "clear", "compact"}
            assert needed <= set(entry.get("matcher", "").split("|")), entry.get("matcher")
            assert hook.get("timeout") == 10, hook.get("timeout")
            print("registered")
            sys.exit(0)
print("not registered: " + command)
sys.exit(1)
' "$REPO/.claude/settings.json" 'python3 -I -B "$CLAUDE_PROJECT_DIR/tests/caw-language.py"' 2>&1)"
  RC=$?
  status_is 0
  has "registered"
}

test_usage() {
  OUT="$(python3 -I -B "$HOOK" --help 2>&1)"
  RC=$?
  status_is 0
  has "usage: tests/caw-language.py"
  has "Exit codes"
  OUT="$(python3 -I -B "$HOOK" --bogus </dev/null 2>&1)"
  RC=$?
  status_is 2
  OUT="$(bash "$HERE/test-caw-language.sh" --help 2>&1)"
  RC=$?
  status_is 0
  has "Usage: tests/test-caw-language.sh"
  OUT="$(bash "$HERE/test-caw-language.sh" --bogus 2>&1)"
  RC=$?
  status_is 2
  has "unknown argument"
}

TESTS="$(declare -F | awk '{ print $3 }' | grep '^test_')"
if [ -n "$ONLY" ]; then
  printf '%s\n' "$TESTS" | grep -qxF "$ONLY" || { echo "error: no test named $ONLY" >&2; exit 2; }
  TESTS="$ONLY"
fi
for CURRENT in $TESTS; do
  COUNT=$((COUNT + 1))
  "$CURRENT"
done
if [ "$FAILED" -eq 0 ]; then echo "ok: $COUNT tests"; else echo "failed: $FAILED checks"; exit 1; fi
