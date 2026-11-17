#!/usr/bin/env bash
# Work area of the workspace: every change to a project or POC is made in a local clone under tmp/work/, pushed to the
# remote at every commit, and reaches the base only through the gate.
set -euo pipefail

# Prints the command reference.
usage() {
  cat <<'USAGE'
Usage: scripts/aiwp-cmds.sh <command> [args] [--help]

Work happens in tmp/work/<work>/<clone>/: a local clone (git clone --local) of a repo of projects/ (or of custom/, for
POCs), on the branch of the request. Everything is allowed inside a clone; projects/ and the core change only through
the gate. <work> is <yyyy-mm-dd>-<kebab-slug>, one folder per request.

Commands:
  open <work> <repo>... [--branch <type>/<slug>]
        <repo> is a repo folder relative to projects/ (e.g. billing-api, acme/billing-web), or "custom" for
        a POC. For each: clones it to tmp/work/<work>/<last folder of repo>/, points the clone's origin at the real
        remote of the repo, creates the branch (default feat/<slug of work>) from the base (developer, else main),
        installs the clone's git hooks (below), copies the repo's .env and local.settings.json files, and pushes the
        branch. Prints "path: <clone>". An existing clone of the same repo is reused. For a repo of projects/ it also
        prints its state (scripts/aiwp-project-state.sh): with no marker or out of date, an attention: line asks
        for authorization to run /normalize-projects; the work goes on either way.
  run <work>/<clone> -- <command>...
        Runs the command with the clone as the current folder. Refuses a path outside tmp/work/.
  status [<work>]
        Per clone: branch, base, commits ahead of the base, commits not on the remote, files changed not committed.
  push <work>/<clone>
        Pushes the branch now (what a failed automatic push left behind), with the pre-push checks.
  close <work> [--discard]
        Deletes tmp/work/<work>/ when every clone has nothing uncommitted, nothing off the remote, and its branch in
        the base of its source repo. Otherwise lists what would be lost and exits 1; --discard deletes anyway (the
        remote branches stay).
  up <work>/<clone> | <repo> [-- <docker compose options>...]
        Publishes to the local Docker: before the build, tags each image of the stack's running containers as
        <name>:rollback-latest and <name>:rollback-<yyyymmdd-hhmmss>, keeping the last 3; then
        docker compose up -d --build; then tags each image of the stack as <name>:published-<yyyymmdd-hhmmss>-<sha>.
        <repo> (relative to projects/) publishes from projects/<repo> itself.
  rollback <work>/<clone> | <repo> [-- <docker compose options>...]
        Points each image of the stack back to its rollback-latest tag and runs docker compose up -d --no-build.
        Volumes are never touched.
  gate, release, apply, developer, checkpoint, bring
        The only ways into projects/: scripts/aiwp-gate.sh --help.

Git hooks of a clone (written by open; never part of any repo):
  post-commit, post-rewrite, post-merge
                             push the branch: git push --force-with-lease=<branch>:<sha pushed last> origin
                             HEAD:refs/heads/<branch>. Only the branch open created; never developer, main or master.
  pre-push                   reads every ref line first; refuses a push to developer, main or master; for each pushed
                             sha, takes the commits the remote does not have (git ls-remote) and refuses one that adds
                             or renames to .env or local.settings.json (merges included) and a secret found by gitleaks.
                             Docker down or the remote unreadable: the push is refused, the commit stays in the clone.

Internal: _autopush <clone>, _prepush <clone> <remote> (refs on stdin), _scan-range <clone> <sha> <base ref> (the
gate's check of every commit that enters the base), _state-note <repo> (the state lines of open and the gate; never
fails), _stop-check (Claude Code Stop hook JSON on stdin; blocks the end
of a reply once while a clone has a commit, on a branch or a detached HEAD, not on the remote).

Environment: AIWP_SECRETS_CMD replaces the gitleaks run (tests); it gets the repo and the range as arguments.
Exit: 0 ok; 1 refused or failed; 2 usage error.
USAGE
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
work_root="$root/tmp/work"
work_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*$'
protected_re='^(developer|main|master)$'

# Prints an error and exits with the given code.
die() {
  local code="$1"
  shift
  echo "error: $*" >&2
  exit "$code"
}

# Prints the base branch of a repo folder: developer when it has one, else main.
base_of() {
  if git -C "$1" rev-parse -q --verify refs/heads/developer >/dev/null; then echo developer; else echo main; fi
}

# Prints the physical path of a folder, or fails.
physical() {
  (cd "$1" 2>/dev/null && pwd -P)
}

# Resolves <work>/<clone> to the clone's physical path under tmp/work/, or exits 1.
clone_path() {
  local given="$1" path
  case "$given" in
    /*) path="$given" ;;
    tmp/work/*) path="$root/$given" ;;
    *) path="$work_root/$given" ;;
  esac
  path="$(physical "$path")" || die 1 "not found: $given"
  case "$path/" in
    "$work_root"/*/*/) ;;
    *) die 1 "refused: $given is not a clone under tmp/work/<work>/" ;;
  esac
  [ "$(git -C "$path" rev-parse --show-toplevel 2>/dev/null)" = "$path" ] || die 1 "not a clone: $given"
  echo "$path"
}

