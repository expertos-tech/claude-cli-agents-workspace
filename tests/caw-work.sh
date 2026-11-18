#!/usr/bin/env bash
# Work clones of the maintenance of this repository: each change is made in a local clone under tmp/work/, on its own
# branch from origin/developer, and pushed at every commit by the clone's git hooks once the company-terms scan of
# what leaves passes. Writes only under tmp/work/. Modeled on workspace/scripts/aiwp-cmds.sh.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Prints the command reference.
usage() {
  cat <<'USAGE'
Usage: bash tests/caw-work.sh <command> [args] [--help]

The maintenance works in tmp/work/<work>/claude-cli-agents-workspace/: a local clone of this repository on the branch
of the change, started from origin/developer. <work> is <yyyy-mm-dd>-<kebab-slug>: the day the work opened and the slug
of its branch. The script writes only under tmp/work/.

Commands:
  open <type>/<slug>
        <type>: feat fix docs refactor test chore perf build ci style; <slug>: kebab-case. Refuses developer, main
        (as the name or the slug) and the name of a tag, here or on the remote. Clones this repository
        (git clone --local) into tmp/work/<today>-<slug>/claude-cli-agents-workspace, points its origin at this
        repository's origin, fetches it, creates the branch from origin/developer (the clone keeps no other local
        branch), records it (git config caw.branch), writes the clone's git hooks (below) and pushes the branch with
        its upstream, through those hooks. Prints "path: tmp/work/<work>/claude-cli-agents-workspace". A clone of the
        same branch, in any work folder, is reused. Refused: a clone of another branch in the folder, and the branch
        already on the remote with no clone here.
  run <work>[/<clone>] -- <command>...
        Runs the command (no shell) with the clone as the current folder. Refuses, running nothing, an argument (or
        the value after = of --opt=value, -o=value or NAME=value) that names a path outside the clone: an absolute
        path not under it (/dev/null is fine), one starting with ~, or a relative one that leaves it through .. or a
        symbolic link. Refuses --no-verify (or an abbreviation) and any argument holding core.hooksPath: they would
        skip the hooks. When AIWP_TERMS_FILE is not set and this repository finds a terms list, exports it as
        AIWP_TERMS_FILE, so tests/check.sh in the clone scans with the same list.
  status [<work>]
        Fetches origin (--prune), then one line per clone: branch, commits ahead of origin/developer, commits not on
        the remote, files not committed, and whether the branch is in origin/developer.
  close <work> [--discard]
        Fetches origin and refuses, listing what would be lost, when the work folder holds something that is not a
        clone made by open, or a clone with files not committed, a stash, commits not on the remote, or its branch
        not in origin/developer. Otherwise deletes the remote work branch (git push origin --delete, through the
        pre-push hook) and tmp/work/<work>/. --discard deletes the folder anyway and leaves the remote branch.

Git hooks of a clone (written by open into the clone's .git/hooks, with the clone's core.hooksPath set to it; never
part of any repository). They call this script by the absolute path it had when it ran open.
  post-commit, post-merge    push the branch: git push origin HEAD:refs/heads/<branch>, never forced. Nothing on a
                             detached HEAD, during a rebase, or with another branch checked out.
  post-rewrite               the same at the end of a rebase; an amend is pushed by post-commit.
                             A failed push says what to do and never fails the commit: the commit stays in the clone.
  pre-push                   reads every ref line first, then refuses the whole push of developer, main, a tag or any
                             ref outside refs/heads/, and a push that is not a fast-forward (a force push: an amend or
                             a rebase of pushed commits). A deletion of another branch passes. Then it scans what
                             leaves, the commits the remote does not have (git ls-remote): every version of a file
                             they add or change, and their messages, against the terms list (tests/lib/terms.sh, the
                             lookup of tests/check.sh --help). A match refuses the push and prints
                             <commit>:<path>:<line>:<text>; never paste those lines into an issue, a commit or a pull
                             request. AIWP_TERMS_FILE naming no file refuses; no terms list prints
                             "SKIP terms scan: no terms list" and the push goes.

