#!/usr/bin/env bash
# Records activity history entries in the history.txt of a project, or of a tool or POC of the custom layer. Never
# writes in the core: the workspace root and tools/ (the product's tools) are not targets.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Prints the help text.
usage() {
  cat <<'USAGE'
Usage:
  scripts/history.sh add --target <dir> --request <text> --fact <text> [--fact <text>...]
                         --files <text> [--decision <text>...] [--pending <text>...]
                         [--risk <text>...] [--author <name>] [--new-item] [--dry-run]
  scripts/history.sh flush
  scripts/history.sh show --target <dir> [--last <n>]

  --target  a repo folder of projects/ at any depth (projects/<name>, projects/<folder>/<name>...),
            a repo inside another one included, or a folder of projects/ in no repo; a tool of your
            own, custom/tools/<name>; or a POC, custom/pocs/<name>. A folder inside a repo that is
            not a repo root is refused (the history of a repo is at its root). The history of a
            tool lives with it in the custom layer; tools/<name> (the product's tools, read-only)
            and the workspace root are refused.
  add       queues one entry and writes the queue to <target>/history.txt. Never waits:
            when another writer holds the lock, the entry stays queued and that writer
            writes it. Prints "recorded:" or "queued:".
  --new-item  only with --target custom/tools/<name> or custom/pocs/<name>: creates the folder
            when it does not exist yet (an item that so far exists only on a prompt's branch).
            Without it, a missing folder is exit 2.
  flush     writes whatever is left in the queue (e.g. after a writer died).
  show      prints the last <n> entries of <target>/history.txt (default 5).

  Every value is one line. Author: --author, else git config user.name, else $USER.
  Queue and lock live in .history/ (git-ignored). A lock older than 1 minute is stale.
  Where deletion is not allowed, written entries stay in .history/saved/ and released
  locks in .history/released/.

Exit codes: 0 recorded or queued; 1 entry not written; 2 usage error.

Example:
  bash scripts/history.sh add --target projects/billing-api --request "create the invoices endpoint" \
    --fact "endpoint created; tests passed" --files "src/invoice.go, README.md"
USAGE
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -r "$root/scripts/lib/projects.sh" ] || { echo "error: scripts/lib/projects.sh not found" >&2; exit 2; }
# shellcheck source=lib/projects.sh
. "$root/scripts/lib/projects.sh"
state="$root/.history"
queue="$state/queue"
lock="$state/lock"
file_name="history.txt"

# Prints an error and exits with the given code.
die() {
  local code="$1"
  shift
  echo "error: $*" >&2
  exit "$code"
}

# Refuses a project target inside a repo that is not the root of a repo: the history of a repo is at its root.
check_project_target() {
  projects_check_target "$root" "$1" || exit 2
}

# Validates a --target value and prints it normalized (no trailing slash).
# A second argument "new-item" creates a missing custom/tools/<name> or custom/pocs/<name> folder (the "create" mode
# only checks the form and leaves the folder alone, for --dry-run).
resolve_target() {
  local target="${1%/}" mode="${2:-}"
  [ -n "$target" ] || target="."
  local kebab='[a-z0-9]+(-[a-z0-9]+)*' msg="--target must be projects/<folder>[/<folder>...], custom/tools/<name> or custom/pocs/<name>"
  case "$target" in
    projects/*)
      [[ "${target#*/}" =~ ^$kebab(/$kebab)*$ ]] || die 2 "$msg"
      check_project_target "$target" ;;
    custom/tools/* | custom/pocs/*) [[ "${target#custom/*/}" =~ ^$kebab$ ]] || die 2 "$msg" ;;
    tools/*) die 2 "tools/ holds the product's tools, read-only; the history of a tool of yours lives in custom/tools/<name>" ;;
    *) die 2 "$msg" ;;
  esac
  if [ -n "$mode" ]; then
    case "$target" in
      custom/tools/* | custom/pocs/*) ;;
      *) die 2 "--new-item is valid only with --target custom/tools/<name> or custom/pocs/<name>" ;;
    esac
    [ -d "$root/custom" ] || die 2 "custom/ not found: the custom layer holds $target"
    [ "$mode" = "check" ] || mkdir -p "$root/$target"
    echo "$target"
    return 0
  fi
  [ -d "$root/$target" ] || die 2 "target folder not found: $target"
  echo "$target"
}

# Fails when a value is empty or spans more than one line.
check_value() {
  local flag="$1" value="$2"
  [ -n "${value//[[:space:]]/}" ] || die 2 "$flag is empty"
  case "$value" in
    *$'\n'* | *$'\r'* | *$'\t'*) die 2 "$flag must be one line without tabs" ;;
  esac
}

# Prints the first line of a new history.txt for a target.
header() {
  local target="$1"
  printf '# Activity history of %s\n' "${target##*/}"
  printf '# One entry per request, oldest first. Never edit past entries.\n'
  printf '# Optional record. Write with: bash scripts/history.sh add\n'
}

