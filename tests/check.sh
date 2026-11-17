#!/usr/bin/env bash
# Gate of the repository, run from its root by whoever maintains it: the product gate on workspace/, then the
# company-terms scan of the whole repository (the files outside workspace/ included). It writes nothing in the
# repository but the git-ignored check ledger of the product gate.
set -uo pipefail

usage() {
  cat <<'USAGE'
Usage: tests/check.sh [check-workspace.sh options] [--help]

Runs the gate of the repository, from any cwd:
  1. workspace/scripts/check-workspace.sh with the options given (for example --all, --base <ref>, --floor,
     --i18n-pending: translation findings are reported as pending and pass, until the release),
     judging the product in workspace/ only;
  2. repo-terms: no file of the repository, tracked or untracked, outside or inside workspace/, matches a line of
     the terms list (extended regex, any case; blank and # lines ignored). Nothing is exempt here: no history, no
     changelog. No terms list prints SKIP.

Terms list (company terms that must never reach the public repository), the first that exists:
  1. $AIWP_TERMS_FILE (set but missing: the gate fails);
  2. $AIWP_WORKSPACE/custom/core-terms.txt, the custom layer of a work workspace;
     AIWP_WORKSPACE defaults to $HOME/Development/ai-workspace;
  3. workspace/custom/core-terms.txt (git-ignored), the product gate's own lookup.
The list found is passed to the product gate as AIWP_TERMS_FILE. Matching lines are printed: never paste them
into an issue, a commit or a pull request.

Exit codes: 0 every check passed; 1 a check failed; 2 usage error.

Examples:
  bash tests/check.sh --all
  bash tests/check.sh --all --base "$(git rev-list --max-parents=0 HEAD)"   # judge every file since the first commit
USAGE
}

for arg in "$@"; do
  case "$arg" in --help | -h) usage; exit 0 ;; esac
done

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
gate="$repo/workspace/scripts/check-workspace.sh"
[ -f "$gate" ] || { echo "error: product gate not found: $gate" >&2; exit 2; }

# Prints the terms list to use, or nothing; returns 1 when AIWP_TERMS_FILE names no file.
terms_list() {
  local ws
  if [ -n "${AIWP_TERMS_FILE:-}" ]; then
    [ -f "$AIWP_TERMS_FILE" ] || return 1
    echo "$AIWP_TERMS_FILE"
    return 0
  fi
  ws="${AIWP_WORKSPACE:-${HOME:-}/Development/ai-workspace}"
  if [ -f "$ws/custom/core-terms.txt" ]; then echo "$ws/custom/core-terms.txt"; return 0; fi
  if [ -f "$repo/workspace/custom/core-terms.txt" ]; then echo "$repo/workspace/custom/core-terms.txt"; fi
}

list="$(terms_list)" || { echo "error: AIWP_TERMS_FILE names no file: $AIWP_TERMS_FILE" >&2; exit 1; }
failed=0

echo "== product gate (workspace/)"
if [ -n "$list" ]; then
  AIWP_TERMS_FILE="$list" bash "$gate" "$@"
else
  bash "$gate" "$@"
fi
rc=$?
[ "$rc" -eq 2 ] && exit 2
[ "$rc" -eq 0 ] || failed=1

echo "== repository"
if [ -z "$list" ]; then
  echo "SKIP repo-terms: no terms list (set AIWP_TERMS_FILE or AIWP_WORKSPACE)"
else
  patterns="$(mktemp)"
  trap 'rm -f "$patterns"' EXIT
  sed -e '1s/^\xEF\xBB\xBF//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$list" | grep -vE '^(#|$)' >"$patterns" || true
  if [ ! -s "$patterns" ]; then
    echo "SKIP repo-terms: the terms list holds no term"
  else
    grc=0
    git -C "$repo" grep -n -I -i -E --untracked -f "$patterns" -- . ':(exclude)workspace/custom/' || grc=$?
    case "$grc" in
      1) echo "PASS repo-terms" ;;
      0)
        echo "FAIL repo-terms: the lines above hold a company term; say it without the name"
        failed=1
        ;;
      *)
        echo "FAIL repo-terms: the search failed (git grep $grc)"
        failed=1
        ;;
    esac
  fi
fi

exit "$failed"