Internal: _autopush <clone> [<post-rewrite kind>], _prepush <clone> <remote> (the ref lines on stdin).

Exit codes: 0 ok; 1 refused or failed; 2 usage error.

Examples:
  bash tests/caw-work.sh open feat/autonomous-work
  bash tests/caw-work.sh run 2026-11-18-autonomous-work -- git status --short
  bash tests/caw-work.sh run 2026-11-18-autonomous-work -- bash tests/check.sh --base origin/developer --i18n-pending
  bash tests/caw-work.sh status
  bash tests/caw-work.sh close 2026-11-18-autonomous-work
USAGE
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
script="$root/tests/$(basename "${BASH_SOURCE[0]}")"
work_root="$root/tmp/work"
clone_dir=claude-cli-agents-workspace
work_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*$'
branch_re='^(feat|fix|docs|refactor|test|chore|perf|build|ci|style)/[a-z0-9]+(-[a-z0-9]+)*$'
zero_re='^0+$'

# Prints an error and exits with the given code.
die() {
  local code="$1"
  shift
  echo "error: $*" >&2
  exit "$code"
}

[ -r "$root/tests/lib/terms.sh" ] || die 1 "tests/lib/terms.sh not found"
# shellcheck source=lib/terms.sh
. "$root/tests/lib/terms.sh"

# Runs a command under timeout(1) when there is one (macOS has none by default), else as it is.
with_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"; else "$@"; fi
}

# Fetches origin into a clone, pruning the tracking refs of branches the remote no longer has, so that "on the remote"
# means what the remote has now. Returns non-zero when origin cannot be fetched.
fetch_origin() {
  with_timeout 120 git -C "$1" fetch -q --prune origin 2>/dev/null
}

# Prints the commits of HEAD and of the local branches that no tracking ref of origin has.
off_remote() {
  git -C "$1" rev-list HEAD --branches --not --remotes=origin 2>/dev/null || true
}

# Prints the branch a clone was opened for, or fails when the folder is not a clone made by open.
clone_branch() {
  [ -e "$1/.git" ] || return 1
  git -C "$1" config --get caw.branch 2>/dev/null
}

# Resolves <work>[/<clone>] to the physical path of a clone made by open, or exits (2 for a malformed argument, 1 for a
# clone that is not there).
clone_path() {
  local given="$1" work name path
  work="${given%%/*}"
  name="$clone_dir"
  [ "$work" = "$given" ] || name="${given#*/}"
  [[ "$work" =~ $work_re ]] || die 2 "<work> must be <yyyy-mm-dd>-<kebab-slug>: $given"
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die 2 "<clone> must be a folder name of tmp/work/<work>/: $given"
  path="$work_root/$work/$name"
  [ "$(cd "$path" 2>/dev/null && pwd -P)" = "$path" ] || die 1 "not found: tmp/work/$work/$name"
  clone_branch "$path" >/dev/null || die 1 "not a clone made by open: tmp/work/$work/$name"
  echo "$path"
}

