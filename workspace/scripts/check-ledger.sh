#!/usr/bin/env bash
# Check ledger: records which check passed for which inputs, so a check runs once per state of the code.
# Sourced by scripts/validate.sh and scripts/check-workspace.sh, which set LEDGER_ROOT. Rule: rules/scripts.md.
# Only PASS is recorded. An empty key means "do not cache": nothing hits and nothing is recorded.

# Prints the sha256 of stdin.
ledger_hash() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1; else sha256sum | cut -d' ' -f1; fi
}

# Prints the ledger folder, in the main checkout, so worktrees and merge candidates share it.
ledger_dir() {
  local common
  common="$(cd "$LEDGER_ROOT" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P)" || return 1
  echo "${common%/.git}/.history/check-ledger"
}

# Prints what identifies the content of folder $1: tree at HEAD, uncommitted diff, untracked files. Nothing outside git.
ledger_folder_state() {
  local dir="$1" tree f
  tree="$(git -C "$dir" rev-parse -q --verify 'HEAD:./' 2>/dev/null)" || return 0
  echo "$tree"
  git -C "$dir" diff --binary HEAD -- .
  git -C "$dir" ls-files --others --exclude-standard -z -- . | while IFS= read -r -d '' f; do
    printf '%s ' "$f"
    git hash-object -- "$dir/$f"
  done
}

# Prints the state of folder $1 and of the repos nested in it (projects/ is git-ignored by the workspace repo).
# Prints nothing when $1 is not in git, so that state is never cached.
ledger_tree_state() {
  local state repo
  state="$(ledger_folder_state "$1")"
  [ -n "$state" ] || return 0
  printf '%s\n' "$state"
  for repo in "$1"/*/.git "$1"/*/*/.git "$1"/*/*/*/.git; do
    if [ -e "$repo" ]; then ledger_folder_state "${repo%/.git}"; fi
  done
}

# Prints the key of check $1 for state $2, or nothing when the ledger is off or the state is empty.
# The gate's own files are part of the key: changing the gate invalidates what it passed.
ledger_key() {
  local f
  [ -z "${CHECK_LEDGER_DISABLE:-}" ] || return 0
  [ -n "$2" ] || return 0
  {
    printf '%s\n%s\n' "$1" "$2"
    find "$LEDGER_ROOT/scripts/check-ledger.sh" "$LEDGER_ROOT/scripts/validate.sh" "$LEDGER_ROOT/scripts/check-workspace.sh" \
      "$LEDGER_ROOT/docker/compose.yaml" "$LEDGER_ROOT/docker/config" -type f 2>/dev/null | LC_ALL=C sort |
      while IFS= read -r f; do cat -- "$f"; done || true
  } | ledger_hash
}

# Returns 0 when key $1 holds a PASS younger than $2 seconds (0: no expiry).
ledger_hit() {
  local file when
  [ -n "$1" ] || return 1
  file="$(ledger_dir)/$1" || return 1
  [ -f "$file" ] || return 1
  [ "${2:-0}" -ne 0 ] || return 0
  when="$(cat "$file")"
  case "$when" in '' | *[!0-9]*) return 1 ;; esac
  [ "$(($(date +%s) - when))" -lt "$2" ]
}

# Records a PASS for key $1 and drops records older than 7 days. A ledger that cannot write only costs a rerun.
ledger_record() {
  local dir
  [ -n "$1" ] || return 0
  dir="$(ledger_dir)" || return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  { date +%s >"$dir/.$1.$$" && mv -f "$dir/.$1.$$" "$dir/$1"; } 2>/dev/null || true
  find "$dir" -type f -mtime +7 -exec rm -f {} + 2>/dev/null || true
  return 0
}
