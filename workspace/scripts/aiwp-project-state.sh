#!/usr/bin/env bash
# Prints whether each project of projects/ and each POC of custom/pocs/ is a workspace project, and of which version:
# the marker on line 1 of its README.md against the workspace VERSION and migrations/. Read only: it never writes,
# fetches or changes a checkout, so the UserPromptSubmit hook, aiwp-cmds.sh open, the gate and /normalize-projects can
# all call it.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Prints the command reference.
usage() {
  cat <<'USAGE'
Usage: scripts/aiwp-project-state.sh [--porcelain] [--] [<project>...]

The marker is line 1 of the README.md of a project (or of a POC folder), read with the fixed expression
  ^<!-- AI-WORKSPACE-PROJECT ([0-9]+\.[0-9]+\.[0-9]+) -->$   (a trailing carriage return is ignored)
For a project of projects/ the README.md that counts is the committed one of developer (git show, never the
checkout); without developer, the one of main; a repo with no commit yet, the file in the folder. For a POC,
custom/pocs/<poc>/README.md. The project is out of date only when a file migrations/<x.y.z>.md exists with a version
above its marker and up to the workspace VERSION: a newer workspace with no new migration asks nothing.

States:
  none        no marker (or no README.md): not a workspace project yet; /normalize-projects brings it in
  current     the marker has no migration pending
  outdated    migrations newer than the marker are pending (listed)
  newer       the marker is above the workspace VERSION: the project was normalized by a newer workspace
  workspace   the workspace's own repository (claude-cli-agents-workspace): recognized, never normalized

<project>: a folder relative to projects/ (billing-api, acme/billing-web), projects/<path>, custom/pocs/<poc>,
pocs/<poc>, or a bare name, matched against the last folder of every repo of projects/ and every POC (all matches
are printed). No <project>: every repo of projects/, at any depth, and every POC that custom/pocs/.gitignore keeps.

Output, one line per project:
  <path>: <state in words>; developer <exists|missing>; checkout on <branch>
--porcelain: tab-separated fields, for scripts:
  kind name path state marker version pending source developer checkout
  (kind project|poc; marker and pending "-" when empty, pending comma-separated; source developer|main|folder|file;
  developer yes|no and checkout <branch>|detached for a project, "-" for a POC)

Exit: 0 every project named was found (whatever its state); 1 a project not found, or VERSION unreadable; 2 usage.

Examples:
  bash scripts/aiwp-project-state.sh
  bash scripts/aiwp-project-state.sh billing-api custom/pocs/cache-test
  bash scripts/aiwp-project-state.sh --porcelain acme/billing-web
USAGE
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
[ -r "$root/scripts/lib/projects.sh" ] || { echo "error: scripts/lib/projects.sh not found" >&2; exit 2; }
# shellcheck source=lib/projects.sh
. "$root/scripts/lib/projects.sh"
MARKER_RE='^<!-- AI-WORKSPACE-PROJECT ([0-9]+\.[0-9]+\.[0-9]+) -->$'
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
OWN_NAME="claude-cli-agents-workspace"
porcelain=0
args=()

while [ $# -gt 0 ]; do
  case "$1" in
    --porcelain) porcelain=1 ;;
    --help | -h) usage; exit 0 ;;
    --) shift; args+=("$@"); break ;;
    -*) echo "error: unknown option: $1" >&2; exit 2 ;;
    *) args+=("$1") ;;
  esac
  shift
done

version="$(tr -d '[:space:]' <"$root/VERSION" 2>/dev/null || true)"
[[ "$version" =~ $SEMVER_RE ]] || { echo "error: VERSION of the workspace is missing or not x.y.z" >&2; exit 1; }

# Succeeds when version $1 is above version $2 (both x.y.z).
version_gt() {
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<<"$1"
  IFS=. read -r b1 b2 b3 <<<"$2"
  [ "$((10#$a1))" -ne "$((10#$b1))" ] && { [ "$((10#$a1))" -gt "$((10#$b1))" ]; return; }
  [ "$((10#$a2))" -ne "$((10#$b2))" ] && { [ "$((10#$a2))" -gt "$((10#$b2))" ]; return; }
  [ "$((10#$a3))" -gt "$((10#$b3))" ]
}

