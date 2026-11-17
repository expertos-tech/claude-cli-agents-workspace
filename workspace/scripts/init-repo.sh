#!/usr/bin/env bash
# Creates a project repo in projects/, or a POC or a tool of your own in the custom layer (custom/pocs/, custom/tools/),
# with base files. Nothing is ever written in the core: tools/ holds the product's tools.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Prints the help text.
usage() {
  cat <<'USAGE'
Usage: scripts/init-repo.sh --type <project|poc|tool> --name <kebab-name> [--parent <folder>[/<folder>...]] [--help]

  project  projects/<name>/ as an independent git repo (README, CHANGELOG, docs/, .gitignore).
           With --parent: projects/<parent>/<name>/ is the repo, at any depth; the folders of <parent> stay
           plain folders. Where a project goes is the human's decision.
  --client <kebab-name>  same as --parent with a single folder.
  poc      custom/pocs/<name>/, with a hypothesis README and CHANGELOG, and its row in custom/pocs/README.md.
  tool     custom/tools/<name>/, a tool of your own, with README and CHANGELOG, and its row in custom/tools/README.md.
           tools/ of the root holds the product's tools: read-only in an installed workspace, never written here.
  poc and tool are versioned in the custom layer repo; no custom/ repo: exit 1.

A project's row goes to custom/projects.md, the project index of the custom layer. No such file: the project is still
created, and an attention: line says the row is missing.

The README.md of a project and of a POC starts with the marker of the workspace version,
<!-- AI-WORKSPACE-PROJECT <VERSION> -->, so the new item is a workspace project from the start
(scripts/aiwp-project-state.sh). No readable VERSION: exit 1, nothing created.

Idempotent: existing files are never overwritten. Prints created paths only. The index row goes right below the last
row of the index's first table (at the end when it has none), once per name.

Exit 1 (nothing created) when: a folder above the project holds a .git (a repo never holds another); the project
folder exists with no .git and a folder below it holds one (a grouping folder); custom/ is missing or not a repo of
its own (poc, tool); or the item is ignored by the custom layer (custom/pocs/.gitignore keeps excluded POCs out).
Exit 2 on usage errors.

Example:
  bash scripts/init-repo.sh --type project --name billing-api
  bash scripts/init-repo.sh --type project --parent acme --name billing-api
  bash scripts/init-repo.sh --type tool --name log-viewer
USAGE
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -r "$root/scripts/lib/projects.sh" ] || { echo "error: scripts/lib/projects.sh not found" >&2; exit 2; }
# shellcheck source=lib/projects.sh
. "$root/scripts/lib/projects.sh"
type=""
parent_flag=""
name=""
parent=""

while [ $# -gt 0 ]; do
  case "$1" in
    --type|--name|--parent|--client)
      [ $# -ge 2 ] || { echo "error: $1 needs a value" >&2; exit 2; }
      case "$1" in
        --type) type="$2" ;;
        --name) name="$2" ;;
        --parent|--client) projects_set_parent "$1" "$2" || exit 2 ;;
      esac
      shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

