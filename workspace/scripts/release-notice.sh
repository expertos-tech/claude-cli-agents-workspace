#!/usr/bin/env bash
# Claude Code SessionStart hook: tells the session its pilot mode (the default of this installation, from
# scripts/pilot-mode.sh) and, when a newer release of Claude CLI Agents Workspace exists, to say so and to ask the
# person to close it and run aiwp update in a terminal. Detection only: it never updates, swaps or repairs a file.
set -uo pipefail

# Prints the command reference.
usage() {
  cat <<'USAGE'
Usage: scripts/release-notice.sh [--help]

SessionStart hook (matcher startup|resume|clear|compact). It prints the hook JSON that adds to the session context:

1. The pilot mode, on startup, clear and compact (a /clear or a compaction drops it; resume keeps the transcript, so
   not then): the line of scripts/pilot-mode.sh context, exactly one of
     Pilot mode: assisted (the default of this installation). Read rules/assisted.md in full before your first reply and follow it.
     Pilot mode: auto (the default of this installation).
     Pilot mode: auto (/pilot is turned off in custom/rules-config.json).
   from .claude/pilot-mode (scripts/pilot-mode.sh --help). Any workspace, installed or not. Nothing when
   scripts/pilot-mode.sh is missing.
2. The release notice, on startup and resume, in an installed workspace (.aiwp/manifest.json at the root): it runs
   the workspace's own scripts/aiwp.sh check --quiet: the release check of aiwp, one answer kept per day, a 5 s limit
   on the remote, offline-safe. When that reports a newer release (or an update that stopped halfway), one line: "A
   new workspace version X was detected (this workspace: Y). Tell the person to close this session and run `aiwp
   update` in a terminal.", and that Claude never runs the update itself. No notice: nothing new; a pinned workspace
   (aiwp rollback; aiwp update would clear the pin); offline; no answer within 12 s; not an installed workspace (the
   product repository, any folder without the manifest); aiwp.sh missing; any error. It never runs aiwp update,
   rollback or repair.

The source (startup, resume, clear, compact) is read from the hook JSON on stdin; with none, or one it does not know,
it does both. Nothing to say: no output.

Workspace root: $CLAUDE_PROJECT_DIR, else the parent of this script's folder.
Test seam: RELEASE_NOTICE_LIMIT_SECONDS (1 to 99) in place of the 12 s limit.

Exit codes: always 0 (a hook that warns never blocks a session); 2 on an unknown option.

Example:
  CLAUDE_PROJECT_DIR=~/my-workspace bash scripts/release-notice.sh </dev/null
USAGE
}

# The longest the check may take; the hook's own timeout in settings.json is longer. Test seam:
# RELEASE_NOTICE_LIMIT_SECONDS (whole seconds).
LIMIT_SECONDS=12
[[ "${RELEASE_NOTICE_LIMIT_SECONDS:-}" =~ ^[1-9][0-9]?$ ]] && LIMIT_SECONDS="$RELEASE_NOTICE_LIMIT_SECONDS"

case "${1:-}" in
  --help | -h) usage; exit 0 ;;
  "") ;;
  *) echo "error: unknown option: $1; see --help" >&2; exit 2 ;;
esac

# The hook JSON on stdin: only its source is used. It is read to the end so the caller's write never fails.
input=""
[ -t 0 ] || input="$(head -c 65536 2>/dev/null; cat >/dev/null 2>&1)" || input=""
source_name="$(printf '%s' "$input" | tr -d '\n' | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p')"
case "$source_name" in
  startup | resume | clear | compact) ;;
  *) source_name="" ;;
esac

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
pilot_line=""
release_text=""

# Prints the hook JSON with the pilot line and the release notice, each on its own line, and ends the hook; nothing
# when there is neither. The texts are fixed sentences (the versions only in the X.Y.Z form), so nothing needs
# escaping beyond the line break.
emit() {
  local context="$pilot_line"
  [ -z "$release_text" ] || context="${context:+$context\\n}$release_text"
  [ -n "$context" ] || exit 0
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$context"
  exit 0
}

# 1. The pilot mode: not on resume, which keeps the transcript and the line it had.
pilot_script="$(dirname "${BASH_SOURCE[0]}")/pilot-mode.sh"
if [ "$source_name" != resume ] && [ -f "$pilot_script" ]; then
  pilot_line="$(bash "$pilot_script" context --root "$root" 2>/dev/null </dev/null | grep -E '^Pilot mode: ' | head -n 1 |
    tr -cd '[:print:]')" || pilot_line=""
fi

# 2. The release notice: on startup and resume only, as before the pilot mode joined this hook.
case "$source_name" in clear | compact) emit ;; esac
[ -f "$root/.aiwp/manifest.json" ] && [ -f "$root/scripts/aiwp.sh" ] || emit

# Runs the release check of the workspace's aiwp into a temp file, and stops waiting after LIMIT_SECONDS: a check that
# is still running then is dropped. Its output goes only to that file, so nothing it leaves running holds the hook's
# output open.
out_file="$(mktemp 2>/dev/null)" || emit
trap 'rm -f "$out_file"' EXIT
(cd "$root" && exec bash scripts/aiwp.sh check --quiet) >"$out_file" 2>/dev/null </dev/null &
pid=$!
waited=0
SECONDS=0
while kill -0 "$pid" 2>/dev/null; do
  # Ticks and the clock: a loaded machine that stretches each 0.1 s tick still stops at the limit.
  if [ "$waited" -ge "$((LIMIT_SECONDS * 10))" ] || [ "$SECONDS" -ge "$LIMIT_SECONDS" ]; then
    kill "$pid" 2>/dev/null
    emit
  fi
  sleep 0.1
  waited=$((waited + 1))
done
lines="$(grep -E '^attention: ' "$out_file" | head -n 2 | tr -cd '[:print:]\n')" || lines=""
[ -n "$lines" ] || emit

# The context line: the versions are taken only when they have the X.Y.Z form, so nothing else reaches the session.
latest="$(printf '%s\n' "$lines" | sed -n 's/^attention: Claude CLI Agents Workspace \([0-9][0-9.]*\) is available (this workspace: \([0-9][0-9.]*\)).*/\1/p' | head -n 1)"
current="$(printf '%s\n' "$lines" | sed -n 's/^attention: Claude CLI Agents Workspace \([0-9][0-9.]*\) is available (this workspace: \([0-9][0-9.]*\)).*/\2/p' | head -n 1)"
context=""
# A pinned workspace (aiwp rollback) stays on its version on purpose: aiwp update would clear the pin, so no notice.
if [ ! -f "$root/.aiwp/pin" ] && [[ "$latest" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  context="A new workspace version $latest was detected (this workspace: $current). Tell the person to close this session and run \`aiwp update\` in a terminal."
fi
if printf '%s\n' "$lines" | grep -q '^attention: an aiwp update or rollback stopped halfway'; then
  context="${context:+$context }An aiwp update or rollback stopped halfway in this workspace. Tell the person to close this session and run \`aiwp update\` in a terminal, which restores it first."
fi
[ -n "$context" ] || emit
release_text="$context Never run aiwp update, rollback or repair yourself: they change the rules of this open session."
emit
