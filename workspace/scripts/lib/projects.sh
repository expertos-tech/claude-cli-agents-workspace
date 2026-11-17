#!/usr/bin/env bash
# Repo layout of projects/: any folder, at any depth, may be an independent git repo, and a repo never holds another.
# A folder is a repo when it holds a .git entry, a directory or a file. Sourced by init-repo.sh, history.sh,
# aiwp-project-state.sh and aiwp-gate.sh (bring).

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

# Prints the outermost folder above <root>/<rel>, <rel> excluded, that holds a .git entry, relative to <root>.
# Fails, printing nothing, when there is none. <rel> starts with projects/.
projects_repo_above() {
  local root="$1" rest="${2#projects/}" cur=projects
  while [ "${rest#*/}" != "$rest" ]; do
    cur="$cur/${rest%%/*}"
    rest="${rest#*/}"
    if [ -e "$root/$cur/.git" ]; then
      printf '%s\n' "$cur"
      return 0
    fi
  done
  return 1
}

# Succeeds when a folder below <root>/<rel>, <rel> itself excluded, is a repo, found by the walk of projects_repos.
projects_has_repo_below() {
  [ -d "$1/$2" ] || return 1
  [ -n "$(projects_repos_under "$1" "$2" | head -n 1)" ]
}

# Fails, with the reason on stderr, when <root>/<rel> cannot be a repo root: a folder above it is a repo, or it is not
# a repo and a folder below it is one (a grouping folder).
projects_check_repo_root() {
  local root="$1" rel="$2" above
  if above="$(projects_repo_above "$root" "$rel")"; then
    echo "error: $rel is inside the repo $above; a repo never holds another" >&2
    return 1
  fi
  [ ! -e "$root/$rel/.git" ] || return 0
  if projects_has_repo_below "$root" "$rel"; then
    echo "error: $rel is a grouping folder (a folder below it holds a repo); a repo never holds another" >&2
    return 1
  fi
}

# Prints, sorted, each repo folder under <root>/projects, relative to <root>, at any depth. It never descends into a
# repo, a hidden folder or a link, so a repo inside another one or a link loop is never walked. Cost: it walks every
# folder of a plain (non-repo) folder in full, about 1 s per 10,000 folders on bash 3.2, at every session start
# (setup-claude.sh) and claim; with repos only, it reads one level per grouping folder.
projects_repos() {
  [ -d "$1/projects" ] || return 0
  projects_repos_under "$1" projects
}

# Walks <root>/<rel> for projects_repos.
projects_repos_under() {
  local root="$1" rel="$2" d
  for d in "$root/$rel"/*/; do
    d="${d%/}"
    [ -d "$d" ] || continue
    if [ -e "$d/.git" ]; then
      printf '%s\n' "$rel/${d##*/}"
    elif [ ! -L "$d" ]; then
      projects_repos_under "$root" "$rel/${d##*/}"
    fi
  done
}
