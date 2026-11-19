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
  3. caw-layers: every maintenance skill (.claude/skills/caw-<name>) and rule (.claude/rules/<name>.md) with a
     product counterpart is a layer over it, with its three sections (CLAUDE.md "Layout"; tests/lib/layers.sh);
     the session index .claude/session-index.md is a layer over workspace/AGENTS.md with its three sections, and
     .claude/settings.json registers its SessionStart hook tests/caw-session-index.py;
     caw-layers-tests: tests/test-caw-layers.sh, the scenarios of that check on throwaway trees;
     caw-session-index: tests/test-caw-session-index.sh, the scenarios of the SessionStart hook
     tests/caw-session-index.py on this tree (read only) and on throwaway copies.
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
[ -r "$repo/tests/lib/layers.sh" ] || { echo "error: tests/lib/layers.sh not found" >&2; exit 2; }
# shellcheck source=lib/layers.sh
. "$repo/tests/lib/layers.sh"

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
if check_caw_layers "$repo"; then
  echo "PASS caw-layers"
else
  echo "FAIL caw-layers: a layer (skill, rule, session index) must point at its product file and hold its three" \
    "sections, and the settings must register the session index hook (CLAUDE.md, tests/lib/layers.sh)"
  failed=1
fi
if layers_out="$(bash "$repo/tests/test-caw-layers.sh" 2>&1)"; then
  echo "PASS caw-layers-tests"
else
  printf '%s\n' "$layers_out"
  echo "FAIL caw-layers-tests: the scenarios of tests/lib/layers.sh above failed (bash tests/test-caw-layers.sh)"
  failed=1
fi
if index_out="$(bash "$repo/tests/test-caw-session-index.sh" 2>&1)"; then
  echo "PASS caw-session-index"
else
  printf '%s\n' "$index_out"
  echo "FAIL caw-session-index: the scenarios of tests/caw-session-index.py above failed" \
    "(bash tests/test-caw-session-index.sh)"
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
