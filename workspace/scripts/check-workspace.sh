#!/usr/bin/env bash
# Gate of the workspace repo: checks what a branch changed, with the checks that fit those paths.
# Runs on the checkout holding this script; it writes only under the git-ignored .history/: the check ledger and a temporary copy for the secrets scan.
# The product may sit in a subfolder of its git repo (workspace/ of the public repo): every path is relative to the
# folder above scripts/, and changes outside it are not this gate's.
# The check_* functions are called by name through step: SC2329 (never invoked) does not apply.
# shellcheck disable=SC2329
set -euo pipefail

# Script suites, relative to scripts/. Each runs when what it tests changed (suite_inputs), the scripts and libraries it calls included.
# A suite missing from disk FAILS the gate: nothing is skipped silently.
SUITES="
tests/test-projects-layout.sh
tests/check-workspace/test-check-workspace.sh
tests/guard-subagent-model/test-guard-subagent-model.sh
tests/guard-bash/test-guard-bash.sh
tests/setup-claude/test-setup-claude.sh
tests/heavy-run/test-heavy-run.sh
tests/single-agent/test-single-agent.sh
tests/aiwp-cmds/test-aiwp-cmds.sh
tests/aiwp-gate/test-aiwp-gate.sh
tests/aiwp-project-state/test-aiwp-project-state.sh
tests/aiwp/test-aiwp.sh
tests/sync-env/test-sync-env.sh
"

# Locales every document of the product repository is translated to (check_i18n).
I18N_LOCALES="pt-BR es"

# Order of the validate.sh checks in --only (its own order, so the report reads the same).
CHECK_ORDER="secrets vuln iac shell dockerfile markdown mermaid terraform python typescript coverage"

# Prints the command reference.
usage() {
  cat <<'USAGE'
Usage: scripts/check-workspace.sh [--base <ref>] [--all] [--floor] [--no-cache] [--verbose] [--help]

Gate of the product repository, a maintenance tool. It judges the checkout that holds this script, from any cwd. When
that folder is a subfolder of its git repo, only the paths inside it count, relative to it.
In an installed workspace (.aiwp/manifest.json at the root: a read-only core, not a git repository) it checks
nothing: it prints one line saying so and exits 2. There, a project is checked with /merge and scripts/validate.sh.

Changed paths: git diff against the merge-base of HEAD and <ref> (working tree included), plus untracked files.

Checks, cheapest first, with the time of each; the gate stops at the first failure, unless --all (PASS/FAIL per line):
  decisions   no two docs/decisions/NNNN-*.md share a number; no folder or no record passes
  custom-terms  no file of this repo, tracked or untracked, matches a line of the terms list (extended
              regex, any case; blank and # lines ignored), so what belongs to one company stays in the custom
              layer (rules/rules.md "Custom layer"). The list is the file named by AIWP_TERMS_FILE, else
              custom/core-terms.txt; in a linked worktree that file is read from the main checkout.
              AIWP_TERMS_FILE naming no file fails. No list prints SKIP and passes
  i18n        only when the root of the git repo holding the product has an i18n/ folder (the product
              repository; an installed workspace has none and prints SKIP): every document has a translation
              i18n/<locale>/<path> for each locale of I18N_LOCALES, whose line 1 is exactly
              "<!-- source: <path> sha256:<sha256 of the English file> -->", and every file under
              i18n/<locale>/ translates a document that exists. <path> is relative to the repo root. Documents:
              every README.md of the repo and every .md of the root docs/; in the product, every .md of its
              docs/ and of tools/<name>/docs/. Never under i18n/, .claude/, tmp/, docs/decisions/ (of the
              root or the product) or node_modules/ (any depth); git-ignored files are not listed
  settings    rules/agents/settings.json is exactly one JSON document, when changed
  parse       changed files under tools/ parse (*.sh, *.json, *.py), when there are any
  validate    scripts/validate.sh --only <list> --files <changed files>; the list is always "secrets",
              judged on the changed files only, so a secret elsewhere in the checkout (projects/ holds other
              repos) is not the branch's; plus, by changed path, the lint ones judged on the changed files only:
                *.md, *.mmd             markdown, mermaid
                *.sh                    shell
                Dockerfile*             dockerfile, iac
                docker/                 vuln, iac
                *.py                    python
                *.ts, *.tsx             typescript
                *.tf                    terraform
                a folder with .coveragerc  coverage
  suites      each script suite (listed at the top of this script) whose inputs changed, the scripts and
              libraries it calls included; a suite with the same inputs prints CACHED (rules/scripts.md "Check ledger");
              never with --floor

A defect outside the diff does not fail the gate; one in a changed file does. Changed paths under
tools/ add nothing to the validate list and are never lint-gated (rules/rules.md "Workspace layout");
their secrets are still scanned, by a validate run of their own (--only secrets).
No changed path at all is printed as a NOTE: only the whole-checkout checks had anything to judge.

Options:
  --base <ref>  Branch to compare with. Default: main.
  --all         Full report: every suite, whatever changed, and every check after a failure.
  --floor       Skip the script suites; every other check still runs.
  --no-cache    Run every check even when the check ledger holds a PASS for the same inputs.
  --verbose     Print the full output of every check instead of the last 30 lines of failures.
  --help        Show this help.

Environment:
  AIWP_TERMS_FILE  Terms list of the custom-terms check, in place of custom/core-terms.txt.

Exit codes: 0 every check passed; 1 a check failed; 2 usage error.
Also 2: not a git checkout, or an installed workspace (nothing checked).
The checkout runs its own copy of this gate: a branch that changes the gate is judged by its changed copy.

Example:
  bash scripts/check-workspace.sh --base main
USAGE
}

# Prints an error and exits with the given code.
die() {
  local code="$1"
  shift
  echo "error: $*" >&2
  exit "$code"
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
base="main"
verbose=0
all=0
floor=0

while [ $# -gt 0 ]; do
  case "$1" in
    --base)
      [ $# -ge 2 ] || die 2 "--base needs a value"
      [ -n "$2" ] || die 2 "--base needs a value"
      base="$2"
      shift
      ;;
    --all) all=1 ;;
    --floor) floor=1 ;;
    --no-cache) export CHECK_LEDGER_DISABLE=1 ;;
    --verbose) verbose=1 ;;
    --help | -h)
      usage
      exit 0
      ;;
    *) die 2 "unknown option: $1" ;;
  esac
  shift