# Releases the lock; moves it aside where deletion is not allowed (e.g. Cowork folders).
release_lock() {
  rmdir "$lock" 2>/dev/null && return 0
  mkdir -p "$state/released"
  mv "$lock" "$state/released/lock.$$.$RANDOM" 2>/dev/null
}

# Takes the writer lock without waiting; replaces a stale lock left by a dead writer.
try_lock() {
  mkdir -p "$state"
  mkdir "$lock" 2>/dev/null && return 0
  if [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
    release_lock || return 1
    mkdir "$lock" 2>/dev/null && return 0
  fi
  return 1
}

# Returns 0 when the queue holds at least one entry.
has_queued() {
  local f
  for f in "$queue"/*.txt; do
    [ -e "$f" ] && return 0
  done
  return 1
}

# Appends every queued entry, oldest first, to its target history.txt. Caller holds the lock.
# Each entry is moved to saved/ before it is appended, so it is never written twice.
write_queued() {
  local f target dir history status=0
  mkdir -p "$state/saved"
  for f in "$queue"/*.txt; do
    [ -e "$f" ] || continue
    if ! mv "$f" "$state/saved/"; then
      echo "error: cannot move queued entry $(basename "$f") to .history/saved/" >&2
      return 1
    fi
    f="$state/saved/$(basename "$f")"
    target="$(sed -n '1s/^target=//p' "$f")"
    dir="$root/$target"
    if [ -z "$target" ] || [ ! -d "$dir" ]; then
      mkdir -p "$state/failed"
      mv "$f" "$state/failed/"
      echo "error: target missing for queued entry, moved to .history/failed/$(basename "$f")" >&2
      status=1
      continue
    fi
    history="$dir/$file_name"
    [ -e "$history" ] || header "$target" >"$history"
    { printf '\n'; tail -n +2 "$f"; } >>"$history"
    rm -f "$f" 2>/dev/null || true
  done
  return "$status"
}

# Writes the queue while the lock is free; returns 3 when another writer holds it.
drain() {
  while has_queued; do
    try_lock || return 3
    trap 'release_lock || true' EXIT
    if ! write_queued; then
      release_lock || true
      trap - EXIT
      return 1
    fi
    release_lock || true
    trap - EXIT
  done
  return 0
}

# Handles the add subcommand.
cmd_add() {
  local target="" request="" files="" author="" dry_run=0 new_item=0 facts=() decisions=() pending=() risks=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --target | --request | --fact | --files | --decision | --pending | --risk | --author)
        [ $# -ge 2 ] || die 2 "$1 needs a value"
        check_value "$1" "$2"
        case "$1" in
          --target) target="$2" ;;
          --request) request="$2" ;;
          --fact) facts+=("$2") ;;
          --files) files="$2" ;;
          --decision) decisions+=("$2") ;;
          --pending) pending+=("$2") ;;
          --risk) risks+=("$2") ;;
          --author) author="$2" ;;
        esac
        shift
        ;;
      --dry-run) dry_run=1 ;;
      --new-item) new_item=1 ;;
      *) die 2 "unknown option for add: $1" ;;
    esac
    shift
  done
  [ -n "$target" ] || die 2 "--target is required"
  [ -n "$request" ] || die 2 "--request is required"
  [ "${#facts[@]}" -gt 0 ] || die 2 "at least one --fact is required"
  [ -n "$files" ] || die 2 "--files is required (use \"none\" when no file changed)"
  if [ "$new_item" -eq 1 ]; then
    local mode=create
    [ "$dry_run" -eq 0 ] || mode=check
    target="$(resolve_target "$target" "$mode")"
  else
    target="$(resolve_target "$target")"
  fi
  [ -n "$author" ] || author="$(git -C "$root/$target" config user.name 2>/dev/null || true)"
  [ -n "$author" ] || author="${USER:-unknown}"

  local entry v
  entry="--- $(date '+%Y-%m-%d %H:%M %z') | $author"$'\n'"REQUEST: $request"
  for v in "${facts[@]}"; do entry+=$'\n'"FACT: $v"; done
  for v in ${decisions[@]+"${decisions[@]}"}; do entry+=$'\n'"DECISION: $v"; done
  for v in ${pending[@]+"${pending[@]}"}; do entry+=$'\n'"PENDING: $v"; done
  for v in ${risks[@]+"${risks[@]}"}; do entry+=$'\n'"RISK: $v"; done
  entry+=$'\n'"FILES: $files"

  if [ "$dry_run" -eq 1 ]; then
    printf '%s\n' "$entry"
    return 0
  fi

  mkdir -p "$queue"
  local tmp
  tmp="$(mktemp "$queue/.tmp.XXXXXX")"
  printf 'target=%s\n%s\n' "$target" "$entry" >"$tmp"
  mv "$tmp" "$queue/$(date +%Y%m%d%H%M%S)-$$-$RANDOM.txt"

  local status=0
  drain || status=$?
  case "$status" in
    0) echo "recorded: $target/$file_name" ;;
    3) echo "queued: $target (another writer will record it)" ;;
    *) exit 1 ;;
  esac
}

# Handles the flush subcommand.
cmd_flush() {
  [ $# -eq 0 ] || die 2 "flush takes no options"
  local status=0
  drain || status=$?
  case "$status" in
    0) echo "flushed" ;;
    3) echo "busy: another writer is recording the queue" ;;
    *) exit 1 ;;
  esac
}

# Handles the show subcommand.
cmd_show() {
  local target="" last=5
  while [ $# -gt 0 ]; do
    case "$1" in
      --target | --last)
        [ $# -ge 2 ] || die 2 "$1 needs a value"
        case "$1" in
          --target) target="$2" ;;
          --last) last="$2" ;;
        esac
        shift
        ;;
      *) die 2 "unknown option for show: $1" ;;
    esac
    shift
  done
  [ -n "$target" ] || die 2 "--target is required"
  [[ "$last" =~ ^[1-9][0-9]*$ ]] || die 2 "--last must be a positive integer"
  target="$(resolve_target "$target")"
  local history="$root/$target/$file_name"
  [ -f "$history" ] || { echo "no history: $target"; return 0; }
  awk -v n="$last" '
    /^--- / { c++ }
    c > 0 { e[c] = e[c] $0 "\n" }
    END { s = c - n + 1; if (s < 1) s = 1; for (i = s; i <= c; i++) printf "%s", e[i] }
  ' "$history"
}

[ $# -gt 0 ] || { usage >&2; exit 2; }
cmd="$1"
shift
case "$cmd" in
  add) cmd_add "$@" ;;
  flush) cmd_flush "$@" ;;
  show) cmd_show "$@" ;;
  --help | -h) usage ;;
  *) die 2 "unknown command: $cmd" ;;
esac