# Writes the git hooks of a clone into its own .git/hooks and points the clone's core.hooksPath at them, so that a
# hooks path set elsewhere is never used and never written. The $(...) and $1 in the hook text are meant for the hook,
# not for this script: SC2016 does not apply.
# shellcheck disable=SC2016
write_hooks() {
  local clone="$1" hooks
  hooks="$(git -C "$clone" rev-parse --absolute-git-dir)/hooks"
  mkdir -p "$hooks"
  git -C "$clone" config core.hooksPath "$hooks"
  printf '#!/usr/bin/env bash\n# Written by tests/caw-work.sh open: pushes the branch after each commit.\nexec bash %q _autopush "$(git rev-parse --show-toplevel)"\n' "$script" >"$hooks/post-commit"
  printf '#!/usr/bin/env bash\n# Written by tests/caw-work.sh open: pushes the branch after a merge or a pull.\nexec bash %q _autopush "$(git rev-parse --show-toplevel)"\n' "$script" >"$hooks/post-merge"
  printf '#!/usr/bin/env bash\n# Written by tests/caw-work.sh open: pushes the branch at the end of a rebase.\nexec bash %q _autopush "$(git rev-parse --show-toplevel)" "$1"\n' "$script" >"$hooks/post-rewrite"
  printf '#!/usr/bin/env bash\n# Written by tests/caw-work.sh open: refuses developer, main, tags and force; scans what leaves for company terms.\nexec bash %q _prepush "$(git rev-parse --show-toplevel)" "$1"\n' "$script" >"$hooks/pre-push"
  chmod +x "$hooks/post-commit" "$hooks/post-merge" "$hooks/post-rewrite" "$hooks/pre-push"
}

