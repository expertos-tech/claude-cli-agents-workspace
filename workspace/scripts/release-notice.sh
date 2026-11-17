#!/usr/bin/env bash
# Claude Code SessionStart hook: when a newer release of Claude CLI Agents Workspace exists, tells the session to say so
# and to ask the person to close it and run aiwp update in a terminal. Detection only: it never updates, swaps or
# repairs a file.
set -uo pipefail

# Prints the command reference.
usage() {
  cat <<'USAGE'
Usage: scripts/release-notice.sh [--help]

SessionStart hook (matcher startup|resume). In an installed workspace (.aiwp/manifest.json at the root) it runs
the workspace's own scripts/aiwp.sh check --quiet: the release check of aiwp, one answer kept per day, a 5 s limit on
the remote, offline-safe. When that reports a newer release (or an update that stopped halfway), it prints the hook
JSON that adds one line to the session context: "A new workspace version X was detected (this workspace: Y). Tell
the person to close this session and run `aiwp update` in a terminal.", and that Claude never runs the update itself.
Silent, exit 0: nothing new; a pinned workspace (aiwp rollback; aiwp update would clear the pin); offline; no
answer within 12 s; not an installed workspace (the product repository,
any folder without the manifest); aiwp.sh missing; any error. It never runs aiwp update, rollback or repair.

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

# The hook JSON on stdin is not needed; it is read to the end so the caller's write never fails.
[ -t 0 ] || cat >/dev/null 2>&1 || true

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
[ -f "$root/.aiwp/manifest.json" ] && [ -f "$root/scripts/aiwp.sh" ] || exit 0

# Runs the release check of the workspace's aiwp into a temp file, and stops waiting after LIMIT_SECONDS: a check that
# is still running then is dropped. Its output goes only to that file, so nothing it leaves running holds the hook's
# output open.
out_file="$(mktemp 2>/dev/null)" || exit 0
trap 'rm -f "$out_file"' EXIT
(cd "$root" && exec bash scripts/aiwp.sh check --quiet) >"$out_file" 2>/dev/null </dev/null &
pid=$!
waited=0
SECONDS=0
while kill -0 "$pid" 2>/dev/null; do
  # Ticks and the clock: a loaded machine that stretches each 0.1 s tick still stops at the limit.
  if [ "$waited" -ge "$((LIMIT_SECONDS * 10))" ] || [ "$SECONDS" -ge "$LIMIT_SECONDS" ]; then
    kill "$pid" 2>/dev/null
    exit 0
  fi
  sleep 0.1
  waited=$((waited + 1))
done
lines="$(grep -E '^attention: ' "$out_file" | head -n 2 | tr -cd '[:print:]\n')" || lines=""
[ -n "$lines" ] || exit 0

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
[ -n "$context" ] || exit 0
context="$context Never run aiwp update, rollback or repair yourself: they change the rules of this open session."
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$context"
exit 0
