#!/usr/bin/env bash
# Repo layout of projects/: any folder, at any depth, may be an independent git repo, inside another repo too (whether
# the parent ignores it is the developer's choice). A path belongs to the nearest repo above it. A folder is a repo when
# it holds a .git entry, a directory or a file. No layout is refused. Sourced by init-repo.sh, history.sh,
# aiwp-project-state.sh, aiwp-gate.sh (the clean checks) and aiwp-cmds.sh (open).

# Sets the globals parent and parent_flag from --parent (kebab-case folders joined by /) or --client (a single
# kebab-case folder). Fails, with the reason on stderr, on an empty or malformed value or when both flags are given.
# shellcheck disable=SC2034  # parent and parent_flag are globals of the caller.
projects_set_parent() {
  local kebab='[a-z0-9]+(-[a-z0-9]+)*' pattern form="kebab-case folders joined by /"
  pattern="^$kebab(/$kebab)*$"
  [ -n "$2" ] || { echo "error: $1 must not be empty" >&2; return 1; }
  [ -z "${parent_flag:-}" ] || [ "$parent_flag" = "$1" ] || { echo "error: use --parent or --client, not both" >&2; return 1; }
  if [ "$1" = --client ]; then
    pattern="^$kebab$"
    form="kebab-case"
  fi
  [[ "$2" =~ $pattern ]] || { echo "error: $1 must be $form" >&2; return 1; }
  parent_flag="$1"
  parent="$2"
}

# Prints the repo <root>/<rel> belongs to: the nearest folder at or above it, inside projects/, that holds a .git entry,
# relative to <root>. Fails, printing nothing, when there is none. <rel> starts with projects/.
projects_repo_of() {
  local root="$1" cur="${2%/}"
  while :; do
    case "$cur" in projects/*) ;; *) return 1 ;; esac
    if [ -e "$root/$cur/.git" ]; then
      printf '%s\n' "$cur"
      return 0
    fi
    cur="${cur%/*}"
  done
}

# Prints the nearest repo above <root>/<rel>, <rel> excluded, relative to <root>. Fails, printing nothing, when there
# is none.
projects_repo_above() {
  local rel="${2%/}"
  case "$rel" in projects/*/*) projects_repo_of "$1" "${rel%/*}" ;; *) return 1 ;; esac
}

# Fails, with the reason on stderr, when <root>/<rel> is a folder inside a repo that is not the root of a repo itself:
# what belongs to a repo (its history.txt) goes to the root of that repo. A repo root at any depth, a repo inside
# another one and a folder in no repo pass.
projects_check_target() {
  local root="$1" rel="${2%/}" repo
  repo="$(projects_repo_of "$root" "$rel")" || return 0
  [ "$repo" != "$rel" ] || return 0
  echo "error: $rel is inside the repo $repo, not the root of a repo: use $repo" >&2
  return 1
}

# Prints, sorted, the absolute path of each repo below the folder <dir>, <dir> itself excluded, at any depth, repos
# inside repos included. It never descends into a .git, a hidden folder, node_modules or a link (a link to a repo is
# listed, never walked), so a link loop is never walked. Cost: one find over the tree, the repos included.
projects_find_repos() {
  local dir="${1%/}" p
  [ -d "$dir" ] || return 0
  find "$dir" -mindepth 1 \( -name .git -print -prune \) -o \( \( -name '.*' -o -name node_modules \) -prune \) \
    -o \( -type l -exec test -e '{}/.git' ';' -print \) 2>/dev/null |
    while IFS= read -r p; do
      p="${p%/.git}"
      [ "$p" != "$dir" ] && printf '%s\n' "$p"
    done | LC_ALL=C sort -u
}

# Prints, sorted, each repo folder under <root>/projects, relative to <root>, at any depth, a repo inside another one
# included (projects_find_repos).
projects_repos() {
  local base="$1/projects" p
  [ -d "$base" ] || return 0
  projects_find_repos "$base" | while IFS= read -r p; do printf 'projects/%s\n' "${p#"$base"/}"; done
}

# Prints the changes of the checkout of the repo <dir> that count against a clean checkout (git status --porcelain,
# every untracked file listed): a repo inside it that it does not ignore (an untracked "<path>/" holding a .git) is
# not a change of it, nor is a commit moved in a repo it tracks as a gitlink (submodules ignored). Fails when git does.
projects_changes() {
  local dir="${1%/}" out line folder
  # -z: no quoting of unusual names, so a nested repo's folder is found whatever its name.
  out="$(set -o pipefail; git -C "$dir" status --porcelain -z --untracked-files=all --ignore-submodules=all | tr '\0' '\n')" ||
    return 1
  [ -n "$out" ] || return 0
  while IFS= read -r line; do
    case "$line" in
      '?? '*/)
        folder="${line#?? }"
        [ -e "$dir/$folder.git" ] && continue
        ;;
    esac
    printf '%s\n' "$line"
  done <<<"$out"
}