# open: the clone, its branch from origin/developer, its hooks and the first push.
cmd_open() {
  [ $# -eq 1 ] || die 2 "usage: open <type>/<slug>"
  local branch="$1" slug work clone url c found remote_refs
  case "$branch" in --help | -h) usage; return 0 ;; developer | main) die 2 "refused: $branch is never a work branch" ;; esac
  [[ "$branch" =~ $branch_re ]] || die 2 "<type>/<slug> must be one of feat fix docs refactor test chore perf build ci style, a / and a kebab-case slug: $branch"
  slug="${branch#*/}"
  case "$slug" in developer | main) die 2 "refused: $branch would read as the base $slug" ;; esac
  ! git -C "$root" show-ref -q --verify "refs/tags/$branch" || die 1 "refused: $branch is the name of a tag"
  for c in "$work_root"/*/"$clone_dir"; do
    found="$(clone_branch "$c")" || continue
    if [ "$found" = "$branch" ]; then
      echo "path: ${c#"$root"/} (already open)"
      return 0
    fi
  done
  work="$(date +%Y-%m-%d)-$slug"
  clone="$work_root/$work/$clone_dir"
  [ ! -e "$clone" ] || die 1 "tmp/work/$work/$clone_dir is open already for $(clone_branch "$clone" || echo 'something else'), not $branch: choose another slug"
  url="$(git -C "$root" remote get-url origin 2>/dev/null)" || die 1 "this repository has no origin remote"
  mkdir -p "$work_root/$work"
  # Leaves nothing behind when open stops before the first push.
  abandon() {
    rm -rf "${clone:?}"
    rmdir "$work_root/$work" 2>/dev/null || true
    die 1 "$*; nothing was created"
  }
  git clone -q --local "$root" "$clone" || abandon "could not clone this repository"
  git -C "$clone" remote set-url origin "$url"
  # The tracking refs of a local clone are this repository's own branches, not the remote's: drop them, so that "on
  # the remote" always means what the remote has.
  git -C "$clone" for-each-ref --format='%(refname)' refs/remotes/origin | while IFS= read -r c; do
    git -C "$clone" update-ref -d "$c"
  done
  fetch_origin "$clone" || abandon "could not fetch origin ($url)"
  git -C "$clone" rev-parse -q --verify refs/remotes/origin/developer >/dev/null || abandon "origin has no developer"
  remote_refs="$(with_timeout 60 git -C "$clone" ls-remote origin "refs/tags/$branch" "refs/heads/$branch")" ||
    abandon "could not read origin"
  case "$remote_refs" in
    *refs/tags/*) abandon "refused: $branch is the name of a tag on origin" ;;
    *refs/heads/*) abandon "$branch is on origin already with no clone here: choose another slug" ;;
  esac
  git -C "$clone" switch -q --no-track -c "$branch" refs/remotes/origin/developer
  git -C "$clone" for-each-ref --format='%(refname:short)' refs/heads | while IFS= read -r c; do
    [ "$c" = "$branch" ] || git -C "$clone" branch -q -D "$c"
  done
  git -C "$clone" config caw.branch "$branch"
  write_hooks "$clone"
  if with_timeout 120 git -C "$clone" push -q -u origin "HEAD:refs/heads/$branch"; then
    echo "pushed: $branch"
  else
    echo "attention: the first push of $branch failed (above); the next commit pushes it again"
  fi
  echo "path: tmp/work/$work/$clone_dir"
}

# Prints one line per argument of a command that run refuses, with the reason; prints nothing when every one is fine.
refused_args() {
  python3 -I - "$@" <<'PY'
import os
import re
import sys

ASSIGN = re.compile(r"^(--?[A-Za-z0-9][A-Za-z0-9_.-]*|[A-Za-z_][A-Za-z0-9_]*)=(.*)$", re.S)


def outside(clone, value):
    """Return why a value names a path outside the clone, or an empty string when it does not."""
    if value in ("", "/dev/null"):
        return ""
    if value.startswith("~"):
        return "a path under ~ is outside the clone"
    path = os.path.realpath(value if os.path.isabs(value) else os.path.join(clone, value))
    if path == clone or path.startswith(clone + os.sep):
        return ""
    return "a path outside the clone"


def main():
    """Print each refused argument of sys.argv[2:] for the clone sys.argv[1], with the reason."""
    clone = os.path.realpath(sys.argv[1])
    for arg in sys.argv[2:]:
        if "core.hookspath" in arg.lower():
            print(f"  {arg}: core.hooksPath would skip the clone's hooks")
            continue
        if "--no-verify" in arg or (arg.startswith("--no-v") and "--no-verify".startswith(arg)):
            print(f"  {arg}: --no-verify would skip the clone's hooks")
            continue
        values = [arg]
        match = ASSIGN.match(arg)
        if match:
            values.append(match.group(2))
        for value in values:
            why = outside(clone, value)
            if why:
                print(f"  {arg}: {why}")
                break


main()
PY
}

# run: the command in the clone, with no shell, after the argument checks.
cmd_run() {
  if [ $# -lt 3 ] || [ "$2" != "--" ]; then die 2 "usage: run <work>[/<clone>] -- <command>..."; fi
  local clone bad list
  clone="$(clone_path "$1")"
  shift 2
  bad="$(refused_args "$clone" "$@")" || die 1 "the argument check did not run"
  if [ -n "$bad" ]; then
    printf 'refused: nothing was run:\n%s\n' "$bad" >&2
    exit 1
  fi
  if [ -z "${AIWP_TERMS_FILE:-}" ]; then
    list="$(terms_list "$root")" || list=""
    [ -z "$list" ] || export AIWP_TERMS_FILE="$list"
  fi
  cd "$clone"
  exec "$@"
}

# Prints the status line of one clone.
clone_status() {
  local clone="$1" branch note="" ahead off dirty indev
  branch="$(clone_branch "$clone")" || { echo "${clone#"$root"/}  not a clone made by open"; return 0; }
  fetch_origin "$clone" || note="  (origin not fetched: as of the last fetch)"
  ahead="$(git -C "$clone" rev-list --count "refs/remotes/origin/developer..refs/heads/$branch" 2>/dev/null || echo '?')"
  off="$(off_remote "$clone" | grep -c . || true)"
  dirty="$(git -C "$clone" status --porcelain | grep -c . || true)"
  indev=no
  git -C "$clone" merge-base --is-ancestor "refs/heads/$branch" refs/remotes/origin/developer 2>/dev/null && indev=yes
  printf '%s  branch=%s ahead=%s not-pushed=%s uncommitted=%s in-developer=%s%s\n' "${clone#"$root"/}" "$branch" \
    "$ahead" "$off" "$dirty" "$indev" "$note"
  # Stage 3 (the Docker copy): the Docker groups of the clone (agent_<MMDD>-<slug>) are listed here, one line each.
}

# status: every clone, or the clones of one work.
cmd_status() {
  local clone found=0 clones=()
  case "${1:-}" in --help | -h) usage; return 0 ;; esac
  if [ $# -ge 1 ]; then
    [[ "$1" =~ $work_re ]] || die 2 "usage: status [<work>]"
    clones=("$work_root/$1"/*/)
  else
    clones=("$work_root"/*/*/)
  fi
  for clone in "${clones[@]}"; do
    [ -e "${clone}.git" ] || continue
    found=1
    clone_status "${clone%/}"
  done
  [ "$found" -eq 1 ] || echo "no clone under tmp/work/${1:-}"
}