# Prints the source repo folder of a repo argument (relative to projects/, or "custom"), or exits 1.
source_repo() {
  local repo="${1%/}" src
  if [ "$repo" = custom ]; then
    src="$root/custom"
  else
    case "$repo" in /* | *..* | '') die 2 "<repo> is a folder relative to projects/: $1" ;; esac
    src="$root/projects/$repo"
  fi
  src="$(physical "$src")" || die 1 "repo not found: $1"
  [ "$(git -C "$src" rev-parse --show-toplevel 2>/dev/null)" = "$src" ] || die 1 "not the root of a git repo: $1"
  echo "$src"
}

# Writes the git hooks of a clone; they call this script by its absolute path. The $(...) in the hook text is meant
# for the hook, not for this script: SC2016 does not apply.
# shellcheck disable=SC2016
write_hooks() {
  local clone="$1" hooks script="$root/scripts/aiwp-cmds.sh"
  hooks="$(git -C "$clone" rev-parse --git-path hooks)"
  case "$hooks" in /*) ;; *) hooks="$clone/$hooks" ;; esac
  mkdir -p "$hooks"
  printf '#!/usr/bin/env bash\n# Written by scripts/aiwp-cmds.sh open: pushes the branch after each commit.\nexec bash %q _autopush "$(git rev-parse --show-toplevel)"\n' "$script" >"$hooks/post-commit"
  printf '#!/usr/bin/env bash\n# Written by scripts/aiwp-cmds.sh open: pushes the branch after a rebase or an amend.\nexec bash %q _autopush "$(git rev-parse --show-toplevel)"\n' "$script" >"$hooks/post-rewrite"
  printf '#!/usr/bin/env bash\n# Written by scripts/aiwp-cmds.sh open: pushes the branch after a merge or a pull.\nexec bash %q _autopush "$(git rev-parse --show-toplevel)"\n' "$script" >"$hooks/post-merge"
  printf '#!/usr/bin/env bash\n# Written by scripts/aiwp-cmds.sh open: checks what leaves the machine.\nexec bash %q _prepush "$(git rev-parse --show-toplevel)" "$1"\n' "$script" >"$hooks/pre-push"
  chmod +x "$hooks/post-commit" "$hooks/post-rewrite" "$hooks/post-merge" "$hooks/pre-push"
}

# Copies the local env files of the source repo (git-ignored, never in a clone) to the same paths in the clone.
copy_env_files() {
  local src="$1" clone="$2" f rel
  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    [ -e "$clone/$rel" ] && continue
    mkdir -p "$(dirname "$clone/$rel")"
    cp -p "$f" "$clone/$rel"
    echo "copied: $rel"
  done < <(find "$src" \( -name .git -o -name node_modules -o -name .terraform \) -prune -o -type f \
    \( -name .env -o -name local.settings.json \) -print0 2>/dev/null)
}

# Pushes the branch of a clone to its remote; prints the outcome. Returns 1 when the branch is not on the remote.
push_branch() {
  local clone="$1" branch current pushed
  branch="$(git -C "$clone" config --get aiwp.branch)" || { echo "aiwp: not a clone made by open: $clone" >&2; return 1; }
  current="$(git -C "$clone" symbolic-ref -q --short HEAD)" || current=""
  if [ "$current" != "$branch" ]; then
    echo "aiwp: HEAD is not on $branch: nothing pushed" >&2
    return 1
  fi
  [[ "$branch" =~ $protected_re ]] && { echo "aiwp: refused to push $branch" >&2; return 1; }
  # The lease is the sha this clone pushed last (none yet: the branch must not exist on the remote), so a rewrite
  # never overwrites a commit someone else pushed to the same branch.
  pushed="$(git -C "$clone" config --get aiwp.pushed || true)"
  if timeout 120 git -C "$clone" push -q --force-with-lease="refs/heads/$branch:$pushed" origin "HEAD:refs/heads/$branch" 2>&1; then
    git -C "$clone" config aiwp.pushed "$(git -C "$clone" rev-parse HEAD)"
    git -C "$clone" update-ref "refs/remotes/origin/$branch" HEAD
    echo "aiwp: pushed $branch $(git -C "$clone" rev-parse --short HEAD)"
  else
    echo "aiwp: NOT pushed: $branch stays only in this clone; run: bash scripts/aiwp-cmds.sh push ${clone#"$work_root"/}" >&2
    return 1
  fi
}

# Runs the secret scan on the commits of a revision range ("<sha> --not <sha>..."): AIWP_SECRETS_CMD in tests, else
# gitleaks in Docker. Its stdin is /dev/null: docker compose run keeps stdin open and would eat the hook's ref lines.
scan_secrets() {
  local clone="$1" range="$2"
  if [ -n "${AIWP_SECRETS_CMD:-}" ]; then
    "$AIWP_SECRETS_CMD" "$clone" "$range" </dev/null
    return
  fi
  command -v docker >/dev/null 2>&1 || { echo "aiwp: docker not found: the secret scan cannot run" >&2; return 2; }
  WORKSPACE_DIR="$root" timeout 300 docker compose --progress quiet -f "$root/docker/compose.yaml" run --rm -T gitleaks \
    git "/work/${clone#"$root"/}" --log-opts="$range" --no-banner --redact -v --config /work/docker/config/gitleaks-history.toml </dev/null
}

# Judges the commits of a revision range ("<sha> --not <sha>..."): refuses one that adds or renames to .env or
# local.settings.json (merges included) and a secret gitleaks finds. Returns 0 when none, 1 otherwise.
check_commits() {
  local clone="$1" revs="$2" envs rc=0
  # shellcheck disable=SC2086  # revs is a list of revisions, split on purpose
  [ "$(git -C "$clone" rev-list --count $revs)" -gt 0 ] || return 0
  # shellcheck disable=SC2086
  envs="$(git -C "$clone" log --format= --name-only -m --no-renames --diff-filter=d $revs |
    grep -E '(^|/)(\.env|local\.settings\.json)$' | sort -u || true)"
  if [ -n "$envs" ]; then
    printf 'aiwp: refused: these commits carry a local env file:\n%s\nrewrite the branch in the clone without it (git rebase -i is fine here)\n' "$envs" >&2
    return 1
  fi
  scan_secrets "$clone" "$revs" >&2 || rc=$?
  case "$rc" in
    0) return 0 ;;
    1) echo "aiwp: refused: a secret in the commits above; rewrite the branch in the clone without it" >&2; return 1 ;;
    *) echo "aiwp: refused: the secret scan did not run (exit $rc)" >&2; return 1 ;;
  esac
}

# pre-push: reads every "<local ref> <local sha> <remote ref> <remote sha>" line first, then judges each. What leaves
# the machine is every commit of the pushed sha that the remote being pushed to does not have (git ls-remote, never
# the local tracking refs, which can be stale or copied from projects/): a protected target, or check_commits failing,
# refuses the whole push.
cmd_prepush() {
  local clone="$1" remote="${2:-origin}" line local_sha remote_ref target known=() sha revs lines=() remote_list i
  while IFS= read -r line; do lines+=("$line"); done
  remote_list="$(timeout 60 git -C "$clone" ls-remote "$remote" 'refs/heads/*' 2>/dev/null)" || {
    echo "aiwp: refused: the remote cannot be read to know what is already there" >&2
    return 1
  }
  while read -r sha _; do
    [ -n "$sha" ] && git -C "$clone" cat-file -e "$sha^{commit}" 2>/dev/null && known+=("$sha")
  done <<<"$remote_list"
  for i in ${lines[@]+"${!lines[@]}"}; do
    read -r _ local_sha remote_ref _ <<<"${lines[$i]}"
    target="${remote_ref#refs/heads/}"
    if [[ "$target" =~ $protected_re ]]; then
      echo "aiwp: refused: a clone never pushes to $target; the gate moves the base (bash scripts/aiwp-cmds.sh gate)" >&2
      return 1
    fi
    [[ "$local_sha" =~ ^0+$ ]] && continue
    revs="$local_sha${known[*]+ --not ${known[*]}}"
    check_commits "$clone" "$revs" || return 1
  done
  return 0
}

# Prints the state of a repo of projects/ (relative path) and, with no marker or out of date, the attention line that
# asks for authorization to normalize it. Never fails: the state only warns.
state_note() {
  local rel="$1" line kind state marker version pending
  line="$(timeout 20 bash "$root/scripts/aiwp-project-state.sh" --porcelain -- "$rel" 2>/dev/null | head -n 1)" || true
  [ -n "$line" ] || return 0
  IFS=$'\t' read -r kind _ _ state marker version pending _ <<<"$line"
  [ "$kind" = project ] || return 0
  case "$state" in
    none) echo "attention: projects/$rel has no AI-WORKSPACE-PROJECT marker: not a workspace project yet. Ask the person for authorization to run /normalize-projects $rel; the work goes on either way" ;;
    outdated) echo "attention: projects/$rel is on workspace version $marker, the workspace on $version, with migrations ${pending//,/, } pending. Ask the person for authorization to run /normalize-projects $rel; the work goes on either way" ;;
    current) echo "state: projects/$rel is up to date (marker $marker)" ;;
    newer) echo "state: projects/$rel has marker $marker, newer than the workspace ($version)" ;;
    workspace) echo "state: projects/$rel is the workspace's own repository" ;;
  esac
  return 0
}

# open: one clone per repo, branch from the base, hooks, env files, first push.
cmd_open() {
  local work="" branch="" repos=() repo src name clone base url slug start
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch) [ $# -ge 2 ] || die 2 "--branch needs a value"; branch="$2"; shift ;;
      -*) die 2 "unknown option: $1" ;;
      *) if [ -z "$work" ]; then work="$1"; else repos+=("$1"); fi ;;
    esac
    shift
  done
  [[ "$work" =~ $work_re ]] || die 2 "<work> must be <yyyy-mm-dd>-<kebab-slug>: $work"
  [ "${#repos[@]}" -gt 0 ] || die 2 "open needs at least one <repo>"
  slug="${work:11}"
  [ -n "$branch" ] || branch="feat/$slug"
  [[ "$branch" =~ ^[a-z]+/[a-z0-9]+(-[a-z0-9]+)*$ ]] || die 2 "--branch must be <type>/<kebab-slug>: $branch"
  [[ "${branch#*/}" =~ $protected_re ]] && die 2 "--branch cannot be a base: $branch"
  for repo in "${repos[@]}"; do
    src="$(source_repo "$repo")"
    name="${src##*/}"
    clone="$work_root/$work/$name"
    case "$src/" in "$root/projects/"*) state_note "${src#"$root"/projects/}" ;; esac
    if [ -e "$clone" ]; then
      [ "$(git -C "$clone" config --get aiwp.source 2>/dev/null)" = "$src" ] || die 1 "tmp/work/$work/$name exists and is not a clone of $repo"
      echo "path: tmp/work/$work/$name (already open)"
      continue
    fi
    base="$(base_of "$src")"
    mkdir -p "$work_root/$work"
    git clone -q --local --no-checkout "$src" "$clone"
    url="$(git -C "$src" remote get-url origin 2>/dev/null || true)"
    git -C "$clone" config aiwp.source "$src"
    git -C "$clone" config aiwp.branch "$branch"
    git -C "$clone" config aiwp.base "$base"
    start="$(git -C "$src" rev-parse "refs/heads/$base")"
    if [ -n "$url" ]; then
      git -C "$clone" remote set-url origin "$url"
      # The tracking refs of a local clone are the branches of projects/<repo>, not of the remote: drop them, so that
      # "on the remote" always means what the remote really has.
      git -C "$clone" for-each-ref --format='%(refname)' refs/remotes/origin | while IFS= read -r ref; do
        git -C "$clone" update-ref -d "$ref"
      done
      if timeout 120 git -C "$clone" fetch -q origin "+refs/heads/$base:refs/remotes/origin/$base" 2>/dev/null; then
        start="origin/$base"
      else
        echo "attention: could not fetch $base from the remote of $repo; the branch starts from the local $base"
      fi
    else
      echo "attention: $repo has no remote; the branch is pushed to projects/$repo itself, not off the machine"
    fi
    if git -C "$clone" ls-remote --exit-code origin "refs/heads/$branch" >/dev/null 2>&1; then
      rm -rf "${clone:?}"
      rmdir "$work_root/$work" 2>/dev/null || true
      die 1 "$branch already exists on the remote of $repo: choose another --branch"
    fi
    git -C "$clone" checkout -q -b "$branch" "$start"
    git -C "$clone" branch -q --unset-upstream 2>/dev/null || true
    write_hooks "$clone"
    copy_env_files "$src" "$clone"
    if push_branch "$clone" >/dev/null; then
      echo "pushed: $branch"
    else
      echo "attention: the first push of $branch failed; run: bash scripts/aiwp-cmds.sh push $work/$name"
    fi
    echo "path: tmp/work/$work/$name"
  done
}