case "$type" in project|poc|tool) ;; *) echo "error: --type must be project, poc or tool" >&2; exit 2 ;; esac
[[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || { echo "error: --name must be kebab-case" >&2; exit 2; }
if [ -n "$parent" ]; then
  [ "$type" = "project" ] || { echo "error: $parent_flag is valid only with --type project" >&2; exit 2; }
fi
command -v git >/dev/null 2>&1 || { echo "error: git not found" >&2; exit 2; }

out="$root"
today="$(date +%Y-%m-%d)"
version="$(tr -d '[:space:]' <"$root/VERSION" 2>/dev/null || true)"
if [ "$type" != tool ] && ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: VERSION of the workspace is missing or not x.y.z: the marker of a new $type needs it" >&2
  exit 1
fi
marker="<!-- AI-WORKSPACE-PROJECT $version -->"

# Writes stdin to a file only when it does not exist yet.
write_new() {
  local file="$1"
  if [ -e "$file" ]; then
    cat >/dev/null
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  cat >"$file"
  file="${file#"$out"/}"
  echo "created: ${file#"$root"/}"
}

# Initializes a git repo with main as the default branch when the folder is not one yet.
init_git() {
  local dir="$1"
  [ -e "$dir/.git" ] && return 0
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  echo "git init: ${dir#"$root"/}"
}

# Writes the default .gitignore of a new repo.
write_gitignore() {
  write_new "$1/.gitignore" <<'GI'
.env
**/.env
**/.terraform/
*.tfstate
*.tfstate.*
*.tfplan
coverage/
GI
}

# Writes a CHANGELOG.md with an Unreleased section.
write_changelog() {
  write_new "$1/CHANGELOG.md" <<CL
# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions in [SemVer](https://semver.org/).

## [Unreleased]

### Added

- Initial structure ($today).
CL
}

# Adds a row to an index file unless a row for the key is there: right below the last row of its first table, or at
# the end when the file has no table. Text after the table stays where it is.
index_row() {
  local file="$1" key="$2" row="$3" tmp
  grep -q -F "| $key |" "$file" && return 0
  tmp="$(mktemp)"
  ROW="$row" awk '
    !done && /^\|/ { in_table = 1; print; next }
    !done && in_table { print ENVIRON["ROW"]; done = 1 }
    { print }
    END { if (!done) print ENVIRON["ROW"] }
  ' "$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
  file="${file#"$out"/}"
  echo "indexed: ${file#"$root"/}"
}

if [ "$type" = "project" ]; then
  label="${parent:+$parent/}$name"
  dir="$root/projects/$label"
  projects_check_repo_root "$root" "projects/$label" || exit 1
  init_git "$dir"
  write_gitignore "$dir"
  write_changelog "$dir"
  write_new "$dir/README.md" <<RM
$marker
# $name

## What it is

## How to run

## How to test

## How to deploy
RM
  write_new "$dir/docs/README.md" <<DR
# $name documentation

| Page | Content |
| --- | --- |
| overview.md | What it is, why it exists, users and scope |
| architecture.md | Components, flows and diagram |
| decisions.md | The single decisions file: how it works, implementation strategy, stack; each later decision in a `## D-n <title>` section, adjustments in its change history |
| operations.md | Configuration, deployment, rollback, monitoring |
| costs.md | Monthly cloud cost, method, assumptions and recommendation |
DR
  index="$root/custom/projects.md"
  if [ -f "$index" ]; then
    index_row "$index" "$label" "| $label | | |"
  else
    echo "attention: custom/projects.md not found: add the row of $label to the project index of the custom layer"
  fi
  exit 0
fi

# poc and tool: an item of the custom layer, a git repo of its own.
[ -d "$root/custom" ] || { echo "error: custom/ not found: a $type lives in the custom layer (custom/${type}s/)" >&2; exit 1; }
[ "$(cd "$root/custom" && git rev-parse --show-toplevel 2>/dev/null)" = "$(cd "$root/custom" && pwd -P)" ] ||
  { echo "error: custom/ is not a git repo of its own: set up the custom layer there (aiwp new)" >&2; exit 1; }
repo="$root/custom/${type}s"
dir="$repo/$name"
# Refuse ignored destinations (custom/pocs/.gitignore keeps excluded POCs out) before writing any file or row.
if git -C "$root/custom" check-ignore -q -- "${type}s/$name/"; then
  echo "error: ${dir#"$root"/} is ignored and outside this workspace" >&2
  exit 1
fi
if [ "$type" = "poc" ]; then
  write_new "$repo/README.md" <<'PR'
# POCs

POCs that test hypotheses. One folder per POC.

| Item | Type | Goal |
| --- | --- | --- |
PR
else
  write_new "$repo/README.md" <<'PR'
# Tools

Your own tools that support local environments, in the custom layer. One folder per tool. The product's tools are in
tools/ of the workspace root.

| Item | Type | Goal |
| --- | --- | --- |
PR
fi
write_changelog "$dir"
if [ "$type" = "poc" ]; then
  write_new "$dir/README.md" <<RM
$marker
# $name (POC)

## Hypothesis

## How to run

## Result

## Conclusion
RM
else
  write_new "$dir/README.md" <<RM
# $name

## What it is

## How to run

## How to test
RM
fi
index_row "$repo/README.md" "$name" "| $name | $type | |"
