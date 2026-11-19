#!/usr/bin/env bash
# The default pilot mode of this installation: .claude/pilot-mode (git-ignored, writable), one line, auto or assisted.
# Read by the session start (release-notice.sh prints the context line), shown and written by /pilot.
set -euo pipefail

# Prints the command reference.
usage() {
  cat <<'USAGE'
Usage: scripts/pilot-mode.sh [show | set <auto|assisted> | context] [--root <dir>] [--help]

The default pilot mode of this installation, the mode every new session starts in. It lives in .claude/pilot-mode
(git-ignored, per installation, never in custom/), one line: auto or assisted. No file, an empty one, a link or a value
it does not know: assisted. manual is a choice of one session (/pilot manual) and never a default. When
custom/rules-config.json turns the skill pilot off (scripts/rules-config.py build leaves it out), the mode is auto
whatever the file says: there is no /pilot to leave assisted with.

Commands:
  show        (the default) print the default in force and where it comes from, one line:
                default: assisted (no .claude/pilot-mode)
                default: auto (.claude/pilot-mode)
                default: assisted (.claude/pilot-mode holds a value it does not know)
                default: auto (/pilot is turned off in custom/rules-config.json)
  set <mode>  write auto or assisted to .claude/pilot-mode (a temporary file renamed over it, so a link there is
              replaced, never followed; a folder there is refused, exit 1), then print "written: .claude/pilot-mode (<mode>)". /pilot auto and
              /pilot assisted run it. manual, or anything else, is a usage error and writes nothing.
  context     print the line the SessionStart hook adds to the session context, exactly one of:
                Pilot mode: assisted (the default of this installation). Read rules/assisted.md in full before your first reply and follow it.
                Pilot mode: auto (the default of this installation).
                Pilot mode: auto (/pilot is turned off in custom/rules-config.json).
              Always exits 0: a session start never fails here.

Options:
  --root <dir>  Workspace root. Default: the parent of this script's folder.
  --help        Show this help.

Exit codes: 0 done; 1 the file could not be written; 2 usage error.

Examples:
  bash scripts/pilot-mode.sh
  bash scripts/pilot-mode.sh set auto
USAGE
}

FILE_REL=".claude/pilot-mode"
LINE_ASSISTED="Pilot mode: assisted (the default of this installation). Read rules/assisted.md in full before your first reply and follow it."
LINE_AUTO="Pilot mode: auto (the default of this installation)."
LINE_OFF="Pilot mode: auto (/pilot is turned off in custom/rules-config.json)."

action=""
mode=""
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || { echo "error: --root needs a value" >&2; exit 2; }
      root="$(cd "$2" 2>/dev/null && pwd)" || { echo "error: --root is not a folder: $2" >&2; exit 2; }
      shift ;;
    --help | -h) usage; exit 0 ;;
    show | context)
      [ -z "$action" ] || { echo "error: one command only; see --help" >&2; exit 2; }
      action="$1" ;;
    set)
      [ -z "$action" ] || { echo "error: one command only; see --help" >&2; exit 2; }
      action="set"
      [ $# -ge 2 ] || { echo "error: set needs a mode: auto or assisted" >&2; exit 2; }
      mode="$2"
      shift ;;
    *) echo "error: unknown argument: $1; see --help" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$action" ] || action="show"

file="$root/$FILE_REL"

# Sets DEFAULT to the mode the file holds: auto or assisted, the latter for no file, an empty one, a link or an unknown
# value; and FILE_STATE to none, known or unknown.
read_default() {
  local value=""
  DEFAULT=assisted
  FILE_STATE=none
  if [ -f "$file" ] && [ ! -L "$file" ]; then
    FILE_STATE=unknown
    IFS= read -r value <"$file" 2>/dev/null || true
    value="$(printf '%s' "$value" | tr -d '[:space:]')"
  fi
  case "$value" in
    auto | assisted) FILE_STATE=known; DEFAULT="$value" ;;
  esac
}

# Succeeds when custom/rules-config.json turns the skill pilot off: the core item the build of scripts/rules-config.py
# leaves out ("skills pilot" in its skip list), the same effect setup-claude.sh gives it. A build that cannot run counts
# as on, as setup-claude.sh then loads the whole core.
pilot_off() {
  local stage rc=1
  [ -f "$root/custom/rules-config.json" ] || return 1
  stage="$(mktemp -d 2>/dev/null)" || return 1
  if python3 -I -B "$(dirname "${BASH_SOURCE[0]}")/rules-config.py" --root "$root" build --out "$stage" >/dev/null 2>&1 &&
    grep -qxF 'skills pilot' "$stage/skip" 2>/dev/null; then
    rc=0
  fi
  rm -rf "$stage"
  return "$rc"
}

case "$action" in
  show)
    read_default
    if pilot_off; then
      echo "default: auto (/pilot is turned off in custom/rules-config.json)"
    elif [ "$FILE_STATE" = known ]; then
      echo "default: $DEFAULT ($FILE_REL)"
    elif [ "$FILE_STATE" = unknown ]; then
      echo "default: assisted ($FILE_REL holds a value it does not know)"
    else
      echo "default: assisted (no $FILE_REL)"
    fi ;;
  context)
    # Nothing here may fail the session start: any error still prints a line, the default one.
    set +e
    read_default 2>/dev/null
    if pilot_off; then
      echo "$LINE_OFF"
    elif [ "$DEFAULT" = auto ]; then
      echo "$LINE_AUTO"
    else
      echo "$LINE_ASSISTED"
    fi
    exit 0 ;;
  set)
    case "$mode" in
      auto | assisted) ;;
      manual) echo "error: manual is a choice of one session (/pilot manual), never a default; nothing written" >&2; exit 2 ;;
      *) echo "error: unknown mode: $mode; the default is auto or assisted" >&2; exit 2 ;;
    esac
    mkdir -p "$root/.claude" 2>/dev/null || { echo "error: cannot create $root/.claude" >&2; exit 1; }
    # mv onto a link to a folder (or onto a folder) would move the file into it: drop a link, refuse a folder.
    if [ -L "$file" ]; then
      rm -f "$file" || { echo "error: cannot remove the link $FILE_REL" >&2; exit 1; }
    elif [ -d "$file" ]; then
      echo "error: $FILE_REL is a folder; nothing written" >&2
      exit 1
    fi
    tmp="$(mktemp "$root/.claude/.pilot-mode.XXXXXX" 2>/dev/null)" || { echo "error: cannot write in $root/.claude" >&2; exit 1; }
    if ! { printf '%s\n' "$mode" >"$tmp" && chmod 644 "$tmp" && mv -f "$tmp" "$file"; }; then
      rm -f "$tmp"
      echo "error: cannot write $FILE_REL" >&2
      exit 1
    fi
    echo "written: $FILE_REL ($mode)"
    if pilot_off; then
      echo "note: /pilot is turned off in custom/rules-config.json: sessions start in auto whatever this file says"
    fi ;;
esac