# close: deletes a work folder when nothing in it would be lost, and the remote branch of each clone once it is in
# developer; --discard deletes the folder anyway and leaves the remote branches.
cmd_close() {
  local work="${1:-}" discard=0 entry name branch problems="" gone=()
  case "$work" in --help | -h) usage; return 0 ;; esac
  case "${2:-}" in "") ;; --discard) discard=1 ;; *) die 2 "usage: close <work> [--discard]" ;; esac
  [ $# -le 2 ] || die 2 "usage: close <work> [--discard]"
  [[ "$work" =~ $work_re ]] || die 2 "usage: close <work> [--discard]"
  [ -d "$work_root/$work" ] || die 1 "not found: tmp/work/$work"
  if [ "$discard" -eq 0 ]; then
    for entry in "$work_root/$work"/* "$work_root/$work"/.[!.]*; do
      [ -e "$entry" ] || continue
      name="${entry##*/}"
      branch="$(clone_branch "$entry")" || { problems+="  $name: not a clone made by open"$'\n'; continue; }
      if ! fetch_origin "$entry"; then
        problems+="  $name: origin could not be fetched: what the remote has is unknown"$'\n'
        continue
      fi
      [ -z "$(git -C "$entry" status --porcelain)" ] || problems+="  $name: files changed and not committed"$'\n'
      [ -z "$(git -C "$entry" stash list)" ] || problems+="  $name: a stash"$'\n'
      [ -z "$(off_remote "$entry")" ] || problems+="  $name: commits not on the remote"$'\n'
      if ! git -C "$entry" merge-base --is-ancestor "refs/heads/$branch" refs/remotes/origin/developer 2>/dev/null; then
        problems+="  $name: $branch is not in origin/developer"$'\n'
      elif git -C "$entry" rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null; then
        gone+=("$entry")
      fi
    done
    if [ -n "$problems" ]; then
      printf 'refused: closing tmp/work/%s would lose:\n%s' "$work" "$problems" >&2
      echo "commit, push or merge it first, or close with --discard to delete it anyway (the remote branch stays)" >&2
      exit 1
    fi
    for entry in ${gone[@]+"${gone[@]}"}; do
      branch="$(clone_branch "$entry")"
      if with_timeout 120 git -C "$entry" push -q origin --delete "$branch"; then
        echo "deleted on origin: $branch (it is in developer)"
      else
        echo "attention: could not delete $branch on origin; it is in developer, delete it by hand"
      fi
    done
  fi
  # Stage 3 (the Docker copy): the Docker groups of the work (agent_<MMDD>-<slug>) are destroyed here, before the folder.
  rm -rf "${work_root:?}/$work"
  if [ "$discard" -eq 1 ]; then echo "discarded: tmp/work/$work (the remote branch stays)"; else echo "closed: tmp/work/$work"; fi
}

# Prints why a push that is not a fast-forward of <remote ref> at <remote sha> is refused, and how to keep the change.
force_refused() {
  echo "caw-work: refused: $1 on the remote (${2:0:12}) is not in what this push sends: that is a force push, which a work clone never does (an amend or a rebase of pushed commits)." >&2
  echo "caw-work: to keep the change, commit it on top of what is pushed: git reset --soft ${2:0:12}, then git commit" >&2
}