# run: the command in the clone.
cmd_run() {
  [ $# -ge 3 ] && [ "$2" = "--" ] || die 2 "usage: run <work>/<clone> -- <command>..."
  local clone
  clone="$(clone_path "$1")"
  shift 2
  cd "$clone"
  exec "$@"
}

# Prints the commits of HEAD (detached included) and of the local branches that no remote-tracking ref of origin has (the tracking refs are the remote's own:
# open drops the ones a local clone copies from projects/).
off_remote() {
  local clone="$1"
  git -C "$clone" rev-list HEAD --branches --not --remotes=origin 2>/dev/null || true
}

# Prints the status lines of one clone.
clone_status() {
  local clone="$1" branch base ahead off dirty
  branch="$(git -C "$clone" config --get aiwp.branch || echo '?')"
  base="$(git -C "$clone" config --get aiwp.base || echo '?')"
  ahead="$(git -C "$clone" rev-list --count "origin/$base..refs/heads/$branch" 2>/dev/null || echo '?')"
  off="$(off_remote "$clone" | grep -c . || true)"
  dirty="$(git -C "$clone" status --porcelain | wc -l | tr -d ' ')"
  printf '%s  branch=%s base=%s ahead=%s not-pushed=%s uncommitted=%s\n' "${clone#"$root"/}" "$branch" "$base" "$ahead" "$off" "$dirty"
}

# status: every clone, or the clones of one work.
cmd_status() {
  local pattern clone found=0
  if [ $# -ge 1 ]; then pattern="$work_root/$1/*/"; else pattern="$work_root/*/*/"; fi
  for clone in $pattern; do
    [ -d "$clone/.git" ] || continue
    found=1
    clone_status "${clone%/}"
  done
  [ "$found" -eq 1 ] || echo "no clone under tmp/work/${1:-}"
}

# close: delete a work folder when nothing in it would be lost: no change, stash or local commit off the remote in any
# clone, every work branch in the base of its source repo, and nothing in the folder but clones and gate files.
cmd_close() {
  local work="${1:-}" discard=0 entry clone src base branch problems=""
  [ "${2:-}" = "--discard" ] && discard=1
  [[ "$work" =~ $work_re ]] || die 2 "usage: close <work> [--discard]"
  [ -d "$work_root/$work" ] || die 1 "not found: tmp/work/$work"
  for entry in "$work_root/$work"/* "$work_root/$work"/.[!.]*; do
    [ -e "$entry" ] || continue
    case "${entry##*/}" in gate-*.md | .gate-*) continue ;; esac
    if [ ! -d "$entry/.git" ] || ! git -C "$entry" config --get aiwp.branch >/dev/null; then
      problems+="  ${entry##*/}: not a clone made by open"$'\n'
      continue
    fi
    clone="$entry"
    branch="$(git -C "$clone" config --get aiwp.branch)"
    src="$(git -C "$clone" config --get aiwp.source || echo '')"
    base="$(git -C "$clone" config --get aiwp.base || echo developer)"
    [ -z "$(git -C "$clone" status --porcelain)" ] || problems+="  ${clone##*/}: files changed and not committed"$'\n'
    [ -z "$(git -C "$clone" stash list)" ] || problems+="  ${clone##*/}: a stash"$'\n'
    [ -z "$(off_remote "$clone")" ] || problems+="  ${clone##*/}: commits not on the remote"$'\n'
    if [ -z "$src" ] || ! git -C "$clone" rev-parse -q --verify "refs/heads/$branch" >/dev/null ||
      ! git -C "$src" merge-base --is-ancestor "$(git -C "$clone" rev-parse "refs/heads/$branch")" "$base" 2>/dev/null; then
      problems+="  ${clone##*/}: $branch is not in $base of ${src#"$root"/}"$'\n'
    fi
  done
  if [ -n "$problems" ] && [ "$discard" -eq 0 ]; then
    printf 'refused: closing tmp/work/%s would lose:\n%s' "$work" "$problems" >&2
    echo "run the gate, push, or close with --discard to delete it anyway (remote branches stay)" >&2
    exit 1
  fi
  rm -rf "${work_root:?}/$work"
  echo "closed: tmp/work/$work"
}

# Resolves the folder up/rollback run in: a clone (<work>/<clone>, or tmp/work/<work>/<clone>) or projects/<repo>.
stack_folder() {
  if [ -d "$work_root/${1#tmp/work/}" ] && [[ "${1#tmp/work/}" == */* ]]; then
    clone_path "$1"
  else
    source_repo "$1"
  fi
}

# Prints "<container image ref> <image id>" for each running container of the stack.
stack_images() {
  local folder="$1"
  shift
  (cd "$folder" && docker compose "$@" ps -aq) | while IFS= read -r id; do
    [ -n "$id" ] && docker inspect -f '{{.Config.Image}} {{.Image}}' "$id"
  done | sort -u
}

# Keeps the newest 3 tags of a name matching a prefix; removes only the tag, never an image another tag uses.
prune_tags() {
  local name="$1" prefix="$2"
  docker image ls --format '{{.Tag}}' "$name" | { grep -E "^$prefix-[0-9]{8}-[0-9]{6}" || true; } | sort -r | tail -n +4 |
    while IFS= read -r tag; do
      if docker image rm "$name:$tag" >/dev/null 2>&1; then echo "untagged: $name:$tag"; else echo "attention: kept $name:$tag (in use)"; fi
    done
}

# up: rollback tags, then docker compose up -d --build, then published tags.
cmd_up() {
  [ $# -ge 1 ] || die 2 "usage: up <work>/<clone> | <repo> [-- <docker compose options>...]"
  local folder stamp sha ref id name covered=" " last
  folder="$(stack_folder "$1")"
  shift
  [ "${1:-}" != "--" ] || shift
  command -v docker >/dev/null 2>&1 || die 1 "docker not found"
  stamp="$(date +%Y%m%d-%H%M%S)"
  while read -r ref id; do
    [ -n "$ref" ] || continue
    name="${ref%:*}"
    [ "$name" != "$ref" ] || name="$ref"
    docker tag "$id" "$name:rollback-latest"
    docker tag "$id" "$name:rollback-$stamp"
    echo "rollback: $name:rollback-latest ($id)"
    prune_tags "$name" rollback
    covered+=" $name "
  done < <(stack_images "$folder" "$@")
  # An image with no container (the stack is down): the checkpoint is its newest published tag, when there is one.
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    name="${ref%:*}"
    [ "$name" != "$ref" ] || name="$ref"
    case "$covered" in *" $name "*) continue ;; esac
    last="$(docker image ls --format '{{.Tag}}' "$name" | { grep -E '^published-[0-9]{8}-[0-9]{6}' || true; } | sort -r | head -n 1)"
    [ -n "$last" ] || { echo "first publication of $name: no checkpoint yet"; continue; }
    docker tag "$name:$last" "$name:rollback-latest"
    docker tag "$name:$last" "$name:rollback-$stamp"
    echo "rollback: $name:rollback-latest ($last)"
    prune_tags "$name" rollback
  done < <(cd "$folder" && docker compose "$@" config --images)
  (cd "$folder" && docker compose "$@" up -d --build)
  sha="$(git -C "$folder" rev-parse --short HEAD 2>/dev/null || echo nogit)"
  while read -r ref id; do
    [ -n "$ref" ] || continue
    name="${ref%:*}"
    [ "$name" != "$ref" ] || name="$ref"
    docker tag "$id" "$name:published-$stamp-$sha"
    prune_tags "$name" published
  done < <(stack_images "$folder" "$@")
  echo "published: ${folder#"$root"/} at $sha"
}

# rollback: each image of the stack back to its rollback-latest tag, then up -d --no-build.
cmd_rollback() {
  [ $# -ge 1 ] || die 2 "usage: rollback <work>/<clone> | <repo> [-- <docker compose options>...]"
  local folder ref name moved=0
  folder="$(stack_folder "$1")"
  shift
  [ "${1:-}" != "--" ] || shift
  command -v docker >/dev/null 2>&1 || die 1 "docker not found"
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    name="${ref%:*}"
    [ "$name" != "$ref" ] || name="$ref"
    if docker image inspect "$name:rollback-latest" >/dev/null 2>&1; then
      docker tag "$name:rollback-latest" "$ref"
      echo "rolled back: $ref <- $name:rollback-latest"
      moved=1
    fi
  done < <(cd "$folder" && docker compose "$@" config --images)
  [ "$moved" -eq 1 ] || die 1 "no rollback-latest tag for the images of this stack"
  (cd "$folder" && docker compose "$@" up -d --no-build)
}

# _stop-check: Claude Code Stop hook. Blocks the end of a reply once while a clone has commits not on its remote.
cmd_stop_check() {
  local active clone stale=""
  # A second stop in a row means the session already tried: let it end, so the hook never loops.
  active="$(python3 -I -c 'import json, sys
try:
    print("yes" if json.load(sys.stdin).get("stop_hook_active") else "no")
except ValueError:
    print("no")')"
  [ "$active" = no ] || exit 0
  for clone in "$work_root"/*/*/; do
    clone="${clone%/}"
    [ -d "$clone/.git" ] || continue
    git -C "$clone" config --get aiwp.branch >/dev/null 2>&1 || continue
    [ -z "$(off_remote "$clone")" ] || stale+="${clone#"$work_root"/} "
  done
  [ -n "$stale" ] || exit 0
  python3 -I -c 'import json, sys; print(json.dumps({"decision": "block", "reason": sys.argv[1]}))' \
    "Commits not on the remote in tmp/work: ${stale% }. Run bash scripts/aiwp-cmds.sh push <work>/<clone> for each; if the push cannot run, tell the human why and stop."
}

[ $# -ge 1 ] || { usage >&2; exit 2; }
command="$1"
shift
case "$command" in
  --help | -h | help) usage ;;
  open) cmd_open "$@" ;;
  run) cmd_run "$@" ;;
  status) cmd_status "$@" ;;
  push) push_branch "$(clone_path "${1:-}")" ;;
  close) cmd_close "$@" ;;
  up) cmd_up "$@" ;;
  rollback) cmd_rollback "$@" ;;
  gate | release | apply | developer | checkpoint | bring) exec bash "$root/scripts/aiwp-gate.sh" "$command" "$@" ;;
  _autopush)
    # Inside a rebase HEAD is detached and each picked commit fires post-commit: post-rewrite pushes at the end.
    git -C "$1" symbolic-ref -q HEAD >/dev/null || exit 0
    push_branch "$1" || true
    ;;
  _prepush) cmd_prepush "$1" "${2:-origin}" ;;
  _state-note) state_note "${1:-}" ;;
  _scan-range)
    # The gate's own check: every commit of <sha> that <base ref> does not have, whatever any remote holds.
    [ $# -eq 3 ] || die 2 "usage: _scan-range <clone> <sha> <base ref>"
    check_commits "$1" "$2 --not $3"
    ;;
  _stop-check) cmd_stop_check ;;
  *) echo "error: unknown command: $command" >&2; usage >&2; exit 2 ;;
esac