done

if [ -f "$root/.aiwp/manifest.json" ]; then
  echo "check-workspace: an installed workspace has a read-only core and no git repository; this gate runs only in the product repository. Check a project with /merge or scripts/validate.sh."
  exit 2
fi
command -v git >/dev/null 2>&1 || die 2 "git not found"
git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || die 2 "not a git checkout: $root"
git -C "$root" rev-parse --verify -q "$base^{commit}" >/dev/null || die 2 "base not found: $base"
merge_base="$(git -C "$root" merge-base HEAD "$base" 2>/dev/null)" || die 1 "no common ancestor between HEAD and $base"

LEDGER_ROOT="$root"
# shellcheck source=scripts/check-ledger.sh
. "$root/scripts/check-ledger.sh"
logdir="$(mktemp -d)"
trap 'rm -rf "$logdir"' EXIT
failed=0
changed_list=()

# Fills changed_list with the changed paths: diff to the merge-base (renames as two paths) plus untracked files.
# Relative to $root (diff --relative, ls-files from $root), so a product in a subfolder of its repo sees its own paths.
# NUL-separated, because git quotes a name holding a quote, tab or backslash on any other output, and such a line
# matches no rule. A git that fails stops the gate: an empty list would pass every check.
read_changed_paths() {
  local list="$logdir/changed.list" p
  git -C "$root" diff --relative --name-only --no-renames -z "$merge_base" >"$list" || die 1 "git diff failed: the changed paths are unknown"
  git -C "$root" ls-files --others --exclude-standard -z >>"$list" || die 1 "git ls-files failed: the changed paths are unknown"
  changed_list=()
  while IFS= read -r -d '' p; do
    changed_list+=("$p")
  done <"$list"
  if [ "${#changed_list[@]}" -eq 0 ]; then echo "NOTE no changed paths against $base: only the whole-checkout checks judge anything"; fi
}

