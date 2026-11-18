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
     the terms list (extended regex, any case; blank and # lines ignored) the owner has not accepted. Nothing is
     exempt here: no history, no changelog. No terms list prints SKIP. A line the owner kept after the warning of a
     work clone's push (bash tests/caw-work.sh push <work> --accept-terms, recorded in <terms list>.accepted) is
     skipped: PASS says how many matching lines it skipped, never the term.
  3. caw-layers: every maintenance skill with a product counterpart is a layer over it (CLAUDE.md "Layout").
  4. caw-work: tests/test-caw-work.sh, the scenarios of tests/caw-work.sh (work clones under tmp/work/ and their
     git hooks), in a throwaway repository with a local remote; it never touches this repository.
  5. review-fixtures: tests/test-review-fixtures.sh, the judge of tests/review-fixtures.sh and the fixture set (one
     BLOCKER fixture per hard rule of workspace/rules/security.md), with made-up reports. The fixtures themselves run
     against the reviewer only at the release (/caw-merge --main): they call the model.

Terms list (company terms that must never reach the public repository), the first that exists:
  1. $AIWP_TERMS_FILE (set but missing: the gate fails);
  2. $AIWP_WORKSPACE/custom/core-terms.txt, the custom layer of a work workspace;
     AIWP_WORKSPACE defaults to $HOME/Development/ai-workspace;
  3. workspace/custom/core-terms.txt (git-ignored), the product gate's own lookup.
The list found is passed to the product gate as AIWP_TERMS_FILE; with accepted terms, a private temporary copy of the
list without them is passed instead. Matching lines are printed: never paste them into an issue, a commit or a pull
request.

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

# Checks the maintenance skills that are layers over a product skill (CLAUDE.md "Layout"). A layer is any
# .claude/skills/caw-*/SKILL.md whose body starts with "@<path>", whatever its name: the path must be an existing
# workspace/rules/skills/<skill>/SKILL.md, and the body must hold the sections "Ignore from the product skill",
# "Mapping" and "CAW rules". A caw-<name> next to a product skill workspace/rules/skills/<name>/ must be a layer over
# that one: its "@" line names it, and a missing "@" line fails.
# Prints one line per problem; returns 1 when there is any.
check_caw_layers() {
  local dir name product body first target bad=0 section
  for dir in "$repo"/.claude/skills/caw-*/; do
    [ -f "$dir/SKILL.md" ] || continue
    name="$(basename "$dir")"
    product="workspace/rules/skills/${name#caw-}/SKILL.md"
    body="$(awk 'NR == 1 && $0 == "---" { fm = 1; next } fm && $0 == "---" { fm = 0; next } !fm' "$dir/SKILL.md")"
    first="$(printf '%s\n' "$body" | grep -m1 -v '^[[:space:]]*$' || true)"
    if [ "${first:0:1}" != "@" ]; then
      if [ -f "$repo/$product" ]; then
        echo "  $name: the first line of its body must be @$product"
        bad=1
      fi
      continue
    fi
    target="${first#@}"
    if [ -f "$repo/$product" ] && [ "$target" != "$product" ]; then
      echo "  $name: the first line of its body must be @$product"
      bad=1
    elif [[ ! "$target" =~ ^workspace/rules/skills/[^/]+/SKILL\.md$ ]] || [[ "$target" == *..* ]]; then
      echo "  $name: the target of its @ line is not a product skill: ${target:-<empty>}"
      bad=1
    elif [ ! -f "$repo/$target" ]; then
      echo "  $name: the target of its @ line does not exist: $target"
      bad=1
    fi
    for section in "## Ignore from the product skill" "## Mapping" "## CAW rules"; do
      printf '%s\n' "$body" | grep -qxF "$section" || { echo "  $name: missing section \"$section\""; bad=1; }
    done
  done
  return "$bad"
}

list="$(terms_list "$repo")" || { echo "error: AIWP_TERMS_FILE names no file: $AIWP_TERMS_FILE" >&2; exit 1; }
failed=0
# The terms a scan reports (active) and the ones the owner accepted (tests/lib/terms.sh), in private temporary files.
active="$(mktemp)"
accepted="$(mktemp)"
trap 'rm -f "$active" "$accepted"' EXIT
if [ -n "$list" ]; then
  terms_active "$list" >"$active"
  terms_accepted "$list" >"$accepted"
fi

echo "== product gate (workspace/)"
if [ -z "$list" ]; then
  bash "$gate" "$@"
elif [ -s "$accepted" ]; then
  AIWP_TERMS_FILE="$active" bash "$gate" "$@"
else
  AIWP_TERMS_FILE="$list" bash "$gate" "$@"
fi
rc=$?
[ "$rc" -eq 2 ] && exit 2
[ "$rc" -eq 0 ] || failed=1

echo "== repository"
if check_caw_layers; then
  echo "PASS caw-layers"
else
  echo "FAIL caw-layers: a caw-* layer must point at an existing product skill and hold its three sections (CLAUDE.md)"
  failed=1
fi
if caw_out="$(bash "$repo/tests/test-caw-work.sh" 2>&1)"; then
  echo "PASS caw-work"
else
  printf '%s\n' "$caw_out"
  echo "FAIL caw-work: the scenarios of tests/caw-work.sh above failed (bash tests/test-caw-work.sh)"
  failed=1
fi
if fixtures_out="$(bash "$repo/tests/test-review-fixtures.sh" 2>&1)"; then
  echo "PASS review-fixtures"
else
  printf '%s\n' "$fixtures_out"
  echo "FAIL review-fixtures: the review fixtures or their judge above (bash tests/test-review-fixtures.sh)"
  failed=1
fi
if [ -z "$list" ]; then
  echo "SKIP repo-terms: no terms list (set AIWP_TERMS_FILE or AIWP_WORKSPACE)"
elif [ ! -s "$active" ] && [ ! -s "$accepted" ]; then
  echo "SKIP repo-terms: the terms list holds no term"
else
  grc=1
  if [ -s "$active" ]; then
    grc=0
    git -C "$repo" grep -n -I -i -E --untracked -f "$active" -- . ':(exclude)workspace/custom/' || grc=$?
  fi
  note=""
  if [ -s "$accepted" ]; then
    skipped="$(git -C "$repo" grep -c -I -i -E --untracked -f "$accepted" -- . ':(exclude)workspace/custom/' 2>/dev/null |
      awk -F: '{ s += $NF } END { print s + 0 }')"
    note=" (skipped $skipped matching line(s) of company terms the owner accepted)"
  fi
  case "$grc" in
    1) echo "PASS repo-terms$note" ;;
    0)
      echo "FAIL repo-terms: the lines above hold a company term; say it without the name$note"
      failed=1
      ;;
    *)
      echo "FAIL repo-terms: the search failed (git grep $grc)"
      failed=1
      ;;
  esac
fi

exit "$failed"
