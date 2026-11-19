#!/usr/bin/env bash
# Work area of the workspace: every change to a project or POC is made in a local clone under tmp/work/, pushed to the
# remote at every commit, and reaches the base only through the gate.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Prints the command reference.
usage() {
  cat <<'USAGE'
Usage: scripts/aiwp-cmds.sh <command> [args] [--help]

Work happens in tmp/work/<work>/<clone>/: a local clone (git clone --local) of a repo of projects/ (or of custom/, for
POCs), on the branch of the request. Everything is allowed inside a clone; projects/ and the core change only through
the gate. <work> is <yyyy-mm-dd>-<kebab-slug>, one folder per request.

Commands:
  open <work> <repo>... [--branch <type>/<slug>] [--from-main]
        <repo> is a repo folder relative to projects/, at any depth (e.g. billing-api, acme/billing-web), a repo
        inside another one included (billing/billing-api, where billing/ is a repo itself), or "custom" for a POC.
        For each: clones it to tmp/work/<work>/<clone>/, points the clone's origin at the real remote of the repo,
        creates the branch (default feat/<slug of work>) from the base (developer, else main), installs the clone's
        git hooks (below), copies the repo's .env and local.settings.json files (never those of a repo inside it),
        and pushes the branch. Prints "path: <clone>". An existing clone of the same repo is reused (a clone named
        by the last folder, as before 0.2.0, too). For a repo of projects/ it also prints its state
        (scripts/aiwp-project-state.sh): with no marker or out of date, an attention: line asks for authorization to
        run /normalize-projects; the work goes on either way.
        <clone>: the repo's path relative to projects/ with each / written as -- (billing-api -> billing-api,
        billing/billing-api -> billing--billing-api, acme/billing/billing-api -> acme--billing--billing-api);
        "custom" for custom/. Two repos never share it while folder names are kebab-case (no --); a clone folder
        that belongs to another repo is refused, never reused.
        --from-main: a hotfix clone, to fix production. The branch, fix/<kebab-slug> (default fix/<slug of work
        without a leading "hotfix-">: 2026-11-17-hotfix-login-null -> fix/login-null), starts from main of the remote,
        fetched (no remote: the local main), never from developer; the clone records the base main. It reaches main
        only by gate and hotfix (scripts/aiwp-gate.sh --help). A repo with no main (on its remote, when it has one)
        or with no developer (the normal flow already works from main: open without --from-main) is refused, and
        nothing is created for any repo of the call.
  run <work>/<clone> -- <command>...
        Runs the command with the clone as the current folder. Refuses a path outside tmp/work/.
  status [<work>]
        Per clone: branch, base, commits ahead of the base, commits not on the remote, files changed not committed;
        then one "copy:" line per Docker group of the clone (its agent_ group, by the compose folder label or its
        override file): state, host ports and networks=<service>:edge|internal. Docker not reachable: one line
        "Docker: not reachable", same exit code.
  push <work>/<clone>
        Pushes the branch now (what a failed automatic push left behind), with the pre-push checks.
  close <work> [--discard]
        Deletes tmp/work/<work>/ when every clone has nothing uncommitted, nothing off the remote, and its branch in
        the base of its source repo. Otherwise lists what would be lost and exits 1; --discard deletes anyway (the
        remote branches stay). Before the folder goes, the Docker copy groups of every clone of the work are
        destroyed (below); a refused close destroys nothing.
  up <work>/<clone> [-- <docker compose options>...]
        Publishes the task's copy to the local Docker, never over the final stack: compose project agent_<MMDD>-<slug>
        (the date and slug of <work>: 2026-11-18-add-export -> agent_1118-add-export); when another clone of the same
        work already owns that group, agent_<MMDD>-<slug>--<clone> (a work slug never holds --, so it never collides
        with the group of another work). The compose files of the clone never change: an
        override file outside the clone, tmp/work/<work>/agent-<clone>.compose.yaml (never committed), gives every
        built service the group's own image (<group>-<service>), drops a fixed container_name and a fixed network or
        volume name (compose !reset), and moves every published port to a random free host port in 61000-65535 (on
        Linux free in /proc/net, in docker ps and by a bind test; elsewhere by docker ps and the bind test); the port
        of the last up is kept while it is free. The compose files are checked against an allowlist first. What
        would undo the copy's isolation is refused, named, and nothing starts: Docker Engine older than 28; a
        top-level key other than services, networks, volumes, secrets, configs, name and x-*; a build with network,
        ssh, secrets, additional_contexts or entitlements, or a context or Dockerfile outside the clone; an env_file,
        a bind, or a secret or config file outside the clone (links followed) or of a container runtime socket; a
        volume the files do not declare, or one with driver_opts or a driver other than local; volumes_from a
        container outside the files; a network that is external, not a bridge or with driver_opts; network_mode
        other than service:<x> of the same files; a log driver other than json-file, local or none. What only
        polices the person's own services is a warning, and the copy starts: a service key off the list of
        scripts/agent-copy.py (SERVICE_KEYS: privileged, cap_add, devices, volumes_from, sysctls...); security_opt
        other than no-new-privileges; pid, ipc, uts or cgroup other than service:<x> of the same files (ipc private
        or shareable and cgroup private are no warning); deploy other than resources, replicas, restart_policy,
        update_config, or reserved devices; an extra host on host-gateway. One line per such service,
        "WARNING: service <s> sets <settings>, off the safe list of a copy — <why> — <what to do>": guard-bash
        auto-allows a command in a copy's container only when docker inspect shows it cannot reach the host, so exec
        there may fall back to the permission mode. Every network of
        the copy is internal (internal: true, and driver_opts com.docker.network.bridge.gateway_mode_ipv4 and _ipv6
        set to isolated, so not even its gateway, the host, answers); a service that publishes a port also joins
        <group>_edge (compose key agent-edge, labeled com.docker.compose.project=<group> like the others), the copy's
        only network that is not internal, so its port answers on the host; service names and aliases keep resolving.
        Prints "network: <service> edge", "internal" or "shares <service>" per service. Then docker compose up -d
        --build in the group. Prints "port: <service> <port>/<protocol> -> <host port> http://localhost:<host port>
        <variable>" per port. The
        variables AGENT_GROUP and AGENT_PORT_<SERVICE>_<PORT> (_UDP for udp; service upper-case, other characters
        as _) reach the compose files (interpolation) and every service's environment, and are kept in
        tmp/work/<work>/agent-<clone>.ports.env. No rollback tag for a copy. <repo> is refused: the final stack of
        projects/<repo> changes only by deploy (/docker-deploy).
  down <work>/<clone>
        Stops the copy: docker compose down of its group; containers and networks go, volumes and images stay.
  deploy <repo> [developer|main] [-- <docker compose options>...]
        Updates the final stack of projects/<repo> (only on the person's order, /docker-deploy): the compose project
        its own files give (their name:, else the folder name), never an agent_ group. developer (default): from
        projects/<repo>, which must be on developer with no change. main: from a fresh checkout of main (the remote's
        main when it can be fetched, else the local one) in tmp/deploy/<clone name>-main/, with the repo's .env and
        local.settings.json files and -p forced to the final stack's name; the compose files are those compose would
        read there (-f given, else COMPOSE_FILE of the environment, of --env-file or of the repo's .env, else the
        default names). Every relative bind, secret file and config file, as the compose files write it (in the
        checkout, or above it through .., at any depth), is taken from the same relative path of projects/<repo>
        instead (an override next to the checkout; each mount whole, only its source changed), so the stack keeps the
        data developer uses; one that leads outside the workspace (or its projects/) is refused. When main
        or projects/<repo> tracks a file under such a path, every file there (tracked by main, or by projects/<repo>,
        or not ignored there) must be the same on both sides, else the deploy is refused, nothing deployed. The
        checkout is removed afterwards, and never while a container binds a path in it (then the deploy is refused
        before anything changes). Before the build, tags each image of the stack's
        containers as <name>:rollback-latest and <name>:rollback-<yyyymmdd-hhmmss>, keeping the last 3 (an image with
        no container: its newest published tag); then docker compose up -d --build (never down -v, never a volume
        removed); then tags each image as <name>:published-<yyyymmdd-hhmmss>-<sha>.
  rollback <repo> [-- <docker compose options>...]
        Points each image of the final stack back to its rollback-latest tag and runs docker compose up -d --no-build.
        Volumes are never touched. A clone is refused: a copy has no rollback tags (run up again).
  gate, release, hotfix, hotfix-tag, hotfix-down, apply, developer, checkpoint, bring, bring-branch
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
gate's check of every commit that enters the base), _state-note <repo> (the state lines of open and the gate, a hotfix
waiting to be merged into developer included; never fails), _stop-check (Claude Code Stop hook JSON on stdin; blocks the end
of a reply once while a clone has a commit, on a branch or a detached HEAD, not on the remote), _destroy-copies
<work>[/<clone>] (destroys the copy groups of a work or of one clone; the gate runs it after a merge).