# Returns 0 when path $1 is among the changed paths.
changed_has() {
  local p
  for p in ${changed_list[@]+"${changed_list[@]}"}; do
    if [ "$p" = "$1" ]; then return 0; fi
  done
  return 1
}

# Returns 0 when a changed path lies under folder $1.
changed_under() {
  local p
  for p in ${changed_list[@]+"${changed_list[@]}"}; do
    case "$p" in "$1"/*) return 0 ;; esac
  done
  return 1
}

# Runs one check, prints PASS/FAIL with its time, and shows its output: all of it with --verbose, else the lines that
# say what ran and the last 30 lines of a failure. Stops the gate at the first failure, unless --all.
step() {
  local name="$1" started="$SECONDS"
  shift
  if "$@" >"$logdir/$name.log" 2>&1; then
    echo "PASS $name ($((SECONDS - started))s)"
    if [ "$verbose" -eq 1 ]; then cat "$logdir/$name.log"; else { grep -E '^(CACHED|SLOW|SKIP|suite ok:)' "$logdir/$name.log" || true; } | sed 's/^/  /'; fi
  else
    echo "FAIL $name ($((SECONDS - started))s)"
    failed=1
    if [ "$verbose" -eq 1 ]; then cat "$logdir/$name.log"; else tail -n 30 "$logdir/$name.log" | sed 's/^/  /'; fi
    if [ "$all" -eq 0 ]; then exit 1; fi
  fi
}

# Prints "<number> <file>" for each docs/decisions/NNNN-*.md, sorted by number (0002 and 002 are the same number).
decision_numbers() {
  local f entry number
  # Any case of the extension: on a case-insensitive disk .MD is the same kind of file, and it takes the number too.
  for f in "$root"/docs/decisions/[0-9]*-*.[mM][dD]; do
    [ -e "$f" ] || continue
    entry="${f##*/}"
    number="${entry%%-*}"
    # Not inside $( ): bash 3.2 cannot parse a case pattern list there.
    case "$number" in *[!0-9]*) continue ;; esac
    echo "$((10#$number)) $entry"
  done | sort -n
}

# Fails when two decision records of docs/decisions/ share a number. No folder, or no record in it, passes.
check_decisions() {
  local list dups n
  [ -d "$root/docs/decisions" ] || { echo "no docs/decisions"; return 0; }
  list="$(decision_numbers)" || { echo "could not list the decision records"; return 1; }
  dups="$(printf '%s\n' "$list" | awk 'NF { print $1 }' | uniq -d)" || { echo "could not compare the decision numbers"; return 1; }
  [ -z "$dups" ] && return 0
  for n in $dups; do
    echo "duplicate decision number $n:"
    printf '%s\n' "$list" | awk -v n="$n" '$1 == n { print "  " $2 }'
  done
  echo "renumber the record of the branch not yet merged (rules/docs.md)"
  return 1
}

# Prints the path of the terms list: the file named by AIWP_TERMS_FILE (returns 1 when it names no file), else
# custom/core-terms.txt in this checkout, else in the main checkout of a linked worktree, which holds no custom/ of
# its own (the folder is git-ignored), at the same place below the repo root. Prints nothing when none has it.
custom_terms_list() {
  local common main prefix
  if [ -n "${AIWP_TERMS_FILE:-}" ]; then
    [ -f "$AIWP_TERMS_FILE" ] || return 1
    echo "$AIWP_TERMS_FILE"
    return 0
  fi
  if [ -f "$root/custom/core-terms.txt" ]; then
    echo "$root/custom/core-terms.txt"
    return 0
  fi
  common="$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
  prefix="$(git -C "$root" rev-parse --show-prefix 2>/dev/null)" || prefix=""
  main="$(dirname "$common")"
  if [ -f "$main/${prefix}custom/core-terms.txt" ]; then echo "$main/${prefix}custom/core-terms.txt"; fi
}