# Prints the versions of migrations/<x.y.z>.md, one per line, in ascending order.
migration_versions() {
  local f v list=()
  for f in "$root/migrations"/*.md; do
    [ -f "$f" ] || continue
    v="${f##*/}"
    v="${v%.md}"
    [[ "$v" =~ $SEMVER_RE ]] && list+=("$v")
  done
  [ "${#list[@]}" -gt 0 ] || return 0
  printf '%s\n' "${list[@]}" | sort -t. -k1,1n -k2,2n -k3,3n
}
migrations="$(migration_versions)"

# Prints the marker version of a README first line read on stdin, or nothing.
marker_of() {
  local line
  IFS= read -r line || [ -n "$line" ] || return 0
  line="${line%$'\r'}"
  if [[ "$line" =~ $MARKER_RE ]]; then printf '%s\n' "${BASH_REMATCH[1]}"; fi
}

# Prints the migrations pending for a marker, comma-separated, or nothing.
pending_for() {
  local marker="$1" v out=""
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    if version_gt "$v" "$marker" && ! version_gt "$v" "$version"; then out="${out:+$out,}$v"; fi
  done <<<"$migrations"
  printf '%s' "$out"
}

# Succeeds when the repo at $1 is the workspace's own repository: its folder or origin is named after it, or a
# branch of it holds the product layout (workspace/VERSION and workspace/scripts/aiwp-cmds.sh).
is_own_repo() {
  local repo="$1" url ref
  [ "${repo##*/}" = "$OWN_NAME" ] && return 0
  url="$(git --no-optional-locks -C "$repo" remote get-url origin 2>/dev/null || true)"
  url="${url%/}"
  url="${url%.git}"
  [ "${url##*[/:]}" = "$OWN_NAME" ] && return 0
  for ref in refs/heads/developer refs/heads/main HEAD; do
    git --no-optional-locks -C "$repo" cat-file -e "$ref:workspace/VERSION" 2>/dev/null &&
      git --no-optional-locks -C "$repo" cat-file -e "$ref:workspace/scripts/aiwp-cmds.sh" 2>/dev/null && return 0
  done
  return 1
}

# Prints one line for a state: path, kind, state, marker, pending, source, developer, checkout.
report() {
  local path="$1" kind="$2" state="$3" marker="$4" pending="$5" source="$6" developer="$7" checkout="$8" words where
  if [ "$porcelain" -eq 1 ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$kind" "${path##*/}" "$path" "$state" "${marker:--}" "$version" \
      "${pending:--}" "$source" "$developer" "$checkout"
    return 0
  fi
  case "$source" in
    developer | main) where="README.md of $source" ;;
    folder) where="README.md of the folder (no commit yet)" ;;
    *) where="$path/README.md" ;;
  esac
  case "$state" in
    none) words="not a workspace project: no marker in $where" ;;
    current) words="up to date (marker $marker, workspace $version)" ;;
    outdated) words="out of date: marker $marker, workspace $version, pending migrations ${pending//,/, }" ;;
    newer) words="marker $marker is newer than the workspace ($version): update the workspace" ;;
    workspace) words="the workspace's own repository: never normalized" ;;
  esac
  if [ "$kind" = project ]; then
    if [ "$developer" = yes ]; then words="$words; developer exists"; else words="$words; developer missing"; fi
    words="$words; checkout on $checkout"
  fi
  printf '%s: %s\n' "$path" "$words"
}

# Prints the state from a marker (empty: none).
state_of() {
  local marker="$1"
  if [ -z "$marker" ]; then
    echo none
  elif version_gt "$marker" "$version"; then
    echo newer
  elif [ -n "$(pending_for "$marker")" ]; then
    echo outdated
  else
    echo current
  fi
}