Docker copy groups: a group is destroyed (containers, networks, volumes, then the images it built) only by its label
com.docker.compose.project=<name> and only when the name matches ^agent_[0-9]{4}-[a-z0-9][a-z0-9-]*$; any other name
is refused, even when named. The groups of a clone: the names in its override file and the agent_ projects whose
compose folder label lies in the clone. The work is in scripts/agent-copy.py.

Environment: AIWP_SECRETS_CMD replaces the gitleaks run (tests); it gets the repo and the range as arguments.
AIWP_CUSTOM_DIR (as in run-tools.sh): binds under custom/ of the workspace are read from that folder instead.
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
  [ "$src" != "$root/projects" ] || die 2 "<repo> is a folder relative to projects/: $1"
  [ "$(git -C "$src" rev-parse --show-toplevel 2>/dev/null)" = "$src" ] || die 1 "not the root of a git repo: $1"
  echo "$src"
}

# Prints the folder name of the clone of a source repo in tmp/work/<work>/: "custom" for custom/; for a repo of
# projects/, its path relative to projects/ with each / written as -- (billing/billing-api -> billing--billing-api).
clone_name() {
  local repo="${1%/}" src="$2" rel
  if [ "$repo" = custom ]; then
    echo custom
    return 0
  fi
  case "$src/" in
    "$root/projects/"*) rel="${src#"$root"/projects/}" ;;
    *)
      # A link of projects/ to a folder elsewhere: the path given, without ./ and empty segments.
      rel="/$repo/"
      while [[ "$rel" == *//* || "$rel" == */./* ]]; do
        rel="${rel//\/\//\/}"
        rel="${rel//\/.\//\/}"
      done
      rel="${rel#/}"
      rel="${rel%/}"
      ;;
  esac
  printf '%s\n' "${rel//\//--}"
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

# Copies the local env files of the source repo (git-ignored, never in a clone) to the same paths in the clone; those
# of a repo inside it belong to that repo and stay.
copy_env_files() {
  local src="$1" clone="$2" f rel nested=() n inner
  while IFS= read -r n; do [ -n "$n" ] && nested+=("$n"); done < <(projects_find_repos "$src")
  while IFS= read -r -d '' f; do
    inner=0
    for n in ${nested[@]+"${nested[@]}"}; do
      case "$f" in "$n"/*) inner=1 ;; esac
    done
    [ "$inner" -eq 0 ] || continue
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
  local rel="$1" line kind state marker version pending hotfix
  line="$(timeout 20 bash "$root/scripts/aiwp-project-state.sh" --porcelain -- "$rel" 2>/dev/null | head -n 1)" || true
  [ -n "$line" ] || return 0
  IFS=$'\t' read -r kind _ _ state marker version pending _ _ _ hotfix _ <<<"$line"
  [ "$kind" = project ] || return 0
  [ "$hotfix" != yes ] || echo "attention: projects/$rel has a hotfix on main not merged into developer yet: /merge into developer and the release are refused until it is merged down (bash scripts/aiwp-cmds.sh hotfix-down $rel, or a fix/<slug>-developer clone through /merge when it conflicts)"
  case "$state" in
    none) echo "attention: projects/$rel has no AI-WORKSPACE-PROJECT marker: not a workspace project yet. Ask the person for authorization to run /normalize-projects $rel; the work goes on either way" ;;
    outdated) echo "attention: projects/$rel is on workspace version $marker, the workspace on $version, with migrations ${pending//,/, } pending. Ask the person for authorization to run /normalize-projects $rel; the work goes on either way" ;;
    current) echo "state: projects/$rel is up to date (marker $marker)" ;;
    newer) echo "state: projects/$rel has marker $marker, newer than the workspace ($version)" ;;
    workspace) echo "state: projects/$rel is the workspace's own repository" ;;
  esac
  return 0
}

# Fails, before anything is created, unless a repo can take a hotfix clone: main on its remote (with no remote, the
# local main) and developer, here or on the remote.
require_hotfix_source() {
  local repo="$1" src="$2" heads="" dev=0
  if git -C "$src" remote get-url origin >/dev/null 2>&1; then
    heads="$(timeout 120 git -C "$src" ls-remote origin refs/heads/main refs/heads/developer 2>/dev/null)" ||
      die 1 "could not read the remote of $repo: a hotfix starts from main of the remote; nothing was created"
    printf '%s\n' "$heads" | awk '$2 == "refs/heads/main" { found = 1 } END { exit !found }' ||
      die 1 "$repo has no main on its remote: a hotfix starts from main (production); nothing was created"
  else
    git -C "$src" rev-parse -q --verify refs/heads/main >/dev/null ||
      die 1 "$repo has no main: a hotfix starts from main (production); nothing was created"
  fi
  git -C "$src" rev-parse -q --verify refs/heads/developer >/dev/null && dev=1
  printf '%s\n' "$heads" | awk '$2 == "refs/heads/developer" { found = 1 } END { exit !found }' && dev=1
  [ "$dev" = 1 ] || die 1 "$repo has no developer: its base is main, and the normal flow already works from it (open without --from-main); nothing was created"
}

# open: one clone per repo, branch from the base, hooks, env files, first push.
cmd_open() {
  local work="" branch="" repos=() repo src name clone base url slug start from_main=0 kind
  while [ $# -gt 0 ]; do
    case "$1" in
      --branch) [ $# -ge 2 ] || die 2 "--branch needs a value"; branch="$2"; shift ;;
      --from-main) from_main=1 ;;
      -*) die 2 "unknown option: $1" ;;
      *) if [ -z "$work" ]; then work="$1"; else repos+=("$1"); fi ;;
    esac
    shift
  done
  [[ "$work" =~ $work_re ]] || die 2 "<work> must be <yyyy-mm-dd>-<kebab-slug>: $work"
  [ "${#repos[@]}" -gt 0 ] || die 2 "open needs at least one <repo>"
  # Loaded here, before any clone, and only by open: the Stop hook (_stop-check) never depends on it.
  [ -r "$root/scripts/lib/projects.sh" ] || die 1 "scripts/lib/projects.sh not found"
  # shellcheck source=lib/projects.sh
  . "$root/scripts/lib/projects.sh"
  slug="${work:11}"
  if [ "$from_main" = 1 ]; then
    [ -n "$branch" ] || branch="fix/${slug#hotfix-}"
    [[ "$branch" =~ ^fix/[a-z0-9]+(-[a-z0-9]+)*$ ]] || die 2 "--from-main needs a branch fix/<kebab-slug>: $branch"
  fi
  [ -n "$branch" ] || branch="feat/$slug"
  [[ "$branch" =~ ^[a-z]+/[a-z0-9]+(-[a-z0-9]+)*$ ]] || die 2 "--branch must be <type>/<kebab-slug>: $branch"
  [[ "${branch#*/}" =~ $protected_re ]] && die 2 "--branch cannot be a base: $branch"
  if [ "$from_main" = 1 ]; then
    # Every repo is checked before the first clone: a refusal leaves nothing behind.
    for repo in "${repos[@]}"; do
      src="$(source_repo "$repo")"
      require_hotfix_source "$repo" "$src"
    done
  fi
  for repo in "${repos[@]}"; do
    src="$(source_repo "$repo")"
    name="$(clone_name "$repo" "$src")"
    # A clone opened before the name had the whole path (the last folder only) is reused under its name.
    if [ ! -e "$work_root/$work/$name" ] && [ -e "$work_root/$work/${src##*/}" ] &&
      [ "$(git -C "$work_root/$work/${src##*/}" config --get aiwp.source 2>/dev/null)" = "$src" ]; then
      name="${src##*/}"
    fi
    clone="$work_root/$work/$name"
    case "$src/" in "$root/projects/"*) state_note "${src#"$root"/projects/}" ;; esac
    if [ -e "$clone" ]; then
      [ "$(git -C "$clone" config --get aiwp.source 2>/dev/null)" = "$src" ] || die 1 "tmp/work/$work/$name exists and is not a clone of $repo"
      kind="$(git -C "$clone" config --get aiwp.hotfix 2>/dev/null || echo 0)"
      [ "$kind" = "$from_main" ] || die 1 "tmp/work/$work/$name is open already$([ "$kind" = 1 ] && echo " as a hotfix clone (from main)" || echo " from its base"): use another <work>"
      echo "path: tmp/work/$work/$name (already open)"
      continue
    fi
    if [ "$from_main" = 1 ]; then base=main; else base="$(base_of "$src")"; fi
    mkdir -p "$work_root/$work"
    git clone -q --local --no-checkout "$src" "$clone"
    url="$(git -C "$src" remote get-url origin 2>/dev/null || true)"
    git -C "$clone" config aiwp.source "$src"
    git -C "$clone" config aiwp.branch "$branch"
    git -C "$clone" config aiwp.base "$base"
    [ "$from_main" = 0 ] || git -C "$clone" config aiwp.hotfix 1
    # The local base may be missing (a repo cloned with developer as its default branch has no local main): then only
    # the remote gives the start.
    start="$(git -C "$src" rev-parse -q --verify "refs/heads/$base" 2>/dev/null || true)"
    if [ -n "$url" ]; then
      git -C "$clone" remote set-url origin "$url"
      # The tracking refs of a local clone are the branches of projects/<repo>, not of the remote: drop them, so that
      # "on the remote" always means what the remote really has.
      git -C "$clone" for-each-ref --format='%(refname)' refs/remotes/origin | while IFS= read -r ref; do
        git -C "$clone" update-ref -d "$ref"
      done
      if timeout 120 git -C "$clone" fetch -q origin "+refs/heads/$base:refs/remotes/origin/$base" 2>/dev/null; then
        start="origin/$base"
      elif [ "$from_main" = 1 ]; then
        # A hotfix starts from production only: never from a local main that may be behind the remote.
        rm -rf "${clone:?}"
        rmdir "$work_root/$work" 2>/dev/null || true
        die 1 "could not fetch main from the remote of $repo: a hotfix starts from main of the remote; nothing was created for $repo"
      else
        echo "attention: could not fetch $base from the remote of $repo; the branch starts from the local $base"
      fi
    else
      echo "attention: $repo has no remote; the branch is pushed to projects/$repo itself, not off the machine"
    fi
    if [ -z "$start" ]; then
      rm -rf "${clone:?}"
      rmdir "$work_root/$work" 2>/dev/null || true
      die 1 "$repo has no $base to start from, here or on the remote; nothing was created for $repo"
    fi
    [ "$from_main" = 0 ] || echo "hotfix: $branch starts from main ($(git -C "$clone" rev-parse --short "$start")); it reaches main only by the gate and bash scripts/aiwp-cmds.sh hotfix"
    if git -C "$clone" ls-remote --exit-code origin "refs/heads/$branch" >/dev/null 2>&1; then
      rm -rf "${clone:?}"
      rmdir "$work_root/$work" 2>/dev/null || true
      die 1 "$branch already exists on the remote of $repo: choose another --branch"
    fi
    git -C "$clone" checkout -q -b "$branch" "$start"
    git -C "$clone" branch -q --unset-upstream 2>/dev/null || true
    if [ "$from_main" = 1 ]; then
      # git clone --local made a local copy of the checked-out developer: a hotfix clone holds only its fix branch, so
      # no developer work is at hand there, and close never sees that copy as commits off the remote.
      git -C "$clone" for-each-ref --format='%(refname:short)' refs/heads | while IFS= read -r ref; do
        [ "$ref" = "$branch" ] || git -C "$clone" branch -q -D "$ref"
      done
    fi
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

# Runs scripts/agent-copy.py, the Docker work of the task copies.
agent_copy() {
  python3 -I "$root/scripts/agent-copy.py" "$@"
}

# Prints the override file of a clone's copy: tmp/work/<work>/agent-<clone>.compose.yaml.
copy_override() {
  local clone="$1"
  echo "$(dirname "$clone")/agent-${clone##*/}.compose.yaml"
}

# Prints the group recorded in an override file (its name: line), or nothing.
override_group() {
  [ -f "$1" ] || return 0
  sed -n 's/^name: "\(agent_[0-9a-z_-]*\)"$/\1/p' "$1" | head -n 1
}

# Prints the copy group of a clone: the one its override file records, else agent_<MMDD>-<slug> of its work, else
# (another clone of the work records that name) agent_<MMDD>-<slug>--<clone>: a work slug never holds --, so the
# group of a second clone never takes the name of another work's group.
copy_group() {
  local clone="$1" work name base other suffix
  work="$(basename "$(dirname "$clone")")"
  name="${clone##*/}"
  base="$(override_group "$(copy_override "$clone")")"
  [ -z "$base" ] || { echo "$base"; return 0; }
  base="agent_${work:5:2}${work:8:2}-${work:11}"
  for other in "$(dirname "$clone")"/agent-*.compose.yaml; do
    [ -f "$other" ] && [ "$other" != "$(copy_override "$clone")" ] || continue
    if [ "$(override_group "$other")" = "$base" ]; then
      suffix="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-')"
      echo "$base--${suffix#-}"
      return 0
    fi
  done
  echo "$base"
}

# Prints the "copy:" lines of one clone (its groups, state, ports). Docker not reachable: "Docker: not reachable", once
# per run (docker_down records it).
docker_down=0
copies_status() {
  local clone="$1" args group out rc=0 state ports
  [ "$docker_down" -eq 0 ] || return 0
  args=(--under "$clone")
  group="$(override_group "$(copy_override "$clone")")"
  [ -z "$group" ] || args+=(--group "$group")
  command -v docker >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || rc=3
  [ "$rc" -ne 0 ] || out="$(agent_copy list "${args[@]}" 2>/dev/null)" || rc=$?
  case "$rc" in
    0) ;;
    3) docker_down=1; echo "Docker: not reachable"; return 0 ;;
    *) echo "  copy: the groups could not be listed"; return 0 ;;
  esac
  while IFS=$'\t' read -r group state ports; do
    [ -z "$group" ] || echo "  copy: $group $state ports=$ports"
  done <<<"$out"
}