# Fails when this repo, tracked or untracked, holds a term of the terms list (rules/rules.md "Custom layer"):
# one extended regex per line, any case; a BOM and the blanks around a line are dropped, blank and # lines ignored.
# No list prints SKIP: without the custom layer there is nothing to keep apart.
check_custom_terms() {
  local list patterns="$logdir/custom-terms.patterns" rc=0
  list="$(custom_terms_list)" || { echo "AIWP_TERMS_FILE names no file: $AIWP_TERMS_FILE"; return 1; }
  [ -n "$list" ] || { echo "SKIP custom-terms: no custom/core-terms.txt"; return 0; }
  sed -e '1s/^\xEF\xBB\xBF//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$list" | grep -vE '^(#|$)' >"$patterns" || true
  [ -s "$patterns" ] || { echo "SKIP custom-terms: ${list#"$root"/} lists no term"; return 0; }
  git -C "$root" grep -n -I -i -E --untracked -f "$patterns" -- . ':(exclude)custom/' || rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "the search failed (git grep $rc): the custom terms were not checked"
    return 1
  fi
  if [ "$rc" -eq 0 ]; then
    echo "the lines above belong to the custom layer: move them to custom/, or say it without the name"
    return 1
  fi
  return 0
}

# Prints the sha256 of file $1 in hex (sha256sum, else shasum; neither returns 1).
sha256_hex() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum <"$1" | awk '{ print $1 }'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 <"$1" | awk '{ print $1 }'
  else
    return 1
  fi
}

# Returns 0 when $1, a path relative to the repo root, is a document that needs translations; $2 is the product
# folder relative to the repo root, with its trailing slash (empty when the product is the repo root). In scope: every
# README.md and every .md of the root docs/; in the product, every .md of its docs/ and of tools/<name>/docs/. Never:
# i18n/, .claude/ and tmp/ (of the root or the product), node_modules/ at any depth, docs/decisions/.
is_i18n_document() {
  local p="$1" product="$2" rest="$1" tool_rest in_product=0
  case "$p" in
    i18n/* | .claude/* | tmp/* | docs/decisions/* | node_modules/* | */node_modules/*) return 1 ;;
  esac
  case "$p" in "$product"*) rest="${p#"$product"}" in_product=1 ;; esac
  if [ "$in_product" = 1 ]; then
    case "$rest" in i18n/* | .claude/* | tmp/* | docs/decisions/*) return 1 ;; esac
  fi
  case "$rest" in README.md | */README.md | docs/*.md) return 0 ;; esac
  if [ "$in_product" = 1 ]; then
    case "$rest" in
      tools/*/*)
        tool_rest="${rest#tools/}"
        tool_rest="${tool_rest#*/}"
        case "$tool_rest" in docs/*.md) return 0 ;; esac
        ;;
    esac
  fi
  return 1
}

# Prints, one per line and sorted, the documents of repo $1 (tracked or untracked, still on disk) that need
# translations, for the product folder $2 (as in is_i18n_document). Fails when git cannot list the files.
i18n_documents() {
  local top="$1" product="$2" list="$logdir/i18n.files" p
  git -C "$top" ls-files -z --cached --others --exclude-standard >"$list" || return 1
  while IFS= read -r -d '' p; do
    if [ ! -f "$top/$p" ] || [ -L "$top/$p" ]; then continue; fi
    if is_i18n_document "$p" "$product"; then printf '%s\n' "$p"; fi
  done <"$list" | LC_ALL=C sort -u
}

# Fails when a document of the product repository lacks a translation for a locale of I18N_LOCALES, when a
# translation does not start with the exact source line of its document, when that line holds the hash of an
# older English file, or when a file under i18n/<locale>/ translates no document. Without i18n/ at the repo root
# (an installed workspace, a plain checkout) it prints SKIP and passes.
check_i18n() {
  local top product docs="$logdir/i18n.docs" files="$logdir/i18n.all" doc loc tr first hash want rc=0 p rest
  top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || { echo "git rev-parse failed: the translations were not checked"; return 1; }
  [ -d "$top/i18n" ] || { echo "SKIP i18n: no i18n/ at the repo root"; return 0; }
  product="$(git -C "$root" rev-parse --show-prefix 2>/dev/null)" || { echo "git rev-parse failed: the translations were not checked"; return 1; }
  i18n_documents "$top" "$product" >"$docs" || { echo "git ls-files failed: the translations were not checked"; return 1; }
  while IFS= read -r doc; do
    hash="$(sha256_hex "$top/$doc")" && [ -n "$hash" ] || { echo "neither sha256sum nor shasum found to hash $doc"; return 1; }
    want="<!-- source: $doc sha256:$hash -->"
    for loc in $I18N_LOCALES; do
      tr="i18n/$loc/$doc"
      if [ ! -f "$top/$tr" ]; then
        echo "missing translation: $tr (of $doc)"
        rc=1
        continue
      fi
      IFS= read -r first <"$top/$tr" || true
      first="${first%$'\r'}"
      if [ "$first" = "$want" ]; then continue; fi
      case "$first" in
        "<!-- source: $doc sha256:"*" -->")
          echo "outdated translation: $tr (its line 1 holds an older hash of $doc: translate the change, then set sha256:$hash)"
          ;;
        *)
          echo "no source line: $tr (line 1 must be exactly: $want)"
          ;;
      esac
      rc=1
    done
  done <"$docs"
  git -C "$top" ls-files -z --cached --others --exclude-standard -- i18n >"$files" || { echo "git ls-files failed: the translations were not checked"; return 1; }
  while IFS= read -r -d '' p; do
    [ -f "$top/$p" ] || continue
    rest="${p#i18n/}"
    case "$rest" in */*) ;; *) continue ;; esac
    rest="${rest#*/}"
    if ! grep -qxF -- "$rest" "$docs"; then
      echo "orphan translation: $p (no document $rest needs it: delete it, or move it with its document)"
      rc=1
    fi
  done <"$files"
  return "$rc"
}

