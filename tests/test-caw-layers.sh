#!/usr/bin/env bash
# Tests of tests/lib/layers.sh (the caw-layers check of tests/check.sh) on throwaway trees in a temporary folder,
# removed on exit: each scenario builds a minimal repository with maintenance skills and rules, and their product
# counterparts, then asserts the result and the messages. This repository is never touched.
# The tests run through a list built at run time: SC2329 does not apply.
# shellcheck disable=SC2329
set -uo pipefail

usage() {
  cat <<'USAGE'
Usage: tests/test-caw-layers.sh [--only <test_name>] [--help]

Runs the scenarios of tests/lib/layers.sh: valid skill and rule layers pass; a missing target, a removed section, a
product counterpart with no pointer, a pointer naming another rule fail; a rule with no counterpart passes; a YAML
frontmatter is skipped. The session index .claude/session-index.md must exist, point at @workspace/AGENTS.md and hold
its three sections; .claude/settings.json must register the SessionStart hook tests/caw-session-index.py. The boxes
.claude/assisted.md must be a layer over @workspace/rules/assisted.md, with its three sections, whenever either exists. Prints one FAIL line per failed assertion and "ok: <n> tests" at the end.

Exit codes: 0 every test passed; 1 a test failed; 2 usage error.

Examples:
  bash tests/test-caw-layers.sh
  bash tests/test-caw-layers.sh --only test_rule_layer_missing_target
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
[ -r "$HERE/lib/layers.sh" ] || { echo "error: tests/lib/layers.sh not found" >&2; exit 2; }
# shellcheck source=lib/layers.sh
. "$HERE/lib/layers.sh"
BASE="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$BASE"' EXIT
FAILED=0
COUNT=0
OUT=""
RC=0
CURRENT=""
R=""

# Creates a fresh repository tree for the current test and sets R to it: no skill or rule, a valid session index and
# the settings that register its hook.
fresh() {
  R="$BASE/$CURRENT"
  rm -rf "$R"
  mkdir -p "$R/.claude/rules" "$R/.claude/skills" "$R/workspace/rules/skills"
  session_index
  settings_hook
}

# Writes .claude/session-index.md of R with the pointer <target> (default @workspace/AGENTS.md) and the three
# sections, less the one named in <drop> if any.
session_index() {
  local target="${1:-@workspace/AGENTS.md}" drop="${2:-}" section
  {
    printf '%s\n\nThe session index, built by tests/caw-session-index.py.\n\n---\n\n' "$target"
    for section in "## Ignore from the product index" "## Mapping" "## CAW index"; do
      [ "$section" = "$drop" ] || printf '%s\n\n- a line\n\n' "$section"
    done
  } >"$R/.claude/session-index.md"
}

# Writes .claude/settings.json of R with a SessionStart entry of matcher <matcher> (default
# startup|resume|clear|compact) running <command> (default the command of the session index).
settings_hook() {
  local matcher="${1:-startup|resume|clear|compact}" command="${2:-$CAW_SESSION_HOOK}"
  python3 -I -B -c '
import json, sys
hook = {"type": "command", "command": sys.argv[2], "timeout": 10}
settings = {"hooks": {"SessionStart": [{"matcher": sys.argv[1], "hooks": [hook]}]}, "permissions": {"allow": []}}
with open(sys.argv[3], "w", encoding="utf-8") as handle:
    json.dump(settings, handle, indent=2)
' "$matcher" "$command" "$R/.claude/settings.json"
}

# Writes the product rule workspace/rules/<name>.md of R.
product_rule() {
  printf '# %s.md\n\n- a product rule\n' "$1" >"$R/workspace/rules/$1.md"
}

# Writes the product skill workspace/rules/skills/<name>/SKILL.md of R.
product_skill() {
  mkdir -p "$R/workspace/rules/skills/$1"
  printf -- '---\nname: %s\n---\n\n# %s\n' "$1" "$1" >"$R/workspace/rules/skills/$1/SKILL.md"
}

# Writes the maintenance rule .claude/rules/<name>.md of R as a layer whose pointer is <target> (default the
# same-named product rule), with a frontmatter and the three sections, less the one named in <drop> if any.
rule_layer() {
  local name="$1" target="${2:-workspace/rules/$1.md}" drop="${3:-}" section
  {
    printf -- '---\npaths:\n  - "tests/**"\n---\n\n@%s\n\nRead that file in full, then this layer.\n\n---\n\n' "$target"
    for section in "## Ignore from the product rule" "## Mapping" "## CAW rules"; do
      [ "$section" = "$drop" ] || printf '%s\n\n- a line\n\n' "$section"
    done
  } >"$R/.claude/rules/$name.md"
}

# Writes the maintenance skill .claude/skills/caw-<name>/SKILL.md of R as a layer over workspace/rules/skills/<name>,
# with the three sections, less the one named in <drop> if any.
skill_layer() {
  local name="$1" drop="${2:-}" section
  mkdir -p "$R/.claude/skills/caw-$name"
  {
    printf -- '---\nname: caw-%s\n---\n\n@workspace/rules/skills/%s/SKILL.md\n\n---\n\n' "$name" "$name"
    for section in "## Ignore from the product skill" "## Mapping" "## CAW rules"; do
      [ "$section" = "$drop" ] || printf '%s\n\n- a line\n\n' "$section"
    done
  } >"$R/.claude/skills/caw-$name/SKILL.md"
}

# Runs check_caw_layers on R, keeping its output in OUT and its status in RC.
run() {
  OUT="$(check_caw_layers "$R" 2>&1)"
  RC=$?
}

# Records a failed assertion of the current test with <message>.
fail() {
  echo "FAIL $CURRENT: $1"
  [ -z "$OUT" ] || printf '%s\n' "$OUT" | sed 's/^/    | /'
  FAILED=$((FAILED + 1))
}

# Asserts the last run returned <rc>.
status_is() { [ "$RC" -eq "$1" ] || fail "expected status $1, got $RC"; }

# Asserts the output of the last run holds the fixed string <text>.
has() { printf '%s\n' "$OUT" | grep -qF -- "$1" || fail "output lacks: $1"; }

# Asserts the output of the last run is empty.
silent() { [ -z "$OUT" ] || fail "expected no output"; }

test_rule_layer_valid() {
  fresh
  product_rule git
  rule_layer git
  run
  status_is 0
  silent
}

test_rule_layer_missing_target() {
  fresh
  rule_layer git
  run
  status_is 1
  has "  .claude/rules/git.md: the product rule of the layer is gone: workspace/rules/git.md"
}

test_rule_layer_missing_each_section() {
  local section
  for section in "## Ignore from the product rule" "## Mapping" "## CAW rules"; do
    fresh
    product_rule review
    rule_layer review "" "$section"
    run
    status_is 1
    has "  .claude/rules/review.md: missing section \"$section\""
  done
}

test_rule_with_counterpart_and_no_pointer() {
  fresh
  product_rule security
  printf '# security.md\n\n- a maintenance rule\n' >"$R/.claude/rules/security.md"
  run
  status_is 1
  has "  .claude/rules/security.md: must be a layer: the first line of its body must be @workspace/rules/security.md"
}

test_rule_pointer_names_another_rule() {
  fresh
  product_rule models
  product_rule git
  rule_layer models workspace/rules/git.md
  run
  status_is 1
  has "  .claude/rules/models.md: the target of its @ line must be workspace/rules/models.md: workspace/rules/git.md"
}

test_rule_pointer_with_dotdot() {
  fresh
  product_rule docs
  rule_layer docs workspace/rules/../rules/docs.md
  run
  status_is 1
  has "  .claude/rules/docs.md: the target of its @ line must be workspace/rules/docs.md"
}

test_rule_with_no_counterpart_passes() {
  fresh
  printf -- '---\npaths:\n  - "x"\n---\n\n# process.md\n\n- a maintenance rule\n' >"$R/.claude/rules/process.md"
  run
  status_is 0
  silent
}

test_rule_frontmatter_is_skipped() {
  fresh
  product_rule scripts
  # The frontmatter holds an "@" line: only the body counts, so this rule is not a layer.
  printf -- '---\nnote: x\n@workspace/rules/scripts.md\n---\n\n# scripts.md\n' >"$R/.claude/rules/scripts.md"
  run
  status_is 1
  has "  .claude/rules/scripts.md: must be a layer"
  fresh
  product_rule scripts
  rule_layer scripts
  run
  status_is 0
  silent
}

test_skill_layer_valid() {
  fresh
  product_skill merge
  skill_layer merge
  run
  status_is 0
  silent
}

test_skill_layer_missing_target() {
  fresh
  skill_layer merge
  run
  status_is 1
  has "  caw-merge: the target of its @ line does not exist: workspace/rules/skills/merge/SKILL.md"
}

test_skill_with_counterpart_and_no_pointer() {
  fresh
  product_skill commit
  mkdir -p "$R/.claude/skills/caw-commit"
  printf -- '---\nname: caw-commit\n---\n\n# caw-commit\n' >"$R/.claude/skills/caw-commit/SKILL.md"
  run
  status_is 1
  has "  caw-commit: the first line of its body must be @workspace/rules/skills/commit/SKILL.md"
}

test_skill_layer_missing_section() {
  fresh
  product_skill request
  skill_layer request "## Mapping"
  run
  status_is 1
  has "  caw-request: missing section \"## Mapping\""
}

test_skill_with_no_counterpart_passes() {
  fresh
  mkdir -p "$R/.claude/skills/caw-check"
  printf -- '---\nname: caw-check\n---\n\n# caw-check\n' >"$R/.claude/skills/caw-check/SKILL.md"
  run
  status_is 0
  silent
}

test_session_index_valid() {
  fresh
  run
  status_is 0
  silent
}

test_session_index_missing() {
  fresh
  rm "$R/.claude/session-index.md"
  run
  status_is 1
  has "  .claude/session-index.md: missing"
}

test_session_index_missing_each_section() {
  local section
  for section in "## Ignore from the product index" "## Mapping" "## CAW index"; do
    fresh
    session_index "" "$section"
    run
    status_is 1
    has "  .claude/session-index.md: missing section \"$section\""
  done
}

test_session_index_wrong_pointer() {
  fresh
  session_index "@workspace/CLAUDE.md"
  run
  status_is 1
  has "  .claude/session-index.md: the first line of its body must be @workspace/AGENTS.md: @workspace/CLAUDE.md"
}

test_settings_without_session_hook() {
  fresh
  printf '{"permissions": {"allow": []}}\n' >"$R/.claude/settings.json"
  run
  status_is 1
  has "  .claude/settings.json: no SessionStart hook runs $CAW_SESSION_HOOK"
  fresh
  # shellcheck disable=SC2016 # the variable is expanded by Claude Code, never here
  settings_hook "" 'python3 "$CLAUDE_PROJECT_DIR/tests/caw-session-index.py"'
  run
  status_is 1
  has "  .claude/settings.json: no SessionStart hook runs"
}

test_settings_hook_matcher_without_compact() {
  fresh
  settings_hook "startup|resume"
  run
  status_is 1
  has "must match startup|resume|clear|compact: startup|resume"
  fresh
  settings_hook "*"
  run
  status_is 0
  silent
}

test_settings_missing_or_invalid() {
  fresh
  rm "$R/.claude/settings.json"
  run
  status_is 1
  has "  .claude/settings.json: missing"
  fresh
  printf '{ not json\n' >"$R/.claude/settings.json"
  run
  status_is 1
  has "  .claude/settings.json: not valid JSON"
}

# Writes .claude/assisted.md of R as a layer whose pointer is <target> (default @workspace/rules/assisted.md), with
# the three sections, less the one named in <drop> if any.
assisted_layer() {
  local target="${1:-@workspace/rules/assisted.md}" drop="${2:-}" section
  {
    printf '%s\n\nThe boxes at the root.\n\n---\n\n' "$target"
    for section in "## Ignore from the product rule" "## Mapping" "## CAW rules"; do
      [ "$section" = "$drop" ] || printf '%s\n\n- a line\n\n' "$section"
    done
  } >"$R/.claude/assisted.md"
}

test_assisted_layer_valid() {
  fresh
  product_rule assisted
  assisted_layer
  run
  status_is 0
  silent
}

test_assisted_neither_passes() {
  fresh
  run
  status_is 0
  silent
}

test_assisted_layer_missing() {
  fresh
  product_rule assisted
  run
  status_is 1
  has "  .claude/assisted.md: missing: the layer over workspace/rules/assisted.md"
}

test_assisted_layer_without_product_rule() {
  fresh
  assisted_layer
  run
  status_is 1
  has "  .claude/assisted.md: its product rule workspace/rules/assisted.md is missing"
}

test_assisted_layer_wrong_pointer() {
  fresh
  product_rule assisted
  assisted_layer "@workspace/rules/git.md"
  run
  status_is 1
  has "  .claude/assisted.md: the first line of its body must be @workspace/rules/assisted.md: @workspace/rules/git.md"
}

test_assisted_layer_missing_each_section() {
  local section
  for section in "## Ignore from the product rule" "## Mapping" "## CAW rules"; do
    fresh
    product_rule assisted
    assisted_layer "" "$section"
    run
    status_is 1
    has "  .claude/assisted.md: missing section \"$section\""
  done
}

test_usage() {
  OUT="$(bash "$HERE/test-caw-layers.sh" --help 2>&1)"
  RC=$?
  status_is 0
  has "Usage: tests/test-caw-layers.sh"
  OUT="$(bash "$HERE/test-caw-layers.sh" --bogus 2>&1)"
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
