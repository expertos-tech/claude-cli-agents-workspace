#!/usr/bin/env bash
# Tests of tests/caw-session-index.py (the SessionStart hook of the maintenance session) on this repository's tree,
# read only, and on throwaway copies of its index files in a temporary folder, removed on exit: each scenario runs the
# hook with a hook JSON on stdin, then asserts its status, that its output is the SessionStart JSON, and the context.
# The tests run through a list built at run time: SC2329 does not apply. Backticks in single quotes are markdown
# written as is, never a command substitution: SC2016 does not apply.
# shellcheck disable=SC2329,SC2016
set -uo pipefail

usage() {
  cat <<'USAGE'
Usage: tests/test-caw-session-index.sh [--only <test_name>] [--help]

Runs the scenarios of tests/caw-session-index.py: the real tree gives the index of the git, review, security, models,
docs and scripts rules with their layers and without the ignored files; the substitutions of the mapping apply;
the triggers of a file named in several rows merge; "compact" adds the compaction line; a row added to the product's
Reference appears with no change to .claude/session-index.md; an ignored file leaves a row that names others; a
missing file or section, a malformed line or an index too long gives the fallback context with exit 0; empty and
invalid stdin are fine; the context stays under 10,000 characters. Prints one FAIL line per failed assertion and
"ok: <n> tests" at the end.

Exit codes: 0 every test passed; 1 a test failed; 2 usage error.

Examples:
  bash tests/test-caw-session-index.sh
  bash tests/test-caw-session-index.sh --only test_compact_line
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
HOOK="$HERE/caw-session-index.py"
[ -f "$HOOK" ] || { echo "error: tests/caw-session-index.py not found" >&2; exit 2; }
for f in workspace/AGENTS.md .claude/session-index.md; do
  [ -f "$REPO/$f" ] || { echo "error: $f not found" >&2; exit 2; }
done
BASE="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$BASE"' EXIT
FAILED=0
COUNT=0
OUT=""
ERR=""
RC=0
CURRENT=""
R=""
FALLBACK="The rules index of this session could not be built"

# Creates a fresh tree for the current test with copies of the real index files and maintenance rules, and sets R.
fresh() {
  R="$BASE/$CURRENT"
  rm -rf "$R"
  mkdir -p "$R/workspace" "$R/.claude/rules"
  cp "$REPO/workspace/AGENTS.md" "$R/workspace/AGENTS.md"
  cp "$REPO/.claude/session-index.md" "$R/.claude/session-index.md"
  cp "$REPO"/.claude/rules/*.md "$R/.claude/rules/"
}

# Runs the hook on the tree <root> (empty: the default, this repository) with <stdin> as its input; keeps its status
# in RC, its stderr in ERR, and the additionalContext of its JSON in OUT. An output that is not the SessionStart JSON
# fails the test and leaves OUT empty.
hook() {
  local root="$1" stdin="$2" raw
  local -a args=()
  [ -z "$root" ] || args=(--root "$root")
  raw="$(printf '%s' "$stdin" | python3 -I -B "$HOOK" "${args[@]}" 2>"$BASE/stderr")"
  RC=$?
  ERR="$(cat "$BASE/stderr")"
  OUT="$(printf '%s' "$raw" | python3 -I -B -c '
import json, sys
data = json.load(sys.stdin)
out = data["hookSpecificOutput"]
assert set(data) == {"hookSpecificOutput"} and out["hookEventName"] == "SessionStart"
sys.stdout.write(out["additionalContext"])
' 2>/dev/null)" || {
    OUT=""
    fail "the output is not the SessionStart JSON: ${raw:0:200}"
  }
}

# Records a failed assertion of the current test with <message>.
fail() {
  echo "FAIL $CURRENT: $1"
  [ -z "$OUT" ] || printf '%s\n' "$OUT" | sed 's/^/    | /'
  FAILED=$((FAILED + 1))
}

# Asserts the last run returned <rc>.
status_is() { [ "$RC" -eq "$1" ] || fail "expected status $1, got $RC"; }

# Asserts the context of the last run holds the fixed string <text>.
has() { printf '%s\n' "$OUT" | grep -qF -- "$1" || fail "context lacks: $1"; }

# Asserts the context of the last run does not hold the fixed string <text>.
lacks() { ! printf '%s\n' "$OUT" | grep -qF -- "$1" || fail "context holds: $1"; }

# Asserts the context of the last run has exactly <n> lines starting with the fixed string <prefix>.
lines_starting() {
  local n
  n="$(printf '%s\n' "$OUT" | awk -v p="$2" 'index($0, p) == 1 { c++ } END { print c + 0 }')"
  [ "$n" -eq "$1" ] || fail "expected $1 line(s) starting with $2, got $n"
}

# Asserts the last run printed nothing on stderr (no traceback).
quiet() { [ -z "$ERR" ] || fail "stderr: ${ERR:0:300}"; }

# Asserts the last run gave the fallback context with the reason <reason>.
fallback() {
  status_is 0
  quiet
  has "$FALLBACK: $1"
  has 'Read the section "Reference" of `workspace/AGENTS.md` and `.claude/session-index.md`'
  lacks "- \`workspace/rules/git.md\`"
}

# Inserts the line <line> after the first line of the file <file> that starts with the fixed string <after>.
insert_after() {
  awk -v a="$2" -v l="$3" '{ print } !done && index($0, a) == 1 { print l; done = 1 }' "$1" >"$1.new" && mv "$1.new" "$1"
}

test_real_tree() {
  local name
  hook "" '{"session_id": "x", "hook_event_name": "SessionStart", "source": "startup"}'
  status_is 0
  quiet
  has "Rules index of this session"
  for name in git review security models docs scripts; do
    lines_starting 1 "- \`workspace/rules/$name.md\` (then \`.claude/rules/$name.md\` over it): "
  done
  for name in quality.md rules/rules.md frontend.md infra.md machine-load.md "$FALLBACK"; do
    lacks "$name"
  done
  has "- \`maintainers/requests/README.md\`: before writing, ordering or running a request"
  has "- \`workspace/templates/request.md\`, \`workspace/rules/request-writing.md\`: before writing a functional request"
}

test_substitutions() {
  hook "" '{"source": "startup"}'
  lacks "the gate"
  lacks "a wave"
  lacks "Terraform"
  has "before the review of /caw-merge, or doing one"
  has "before opening a clone, a commit, /caw-merge, a release, or closing a stage"
}

test_merged_triggers() {
  hook "" '{"source": "resume"}'
  lines_starting 1 "- \`workspace/rules/security.md\`"
  has "(then \`.claude/rules/security.md\` over it): before deciding whether a finding or a check is a refusal or a warning (\"Hard rules\", \"Warnings\"); before anything that goes to this public repository: a commit, a plan, a request; when touching code"
  lines_starting 1 "- \`workspace/rules/scripts.md\`"
  has "when touching shell; when touching \`tests/\`, \`install.sh\`, a hook"
}

test_compact_line() {
  local first
  hook "" '{"source": "compact"}'
  status_is 0
  first="$(printf '%s\n' "$OUT" | head -n 1)"
  [ "$first" = "The context was compacted: the rules read before it are gone. Read again the files below that the next task needs before acting." ] ||
    fail "first line is not the compaction line: $first"
  has "- \`workspace/rules/git.md\`"
  for source in startup resume clear; do
    hook "" "{\"source\": \"$source\"}"
    lacks "compacted"
  done
  fresh
  rm "$R/workspace/AGENTS.md"
  hook "$R" '{"source": "compact"}'
  has "The context was compacted"
  has "$FALLBACK"
}

test_product_row_added_appears() {
  fresh
  insert_after "$R/workspace/AGENTS.md" '| `rules/models.md` |' '| `rules/widgets.md` | adding a widget to the gate |'
  insert_after "$R/workspace/AGENTS.md" '| `rules/scripts.md` |' '| `rules/sql.md` | SQL |'
  hook "$R" '{"source": "startup"}'
  status_is 0
  quiet
  has "- \`workspace/rules/widgets.md\`: before adding a widget to /caw-merge"
  has "- \`workspace/rules/sql.md\`: when touching SQL"
  cmp -s "$REPO/.claude/session-index.md" "$R/.claude/session-index.md" || fail "the session index changed"
}

test_layer_named_only_when_it_exists() {
  fresh
  rm "$R/.claude/rules/models.md"
  hook "$R" ""
  has "- \`workspace/rules/models.md\`: before delegating to a subagent"
  lacks ".claude/rules/models.md"
}

test_ignored_file_in_multi_file_row() {
  fresh
  insert_after "$R/workspace/AGENTS.md" '| `rules/models.md` |' '| `rules/quality.md`, `rules/tests.md` | writing a test |'
  insert_after "$R/workspace/AGENTS.md" '| `rules/models.md` |' '| `rules/frontend.md`, `rules/infra.md` | both ignored |'
  hook "$R" ""
  status_is 0
  has "- \`workspace/rules/tests.md\`: before writing a test"
  lacks "quality.md"
  lacks "both ignored"
}

test_missing_agents() {
  fresh
  rm "$R/workspace/AGENTS.md"
  hook "$R" '{"source": "startup"}'
  fallback '`workspace/AGENTS.md` is missing'
}

test_missing_reference_section() {
  fresh
  sed 's/^## Reference$/## Reading list/' "$REPO/workspace/AGENTS.md" >"$R/workspace/AGENTS.md"
  hook "$R" ""
  fallback '`workspace/AGENTS.md` has no section "## Reference"'
}

test_reference_without_rows() {
  fresh
  printf '# AGENTS.md\n\n## Reference\n\nNothing yet.\n\n## Next\n\n| File | Read before |\n| --- | --- |\n| `a.md` | b |\n' \
    >"$R/workspace/AGENTS.md"
  hook "$R" ""
  fallback 'the section "## Reference" of `workspace/AGENTS.md` has no table row'
}

test_missing_session_index() {
  fresh
  rm "$R/.claude/session-index.md"
  hook "$R" '{"source": "clear"}'
  fallback '`.claude/session-index.md` is missing'
}

test_session_index_missing_each_section() {
  local section
  for section in "## Ignore from the product index" "## Mapping" "## CAW index"; do
    fresh
    grep -vxF "$section" "$REPO/.claude/session-index.md" >"$R/.claude/session-index.md"
    hook "$R" ""
    fallback "\`.claude/session-index.md\` has no section \"$section\""
  done
}

test_malformed_lines() {
  fresh
  insert_after "$R/.claude/session-index.md" '- `a wave`' '- `a gate` → the gate'
  hook "$R" ""
  fallback '`.claude/session-index.md` line '
  has 'a mapping bullet must be'
  fresh
  insert_after "$R/.claude/session-index.md" '## Ignore from the product index' '- rules/quality.md: no backticks'
  hook "$R" ""
  fallback '`.claude/session-index.md` line '
  has 'an ignore bullet must start with'
  fresh
  insert_after "$R/workspace/AGENTS.md" '| `rules/models.md` |' '| rules/x.md | no backticks |'
  hook "$R" ""
  fallback '`workspace/AGENTS.md` line '
  has 'a row must be'
}

test_index_too_long() {
  local i
  fresh
  for i in $(seq 1 120); do
    insert_after "$R/workspace/AGENTS.md" '| `rules/models.md` |' \
      "| \`rules/long-$i.md\` | a trigger long enough to make the whole index grow past its limit of characters |"
  done
  hook "$R" '{"source": "compact"}'
  fallback 'the index is '
  [ "${#OUT}" -lt 10000 ] || fail "context of ${#OUT} characters"
}

test_stdin_variants() {
  local stdin
  for stdin in "" "not json" "[1, 2]" '{"source": 5}' '{"source": "other"}' "null"; do
    hook "" "$stdin"
    status_is 0
    quiet
    has "- \`workspace/rules/git.md\`"
    lacks "compacted"
  done
}

test_context_size() {
  hook "" '{"source": "compact"}'
  [ "${#OUT}" -gt 0 ] && [ "${#OUT}" -lt 10000 ] || fail "context of ${#OUT} characters, not under 10,000"
}

test_usage() {
  OUT="$(python3 -I -B "$HOOK" --help 2>&1)"
  RC=$?
  status_is 0
  has "usage: tests/caw-session-index.py"
  has "Exit codes"
  OUT="$(python3 -I -B "$HOOK" --bogus </dev/null 2>&1)"
  RC=$?
  status_is 2
  OUT="$(python3 -I -B "$HOOK" --root "$BASE/none" </dev/null 2>&1)"
  RC=$?
  status_is 2
  has "--root is not a folder"
  OUT="$(bash "$HERE/test-caw-session-index.sh" --help 2>&1)"
  RC=$?
  status_is 0
  has "Usage: tests/test-caw-session-index.sh"
  OUT="$(bash "$HERE/test-caw-session-index.sh" --bogus 2>&1)"
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