# Fails unless file $1 is exactly one JSON document (jq, else python3; neither is a failure). "jq empty" alone
# would pass an empty file and two documents, so it counts them.
json_is_one_document() {
  if command -v jq >/dev/null 2>&1; then
    jq -e -s 'length == 1' "$1" >/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    python3 -I -c 'import json, sys; json.load(open(sys.argv[1]))' "$1"
  else
    echo "neither jq nor python3 found to parse ${1#"$root"/}"
    return 1
  fi
}

# Fails when rules/agents/settings.json changed and is not exactly one JSON document.
check_settings() {
  local file="$root/rules/agents/settings.json"
  changed_has 'rules/agents/settings.json' || { echo "unchanged"; return 0; }
  [ -f "$file" ] || { echo "rules/agents/settings.json is missing"; return 1; }
  json_is_one_document "$file"
}

# Fails when file $1 of a POC or tool does not parse. tsconfig and jsconfig are JSON with comments by design;
# other types have no parser every machine holds, so compiling them stays with the delivery of the item.
parse_poc_file() {
  case "${1##*/}" in
    tsconfig*.json | jsconfig*.json) return 0 ;;
    *.sh) bash -n "$1" ;;
    *.json) json_is_one_document "$1" ;;
    *.py) python3 -I -c 'import sys; compile(open(sys.argv[1], "rb").read(), sys.argv[1], "exec")' "$1" ;;
  esac
}