# status: every clone, or the clones of one work, each with its Docker copy groups.
cmd_status() {
  local pattern clone found=0
  if [ $# -ge 1 ]; then pattern="$work_root/$1/*/"; else pattern="$work_root/*/*/"; fi
  for clone in $pattern; do
    [ -d "$clone/.git" ] || continue
    found=1
    clone_status "${clone%/}"
    copies_status "${clone%/}"
  done
  [ "$found" -eq 1 ] || echo "no clone under tmp/work/${1:-}"
}

# Destroys the copy groups of the clones given (their override files' groups and the agent_ projects whose compose
# folder lies in them). Prints what happened; returns non-zero when a group could not be destroyed or Docker is not
# reachable. Another project is never touched (scripts/agent-copy.py destroy).
destroy_copies() {
  local args=() clone group
  for clone in "$@"; do
    group="$(override_group "$(copy_override "$clone")")"
    [ -z "$group" ] || args+=("$group")
    args+=(--under "$clone")
  done
  [ "${#args[@]}" -gt 0 ] || return 0
  command -v docker >/dev/null 2>&1 || { echo "Docker: not reachable: no copy destroyed"; return 1; }
  agent_copy destroy "${args[@]}" 2>&1
}

# close: delete a work folder when nothing in it would be lost: no change, stash or local commit off the remote in any
# clone, every work branch in the base of its source repo, and nothing in the folder but clones and gate files.
cmd_close() {
  local work="${1:-}" discard=0 entry clone src base branch problems="" clones
  [ "${2:-}" = "--discard" ] && discard=1
  [[ "$work" =~ $work_re ]] || die 2 "usage: close <work> [--discard]"
  [ -d "$work_root/$work" ] || die 1 "not found: tmp/work/$work"
  for entry in "$work_root/$work"/* "$work_root/$work"/.[!.]*; do
    [ -e "$entry" ] || continue
    case "${entry##*/}" in gate-*.md | .gate-* | agent-*.compose.yaml | agent-*.ports.env) continue ;; esac
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
  clones=()
  for entry in "$work_root/$work"/*/; do
    [ -d "$entry.git" ] && clones+=("${entry%/}")
  done
  [ "${#clones[@]}" -eq 0 ] || destroy_copies "${clones[@]}" || echo "attention: a copy group of tmp/work/$work was not destroyed (above); the folder goes anyway"
  rm -rf "${work_root:?}/$work"
  echo "closed: tmp/work/$work"
}

# Succeeds when an argument names a clone of tmp/work/: <work>/<clone>, tmp/work/<work>/<clone> or its absolute path.
is_clone_arg() {
  local given="${1#tmp/work/}"
  case "$1" in /*) given="${1#"$work_root"/}" ;; esac
  [[ "${given%%/*}" =~ $work_re ]] && [[ "$given" == */* ]]
}

