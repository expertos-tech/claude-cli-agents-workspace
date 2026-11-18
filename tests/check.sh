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
  3. caw-layers: every maintenance skill with a product counterpart is a layer over it (CLAUDE.md "Layout").
  4. caw-work: tests/test-caw-work.sh, the scenarios of tests/caw-work.sh (work clones under tmp/work/ and their
     git hooks), in a throwaway repository with a local remote; it never touches this repository.

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
[ -r "$repo/tests/lib/terms.sh" ] || { echo "error: tests/lib/terms.sh not found" >&2; exit 2; }
# shellcheck source=lib/terms.sh
. "$repo/tests/lib/terms.sh"

# Checks every maintenance skill with a product counterpart (.claude/skills/caw-<name>/ next to
# workspace/rules/skills/<name>/) is a layer over it: the first line of its body is "@<path of the product skill>",
# that file exists, and it holds the sections "Ignore from the product skill", "Mapping" and "CAW rules".
# Prints one line per problem; returns 1 when there is any.
check_caw_layers() {
  local dir name product body first bad=0 section
  for dir in "$repo"/.claude/skills/caw-*/; do
    [ -f "$dir/SKILL.md" ] || continue
    name="$(basename "$dir")"
    name="${name#caw-}"
    product="workspace/rules/skills/$name/SKILL.md"
    [ -f "$repo/$product" ] || continue
    body="$(awk 'NR == 1 && $0 == "---" { fm = 1; next } fm && $0 == "---" { fm = 0; next } !fm' "$dir/SKILL.md")"
    first="$(printf '%s\n' "$body" | grep -m1 -v '^[[:space:]]*$' || true)"
    if [ "$first" != "@$product" ]; then
      echo "  caw-$name: the first line of its body must be @$product"
      bad=1
    fi
    for section in "## Ignore from the product skill" "## Mapping" "## CAW rules"; do
      printf '%s\n' "$body" | grep -qxF "$section" || { echo "  caw-$name: missing section \"$section\""; bad=1; }
    done
  done
  return "$bad"
}

list="$(terms_list "$repo")" || { echo "error: AIWP_TERMS_FILE names no file: $AIWP_TERMS_FILE" >&2; exit 1; }
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
if check_caw_layers; then
  echo "PASS caw-layers"
else
  echo "FAIL caw-layers: a maintenance skill with a product counterpart must be a layer over it (CLAUDE.md)"
  failed=1
fi
if caw_out="$(bash "$repo/tests/test-caw-work.sh" 2>&1)"; then
  echo "PASS caw-work"
else
  printf '%s\n' "$caw_out"
  echo "FAIL caw-work: the scenarios of tests/caw-work.sh above failed (bash tests/test-caw-work.sh)"
  failed=1
fi
if [ -z "$list" ]; then
  echo "SKIP repo-terms: no terms list (set AIWP_TERMS_FILE or AIWP_WORKSPACE)"
else
  patterns="$(mktemp)"
  trap 'rm -f "$patterns"' EXIT
  terms_patterns "$list" >"$patterns"
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