# _autopush: the post-commit, post-merge and post-rewrite hooks. Pushes the recorded branch; never fails the commit.
cmd_autopush() {
  local clone="$1" kind="${2:-}" branch current gitdir pushed
  # An amend fires post-commit and then post-rewrite: post-commit already pushed it.
  [ "$kind" != amend ] || return 0
  branch="$(clone_branch "$clone")" || { echo "caw-work: not a clone made by open: $clone" >&2; return 0; }
  # Inside a rebase HEAD is detached and each picked commit fires post-commit: post-rewrite pushes at the end.
  current="$(git -C "$clone" symbolic-ref -q --short HEAD)" || return 0
  gitdir="$(git -C "$clone" rev-parse --absolute-git-dir)"
  if [ "$kind" != rebase ] && { [ -d "$gitdir/rebase-merge" ] || [ -d "$gitdir/rebase-apply" ]; }; then return 0; fi
  if [ "$current" != "$branch" ]; then
    echo "caw-work: HEAD is on $current, not $branch: nothing pushed" >&2
    return 0
  fi
  # git would reject a rewrite of pushed commits as non-fast-forward before the pre-push hook: say why here.
  pushed="$(git -C "$clone" rev-parse -q --verify "refs/remotes/origin/$branch" || true)"
  if [ -n "$pushed" ] && ! git -C "$clone" merge-base --is-ancestor "$pushed" HEAD; then
    force_refused "refs/heads/$branch" "$pushed"
    echo "caw-work: NOT pushed: the commit stays only in this clone" >&2
    return 0
  fi
  if with_timeout 120 git -C "$clone" push -q origin "HEAD:refs/heads/$branch"; then
    echo "caw-work: pushed $branch $(git -C "$clone" rev-parse --short HEAD)"
  else
    echo "caw-work: NOT pushed: the commit stays only in this clone. Fix what the lines above say (an amend or a rebase of commits not on the remote is fine), then commit again, or push: bash tests/caw-work.sh run <work> -- git push origin HEAD:refs/heads/$branch" >&2
  fi
  return 0
}

# Scans what the revisions "<sha> --not <sha>..." bring for company terms: every version of a file their commits add
# or change (merges against each parent), and their messages. Prints each match; returns 0 when none, 1 on a match, 2
# when the scan failed.
scan_commits() {
  local clone="$1" patterns="$2" line commit="" meta path mode sha seen=" " rc found=0
  shift 2
  while IFS= read -r line; do
    case "$line" in
      "commit "*) commit="${line#commit }"; commit="${commit%% *}"; continue ;;
      :*) ;;
      *) continue ;;
    esac
    meta="${line%%$'\t'*}"
    path="${line#*$'\t'}"
    read -r _ mode _ sha _ <<<"$meta"
    [[ "$sha" =~ $zero_re ]] && continue
    [ "$mode" != 160000 ] || continue
    case "$seen" in *" $sha "*) continue ;; esac
    seen+="$sha "
    rc=0
    git -C "$clone" cat-file blob "$sha" | terms_scan "$patterns" "${commit:0:12}:$path" || rc=$?
    case "$rc" in 0) ;; 1) found=1 ;; *) return 2 ;; esac
  done < <(git -C "$clone" log --format='commit %H' --raw --no-abbrev --no-renames -m "$@")
  while IFS= read -r commit; do
    rc=0
    git -C "$clone" log -1 --format=%B "$commit" | terms_scan "$patterns" "${commit:0:12}:message" || rc=$?
    case "$rc" in 0) ;; 1) found=1 ;; *) return 2 ;; esac
  done < <(git -C "$clone" rev-list "$@")
  return "$found"
}