# Reports a repo of projects/ given relative to projects/.
project_state() {
  local rel="$1" repo="$root/projects/$1" g developer=no checkout source marker="" state pending=""
  g=(git --no-optional-locks -C "$repo")
  git -C "$repo" rev-parse -q --verify refs/heads/developer >/dev/null 2>&1 && developer=yes
  checkout="$("${g[@]}" symbolic-ref -q --short HEAD 2>/dev/null || echo detached)"
  if is_own_repo "$repo"; then
    report "projects/$rel" project workspace "" "" - "$developer" "$checkout"
    return 0
  fi
  if [ "$developer" = yes ]; then
    source=developer
  elif "${g[@]}" rev-parse -q --verify refs/heads/main >/dev/null 2>&1; then
    source=main
  else
    source=folder
  fi
  if [ "$source" = folder ]; then
    [ -f "$repo/README.md" ] && marker="$(marker_of <"$repo/README.md")"
  else
    marker="$("${g[@]}" show "refs/heads/$source:README.md" 2>/dev/null | marker_of || true)"
  fi
  state="$(state_of "$marker")"
  [ "$state" != outdated ] || pending="$(pending_for "$marker")"
  report "projects/$rel" project "$state" "$marker" "$pending" "$source" "$developer" "$checkout"
}

# Reports a POC folder of custom/pocs/.
poc_state() {
  local name="$1" marker="" state pending=""
  [ -f "$root/custom/pocs/$name/README.md" ] && marker="$(marker_of <"$root/custom/pocs/$name/README.md")"
  state="$(state_of "$marker")"
  [ "$state" != outdated ] || pending="$(pending_for "$marker")"
  report "custom/pocs/$name" poc "$state" "$marker" "$pending" file - -
}

# Prints the POC folders of custom/pocs/ the custom layer keeps (an ignored one is outside the workspace).
poc_names() {
  local d name
  for d in "$root/custom/pocs"/*/; do
    d="${d%/}"
    [ -d "$d" ] && [ ! -L "$d" ] || continue
    name="${d##*/}"
    git -C "$root/custom" check-ignore -q -- "pocs/$name/" 2>/dev/null && continue
    printf '%s\n' "$name"
  done
}

# Succeeds when projects/<rel> is the root of a repo of projects/.
is_project() {
  local rel="$1"
  [ -n "$rel" ] && [ -e "$root/projects/$rel/.git" ] && [ ! -L "$root/projects/$rel" ]
}

# Reports one argument; fails when it names nothing.
report_arg() {
  local arg="${1%/}" found=0 rel name
  case "$arg" in
    /* | *..* | '') echo "error: not a project of projects/ or a POC of custom/pocs/: $1" >&2; return 1 ;;
  esac
  case "$arg" in
    custom/pocs/* | pocs/*)
      name="${arg#custom/}"
      name="${name#pocs/}"
      if [[ "$name" != */* ]] && [ -d "$root/custom/pocs/$name" ]; then
        if git -C "$root/custom" check-ignore -q -- "pocs/$name/" 2>/dev/null; then
          echo "error: $1 is ignored by the custom layer (custom/pocs/.gitignore): outside this workspace" >&2
          return 1
        fi
        poc_state "$name"
        return 0
      fi
      echo "error: POC not found: $1" >&2
      return 1
      ;;
    projects/*) arg="${arg#projects/}" ;;
  esac
  if is_project "$arg"; then
    project_state "$arg"
    return 0
  fi
  if [[ "$arg" != */* ]]; then
    while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      rel="${rel#projects/}"
      [ "${rel##*/}" = "$arg" ] || continue
      project_state "$rel"
      found=1
    done < <(projects_repos "$root")
    if [ -d "$root/custom/pocs/$arg" ] && ! git -C "$root/custom" check-ignore -q -- "pocs/$arg/" 2>/dev/null; then
      poc_state "$arg"
      found=1
    fi
  fi
  [ "$found" -eq 1 ] && return 0
  echo "error: project not found: $1" >&2
  return 1
}

rc=0
if [ "${#args[@]}" -eq 0 ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] && project_state "${rel#projects/}"
  done < <(projects_repos "$root")
  while IFS= read -r name; do
    [ -n "$name" ] && poc_state "$name"
  done < <(poc_names)
else
  for a in "${args[@]}"; do
    report_arg "$a" || rc=1
  done
fi
exit "$rc"
