#!/usr/bin/env bash
# Claude Code PreToolUse hook for the Bash tool: the human confirms a destructive or outward command, alone in its
# call; a commit that carries a secret, a change to the read-only core of an installed workspace and a way around the
# person's merge order are refused; a line that stays in one clone of tmp/work/ (Docker in the task's own group) is
# allowed with no question. The decision logic lives in guard-bash.py, next to this file.
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
  deny  a way around the person's merge order (/merge is the person's): a line that sets, exports, unsets or clears
        CLAUDECODE or CLAUDE_CODE_SESSION_ID (VAR=x, export, declare, unset, read, printf -v, ${VAR:=x}, env -u,
        env -i, env -, exec -c); one that writes, moves, deletes or links a path under .history/merge-orders/ of the
        root, or a folder that holds it (a redirection, or any command but a reader such as cat, ls, grep; interpreter
        code that names it; links resolved, from the folder the command runs in); and one that names
        scripts/session-title.py, the UserPromptSubmit hook that records the order, in any word or redirection,
        whatever reads it (python3 < it, cat it | python3 -, a wildcard or braces that match it; git reads aside).
  ask   deleting a database: docker volume rm/prune, docker compose down -v / rm -v, docker system prune --volumes,
        docker rm -v; DROP or TRUNCATE given to a SQL client (psql, mysql, mariadb, sqlite3, sqlcmd, mongosh,
        duckdb); dropdb, mysqladmin drop, dotnet ef database drop, prisma migrate reset or db push --force-reset,
        rails/rake db:drop, db:reset, db:purge; rm of a .data folder or of a .db, .sqlite, .mdf or .ldf file. Not in
        the task's own Docker group (see allow below): there they run with no question.
  ask   deleting, moving or emptying tools/observability/.data of the root, Grafana's data, anything in it or a folder
        that holds it, whatever the rest of the line is and wherever it runs, an approved clone included: rm, rmdir,
        mv, shred, truncate, find -delete or -exec rm, rsync --delete, cp, dd, sed -i or a redirection into it, xargs
        fed by a find, interpreter code, a Docker mount (-v <it>:/d) or ssh that names it.
  ask   scripts/aiwp-cmds.sh release, deploy (updates the final stack of a project from a branch), hotfix (pushes a
        fix to main), hotfix-tag (pushes a release tag), hotfix-down
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
  deny  "Run it alone: ..." instead of a question above when the line holds other commands too (joined by ;, &&, ||,
        & or a newline at the top level; a pipeline, a subshell, a compound command (if, for, while, case, { }) and
        what is nested in the asked command (bash -c, $(...)) count as one; a cd, pushd, popd or an assignment alone,
        with no redirection, travels with the asked command). Run the other commands first, then the
        asked one alone in its own call, so the question shows only it. A line that runs a file it wrote itself
        (cat > f.sh ... && bash f.sh) keeps the question: alone, later, that file is not seen.
  allow a line it can tell stays in one clone, tmp/work/<yyyy-mm-dd>-<slug>/<clone>/ (the work trail), when no deny or
        ask above applies:
        - every command runs in that clone (a cd into it from the root counts; scripts/aiwp-cmds.sh run
          <work>/<clone> -- <command> of this workspace counts, wherever it runs, and its command is judged in the
          clone);
        - every path it names stays in that clone, out of its .git (the hooks that scan and push), and is no local
          secret file (.env, local.settings.json, env/<name>.env): each argument and
          each token of it (code or a message given as one word), the value after = (--out=x, of=x, DESTDIR=x), the
          value glued to a short option (-o/x), each piece between colons, every redirection target; read from the
          folder the command runs in, links resolved. /dev/null and 2>&1 are fine; a URL is not a path (file: is);
        - nothing it runs acts on a remote system or outside the clone: git push (the clone's hooks push; a push by
          hand is never allowed), git remote add/set-url, git config writes, ssh, scp, rsync, sftp, curl, wget, cloud
          and cluster CLIs (aws, az, gcloud, kubectl, helm, terraform, tofu, pulumi, gh, glab...), a remote word
          (push, publish, deploy, release, upload, login: npm publish, mvn deploy, twine upload, gem push), a global
          install (npm -g, --location=global, npm link, pip --user, python3 -m pip --user, uv --system, go install,
          cargo install, uv tool install, gem install, bundle --system, dotnet tool -g, composer global, conda, mamba,
          pipx, brew), npm config, links (ln, cp -s), kill, sudo, xargs.
          Installing dependencies (npm install, pip install, uv sync, go mod download, mvn, gradle, dotnet restore) is
          not remote. SQL clients on the host and the workspace scripts (aiwp, aiwp-cmds.sh other than run,
          aiwp-gate.sh) are never allowed here: they keep their own rules;
        - nothing deletes or moves the clone's .git or a folder that holds it (rm -rf ., mv . x, find . -delete,
          find . -exec rm);
        - Docker only in the task's own group, the compose project agent_<MMDD>-<slug> or agent_<MMDD>-<slug>--<clone>
          (a double dash: a work slug never holds one) of that clone's work tmp/work/<yyyy-mm-dd>-<slug>/ (an existing
          clone folder), run from the clone with no docker global option and no DOCKER_* or COMPOSE_* variable on the
          line: docker compose -p <group> (or --project-name), -f naming only files of the clone or the copy's
          override tmp/work/<work>/agent-<clone>.compose.yaml, with up, down (-v, --volumes, --remove-orphans, -t),
          ps, logs, stop, start, restart, build (no --push), config, top, images, port, pause, unpause, or exec with
          only -T -i -t -d -e -w -u --index (grouped short options read as docker does; a SQL client or dropdb it runs
          in the container gets no question) and nothing remote in the container; docker rm, rmi, image rm, volume rm
          or inspect, network rm of resources that all carry the label com.docker.compose.project=<group> (docker
          inspect, 5 s; Docker that does not answer, a resource with no label or of another group: today's rules).
          docker compose run, create, cp, attach, watch, an unknown option and docker run are left to them.
        It stays silent when it cannot tell: a word with $ (a variable, a substitution) or ~, a brace expansion, a
        wildcard that may leave (a dot segment after it, a match that is a link out), a folder it does not know, two
        clones, a redirection with no command, a nested text it could not read.
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
Not seen, by design: a command held in a variable or a function, what a script or an interpreter builds at run time
(an allowed line may run a script of the clone: the trail trusts the clone, not what the script does),
and what runs inside a container or another host beyond the command line given here. Other tools that change
permissions (setfacl, chattr, install -m, a chmod inside a script or an interpreter) are not judged. Grafana's data
and the merge orders: a container that mounts them (docker run -v), a path held in a variable the line does not set
(only its text is matched), archive extraction (tar -C, unzip -d); sudo, ssh localhost or an interpreter that starts
a process with a cleaned environment (only the shell forms above are seen). The own Docker group trusts its compose
files, which live in the clone.
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