# Prints the compose folder of the final stack of a repo of projects/ (rollback, deploy), or exits.
final_folder() {
  is_clone_arg "$1" && die 1 "refused: $1 is a clone: its copy has no rollback tags and is not a final stack (publish it again with up)"
  [ "${1%/}" != custom ] || die 2 "<repo> is a repo of projects/ with a compose stack: $1"
  source_repo "$1"
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

# Tags the images the final stack runs now as <name>:rollback-latest and <name>:rollback-<stamp> (an image with no
# container: its newest published tag), before a build replaces them.
tag_rollback() {
  local folder="$1" stamp="$2" ref id name covered=" " last
  shift 2
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
}

# Tags each image the final stack runs after the build as <name>:published-<stamp>-<sha>.
tag_published() {
  local folder="$1" stamp="$2" sha="$3" ref id name
  shift 3
  while read -r ref id; do
    [ -n "$ref" ] || continue
    name="${ref%:*}"
    [ "$name" != "$ref" ] || name="$ref"
    docker tag "$id" "$name:published-$stamp-$sha"
    prune_tags "$name" published
  done < <(stack_images "$folder" "$@")
}

# up: the task's copy in its own agent_ group, from the clone, through an override file outside it.
cmd_up() {
  [ $# -ge 1 ] || die 2 "usage: up <work>/<clone> [-- <docker compose options>...]"
  is_clone_arg "$1" || die 1 "refused: up publishes a task's copy (<work>/<clone>); the final stack of projects/$1 changes only by the person's /docker-deploy (bash scripts/aiwp-cmds.sh deploy $1 [developer|main])"
  local clone group work base fallback=() suffix
  clone="$(clone_path "$1")"
  shift
  [ "${1:-}" != "--" ] || shift
  command -v docker >/dev/null 2>&1 || die 1 "docker not found"
  command -v python3 >/dev/null 2>&1 || die 1 "python3 not found"
  group="$(copy_group "$clone")"
  work="$(basename "$(dirname "$clone")")"
  base="agent_${work:5:2}${work:8:2}-${work:11}"
  if [ "$group" = "$base" ]; then
    # The work's group may belong to another clone already running it: then this clone's own name.
    suffix="$(printf '%s' "${clone##*/}" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-')"
    fallback=(--fallback "$base--${suffix#-}")
  fi
  agent_copy up "$group" "$clone" "$(copy_override "$clone")" ${fallback[@]+"${fallback[@]}"} --custom-root "$root/custom" -- "$@"
}

# down: the copy's group stops; volumes and images stay.
cmd_down() {
  [ $# -eq 1 ] || die 2 "usage: down <work>/<clone>"
  is_clone_arg "$1" || die 2 "usage: down <work>/<clone> (a task's copy; the final stack is never stopped here)"
  local clone group
  clone="$(clone_path "$1")"
  command -v docker >/dev/null 2>&1 || die 1 "docker not found"
  group="$(override_group "$(copy_override "$clone")")"
  [ -n "$group" ] || group="$(copy_group "$clone")"
  agent_copy down "$group"
}

# Fails when a container binds a path inside a folder about to be deleted (a checkout of main still in use).
require_unbound() {
  local out rc=0
  [ -e "$1" ] || return 0
  out="$(agent_copy bound-under "$1" 2>/dev/null)" || rc=$?
  case "$rc" in
    1) return 0 ;;
    0) die 1 "refused: a container binds ${1#"$root"/}, which is never deleted while in use; nothing deployed: $out" ;;
    *) die 1 "Docker not reachable: ${1#"$root"/} is kept; nothing deployed" ;;
  esac
}

# deploy: the final stack of projects/<repo> from developer (projects/<repo> itself) or main (a fresh checkout), with
# the replaced images tagged for rollback; never down -v, never a volume removed.
cmd_deploy() {
  [ $# -ge 1 ] || die 2 "usage: deploy <repo> [developer|main] [-- <docker compose options>...]"
  local repo="$1" branch=developer src folder project current changes url start stamp sha rc=0 args override="" opts \
    line deploy_opts=()
  shift
  case "${1:-}" in developer | main) branch="$1"; shift ;; esac
  [ "${1:-}" != "--" ] || shift
  src="$(final_folder "$repo")"
  [ -r "$root/scripts/lib/projects.sh" ] || die 1 "scripts/lib/projects.sh not found"
  # shellcheck source=lib/projects.sh
  . "$root/scripts/lib/projects.sh"
  command -v docker >/dev/null 2>&1 || die 1 "docker not found"
  project="$( (cd "$src" && docker compose "$@" config --format json) | python3 -I -c 'import json, sys; print(json.load(sys.stdin).get("name", ""))')" ||
    die 1 "docker compose config failed in projects/$repo"
  [ -n "$project" ] || die 1 "no compose project in projects/$repo"
  [[ "$project" != agent_* ]] || die 1 "refused: $project is a task's copy group, not a final stack"
  if [ "$branch" = developer ]; then
    current="$(git -C "$src" symbolic-ref -q --short HEAD || echo detached)"
    [ "$current" = developer ] || die 1 "projects/$repo is on $current, not developer: the final stack deploys developer as it is checked out"
    changes="$(projects_changes "$src")" || die 1 "git status failed in projects/$repo"
    [ -z "$changes" ] || die 1 "projects/$repo has changes in its checkout: nothing deployed"
    folder="$src"
    deploy_opts=("$@")
  else
    folder="$root/tmp/deploy/$(clone_name "$repo" "$src")-main"
    override="$folder.binds.compose.yaml"
    require_unbound "$folder"
    rm -rf "${folder:?}" "$override"
    mkdir -p "$(dirname "$folder")"
    git clone -q --local --no-checkout "$src" "$folder" || die 1 "could not make the checkout of main"
    url="$(git -C "$src" remote get-url origin 2>/dev/null || true)"
    start=""
    if [ -n "$url" ] && timeout 120 git -C "$folder" fetch -q "$url" main 2>/dev/null; then
      start="$(git -C "$folder" rev-parse FETCH_HEAD)"
    else
      [ -z "$url" ] || echo "attention: could not fetch main from the remote of $repo; deploying the local main"
      start="$(git -C "$src" rev-parse -q --verify refs/heads/main || true)"
    fi
    [ -n "$start" ] || { rm -rf "${folder:?}"; die 1 "$repo has no main to deploy"; }
    git -C "$folder" checkout -q --detach "$start"
    copy_env_files "$src" "$folder"
    # Every bind of the checkout is mounted from projects/<repo> (an override outside the checkout): the stack's data
    # stays where developer keeps it, and the checkout can go. Tracked files that differ there are refused.
    opts="$(agent_copy deploy-binds "$project" "$folder" "$src" "$override" "$root" -- "$@")" ||
      { rm -rf "${folder:?}" "$override"; die 1 "nothing deployed (above)"; }
    while IFS= read -r line; do [ -z "$line" ] || deploy_opts+=("$line"); done <<<"$opts"
  fi
  sha="$(git -C "$folder" rev-parse --short HEAD 2>/dev/null || echo nogit)"
  stamp="$(date +%Y%m%d-%H%M%S)"
  args=(-p "$project" ${deploy_opts[@]+"${deploy_opts[@]}"})
  echo "deploy: $project from projects/$repo $branch at $sha"
  tag_rollback "$folder" "$stamp" "${args[@]}"
  (cd "$folder" && docker compose "${args[@]}" up -d --build) || rc=$?
  [ "$rc" -ne 0 ] || tag_published "$folder" "$stamp" "$sha" "${args[@]}"
  if [ "$branch" = main ]; then
    if agent_copy bound-under "$folder" >/dev/null 2>&1; then
      echo "kept: ${folder#"$root"/} (a container binds a path inside it)"
    else
      rm -rf "${folder:?}" "$override"
    fi
  fi
  [ "$rc" -eq 0 ] || die 1 "docker compose up failed (exit $rc); the images before it are <name>:rollback-latest: bash scripts/aiwp-cmds.sh rollback $repo"
  echo "deployed: $project from projects/$repo $branch at $sha (rollback: bash scripts/aiwp-cmds.sh rollback $repo)"
}

# rollback: each image of the final stack back to its rollback-latest tag, then up -d --no-build.
cmd_rollback() {
  [ $# -ge 1 ] || die 2 "usage: rollback <repo> [-- <docker compose options>...]"
  local folder ref name moved=0
  folder="$(final_folder "$1")"
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
  down) cmd_down "$@" ;;
  deploy) cmd_deploy "$@" ;;
  rollback) cmd_rollback "$@" ;;
  _destroy-copies)
    # The copy groups of a work (every clone) or of one clone: close and the gate's merge.
    [ $# -eq 1 ] || die 2 "usage: _destroy-copies <work>[/<clone>]"
    if [[ "$1" == */* ]]; then
      destroy_copies "$(clone_path "$1")"
    else
      [[ "$1" =~ $work_re ]] && [ -d "$work_root/$1" ] || die 1 "not found: tmp/work/$1"
      targets=()
      for entry in "$work_root/$1"/*/; do [ -d "$entry.git" ] && targets+=("${entry%/}"); done
      [ "${#targets[@]}" -eq 0 ] || destroy_copies "${targets[@]}"
    fi
    ;;
  gate | release | hotfix | hotfix-tag | hotfix-down | apply | developer | checkpoint | bring | bring-branch) exec bash "$root/scripts/aiwp-gate.sh" "$command" "$@" ;;
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