# The only code check of tools/ (rules/rules.md "Workspace layout"): each changed file still on disk parses.
check_poc_parse() {
  local p rc=0
  for p in ${changed_list[@]+"${changed_list[@]}"}; do
    case "$p" in tools/*) ;; *) continue ;; esac
    if [ ! -f "$root/$p" ] || [ -L "$root/$p" ]; then continue; fi
    if ! parse_poc_file "$root/$p"; then
      echo "does not parse: $p"
      rc=1
    fi
  done
  return "$rc"
}

# Prints "yes" when a folder holding .coveragerc contains the path (a parent folder counts), else nothing.
under_coverage_folder() {
  local dir
  dir="$(dirname -- "$1")"
  while [ "$dir" != "." ] && [ "$dir" != "/" ]; do
    if [ -f "$root/$dir/.coveragerc" ]; then echo yes; return 0; fi
    dir="$(dirname -- "$dir")"
  done
  if [ -f "$root/.coveragerc" ]; then echo yes; fi
}

# Prints the comma-separated validate.sh --only list for the changed paths ("secrets" always).
validate_list() {
  local want=" secrets " p base_name list="" c
  for p in ${changed_list[@]+"${changed_list[@]}"}; do
    case "$p" in tools/*) continue ;; esac
    base_name="${p##*/}"
    case "$p" in docker/*) want="$want vuln iac " ;; esac
    case "$base_name" in
      *.md | *.mmd) want="$want markdown mermaid " ;;
      *.sh) want="$want shell " ;;
      Dockerfile*) want="$want dockerfile iac " ;;
      *.py) want="$want python " ;;
      *.ts | *.tsx) want="$want typescript " ;;
      *.tf) want="$want terraform " ;;
    esac
    if [ -n "$(under_coverage_folder "$p")" ]; then want="$want coverage "; fi
  done
  for c in $CHECK_ORDER; do
    case "$want" in *" $c "*) list="${list:+$list,}$c" ;; esac
  done
  echo "$list"
}

# Writes to file $1 the changed files the lint checks judge, and to file $2 those under tools/, never
# lint-gated, whose secrets are still judged. Both hold only files still on disk, not links (the full scan skips them
# too). A line cannot carry a newline in a name, and such a file must not go unjudged.
write_judged_list() {
  local p
  : >"$1"
  : >"$2"
  for p in ${changed_list[@]+"${changed_list[@]}"}; do
    if [ ! -f "$root/$p" ] || [ -L "$root/$p" ]; then continue; fi
    case "$p" in
      *$'\n'*)
        echo "a changed path holds a newline and cannot be judged, rename it: $p"
        return 1
        ;;
    esac
    case "$p" in
      tools/*) printf '%s\n' "$p" >>"$2" ;;
      *) printf '%s\n' "$p" >>"$1" ;;
    esac
  done
}

# Runs scripts/validate.sh with the --only list computed for the changed paths, on the changed files. The changed
# files under tools/ get a secrets-only run first: never lint-gated, but a secret there still fails.
check_validate() {
  local list args judged="$logdir/judged.list" poc="$logdir/poc.list" rc=0
  list="$(validate_list)"
  echo "validate --only $list"
  [ -f "$root/scripts/validate.sh" ] || { echo "scripts/validate.sh is missing"; return 1; }
  write_judged_list "$judged" "$poc" || return 1
  if [ -s "$poc" ]; then
    echo "validate --only secrets, on the changed files under tools/"
    args=(--only secrets)
    if [ "$verbose" -eq 1 ]; then args+=(--verbose); fi
    bash "$root/scripts/validate.sh" "${args[@]}" --files "$poc" || rc=1
  fi
  args=(--only "$list")
  if [ "$verbose" -eq 1 ]; then args+=(--verbose); fi
  args+=(--files "$judged")
  bash "$root/scripts/validate.sh" "${args[@]}" || rc=1
  return "$rc"
}

# Prints what suite $1 tests, relative to scripts/: its script, the scripts and libraries that script calls, its own test
# files. A script a test only exercises in passing is not an input. Nothing: it runs whenever anything under scripts/ changed.
# The hooks these suites check live in rules/agents/settings.json, outside scripts/.
suite_inputs() {
  case "$1" in
    tests/test-projects-layout.sh) echo "tests/test-projects-layout.sh init-repo.sh history.sh lib/projects.sh ../VERSION" ;;
    tests/check-workspace/test-check-workspace.sh) echo "check-workspace.sh check-ledger.sh validate.sh lib/env.sh tests/check-workspace" ;;
    tests/guard-subagent-model/test-guard-subagent-model.sh) echo "guard-subagent-model.sh guard-subagent-model.py tests/guard-subagent-model ../rules/agents/settings.json" ;;
    tests/guard-bash/test-guard-bash.sh) echo "guard-bash.sh guard-bash.py aiwp.sh tests/guard-bash tests/test_guard_bash.py ../rules/agents/settings.json" ;;
    tests/setup-claude/test-setup-claude.sh) echo "setup-claude.sh tests/setup-claude" ;;
    tests/heavy-run/test-heavy-run.sh) echo "heavy-run.sh tests/heavy-run" ;;
    tests/single-agent/test-single-agent.sh) echo "single-agent.sh single-claude.sh history.sh lib/projects.sh tests/single-agent tests/lib ../rules/single-agent ../rules/agents/settings.json" ;;
    tests/aiwp-cmds/test-aiwp-cmds.sh) echo "aiwp-cmds.sh tests/aiwp-cmds" ;;
    tests/aiwp-gate/test-aiwp-gate.sh) echo "aiwp-gate.sh aiwp-cmds.sh aiwp-project-state.sh lib/projects.sh tests/aiwp-gate" ;;
    tests/aiwp-project-state/test-aiwp-project-state.sh) echo "aiwp-project-state.sh lib/projects.sh tests/aiwp-project-state" ;;
    tests/aiwp/test-aiwp.sh) echo "aiwp.sh release-notice.sh tests/aiwp ../rules/agents/settings.json" ;;
    tests/sync-env/test-sync-env.sh) echo "sync-env.sh lib/env.sh tests/sync-env" ;;
  esac
}

# Returns 0 when suite $1 has to run: it has no known inputs, or one of its inputs changed (a script or library it calls
# is an input: a changed gate script runs only the suites that depend on it).
suite_selected() {
  local inputs i p
  if [ "$all" -eq 1 ]; then return 0; fi
  inputs="$(suite_inputs "$1")"
  [ -n "$inputs" ] || return 0
  for i in $inputs; do
    case "$i" in ../*) p="${i#../}" ;; *) p="scripts/$i" ;; esac
    if changed_has "$p" || changed_under "$p"; then return 0; fi
  done
  return 1
}

# Prints the content hash of each file suite $1 tests. Nothing when its inputs are unknown: it is then never cached.
suite_state() {
  local i f
  [ -n "$(suite_inputs "$1")" ] || return 0
  for i in $(suite_inputs "$1"); do
    { find "$root/scripts/$i" -type f 2>/dev/null || true; } | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s ' "${f#"$root"/}"
      git hash-object -- "$f"
    done
  done
}

# Runs each selected suite of SUITES, once per state of its inputs; a suite missing on disk fails.
# Stops at the first failure and prints how to run it alone, unless --all.
check_suites() {
  local suite rc=0 key started elapsed
  for suite in $SUITES; do
    if [ ! -f "$root/scripts/$suite" ]; then
      echo "suite missing: scripts/$suite"
      rc=1
      if [ "$all" -eq 0 ]; then return 1; fi
      continue
    fi
    if ! suite_selected "$suite"; then
      echo "SKIP suite scripts/$suite (its inputs did not change)"
      continue
    fi
    key="$(ledger_key "suite|$suite" "$(suite_state "$suite")")"
    if ledger_hit "$key" 0; then
      echo "CACHED suite scripts/$suite"
      continue
    fi
    started="$SECONDS"
    if bash "$root/scripts/$suite"; then
      elapsed=$((SECONDS - started))
      echo "suite ok: scripts/$suite (${elapsed}s)"
      if [ "$elapsed" -gt 60 ]; then echo "SLOW scripts/$suite: ${elapsed}s, budget 60s (rules/quality.md)"; fi
      ledger_record "$key"
    else
      echo "suite FAILED: scripts/$suite"
      echo "run it alone: bash scripts/$suite"
      rc=1
      if [ "$all" -eq 0 ]; then return 1; fi
    fi
  done
  return "$rc"
}

read_changed_paths

step decisions check_decisions
step custom-terms check_custom_terms
step i18n check_i18n
step settings check_settings
if changed_under tools; then step parse check_poc_parse; fi
step validate check_validate
if [ "$floor" -eq 1 ]; then
  echo "SKIP suites (--floor)"
elif changed_under scripts || changed_has rules/agents/settings.json; then
  step suites check_suites
else
  echo "SKIP suites (nothing under scripts/ changed)"
fi

exit "$failed"
