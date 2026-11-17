#!/usr/bin/env bash
# Claude Code PreToolUse hook for the Bash tool: the human confirms a destructive or outward command; a commit that
# carries a secret and a change to the read-only core of an installed workspace are refused. The decision logic lives
# in guard-bash.py, next to this file.
set -euo pipefail

# Prints the command reference.
usage() {
  cat <<'USAGE'
Usage: scripts/guard-bash.sh [--help]

PreToolUse hook (matcher: Bash). Reads the hook JSON on stdin. Most commands are left to Claude Code's own permission
mode (auto mode judges destruction); this hook holds only what the workspace never lets through:
  deny  a git command that writes in projects/ or in the core (the workspace repo): commit, merge, push, reset,
        checkout, switch, rebase, branch or tag changes, stash push/pop, worktree, update-ref, config set, a fetch
        into a local branch, diff --output... Reads run (status, log, diff, show, fetch, branch -a, stash list...).
        The repo is the one git writes: --git-dir/GIT_DIR, else the one found from where git runs (inside .git too),
        plus the work tree and the local paths a push, fetch, clone, init, config --file or worktree names.
        projects/ and the core change only through scripts/aiwp-cmds.sh gate, release, apply and the steps of
        /normalize-projects (developer, checkpoint, bring). A git command whose
        repo cannot be told (git -C "$VAR") asks.
  deny  terraform or tofu apply, destroy, import, taint, untaint, force-unlock, refresh, test, state rm/mv/push and
        workspace delete, anywhere: only scripts/aiwp-cmds.sh apply runs them, from main of projects/<repo>.
  deny  git push --no-verify, or any prefix git accepts for it (it would skip the clone's pre-push secret scan).
  deny  a git commit in custom/ that carries a file named .env or local.settings.json, or a secret that
        scripts/validate.sh --only secrets finds in its files; asks when that scan cannot run. Commits in the clones
        of tmp/work/ are checked by their pre-push hook instead (scripts/aiwp-cmds.sh --help).
  ask   deleting a database: docker volume rm/prune, docker compose down -v / rm -v, docker system prune --volumes,
        docker rm -v; DROP or TRUNCATE given to a SQL client (psql, mysql, mariadb, sqlite3, sqlcmd, mongosh,
        duckdb); dropdb, mysqladmin drop, dotnet ef database drop, prisma migrate reset or db push --force-reset,
        rails/rake db:drop, db:reset, db:purge; rm of a .data folder or of a .db, .sqlite, .mdf or .ldf file.
  ask   scripts/aiwp-cmds.sh release, hotfix (pushes a fix to main), hotfix-tag (pushes a release tag), hotfix-down
        (merges main into developer and pushes it), checkpoint (pushes the checkpoint tags), developer --create (creates
        developer on the remote), gate --untested (a normalization without its tests), apply --apply and close --discard
        (run, by a shell, or by source).
  ask   git configuration on the line that can run a command (-c core.fsmonitor, core.sshCommand, a pager, an alias,
        a hooks folder, diff.external, remote.*.fetch, --config-env, --upload-pack, GIT_CONFIG_*, GIT_SSH_COMMAND...).
In an installed workspace (the nearest folder above a path with .aiwp/manifest.json, any workspace, not only this
one), the core is every path that is not under a writable path: the root itself included. The writable paths are what
scripts/aiwp.sh _writable prints, run next to this script (custom projects tmp .claude .history .aiwp and the tool
outputs); the root of an installation is not a git repository: the repositories are custom/ and each project, and
the core changes only through aiwp. Outside an installed workspace (this repository's own tree) none of this applies.
  deny  chmod, chown or chgrp whose target reaches the core: links resolved (one the same line makes with ln or cp -l/-s
        too), relative to the folder it runs in (cd, pushd), -R, --reference, options among the files, "--"; also run by
        sudo, env, bash -c, xargs or parallel (judged by what the line feeds them and the folder they run in), and find
        -exec/-execdir/-ok (judged by the folders find walks, as -R). A -R or find that follows links in the tree (-L,
        -H) denies anywhere in a workspace. A glob (* ? [ {) passes only when the folder of its literal prefix is
        writable and no .. follows the wildcard; a -R or glob over a folder that holds this workspace denies.
  deny  git init (--bare, --separate-git-dir, -C <dir>, --git-dir) or git clone whose new repository lands in the core.
  ask   chmod, chown or chgrp of a path held in a variable the line does not set, inside an installed workspace; a
        file in a writable folder that has other hard links; and any of these when scripts/aiwp.sh _writable fails.
  deny  aiwp update, rollback and repair (also ~/.local/bin/aiwp, scripts/aiwp.sh, bash scripts/aiwp.sh, sudo, env,
        bash -c): they swap or restore the read-only core, so the rules of the open session; aiwp forget, which
        changes the registry of workspaces; and aiwp alone or aiwp -- <arguments>, which opens the workspace and
        starts claude inside the session. The person closes the session and runs them in a terminal. Also an aiwp
        whose command word it cannot see (from xargs or parallel, a variable, a command substitution). aiwp check,
        version, list, new (aiwp refuses it over a registered folder) and --help run silently, as does bash -n.
A command given to scripts/aiwp-cmds.sh run <work>/<clone> -- ... is judged in the clone's folder.
  anything else, and --help of any program -> silent (the normal permission flow decides).
How it reads the line: the way a shell groups it. Quotes, escapes, line continuations, # comments, redirections (never
taken as arguments), heredocs, $(...), backticks, <(...), subshells, arithmetic, if/then/do/{ and other keywords.
Where the command runs: it follows git -C <dir>, --git-dir, GIT_DIR=, export, and a cd, pushd or popd earlier in the
line, each inside its own subshell; a cd "$VAR" is followed when VAR is set in the line or in the environment.
Where it looks for a command:
  - after wrappers (sudo, env, timeout, xargs, time, flock, watch, nohup, parallel, sshpass...) with their options
    apart or glued (sudo -u app, sudo -iu app), after runners (uv run, npx, op run, aws-vault exec...), and after "--"
    of any program (<script> -- <command>);
  - in the text of bash -c, eval, trap, env -S, flock -c, su -c, git submodule foreach, and of ssh (its words joined,
    as the remote shell reads them; options before or after the host);
  - in what docker exec/run, docker compose exec/run (with -f, -p, --profile...), kubectl exec and
    scripts/heavy-run.sh launch;
  - in what reaches the stdin of a shell (bash, ssh host, su, sudo -s, docker exec -i c sh), when the line shows it: a
    heredoc, a here-string, an echo or printf piped in, a file the line wrote;
  - in a script the same line writes (cat > f <<EOF, tee f, echo ... > f) and then runs (bash f, ./f, source f,
    bash < f, psql -f f).
A heredoc body is otherwise data; with an unquoted delimiter, its $(...) and backticks are read, because they run.
A command it cannot read (an open quote) asks when it names a guarded program. Malformed input, no python3, any
internal error and a run longer than 240 s ask too: never a silent pass, never a block of every command.
Not seen, by design: a command held in a variable or a function, what a script or an interpreter builds at run time,
and what runs inside a container or another host beyond the command line given here. Other tools that change
permissions (setfacl, chattr, install -m, a chmod inside a script or an interpreter) are not judged.
This is a speed bump with the human's confirmation behind it, not a sandbox.
Workspace root: $CLAUDE_PROJECT_DIR, else the parent of this script's folder.
Test seams: GUARD_BASH_DOCKER (docker binary), GUARD_BASH_VALIDATE (validate script).

Example:
  echo '{"tool_input":{"command":"cd projects/x && git reset --hard"},"cwd":"/tmp"}' | scripts/guard-bash.sh
USAGE
}

# Prints the decision that hands the command to the human, with the cause.
ask() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"guard-bash could not evaluate the command (%s). Confirm only if it does not write to projects/ or the core, does not change the permissions of the core, does not apply Terraform and does not delete a database."}}\n' "$1"
}

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  "") ;;
  *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
esac

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="${CLAUDE_PROJECT_DIR:-$(cd "$here/.." && pwd)}"

if ! command -v python3 >/dev/null 2>&1; then
  # Reads the input to the end, so the caller's write does not fail on a closed pipe.
  [ -t 0 ] || cat >/dev/null
  ask "python3 missing"
  exit 0
fi

if ! errfile="$(mktemp 2>/dev/null)"; then
  [ -t 0 ] || cat >/dev/null
  ask "mktemp failed"
  exit 0
fi
trap 'rm -f "$errfile"' EXIT
# stdout carries only the decision; stderr (the exception type name, or python noise on success) stays apart.
if ! result="$(python3 -I -B "$here/guard-bash.py" "$root" 2>"$errfile")"; then
  ask "$(head -c 80 "$errfile" | tr -cd 'A-Za-z0-9_ ' || true)"
  exit 0
fi
[ -z "$result" ] || printf '%s\n' "$result"
