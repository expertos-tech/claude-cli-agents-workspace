#!/usr/bin/env bash
# Claude Code PreToolUse hook for the Agent tool: Fable in a subagent needs the person's confirmation (it is activated manually, main session only).
# The decision logic lives in guard-subagent-model.py, next to this file.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/guard-subagent-model.sh [--help]

PreToolUse hook (matcher: Agent). Reads the hook JSON on stdin and decides:
  subagent_type "fork" (normalized: NFKC, lowercase, no space, "-" or "_") -> deny (checked first)
  subagent_type with non-ASCII characters after NFKC -> deny
  model contains "fable" (any spelling) -> ask (English text naming the type; needs the person's express request)
  explicit model outside the allowlist -> deny
  explicit model in the allowlist   -> allow silently
  no model, fixed-model agent       -> allow silently
  no model, anything else           -> allow with updatedInput = tool_input + "model":"opus"
  malformed input, no python3       -> exit 2 (blocks), stderr names the cause
Allowlist (strip + lowercase): opus, sonnet, haiku, claude-opus-*, claude-sonnet-*, claude-haiku-*.
Fixed-model agent: .claude/agents/<type>.md whose frontmatter has exactly one model: line in the allowlist and
exactly one name: line equal to the type. No built-in type counts as fixed. Other origins (nested files,
~/.claude/agents, plugins) are not recognized and get opus.
Project root: $CLAUDE_PROJECT_DIR, else the parent of this script's folder.

Example:
  echo '{"tool_input":{"subagent_type":"Plan","prompt":"x"}}' | scripts/guard-subagent-model.sh
USAGE
}

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  "") ;;
  *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
esac

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${CLAUDE_PROJECT_DIR:-$(cd "$here/.." && pwd)}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "guard-subagent-model: python3 not found; blocking every subagent until it is installed." >&2
  exit 2
fi

errfile="$(mktemp)"
trap 'rm -f "$errfile"' EXIT
# stdout carries only the decision; stderr (the exception type name, or python noise on success) stays apart.
if ! result="$(python3 -I -B "$here/guard-subagent-model.py" "$root" 2>"$errfile")"; then
  echo "guard-subagent-model: hook input rejected ($(head -c 200 "$errfile" | tr -d '\n' || true)); blocking (this hook guards the subagent model rule)." >&2
  exit 2
fi
[ -z "$result" ] || printf '%s\n' "$result"