# _prepush: the pre-push hook. Reads every "<local ref> <local sha> <remote ref> <remote sha>" line first, then refuses
# the whole push for a protected or non-branch target or a force push, and scans what leaves for company terms.
cmd_prepush() {
  local clone="$1" remote="${2:-origin}" line lines=() i local_sha remote_ref remote_sha sends=0 list patterns \
    remote_list known=() sha rc=0
  while IFS= read -r line; do [ -z "$line" ] || lines+=("$line"); done
  for i in ${lines[@]+"${!lines[@]}"}; do
    read -r _ local_sha remote_ref remote_sha <<<"${lines[$i]}"
    case "$remote_ref" in
      refs/heads/developer | refs/heads/main)
        echo "caw-work: refused: a work clone never pushes ${remote_ref#refs/heads/}; /caw-merge moves it" >&2
        return 1
        ;;
      refs/tags/*)
        echo "caw-work: refused: a work clone never pushes a tag ($remote_ref); tags come only from /caw-merge --main" >&2
        return 1
        ;;
      refs/heads/*) ;;
      *)
        echo "caw-work: refused: a work clone pushes branches only, not $remote_ref" >&2
        return 1
        ;;
    esac
    [[ "$local_sha" =~ $zero_re ]] && continue
    sends=1
    [[ "$remote_sha" =~ $zero_re ]] && continue
    if ! git -C "$clone" cat-file -e "$remote_sha^{commit}" 2>/dev/null ||
      ! git -C "$clone" merge-base --is-ancestor "$remote_sha" "$local_sha"; then
      force_refused "$remote_ref" "$remote_sha"
      return 1
    fi
  done
  [ "$sends" -eq 1 ] || return 0
  list="$(terms_list "$root")" || {
    echo "caw-work: refused: AIWP_TERMS_FILE names no file: $AIWP_TERMS_FILE" >&2
    return 1
  }
  if [ -z "$list" ]; then
    echo "SKIP terms scan: no terms list" >&2
    return 0
  fi
  patterns="$(terms_patterns "$list")"
  if [ -z "$patterns" ]; then
    echo "SKIP terms scan: the terms list holds no term" >&2
    return 0
  fi
  remote_list="$(with_timeout 60 git -C "$clone" ls-remote "$remote" 'refs/heads/*' 2>/dev/null)" || {
    echo "caw-work: refused: the remote cannot be read to know what is already there" >&2
    return 1
  }
  while read -r sha _; do
    [ -n "$sha" ] && git -C "$clone" cat-file -e "$sha^{commit}" 2>/dev/null && known+=("$sha")
  done <<<"$remote_list"
  for i in ${lines[@]+"${!lines[@]}"}; do
    read -r _ local_sha _ <<<"${lines[$i]}"
    [[ "$local_sha" =~ $zero_re ]] && continue
    rc=0
    scan_commits "$clone" "$patterns" "$local_sha" --not ${known[@]+"${known[@]}"} >&2 || rc=$?
    case "$rc" in
      0) ;;
      1)
        echo "caw-work: refused: the lines above hold a company term (<commit>:<path or message>:<line>:<text>); never paste them into an issue, a commit or a pull request. Rewrite the commits not on the remote without it (git commit --amend, or git rebase -i on them only), then push." >&2
        return 1
        ;;
      *)
        echo "caw-work: refused: the terms scan failed" >&2
        return 1
        ;;
    esac
  done
  return 0
}

[ $# -ge 1 ] || { usage >&2; exit 2; }
command="$1"
shift
case "$command" in
  --help | -h | help) usage ;;
  open) cmd_open "$@" ;;
  run) cmd_run "$@" ;;
  status) cmd_status "$@" ;;
  close) cmd_close "$@" ;;
  _autopush)
    [ $# -ge 1 ] || die 2 "usage: _autopush <clone> [<post-rewrite kind>]"
    cmd_autopush "$@"
    ;;
  _prepush)
    [ $# -ge 1 ] || die 2 "usage: _prepush <clone> <remote>"
    cmd_prepush "$1" "${2:-origin}"
    ;;
  *) echo "error: unknown command: $command" >&2; usage >&2; exit 2 ;;
esac
