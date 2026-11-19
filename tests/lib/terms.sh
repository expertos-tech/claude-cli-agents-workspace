# shellcheck shell=bash
# Company-terms lookup and scan of the repository, shared by tests/check.sh and tests/caw-work.sh. Sourced, never run.
# The terms list holds the company terms that must never reach the public repository: one extended regex per line,
# matched in any case; blank and # lines are ignored. A company term is a warning, never a refusal: the lines of the
# list the owner kept after the warning (tests/caw-work.sh push --accept-terms) are recorded in the private file
# <list>.accepted, next to the list, and no scan reports them again.

# Prints the terms list to use for the repository <repo>, the first that exists: $AIWP_TERMS_FILE,
# $AIWP_WORKSPACE/custom/core-terms.txt (default $HOME/Development/ai-workspace), <repo>/workspace/custom/core-terms.txt;
# prints nothing when there is none. Returns 1 when AIWP_TERMS_FILE is set and names no file.
terms_list() {
  local repo="$1" ws
  if [ -n "${AIWP_TERMS_FILE:-}" ]; then
    [ -f "$AIWP_TERMS_FILE" ] || return 1
    echo "$AIWP_TERMS_FILE"
    return 0
  fi
  ws="${AIWP_WORKSPACE:-${HOME:-}/Development/ai-workspace}"
  if [ -f "$ws/custom/core-terms.txt" ]; then echo "$ws/custom/core-terms.txt"; return 0; fi
  if [ -f "$repo/workspace/custom/core-terms.txt" ]; then echo "$repo/workspace/custom/core-terms.txt"; fi
}

# Prints the patterns of the terms list <list>: a leading byte-order mark dropped, each line trimmed, blank and #
# lines left out. Prints nothing when the list holds no term.
terms_patterns() {
  sed -e '1s/^\xEF\xBB\xBF//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1" | grep -vE '^(#|$)' || true
}

# Prints the path of the private file of the accepted terms of the terms list <list>: <list>.accepted, next to it.
terms_accepted_file() {
  echo "$1.accepted"
}

# Prints the patterns of the terms list <list> the owner accepted: the lines of <list>.accepted (read as the list is:
# trimmed, blank and # lines left out) that are still lines of the list. Prints nothing when none is.
terms_accepted() {
  local file
  file="$(terms_accepted_file "$1")"
  [ -f "$file" ] || return 0
  terms_patterns "$1" | grep -xF -f <(terms_patterns "$file") || true
}

# Prints the patterns of the terms list <list> a scan reports: every pattern but the accepted ones (terms_accepted).
terms_active() {
  terms_patterns "$1" | grep -vxF -f <(terms_accepted "$1") || true
}

# Scans the content on stdin for <patterns> (the output of terms_patterns: extended regex, any case; binary content
# is skipped) and prints each matching line as "<label>:<line number>:<text>". Returns 0 when no line matches, 1 when
# one does, 2 when the search failed. Writes no file.
terms_scan() {
  local patterns="$1" label="$2" out rc=0 line
  out="$(grep -n -I -i -E -f <(printf '%s\n' "$patterns"))" || rc=$?
  case "$rc" in
    0)
      while IFS= read -r line; do printf '%s:%s\n' "$label" "$line"; done <<<"$out"
      return 1
      ;;
    1) return 0 ;;
    *) return 2 ;;
  esac
}
