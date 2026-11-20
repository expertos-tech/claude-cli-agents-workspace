#!/usr/bin/env bash
# Work clones of the maintenance of this repository: each change is made in a local clone under tmp/work/, on its own
# branch from origin/developer, and pushed at every commit by the clone's git hooks once the company-terms scan of
# what leaves passes; a company term is a warning the owner confirms (push --accept-terms), never a refusal. Writes
# under tmp/work/, the owner's accepted terms next to the terms list, and one commit on developer at the root for the
# move of a request to maintainers/requests/doing/ and back (start, close --discard), pushed only after the checks of
# that one move. Modeled on workspace/scripts/aiwp-cmds.sh.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

# Prints the command reference.
usage() {
  cat <<'USAGE'
Usage: bash tests/caw-work.sh <command> [args] [--help]

The maintenance works in tmp/work/<work>/claude-cli-agents-workspace/: a local clone of this repository on the branch
of the change, started from origin/developer. <work> is <yyyy-mm-dd>-<kebab-slug>: the day the work opened and the slug
of its branch. The script writes under tmp/work/; start and close --discard also make one commit on developer at the
root, a move of a request, pushed to origin/developer only within the checks of start (below).

Commands:
  start <name> [--branch <type>/<slug>]
        A request starts: run at the root before open. <name> is a file of maintainers/requests/ (no folder, exactly
        as given). Fetches origin, then refuses, listing every reason, committing and pushing nothing: the root not on
        developer; a file not committed at the root (untracked included); developer with a commit not on
        origin/developer, or behind it; maintainers/requests/<name> not on origin/developer, or
        maintainers/requests/doing/<name> on it already (in progress: /caw-request <name> resumes it or starts
        over); its row in the pending tables of maintainers/requests/README.md (the section "Pending": the one row
        whose Request cell is `<name>`) missing, there more than once, or with a Status other than pending.
        Otherwise one commit "chore(requests): start <name>" (git mv to maintainers/requests/doing/<name>, and the
        Status cell of its row from pending to doing; --branch names the branch in its body), checked before the
        push: one commit on origin/developer, a pure rename of that file (100% similar) and one line of the README
        that differs only in that Status cell; anything else rolls the commit back (git reset --hard to the base,
        the tree having been clean; a file something else wrote meanwhile stays, named) and refuses. Then a plain
        push of developer (never forced, no suite, review or terms scan: its shape is the check). A push refused
        because origin/developer moved meanwhile: the commit is rolled back, developer fast-forwarded to the new
        origin/developer, and everything checked and made again, once; a second refusal rolls back and stops.
        Prints "pushed: developer <sha> chore(requests): start <name>".
  open <type>/<slug> [--request <name>] [--resume]
        <type>: feat fix docs refactor test chore perf build ci style; <slug>: kebab-case. Refuses developer, main
        (as the name or the slug) and the name of a tag, here or on the remote. Clones this repository
        (git clone --local) into tmp/work/<today>-<slug>/claude-cli-agents-workspace, points its origin at this
        repository's origin, fetches it, creates the branch from origin/developer (the clone keeps no other local
        branch), records it (git config caw.branch), writes the clone's git hooks (below) and pushes the branch with
        its upstream, through those hooks. Prints "path: tmp/work/<work>/claude-cli-agents-workspace". A clone of the
        same branch, in any work folder, is reused. Refused: a clone of another branch in the folder, and the branch
        already on the remote with no clone here.
        A new or reused clone gets the "language" of this repository's .claude/settings.local.json in its own (git
        ignores it there too), keeping its other keys and never replacing a language it has: "language: <it> (from
        the root .claude/settings.local.json)".
        --request <name>: the work runs that request: maintainers/requests/doing/<name> must be on origin/developer
        (start moved it there, so the new branch holds the move). Recorded in tmp/work/<work>/.request; refused,
        creating nothing, when another work records it or this work records another request.
        --resume: the branch already on the remote with no clone here is checked out from it (the work goes on
        there, nothing pushed) instead of being refused; not on the remote: it starts from origin/developer, with an
        attention: line.
  run <work>[/<clone>] -- <command>...
        Runs the command (no shell) with the clone as the current folder, only when it is on run's list; anything else
        is refused, running nothing, with "not on run's list: run it as a plain command (the permission mode
        decides)". The list:
        - git with no global option and one of add commit status diff log show restore switch checkout branch merge
          rebase reset stash mv rm rev-parse ls-files blame cherry-pick revert fetch grep config, each with its own
          short list of options, matched exactly: an option off the list, an abbreviation of one on it, or a group of
          short flags with a letter off the list is refused (so no --exec, -x or -i for rebase, no --upload-pack, no
          -O for grep, no --output anywhere). fetch names a remote of the clone (git remote), never a path or URL;
          config only reads (--get, --get-all, --list, -l). Never git push: the hooks push, and push below;
        - a script file of the clone: bash <file> [args], sh <file> [args], python3 <file> [args], with no option
          before the file; python3 -m pytest|unittest [args];
        - the tools shellcheck shfmt ruff markdownlint-cli2 sha256sum wc diff cat head tail ls grep find mkdir touch cp
          mv rm chmod (no sed: edit with the editor or a script file); find with no -exec, -execdir, -ok, -okdir,
          -delete or -fprint*; rm, mv and chmod -R never on the clone itself.
        Every argument, every value of --opt=value and every attached value of a short option (-t<dir>, -at<dir>)
        that names a path must resolve, symbolic links followed, inside the clone and outside its git dir (.git: its
        hooks and config); /dev/null is fine, ~ is not. When AIWP_TERMS_FILE is not set and this repository finds a
        terms list, exports it, so tests/check.sh in the clone scans with the same list.
        Accepted limit: a script file run through bash, sh or python3 (or a config file a listed tool executes, such
        as .markdownlint-cli2.cjs) does whatever it holds, a file that run's own commands wrote included; run checks
        the command line, never what a script does. The terms scan of push and of the hooks still judges what leaves.
        A command with --accept-terms is refused: the owner confirms it as a plain command (below).
  push <work>[/<clone>] [--accept-terms]
        Pushes the branch now, exactly as the hooks do (what an automatic push left behind): the terms scan of what
        leaves runs first, in this script, then git push (never forced) through the clone's pre-push hook, which
        scans again; a removed hook or another hooks path never lets a term out. A company term in what leaves is a
        WARNING, not an error: nothing is pushed, the commit stays in the clone, and the warning says where each
        match is and how to keep it. Exit 1 when it is not pushed.
        --accept-terms: the owner keeps the company terms that match now (the settings ask the owner before this
        runs): their lines of the terms list are recorded in <terms list>.accepted, next to the list (created 600;
        refused inside this repository unless git ignores it), never printed, then the branch is pushed. Later scans,
        and tests/check.sh repo-terms, skip an accepted term, so it is not asked again; a new term warns again.
        Delete a line of that file to be warned about the term again.
  status [<work>]
        Per work that records a request: "tmp/work/<work>  request=maintainers/requests/doing/<name>" ("(missing)"
        when the root has no such file). Fetches origin (--prune), then one line per clone: branch, commits ahead of
        origin/developer, commits not on the remote, files not committed, and whether the branch is in
        origin/developer; then one "copy:" line per Docker copy group of the clone (state, host ports). Docker not
        reachable: one line "Docker: not reachable". Without <work>, last: one "stale: maintainers/requests/doing/
        <name>" line per file of that folder at the root that no work of tmp/work/ records.
  publish <work>[/<clone>]
        Publishes what the clone changed against origin/developer (committed or not, new files included), so the
        owner can test it:
        - a tool (workspace/tools/<tool>/, other than its *.md and docs/): that tool as a copy, from the clone, in
          its own Docker group agent_<MMDD>-<slug>--<tool> (-- never collides with another work's group), through an override file
          tmp/work/<work>/agent-<tool>.compose.yaml (the group's own images, no fixed names, every published port
          moved to a random free port in 61000-65535, the variables AGENT_PORT_<SERVICE>_<PORT> in its environment;
          workspace/scripts/agent-copy.py, as aiwp-cmds.sh up). Its configuration is read from the
          installed workspace: AIWP_WORKSPACE (default $HOME/Development/ai-workspace), its custom/env/<tool>.env and,
          through AIWP_CUSTOM_DIR, its custom/config/. A tool with no compose.yaml has nothing to publish.
        - the installer, a hook, a script or a rule (install.sh, tests/test-install.sh, workspace/scripts/,
          workspace/rules/, workspace/AGENTS.md, workspace/CLAUDE.md, .claude/): a test installation,
          bash tests/test-install.sh in the clone (its output in tmp/work/<work>/agent-test-install.log).
        - anything else alone (documentation, translations, maintainers/, tests/check.sh): "nothing to publish".
        Prints each copy's ports and addresses and where the test installation is. Exit 1 when one failed.
  close <work> [--discard [--start-over]]
        Fetches origin and refuses, listing what would be lost, when the work folder holds something that is not a
        clone made by open, or a clone with files not committed, a stash, commits not on the remote, or its branch
        not in origin/developer. Otherwise deletes tmp/work/<work>/ and then the remote work branch (git push
        <clone's origin URL> --delete, from this repository). --discard deletes the folder anyway and leaves the
        remote branch. The folder goes first, read-only files included (a test installation's: chmod -R u+rwX, no
        symlink followed); the remote branch only once it is all gone, so a delete that fails exits 1, lists what is
        left and leaves the remote branch and the clone to close again. Before
        the folder goes, the work's Docker copy groups are destroyed: the groups of its agent-*.compose.yaml files
        and the agent_ projects whose compose folder lies in a clone, by the label com.docker.compose.project and only
        when the name matches ^agent_[0-9]{4}-[a-z0-9][a-z0-9-]*$; a refused close destroys nothing.
        The request the work records (open --request): with --discard it goes back to pending first, before anything
        is deleted: the reverse of start, "chore(requests): put back <name>" (maintainers/requests/doing/<name> to
        maintainers/requests/<name>, Status cell doing to pending), with every check of start; refused: nothing is
        deleted. A request no longer in doing/ on origin/developer: an attention: line, nothing moved. Without
        --discard it never moves (/caw-merge moved it to qa/).
        --start-over (with --discard: start the request again): the work branch of each clone is deleted on the
        remote first (only a work branch, never developer or main; --force-with-lease with the sha the clone pushed
        last, caw.pushed, so a commit pushed there from elsewhere refuses the close and keeps the folder; a clone
        with no caw.pushed refuses it too, never leasing on its tracking ref), then the folder goes;
        the request stays in doing/ and nothing is committed. Then: open <type>/<slug> --request <name>.

Git hooks of a clone (written by open into the clone's .git/hooks, with the clone's core.hooksPath set to it; never
part of any repository). They call this script by the absolute path it had when it ran open.
  post-commit, post-merge    push the branch as push does: the terms scan, then git push origin HEAD:refs/heads/
                             <branch>, never forced. Nothing on a detached HEAD, during a rebase, or with another
                             branch checked out.
  post-rewrite               the same at the end of a rebase; an amend is pushed by post-commit.
                             A push not made (a company term's WARNING, or a refusal) says what to do and never fails
                             the commit: the commit stays in the clone.
  pre-push                   reads every ref line first, then refuses the whole push of developer, main, a tag or any
                             ref outside refs/heads/, and a push that is not a fast-forward (a force push: an amend or
                             a rebase of pushed commits). A deletion of another branch passes. To a scratch
                             destination, an absolute path (no named remote, no URL) to a folder inside the clone's
                             own tmp/, links resolved (the throwaway repository of tests/test-install.sh), any
                             branch passes, developer and main included; a tag, a ref outside refs/heads/ and a force
                             push stay refused there too, and the scan below still runs, with the commits origin
                             already has counted as sent (scanned when they left). Then it scans what
                             leaves, the commits the remote does not have (git ls-remote): every version of a file
                             they add or change, the paths of those files, their messages, and their author and
                             committer names and e-mails, against the terms list (tests/lib/terms.sh, the
                             lookup of tests/check.sh --help) less the accepted terms. A match stops the push with a
                             WARNING (the repository is public; keep the term with push --accept-terms, or rewrite the
                             commits not on the remote) after the lines <commit>:<path>:<line>:<text>; never paste
                             those lines into an issue, a commit or a pull request. AIWP_TERMS_FILE naming no file
                             and a remote that cannot be read refuse; no terms list prints
                             "SKIP terms scan: no terms list" and the push goes.

Internal: _autopush <clone> [<post-rewrite kind>], _prepush <clone> <remote> (the ref lines on stdin).

Environment: AIWP_WORKSPACE (publish: the installed workspace the tools' configuration comes from); CAW_TEST_INSTALL
replaces bash tests/test-install.sh in publish (tests; it gets the clone as its argument).

Exit codes: 0 ok; 1 refused or failed; 2 usage error.

Examples:
  bash tests/caw-work.sh start autonomous-work.md --branch feat/autonomous-work
  bash tests/caw-work.sh open feat/autonomous-work --request autonomous-work.md
  bash tests/caw-work.sh open feat/autonomous-work --request autonomous-work.md --resume
  bash tests/caw-work.sh run 2026-11-18-autonomous-work -- git status --short
  bash tests/caw-work.sh run 2026-11-18-autonomous-work -- bash tests/check.sh --base origin/developer --i18n-pending
  bash tests/caw-work.sh push 2026-11-18-autonomous-work
  bash tests/caw-work.sh push 2026-11-18-autonomous-work --accept-terms   # the owner keeps the term warned about
  bash tests/caw-work.sh status
  bash tests/caw-work.sh publish 2026-11-18-autonomous-work
  bash tests/caw-work.sh close 2026-11-18-autonomous-work
  bash tests/caw-work.sh close 2026-11-18-autonomous-work --discard                # the request back to pending
  bash tests/caw-work.sh close 2026-11-18-autonomous-work --discard --start-over   # then open ... --request again
USAGE
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
script="$root/tests/$(basename "${BASH_SOURCE[0]}")"
work_root="$root/tmp/work"
clone_dir=claude-cli-agents-workspace
work_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*$'
branch_re='^(feat|fix|docs|refactor|test|chore|perf|build|ci|style)/[a-z0-9]+(-[a-z0-9]+)*$'
zero_re='^0+$'
requests=maintainers/requests
# The name of a request file of maintainers/requests/: one file, no folder.
request_re='^[A-Za-z0-9][A-Za-z0-9._-]*$'

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

# Gives a clone the owner's preferred language: the "language" of this repository's .claude/settings.local.json (a
# JSON object, "language" a non-empty string) written into the clone's own, git-ignored there too, keeping every other
# key and never replacing a language the clone file has. No language at the root: nothing, silently. A clone file that
# is not a JSON object, or one git would not ignore: left as it is, with one "attention:" line. Never fails open.
copy_language() {
  local clone="$1" source="$root/.claude/settings.local.json" ignored=0
  [ -f "$source" ] || return 0
  ! git -C "$clone" check-ignore -q -- .claude/settings.local.json 2>/dev/null || ignored=1
  python3 -I - "$source" "$clone" "$ignored" <<'PY' || echo "attention: the preferred language was not copied into the clone"
import json
import os
import sys
import tempfile

NAME = "settings.local.json"
MAX_READ = 1_000_000


def read_object(path):
    """Return the JSON object of a file, or None when it cannot be read, is malformed or is not an object."""
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.loads(handle.read(MAX_READ))
    except (OSError, ValueError, UnicodeDecodeError):
        return None
    return data if isinstance(data, dict) else None


def has_language(data):
    """Return True when a settings object holds "language" as a non-empty string."""
    value = data.get("language") if isinstance(data, dict) else None
    return isinstance(value, str) and value.strip() != ""


def write_atomically(folder, data):
    """Write the settings object to folder/settings.local.json through a temp file of the same folder and a rename."""
    fd, temp = tempfile.mkstemp(dir=folder, prefix="." + NAME + ".")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp, os.path.join(folder, NAME))
    except BaseException:
        if os.path.exists(temp):
            os.unlink(temp)
        raise


def main():
    """Copy the language of the root settings sys.argv[1] into the clone sys.argv[2] (sys.argv[3]: 1 when git ignores
    the clone's .claude/settings.local.json); print what it did, or why it did not."""
    root_data = read_object(sys.argv[1])
    if not has_language(root_data):
        return
    language = root_data["language"]
    shown = "".join(c if c.isprintable() else "?" for c in language)
    folder = os.path.join(sys.argv[2], ".claude")
    target = os.path.join(folder, NAME)
    where = ".claude/" + NAME + " of the clone"
    if sys.argv[3] != "1":
        print(f"attention: the preferred language was not copied: git does not ignore the {where}")
        return
    if os.path.islink(folder) or (os.path.exists(folder) and not os.path.isdir(folder)):
        print("attention: the preferred language was not copied: .claude of the clone is not a folder")
        return
    data = {}
    if os.path.lexists(target):
        data = read_object(target) if os.path.isfile(target) and not os.path.islink(target) else None
        if data is None:
            print(f"attention: the {where} is not a JSON object: left as it is, without the preferred language")
            return
        if has_language(data):
            return
    data["language"] = language
    os.makedirs(folder, exist_ok=True)
    write_atomically(folder, data)
    print(f"language: {shown} (from the root .claude/{NAME})")


main()
PY
}

# Requests in progress (start, open --request, close --discard): a request moves from maintainers/requests/ to
# maintainers/requests/doing/ (and back) in one commit on developer at the root, pushed only when it is that move and
# nothing else (the one exception to "developer moved outside /caw-merge", .claude/rules/security.md).

# Checks or edits the Status cell of the row of a request in the pending tables of maintainers/requests/README.md (the
# tables of its section "## Pending", by their header cells Request and Status), or verifies that two versions of the
# README differ only in that cell:
#   check <readme> <name> <from>            exactly one row of `<name>`, with the Status <from>
#   edit <readme> <name> <from> <to>        the same, then that cell to <to>, written in place
#   verify <old> <new> <name> <from> <to>   <new> is <old> with only that cell changed from <from> to <to>
# Prints the reason and returns 1 when it does not hold; 2 for a usage error.
readme_status() {
  python3 -I - "$@" <<'PY'
import os
import sys
import tempfile

README = "maintainers/requests/README.md"


def fail(reason):
    """Print why the check does not hold and exit 1."""
    print(reason)
    sys.exit(1)


def read_lines(path):
    """Return the lines of a file with their line ends, or exit 1 when it cannot be read."""
    try:
        with open(path, encoding="utf-8", newline="") as handle:
            return handle.read().splitlines(keepends=True)
    except (OSError, UnicodeDecodeError):
        fail(f"{README} cannot be read")


def cells(line):
    """Return the cells of a table row (the text between its outer pipes), or None for a line that is not one."""
    text = line.rstrip("\r\n").strip()
    if len(text) < 2 or not text.startswith("|") or not text.endswith("|"):
        return None
    return text[1:-1].split("|")


def is_separator(row):
    """Return True for the separator row of a table (---, :---: cells)."""
    return all(cell.strip() and set(cell.strip()) <= set("-:") for cell in row)


def rows_of(lines, name):
    """Return (line index, Status cell index or -1) for each row of the pending tables whose Request cell is `name`."""
    found = []
    pending = False
    header = None
    for index, line in enumerate(lines):
        if line.startswith("## "):
            pending = line.rstrip("\r\n").rstrip() == "## Pending"
            header = None
            continue
        row = cells(line)
        if not pending or row is None:
            header = None
            continue
        if header is None:
            header = [cell.strip() for cell in row]
            continue
        if is_separator(row) or "Request" not in header:
            continue
        at = header.index("Request")
        if at < len(row) and row[at].strip() == "`" + name + "`":
            status = header.index("Status") if "Status" in header and len(row) == len(header) else -1
            found.append((index, status))
    return found


def one_row(lines, name, want):
    """Return (line index, Status cell index) of the one row of `name` whose Status is want, or exit 1 with why not."""
    found = rows_of(lines, name)
    if not found:
        fail(f'no row of `{name}` in the pending tables of {README} (its section "Pending")')
    if len(found) > 1:
        fail(f"{len(found)} rows of `{name}` in the pending tables of {README}: keep one")
    index, status = found[0]
    if status < 0:
        fail(f"the row of `{name}` in {README} has no Status cell (its table needs a Status column)")
    value = cells(lines[index])[status].strip()
    if value != want:
        fail(f"the Status of `{name}` in {README} is {value or 'empty'}, not {want}")
    return index, status


def replaced(line, status, value):
    """Return the table row with its cell number status set to value, the padding and the rest of the line kept."""
    body = line.rstrip("\r\n")
    end = line[len(body):]
    lead = body[: len(body) - len(body.lstrip())]
    trail = body[len(body.rstrip()):]
    parts = body.strip()[1:-1].split("|")
    cell = parts[status]
    parts[status] = cell[: len(cell) - len(cell.lstrip())] + value + cell[len(cell.rstrip()):]
    return lead + "|" + "|".join(parts) + "|" + trail + end


def write_in_place(path, lines):
    """Write the lines to path through a temp file of the same folder and a rename, keeping its mode."""
    folder = os.path.dirname(os.path.abspath(path))
    mode = os.stat(path).st_mode & 0o777
    fd, temp = tempfile.mkstemp(dir=folder, prefix=".README.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write("".join(lines))
        os.chmod(temp, mode)
        os.replace(temp, path)
    except BaseException:
        if os.path.exists(temp):
            os.unlink(temp)
        raise


def main():
    """Run the mode of sys.argv[1] on the arguments that follow it."""
    args = sys.argv[1:]
    if len(args) == 4 and args[0] == "check":
        one_row(read_lines(args[1]), args[2], args[3])
    elif len(args) == 5 and args[0] == "edit":
        lines = read_lines(args[1])
        index, status = one_row(lines, args[2], args[3])
        lines[index] = replaced(lines[index], status, args[4])
        write_in_place(args[1], lines)
    elif len(args) == 6 and args[0] == "verify":
        old, new = read_lines(args[1]), read_lines(args[2])
        index, status = one_row(old, args[3], args[4])
        changed = [i for i in range(max(len(old), len(new))) if i >= len(old) or i >= len(new) or old[i] != new[i]]
        if changed != [index] or new[index] != replaced(old[index], status, args[5]):
            fail(f"{README} changes more than the Status cell of `{args[3]}` ({args[4]} to {args[5]})")
    else:
        print("usage: check|edit|verify ...")
        sys.exit(2)


main()
PY
}

# Fetches origin at the root. Returns non-zero when it cannot.
fetch_root() {
  with_timeout 120 git -C "$root" fetch -q origin 2>/dev/null
}

# Prints, one per line, why the root cannot move <src> to <dst> now (the checks of start, against what origin/developer
# has after the fetch); prints nothing when it may. <from> is the Status the README row must have.
move_problems() {
  local src="$1" dst="$2" name="$3" from="$4" head dirty ahead behind reason dev=refs/remotes/origin/developer
  head="$(git -C "$root" symbolic-ref -q --short HEAD || echo 'a detached HEAD')"
  [ "$head" = developer ] || echo "the root is on $head, not developer"
  dirty="$(git -C "$root" status --porcelain | grep -c . || true)"
  [ "$dirty" -eq 0 ] || echo "$dirty file(s) not committed at the root (git status): commit or remove them first"
  git -C "$root" rev-parse -q --verify "$dev" >/dev/null || { echo "origin has no developer"; return 0; }
  if git -C "$root" rev-parse -q --verify refs/heads/developer >/dev/null; then
    ahead="$(git -C "$root" rev-list --count "$dev..refs/heads/developer")"
    behind="$(git -C "$root" rev-list --count "refs/heads/developer..$dev")"
    [ "$ahead" -eq 0 ] || echo "developer has $ahead commit(s) not on origin/developer: /caw-merge takes them first"
    [ "$behind" -eq 0 ] || echo "developer is $behind commit(s) behind origin/developer: bring them first (git merge --ff-only origin/developer)"
  else
    echo "the root has no developer branch"
  fi
  if [ "$(git -C "$root" cat-file -t "$dev:$src" 2>/dev/null)" != blob ]; then
    if [ "$from" != pending ]; then
      echo "$src is not on origin/developer"
    elif [ -e "$root/$src" ] && [ -n "$(git -C "$root" status --porcelain -- "$src")" ]; then
      echo "$src is not on origin/developer, and not committed: a request starts only from origin/developer. Commit it (/caw-commit) on the branch that wrote it, take that branch into developer with /caw-merge, then run start again"
    elif git -C "$root" cat-file -e "HEAD:$src" 2>/dev/null; then
      echo "$src is not on origin/developer: committed here only; a request starts only from origin/developer. Take its commit there with /caw-merge, then run start again"
    else
      echo "$src is not on origin/developer: a request starts only from there. Written in a work clone: commit it there and take that branch into developer with /caw-merge, then run start again"
    fi
  fi
  if git -C "$root" cat-file -e "$dev:$dst" 2>/dev/null; then
    if [ "$from" = pending ]; then
      echo "$dst is on origin/developer already: the request is in progress (/caw-request $name resumes it or starts over)"
    else
      echo "$dst is on origin/developer already: rename one of the two first"
    fi
  fi
  reason="$(readme_status check <(git -C "$root" show "$dev:$requests/README.md" 2>/dev/null) "$name" "$from")" ||
    echo "$reason"
}

# Prints, one per line, why the commit HEAD of the root is not exactly the move of <src> to <dst> on <base> with the
# Status cell of its README row from <from> to <to>; prints nothing when it is.
moved_problems() {
  local base="$1" src="$2" dst="$3" name="$4" from="$5" to="$6" parents changes expected reason
  parents="$(git -C "$root" rev-list --parents -n 1 HEAD)"
  [ "$parents" = "$(git -C "$root" rev-parse HEAD) $base" ] || echo "HEAD is not one commit on origin/developer"
  changes="$(git -C "$root" diff --no-color --no-ext-diff --name-status -M100% "$base" HEAD | LC_ALL=C sort)"
  expected="$(printf 'M\t%s\nR100\t%s\t%s\n' "$requests/README.md" "$src" "$dst" | LC_ALL=C sort)"
  [ "$changes" = "$expected" ] ||
    echo "the commit changes more than the rename of $src (100% similar) and the README: $(printf '%s' "$changes" | tr '\t\n' ' ;')"
  reason="$(readme_status verify <(git -C "$root" show "$base:$requests/README.md" 2>/dev/null) \
    <(git -C "$root" show "HEAD:$requests/README.md" 2>/dev/null) "$name" "$from" "$to")" || echo "$reason"
}

# Takes the root back to <base>: the commit of a move not pushed is undone (the tree was clean before it), and a
# doing/ folder it left empty goes.
rollback_move() {
  git -C "$root" reset -q --hard "$1"
  rmdir "${root:?}/${requests:?}/doing" 2>/dev/null || true
}

# Prints a refusal on stderr: its title, then each line of <problems>, indented.
refuse_lines() {
  echo "refused: $1:" >&2
  printf '%s\n' "$2" | sed 's/^/  /' >&2
}

# Moves a request at the root in one commit on developer and pushes it: <name> <from: pending|doing> <title> [<body>].
# The checks of start first (move_problems: refused with every reason, nothing changed); then the commit, checked
# (moved_problems: rolled back and refused when it is anything but that move); then a plain push, never forced.
# origin/developer moved meanwhile: rolled back, developer fast-forwarded to it, and everything made again, once.
move_request() {
  local name="$1" from="$2" title="$3" body="${4:-}" to=pending src dst problems base msg attempt
  src="$requests/doing/$name"
  dst="$requests/$name"
  if [ "$from" = pending ]; then to=doing; src="$requests/$name"; dst="$requests/doing/$name"; fi
  msg="$title"
  [ -z "$body" ] || msg+=$'\n\n'"$body"
  [ -z "${CLAUDECODE:-}" ] || msg+=$'\n\n[#automatic-agent-commit]'
  for attempt in 1 2; do
    fetch_root || die 1 "could not fetch origin at the root: nothing was committed or pushed"
    problems="$(move_problems "$src" "$dst" "$name" "$from")"
    if [ -n "$problems" ]; then
      refuse_lines "$title: nothing was committed or pushed" "$problems"
      exit 1
    fi
    base="$(git -C "$root" rev-parse HEAD)"
    mkdir -p "$root/${dst%/*}"
    if ! git -C "$root" mv -- "$src" "$dst" ||
      ! readme_status edit "$root/$requests/README.md" "$name" "$from" "$to" >&2 ||
      ! git -C "$root" add -- "$requests/README.md" ||
      ! git -C "$root" commit -q -m "$msg" -- "$src" "$dst" "$requests/README.md"; then
      rollback_move "$base"
      die 1 "the commit of $title failed (above): rolled back; nothing was pushed"
    fi
    problems="$(moved_problems "$base" "$src" "$dst" "$name" "$from" "$to")"
    if [ -n "$problems" ]; then
      rollback_move "$base"
      refuse_lines "the commit is not only the move of $src: rolled back, nothing was pushed" "$problems"
      [ -z "$(git -C "$root" status --porcelain)" ] ||
        echo "attention: the root holds files that were not there before (git status): something else wrote them during the commit (a git hook?); nothing deletes them" >&2
      exit 1
    fi
    if with_timeout 120 git -C "$root" push -q origin refs/heads/developer:refs/heads/developer; then
      echo "pushed: developer $(git -C "$root" rev-parse --short HEAD) $title"
      return 0
    fi
    rollback_move "$base"
    fetch_root || die 1 "the push of developer failed and origin cannot be fetched: rolled back; nothing was pushed"
    [ "$(git -C "$root" rev-parse refs/remotes/origin/developer)" != "$base" ] ||
      die 1 "the push of developer was refused (above): rolled back; nothing was pushed"
    [ "$attempt" -eq 1 ] || die 1 "origin/developer moved again during the push: rolled back; nothing was pushed; run it again"
    git -C "$root" merge-base --is-ancestor "$base" refs/remotes/origin/developer ||
      die 1 "origin/developer moved and no longer holds developer: rolled back; nothing was pushed"
    git -C "$root" merge -q --ff-only refs/remotes/origin/developer ||
      die 1 "origin/developer moved and developer could not be fast-forwarded to it: rolled back; nothing was pushed"
    echo "origin/developer moved during the push: developer fast-forwarded to it; checking and committing again, once"
  done
}

# Refuses (exit 2) a <name> that is not one file of maintainers/requests/.
check_request_name() {
  [[ "$1" =~ $request_re ]] && [ "$1" != README.md ] ||
    die 2 "<name> is one file of $requests/ (no folder, not README.md), exactly as given: $1"
}

# start: the move of a pending request to doing/, before its clone opens.
cmd_start() {
  local name="" branch="" body="" usage_line="usage: start <name> [--branch <type>/<slug>]"
  while [ $# -gt 0 ]; do
    case "$1" in
      --help | -h) usage; return 0 ;;
      --branch) [ $# -ge 2 ] || die 2 "--branch needs a value"; branch="$2"; shift ;;
      -*) die 2 "$usage_line" ;;
      *) [ -z "$name" ] || die 2 "$usage_line"; name="$1" ;;
    esac
    shift
  done
  [ -n "$name" ] || die 2 "$usage_line"
  check_request_name "$name"
  if [ -n "$branch" ]; then
    [[ "$branch" =~ $branch_re ]] || die 2 "--branch must be <type>/<kebab-slug>: $branch"
    body="- in progress on the branch $branch"
  fi
  move_request "$name" pending "chore(requests): start $name" "$body"
  echo "request: $requests/doing/$name (in progress); next: bash tests/caw-work.sh open ${branch:-<type>/<slug>} --request $name"
}

# Prints the request a work records (maintainers/requests/doing/<name>), or nothing.
work_request() {
  local f="$work_root/$1/.request" rel name
  [ -f "$f" ] || return 0
  rel="$(head -n 1 "$f")"
  name="${rel#"$requests"/doing/}"
  if [ "$name" != "$rel" ] && [[ "$name" =~ $request_re ]]; then echo "$rel"; fi
  return 0
}

# Prints the works of tmp/work/ that record the request given (maintainers/requests/doing/<name>), one per line.
works_recording() {
  local f
  for f in "$work_root"/*/.request; do
    [ -f "$f" ] || continue
    if [ "$(head -n 1 "$f")" = "$1" ]; then basename "$(dirname "$f")"; fi
  done
  return 0
}

# Refuses, creating nothing, a request another work records, or a work that records another request.
check_request_record() {
  local work="$1" rel="$requests/doing/$2" other
  other="$(work_request "$work")"
  [ -z "$other" ] || [ "$other" = "$rel" ] ||
    die 1 "tmp/work/$work records another request ($other): use another branch; nothing was created"
  while IFS= read -r other; do
    [ -z "$other" ] || [ "$other" = "$work" ] ||
      die 1 "$rel is in progress in tmp/work/$other: resume it there, or start over (bash tests/caw-work.sh close $other --discard --start-over); nothing was created"
  done < <(works_recording "$rel")
}

# Records the request of a work (tmp/work/<work>/.request) and says so.
record_request() {
  printf '%s/doing/%s\n' "$requests" "$2" >"$work_root/$1/.request"
  echo "request: $requests/doing/$2 (in progress in tmp/work/$1)"
}

# Prints one "stale:" line per file of maintainers/requests/doing/ at the root that no work of tmp/work/ records.
stale_requests() {
  local f rel
  for f in "$root/$requests/doing"/*; do
    [ -f "$f" ] || continue
    rel="$requests/doing/${f##*/}"
    [ -z "$(works_recording "$rel")" ] || continue
    echo "stale: $rel (no work here records it: /caw-request ${f##*/} resumes it or starts over)"
  done
}

# open: the clone, its branch from origin/developer (or, with --resume, from the remote branch), its hooks and the
# first push; with --request, the request of the work recorded.
cmd_open() {
  local branch="" request="" resume=0 resumed=0 slug work clone url c found remote_refs start
  local usage_line="usage: open <type>/<slug> [--request <name>] [--resume]"
  while [ $# -gt 0 ]; do
    case "$1" in
      --help | -h) usage; return 0 ;;
      --request) [ $# -ge 2 ] && [ -n "$2" ] || die 2 "--request needs a file name"; request="$2"; shift ;;
      --resume) resume=1 ;;
      -*) die 2 "$usage_line" ;;
      *) [ -z "$branch" ] || die 2 "$usage_line"; branch="$1" ;;
    esac
    shift
  done
  [ -n "$branch" ] || die 2 "$usage_line"
  case "$branch" in developer | main) die 2 "refused: $branch is never a work branch" ;; esac
  [[ "$branch" =~ $branch_re ]] || die 2 "<type>/<slug> must be one of feat fix docs refactor test chore perf build ci style, a / and a kebab-case slug: $branch"
  slug="${branch#*/}"
  case "$slug" in developer | main) die 2 "refused: $branch would read as the base $slug" ;; esac
  [ -z "$request" ] || check_request_name "$request"
  ! git -C "$root" show-ref -q --verify "refs/tags/$branch" || die 1 "refused: $branch is the name of a tag"
  for c in "$work_root"/*/"$clone_dir"; do
    found="$(clone_branch "$c")" || continue
    if [ "$found" = "$branch" ]; then
      work="$(basename "$(dirname "$c")")"
      [ -z "$request" ] || check_request_record "$work" "$request"
      copy_language "$c"
      echo "path: ${c#"$root"/} (already open)"
      [ -z "$request" ] || record_request "$work" "$request"
      return 0
    fi
  done
  work="$(date +%Y-%m-%d)-$slug"
  clone="$work_root/$work/$clone_dir"
  [ ! -e "$clone" ] || die 1 "tmp/work/$work/$clone_dir is open already for $(clone_branch "$clone" || echo 'something else'), not $branch: choose another slug"
  [ -z "$request" ] || check_request_record "$work" "$request"
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
  if [ -n "$request" ] && ! git -C "$clone" cat-file -e "refs/remotes/origin/developer:$requests/doing/$request" 2>/dev/null; then
    abandon "$requests/doing/$request is not on origin/developer: run bash tests/caw-work.sh start $request first"
  fi
  remote_refs="$(with_timeout 60 git -C "$clone" ls-remote origin "refs/tags/$branch" "refs/heads/$branch")" ||
    abandon "could not read origin"
  start=refs/remotes/origin/developer
  case "$remote_refs" in
    *refs/tags/*) abandon "refused: $branch is the name of a tag on origin" ;;
    *refs/heads/*)
      [ "$resume" -eq 1 ] || abandon "$branch is on origin already with no clone here: choose another slug (or --resume to go on with it)"
      git -C "$clone" rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null || abandon "could not fetch $branch from origin"
      start="refs/remotes/origin/$branch"
      resumed=1
      ;;
    *) [ "$resume" -eq 0 ] || echo "attention: $branch is not on origin: it starts from origin/developer" ;;
  esac
  git -C "$clone" switch -q --no-track -c "$branch" "$start"
  git -C "$clone" for-each-ref --format='%(refname:short)' refs/heads | while IFS= read -r c; do
    [ "$c" = "$branch" ] || git -C "$clone" branch -q -D "$c"
  done
  git -C "$clone" config caw.branch "$branch"
  write_hooks "$clone"
  copy_language "$clone"
  if [ "$resumed" -eq 1 ]; then
    git -C "$clone" branch -q --set-upstream-to="origin/$branch"
    git -C "$clone" config caw.pushed "$(git -C "$clone" rev-parse HEAD)"
    echo "resumed: $branch from origin ($(git -C "$clone" rev-parse --short HEAD))"
  elif with_timeout 120 git -C "$clone" push -q -u origin "HEAD:refs/heads/$branch"; then
    git -C "$clone" config caw.pushed "$(git -C "$clone" rev-parse HEAD)"
    echo "pushed: $branch"
  else
    echo "attention: the first push of $branch failed (above); the next commit pushes it again"
  fi
  echo "path: tmp/work/$work/$clone_dir"
  [ -z "$request" ] || record_request "$work" "$request"
}

# Prints one line per reason run refuses a command; prints nothing when it may run. run is an allowlist: git with the
# listed subcommands, a script file of the clone through bash, sh or python3, and the listed tools; every path it names
# stays inside the clone and out of its git dir.
refused_args() {
  local clone="$1"
  shift
  python3 -I - "$clone" "$(git -C "$clone" rev-parse --absolute-git-dir)" "$(git -C "$clone" remote)" "$@" <<'PY'
import os
import sys

NOT_LISTED = "not on run's list: run it as a plain command (the permission mode decides)"
TOOLS = {
    "shellcheck", "shfmt", "ruff", "markdownlint-cli2", "sha256sum", "wc", "diff", "cat", "head", "tail", "ls", "grep",
    "find", "mkdir", "touch", "cp", "mv", "rm", "chmod",
}
FIND_ACTIONS = {"-exec", "-execdir", "-ok", "-okdir", "-delete", "-fprint", "-fprint0", "-fprintf", "-fls"}
# The git subcommands of run and, for each, the options it may take, matched exactly (git accepts abbreviated long
# options and grouped short flags, so nothing is matched by prefix): long flags, long options with a value (--opt=value
# or --opt value), short flags, short options with a value (the last of a group: attached, or the next argument).
FMT = {"--format", "--pretty"}
READ = {"--stat", "--name-only", "--name-status", "--oneline", "--no-color", "--patch", "--shortstat", "--numstat"}
GIT_OPTIONS = {
    "add": ({"--all", "--update", "--intent-to-add", "--dry-run", "--verbose"}, set(), "AuNnv", ""),
    "commit": ({"--amend", "--no-edit", "--allow-empty", "--all", "--quiet"}, {"--message", "--file", "--fixup"}, "aq", "mFC"),
    "status": ({"--short", "--porcelain", "--branch"}, set(), "sb", ""),
    "diff": (READ | {"--cached", "--staged", "--check"}, {"--diff-filter"}, "pw", "U"),
    "show": (READ | {"--no-patch"}, FMT, "ps", ""),
    "log": (READ | {"--graph", "--all", "--reverse", "--first-parent", "--no-merges", "--merges", "--decorate"},
            FMT | {"--since", "--until", "--author", "--grep", "--max-count"}, "p", "n"),
    "restore": ({"--staged", "--worktree"}, {"--source"}, "SW", "s"),
    "switch": ({"--detach", "--quiet"}, {"--create"}, "q", "c"),
    "checkout": ({"--quiet"}, set(), "q", "b"),
    "branch": ({"--list", "--show-current", "--all", "--verbose", "--merged", "--no-merged"}, set(), "ladDv", ""),
    "merge": ({"--no-edit", "--ff-only", "--no-ff", "--abort", "--continue", "--quiet"}, {"--message"}, "q", "m"),
    "rebase": ({"--continue", "--abort", "--skip", "--quiet"}, {"--onto"}, "q", ""),
    "reset": ({"--soft", "--mixed", "--hard", "--quiet"}, set(), "q", ""),
    "stash": ({"--include-untracked", "--keep-index", "--quiet"}, {"--message"}, "uq", "m"),
    "mv": ({"--force", "--dry-run", "--verbose"}, set(), "fnkv", ""),
    "rm": ({"--cached", "--force", "--quiet", "--dry-run"}, set(), "rfqn", ""),
    "rev-parse": ({"--short", "--abbrev-ref", "--show-toplevel", "--verify", "--quiet", "--symbolic-full-name"}, set(), "q", ""),
    "ls-files": ({"--others", "--exclude-standard", "--cached", "--modified", "--deleted", "--stage"}, set(), "ocmdsz", ""),
    "blame": (set(), set(), "w", "L"),
    "cherry-pick": ({"--continue", "--abort", "--skip", "--no-commit", "--no-edit"}, set(), "n", ""),
    "revert": ({"--continue", "--abort", "--skip", "--no-commit", "--no-edit"}, set(), "n", ""),
    "fetch": ({"--prune", "--quiet"}, set(), "qp", ""),
    "grep": (set(), set(), "nilcwEF", "e"),
    "config": ({"--get", "--get-all", "--list"}, set(), "l", ""),
}


def resolve(clone, value):
    """Return the real path a value names, relative to the clone when it is not absolute."""
    return os.path.realpath(value if os.path.isabs(value) else os.path.join(clone, value))


def under(path, folder):
    """Return True when a real path is the folder or inside it."""
    return path == folder or path.startswith(folder + os.sep)


def path_reason(clone, gitdirs, value):
    """Return why a value names a path run refuses (outside the clone, or in its git dir), or an empty string."""
    if value in ("", "/dev/null"):
        return ""
    if value.startswith("~"):
        return "a path under ~ is outside the clone"
    path = resolve(clone, value)
    if not under(path, clone):
        return "a path outside the clone"
    if any(under(path.lower(), g.lower()) for g in gitdirs):
        return "a path in the clone's git dir (.git, its hooks and config)"
    return ""


def candidates(arg):
    """Return the values of an argument that may name a path: itself, the value of --opt=value, and every attached
    value of a short-option cluster (-t<dir>, -at<dir>)."""
    values = [arg]
    if arg.startswith("--") and "=" in arg:
        values.append(arg.split("=", 1)[1])
    elif arg.startswith("-") and not arg.startswith("--") and len(arg) > 2:
        values.extend(arg[k:] for k in range(2, len(arg)))
    return values


def git_positionals(sub, args):
    """Return the arguments of a git subcommand that are not options, and why an option is not on its list."""
    longs, long_values, shorts, short_values = GIT_OPTIONS[sub]
    positional, i = [], 0
    while i < len(args):
        arg = args[i]
        i += 1
        if arg == "--":
            return positional + args[i:], ""
        if arg.startswith("--"):
            name, eq, _ = arg.partition("=")
            if name in longs and not eq:
                continue
            if name in long_values and (eq or i < len(args)):
                i += 0 if eq else 1
                continue
            return [], f"git {sub} {arg}: not on run's list of options for git {sub}"
        if arg.startswith("-") and arg != "-":
            if sub in ("log", "show") and arg[1:].isdigit():
                continue
            for k, letter in enumerate(arg[1:], start=1):
                if letter in short_values:
                    i += 0 if arg[k + 1 :] or i >= len(args) else 1
                    break
                if letter not in shorts:
                    return [], f"git {sub} {arg}: -{letter} is not on run's list of options for git {sub}"
            continue
        positional.append(arg)
    return positional, ""


def git_reason(args, remotes):
    """Return why a git call is not allowed (a subcommand or an option off run's list), or an empty string."""
    if not args or args[0] not in GIT_OPTIONS:
        return f"git {args[0] if args else ''}: {NOT_LISTED}"
    sub, rest = args[0], args[1:]
    positional, why = git_positionals(sub, rest)
    if why:
        return why
    if sub == "fetch" and (not positional or positional[0] not in remotes):
        return f"git fetch: name a remote of the clone ({', '.join(sorted(remotes)) or 'none'}), not a path or URL"
    if sub == "rebase" and len(positional) > 1:
        return "git rebase: one upstream ref at most"
    if sub == "config" and not any(a in ("--get", "--get-all", "--list") or a == "-l" for a in rest):
        return "git config: only --get, --get-all, --list or -l"
    return ""


def script_reason(clone, gitdirs, name, args):
    """Return why bash/sh/python3 is refused: it runs only a script file of the clone (python3: or -m pytest or
    unittest), with no interpreter option before it."""
    if name == "python3" and len(args) >= 2 and args[0] == "-m":
        return "" if args[1] in ("pytest", "unittest") else "python3 -m: only pytest or unittest"
    if not args or args[0].startswith("-"):
        return f"{name} runs a script file of the clone, with no option before it"
    path = resolve(clone, args[0])
    if path_reason(clone, gitdirs, args[0]) or not os.path.isfile(path):
        return f"{args[0]} is not a script file of the clone"
    return ""


def command_reason(clone, gitdirs, remotes, argv):
    """Return why the program of the command, or how it is called, is not on run's list, or an empty string."""
    name, rest = argv[0], argv[1:]
    if name == "git":
        return git_reason(rest, remotes)
    if name in ("bash", "sh", "python3"):
        return script_reason(clone, gitdirs, name, rest)
    if name not in TOOLS:
        return f"{name}: {NOT_LISTED}"
    if name == "find":
        hit = [a for a in rest if a in FIND_ACTIONS]
        return f"find {hit[0]} runs, deletes or writes: {NOT_LISTED}" if hit else ""
    if name in ("rm", "mv", "chmod"):
        recursive = any(a == "--recursive" or (a.startswith("-") and not a.startswith("--") and "R" in a) for a in rest)
        targets = [a for a in rest if not a.startswith("-")]
        if name == "mv":
            targets = targets[:-1]
        if (name != "chmod" or recursive) and any(resolve(clone, a) == clone for a in targets):
            return f"{name} on the clone itself"
    return ""


def main():
    """Print each reason run refuses the command sys.argv[4:] in the clone sys.argv[1] (git dir sys.argv[2], remote
    names sys.argv[3], one per line)."""
    clone = os.path.realpath(sys.argv[1])
    gitdirs = {os.path.realpath(sys.argv[2]), os.path.join(clone, ".git")}
    remotes = set(sys.argv[3].split())
    argv = sys.argv[4:]
    if "--accept-terms" in argv:
        print("  --accept-terms: the owner confirms it: run it as a plain command (the settings ask the owner)")
    for arg in argv[1:]:
        for value in candidates(arg):
            why = path_reason(clone, gitdirs, value)
            if why:
                print(f"  {arg}: {why}")
                break
    why = command_reason(clone, gitdirs, remotes, argv)
    if why:
        print(f"  {why}")


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
  copies_status "$clone"
}

# Runs the product's agent-copy.py of this repository (the Docker copy of a task: up, list, destroy).
agent_copy() {
  python3 -I "$root/workspace/scripts/agent-copy.py" "$@"
}

# Prints the groups the override files of a work folder record (agent-*.compose.yaml, their name: line).
work_groups() {
  local file
  for file in "$1"/agent-*.compose.yaml; do
    [ -f "$file" ] && sed -n 's/^name: "\(agent_[0-9a-z_-]*\)"$/\1/p' "$file" | head -n 1
  done
  return 0
}

# Prints the "copy:" lines of one clone, or "Docker: not reachable" once per run (docker_down records it).
docker_down=0
copies_status() {
  local clone="$1" args group state ports out rc=0
  [ "$docker_down" -eq 0 ] || return 0
  args=(--under "$clone")
  while IFS= read -r group; do [ -z "$group" ] || args+=(--group "$group"); done < <(work_groups "$(dirname "$clone")")
  { command -v docker >/dev/null 2>&1 && [ -f "$root/workspace/scripts/agent-copy.py" ]; } || rc=3
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

# Destroys the Docker copy groups of a work folder (its override files' groups and the agent_ projects whose compose
# folder lies in one of its clones), by label and agent_ name only. Returns non-zero when one was not destroyed.
destroy_copies() {
  local folder="$1" args=() group entry
  while IFS= read -r group; do [ -z "$group" ] || args+=("$group"); done < <(work_groups "$folder")
  for entry in "$folder"/*/; do [ -e "${entry}.git" ] && args+=(--under "${entry%/}"); done
  [ "${#args[@]}" -gt 0 ] || return 0
  { command -v docker >/dev/null 2>&1 && [ -f "$root/workspace/scripts/agent-copy.py" ]; } ||
    { echo "Docker: not reachable: no copy destroyed"; return 1; }
  agent_copy destroy "${args[@]}" 2>&1
}

# Prints the group of a work: agent_<MMDD>-<slug>.
work_group() {
  echo "agent_${1:5:2}${1:8:2}-${1:11}"
}

# Publishes one tool of the clone as a copy in its own group, with the installed workspace's configuration.
publish_tool() {
  local clone="$1" work="$2" tool="$3" dir ws custom args=() rc=0
  dir="$clone/workspace/tools/$tool"
  if [ ! -f "$dir/compose.yaml" ]; then
    echo "nothing to publish for workspace/tools/$tool: it has no compose.yaml"
    return 0
  fi
  ws="${AIWP_WORKSPACE:-$HOME/Development/ai-workspace}"
  custom="$ws/custom"
  [ ! -f "$custom/env/$tool.env" ] || args+=(--env-file "$custom/env/$tool.env")
  echo "copy: workspace/tools/$tool"
  if [ -d "$custom" ]; then
    AIWP_CUSTOM_DIR="$custom" agent_copy up "$(work_group "$work")--$tool" "$dir" "$work_root/$work/agent-$tool.compose.yaml" \
      ${args[@]+"${args[@]}"} --custom-root "$clone/workspace/custom" --allow-root "$clone" --allow-root "$custom" || rc=$?
  else
    echo "attention: $custom not found (AIWP_WORKSPACE): the copy runs without the installed configuration"
    agent_copy up "$(work_group "$work")--$tool" "$dir" "$work_root/$work/agent-$tool.compose.yaml" --allow-root "$clone" || rc=$?
  fi
  return "$rc"
}

# Builds a test installation from the clone (tests/test-install.sh) and prints where it is.
publish_install() {
  local clone="$1" work="$2" log rc=0
  log="$work_root/$work/agent-test-install.log"
  echo "test installation: from tmp/work/$work/$clone_dir (log: ${log#"$root"/})"
  if [ -n "${CAW_TEST_INSTALL:-}" ]; then
    "$CAW_TEST_INSTALL" "$clone" >"$log" 2>&1 || rc=$?
  else
    (cd "$clone" && bash tests/test-install.sh) >"$log" 2>&1 || rc=$?
  fi
  grep -E '^(test installation:|workspace:|open a session:|result:|FAIL )' "$log" | sed 's/^/  /' || true
  if [ "$rc" -eq 0 ]; then echo "published: test installation (above)"; else echo "error: the test installation failed (exit $rc): ${log#"$root"/}"; fi
  return "$rc"
}

# publish: by what the clone changed against origin/developer, a tool copy, a test installation, or nothing.
cmd_publish() {
  [ $# -eq 1 ] || die 2 "usage: publish <work>[/<clone>]"
  local clone work path install=0 tools=() tool seen=" " rc=0
  case "$1" in --help | -h) usage; return 0 ;; esac
  clone="$(clone_path "$1")"
  work="$(basename "$(dirname "$clone")")"
  fetch_origin "$clone" || echo "attention: origin not fetched: compared with origin/developer as of the last fetch"
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      install.sh | tests/test-install.sh | workspace/scripts/* | workspace/rules/* | workspace/AGENTS.md | workspace/CLAUDE.md | .claude/*)
        install=1 ;;
      workspace/tools/*/*.md | workspace/tools/*/docs/*) ;;
      workspace/tools/*/*)
        tool="${path#workspace/tools/}"
        tool="${tool%%/*}"
        case "$seen" in *" $tool "*) ;; *) seen+="$tool "; tools+=("$tool") ;; esac
        ;;
    esac
  done < <(
    git -C "$clone" diff --name-only refs/remotes/origin/developer --
    git -C "$clone" ls-files --others --exclude-standard
  )
  if [ "${#tools[@]}" -eq 0 ] && [ "$install" -eq 0 ]; then
    echo "nothing to publish: no tool, installer, hook, script or rule changed"
    return 0
  fi
  for tool in ${tools[@]+"${tools[@]}"}; do
    publish_tool "$clone" "$work" "$tool" || rc=1
  done
  [ "$install" -eq 0 ] || publish_install "$clone" "$work" || rc=1
  return "$rc"
}

# status: every work, or one, with the request it records and each clone; with no work given, the stale requests of
# maintainers/requests/doing/ last.
cmd_status() {
  local work clone rel found=0 works=()
  case "${1:-}" in --help | -h) usage; return 0 ;; esac
  if [ $# -ge 1 ]; then
    [[ "$1" =~ $work_re ]] || die 2 "usage: status [<work>]"
    works=("$work_root/$1")
  else
    works=("$work_root"/*)
  fi
  for work in "${works[@]}"; do
    [ -d "$work" ] || continue
    rel="$(work_request "${work##*/}")"
    if [ -n "$rel" ]; then
      if [ -f "$root/$rel" ]; then
        echo "tmp/work/${work##*/}  request=$rel"
      else
        echo "tmp/work/${work##*/}  request=$rel (missing)"
      fi
    fi
    for clone in "$work"/*/; do
      [ -e "${clone}.git" ] || continue
      found=1
      clone_status "${clone%/}"
    done
  done
  [ "$found" -eq 1 ] || echo "no clone under tmp/work/${1:-}"
  [ $# -ge 1 ] || stale_requests
}

# Deletes the work branch of a clone on origin for a start over, from this repository: only a work branch, never
# developer or main, with --force-with-lease against the sha the clone pushed last (caw.pushed, only that: a tracking
# ref a fetch moved may hold a commit pushed from elsewhere), so a commit pushed there from elsewhere is never deleted.
# Returns 1 when the branch stays.
delete_for_start_over() {
  local clone="$1" branch url remote pushed
  branch="$(clone_branch "$clone")" || { echo "refused: ${clone#"$root"/} is not a clone made by open" >&2; return 1; }
  if [[ ! "$branch" =~ $branch_re ]]; then
    echo "refused: $branch is not a work branch: never deleted" >&2
    return 1
  fi
  case "${branch#*/}" in developer | main) echo "refused: $branch reads as a base: never deleted" >&2; return 1 ;; esac
  url="$(git -C "$clone" remote get-url origin 2>/dev/null)" || { echo "refused: ${clone#"$root"/} has no origin" >&2; return 1; }
  remote="$(with_timeout 60 git -C "$root" ls-remote "$url" "refs/heads/$branch")" ||
    { echo "refused: origin cannot be read: $branch stays" >&2; return 1; }
  if [ -z "$remote" ]; then
    echo "not on origin: $branch"
    return 0
  fi
  # The lease is only the sha this clone pushed: its tracking ref may hold a commit another clone pushed.
  pushed="$(git -C "$clone" config --get caw.pushed || true)"
  if [ -z "$pushed" ]; then
    echo "refused: ${clone#"$root"/} records no sha it pushed (caw.pushed): $branch stays on origin, since what it holds may have been pushed from elsewhere; the owner checks it (git log origin/$branch) and deletes it by hand at the root (git push origin --delete $branch), then closes again; or the work goes on in this clone instead" >&2
    return 1
  fi
  if with_timeout 120 git -C "$root" push -q --force-with-lease="refs/heads/$branch:$pushed" "$url" ":refs/heads/$branch" 2>/dev/null; then
    echo "deleted on origin: $branch (start over)"
    return 0
  fi
  echo "refused: $branch could not be deleted on origin (a commit pushed there from elsewhere, or origin refused): it stays" >&2
  return 1
}

# close: deletes a work folder when nothing in it would be lost, and the remote branch of each clone once it is in
# developer; --discard deletes the folder anyway and leaves the remote branches, after putting the request the work
# records back to pending; --start-over deletes the remote work branches first and keeps the request in doing/.
cmd_close() {
  local work="" discard=0 start_over=0 entry name branch url i problems="" gone=() branches=() urls=() rel="" request=""
  local failed=0 usage_line="usage: close <work> [--discard [--start-over]]"
  while [ $# -gt 0 ]; do
    case "$1" in
      --help | -h) usage; return 0 ;;
      --discard) discard=1 ;;
      --start-over) start_over=1 ;;
      -*) die 2 "$usage_line" ;;
      *) [ -z "$work" ] || die 2 "$usage_line"; work="$1" ;;
    esac
    shift
  done
  [[ "$work" =~ $work_re ]] || die 2 "$usage_line"
  [ "$start_over" -eq 0 ] || [ "$discard" -eq 1 ] || die 2 "--start-over goes with --discard: close <work> --discard --start-over"
  [ -d "$work_root/$work" ] || die 1 "not found: tmp/work/$work"
  if [ "$discard" -eq 0 ]; then
    for entry in "$work_root/$work"/* "$work_root/$work"/.[!.]*; do
      [ -e "$entry" ] || continue
      name="${entry##*/}"
      case "$name" in agent-*.compose.yaml | agent-*.ports.env | agent-test-install.log | .request) continue ;; esac
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
    # What the remote deletes need, read before the clones go: the branch and the clone's origin URL.
    for entry in ${gone[@]+"${gone[@]}"}; do
      branch="$(clone_branch "$entry")"
      url="$(git -C "$entry" remote get-url origin 2>/dev/null)" || url=""
      branches+=("$branch")
      urls+=("$url")
    done
  fi
  rel="$(work_request "$work")"
  request="${rel#"$requests"/doing/}"
  if [ -n "$rel" ] && [ "$discard" -eq 1 ] && [ "$start_over" -eq 0 ]; then
    # The request goes back to pending before anything is deleted: a refusal keeps the work as it is.
    fetch_root || die 1 "could not fetch origin at the root: $rel was not put back; nothing was deleted"
    if git -C "$root" cat-file -e "refs/remotes/origin/developer:$rel" 2>/dev/null; then
      (move_request "$request" doing "chore(requests): put back $request" "- tmp/work/$work discarded: the request is pending again") ||
        die 1 "tmp/work/$work was not deleted: fix what the lines above say and close again"
      echo "request: $requests/$request (pending again)"
    else
      echo "attention: $rel is not on origin/developer (moved or put back already): no request to move"
    fi
  fi
  if [ "$start_over" -eq 1 ]; then
    # The remote work branches go first: one that stays keeps the folder, so the close can run again.
    for entry in "$work_root/$work"/*/; do
      [ -e "${entry}.git" ] || continue
      branches+=("$(clone_branch "${entry%/}" || true)")
      delete_for_start_over "${entry%/}" || failed=1
    done
    [ "$failed" -eq 0 ] || die 1 "refused: a remote work branch of tmp/work/$work stays (above); nothing else was deleted"
  fi
  destroy_copies "$work_root/$work" || echo "attention: a Docker copy group of tmp/work/$work was not destroyed (above); the folder goes anyway"
  if ! remove_folder "$work_root/$work"; then
    echo "error: could not delete tmp/work/$work completely (above)" >&2
    find "$work_root/$work" -mindepth 1 -maxdepth 1 2>/dev/null | head -n 5 | while IFS= read -r entry; do
      echo "left: ${entry#"$root"/}" >&2
    done
    if [ "$discard" -eq 0 ]; then
      for branch in ${branches[@]+"${branches[@]}"}; do
        echo "the remote branch stays: $branch (deleted only once the folder is gone)" >&2
      done
    fi
    echo "make what is left deletable and close again (--discard once it is no longer a clone)" >&2
    exit 1
  fi
  if [ "$start_over" -eq 1 ]; then
    echo "discarded: tmp/work/$work (started over: its remote work branch is deleted)"
    [ -z "$rel" ] || echo "request: $rel stays in doing/; next: bash tests/caw-work.sh open ${branches[0]:-<type>/<slug>} --request $request"
    return 0
  fi
  if [ "$discard" -eq 1 ]; then echo "discarded: tmp/work/$work (the remote branch stays)"; else echo "closed: tmp/work/$work"; fi
  for i in ${branches[@]+"${!branches[@]}"}; do
    delete_remote_branch "${urls[$i]}" "${branches[$i]}"
  done
  if [ -n "$rel" ] && [ "$discard" -eq 0 ] && [ -f "$root/$rel" ]; then
    echo "attention: $rel is still in doing/ at the root: /caw-merge moves it to qa/; status lists it as stale until then"
  fi
  return 0
}

# Deletes a work folder: makes what it holds writable for the owner first (a test installation leaves its core 555 and
# 444), never following a symlink out of it (chmod -R, -P being the default on Linux and macOS, does not follow the
# symlinks it meets; a work folder that is itself a symlink is only unlinked). Returns non-zero unless it is all gone.
remove_folder() {
  local dir="$1"
  [ -L "$dir" ] || chmod -R u+rwX "$dir" 2>/dev/null || true
  rm -rf "${dir:?}" || true
  [ ! -e "$dir" ] && [ ! -L "$dir" ]
}

# Deletes a work branch on the remote <url> of its clone, once the clone is gone, from this repository (a plain push
# --delete, never forced; only a name of a work branch, never developer, main or a tag).
delete_remote_branch() {
  local url="$1" branch="$2"
  if [[ ! "$branch" =~ $branch_re ]] || [ -z "$url" ]; then
    echo "attention: $branch was not deleted on origin: not a work branch or no origin URL; delete it by hand"
  elif with_timeout 120 git -C "$root" push -q "$url" --delete "refs/heads/$branch"; then
    echo "deleted on origin: $branch (it is in developer)"
  else
    echo "attention: could not delete $branch on origin; it is in developer, delete it by hand"
  fi
}

# Prints why a push that is not a fast-forward of <remote ref> at <remote sha> is refused, and how to keep the change.
force_refused() {
  echo "caw-work: refused: $1 on the remote (${2:0:12}) is not in what this push sends: that is a force push, which a work clone never does (an amend or a rebase of pushed commits)." >&2
  echo "caw-work: to keep the change, commit it on top of what is pushed: git reset --soft ${2:0:12}, then git commit" >&2
}

# Pushes the recorded branch of a clone, never forced, after its own terms scan of what leaves and through the
# clone's pre-push hook; with <accept> 1 the company terms that match are accepted first (scan_leaving). Returns 0
# when it is pushed, 1 when not, with the reason or the warning and what to do on stderr.
push_branch() {
  local clone="$1" accept="${2:-0}" branch current pushed sha rc=0
  branch="$(clone_branch "$clone")" || { echo "caw-work: not a clone made by open: $clone" >&2; return 1; }
  [[ "$branch" =~ $branch_re ]] || { echo "caw-work: refused: the recorded branch $branch is not a work branch" >&2; return 1; }
  current="$(git -C "$clone" symbolic-ref -q --short HEAD)" || current=""
  if [ "$current" != "$branch" ]; then
    echo "caw-work: HEAD is not on $branch: nothing pushed" >&2
    return 1
  fi
  # git would reject a rewrite of pushed commits as non-fast-forward before the pre-push hook: say why here.
  pushed="$(git -C "$clone" rev-parse -q --verify "refs/remotes/origin/$branch" || true)"
  if [ -n "$pushed" ] && ! git -C "$clone" merge-base --is-ancestor "$pushed" HEAD; then
    force_refused "refs/heads/$branch" "$pushed"
    echo "caw-work: NOT pushed: the commit stays only in this clone" >&2
    return 1
  fi
  # The scan runs here, before git push, so a pre-push hook removed or bypassed in the clone never lets a term out;
  # the hook scans again as a second check.
  scan_leaving "$clone" origin "$(git -C "$clone" rev-parse HEAD)" "$accept" || rc=$?
  case "$rc" in
    0) ;;
    3)
      echo "caw-work: NOT pushed, waiting for the owner (a warning, not an error): the commit stays only in this clone" >&2
      return 1
      ;;
    *)
      echo "caw-work: NOT pushed: the commit stays only in this clone; fix what the lines above say, then commit again or push: bash tests/caw-work.sh push ${clone#"$work_root"/}" >&2
      return 1
      ;;
  esac
  sha="$(git -C "$clone" rev-parse HEAD)"
  if with_timeout 120 git -C "$clone" -c "core.hooksPath=$(git -C "$clone" rev-parse --absolute-git-dir)/hooks" \
    push -q origin "HEAD:refs/heads/$branch"; then
    # The lease of a start over (close --discard --start-over): the sha this clone pushed last.
    git -C "$clone" config caw.pushed "$sha"
    echo "caw-work: pushed $branch $(git -C "$clone" rev-parse --short "$sha")"
    return 0
  fi
  echo "caw-work: NOT pushed: the commit stays only in this clone. Fix what the lines above say (an amend or a rebase of commits not on the remote is fine), then commit again, or push: bash tests/caw-work.sh push ${clone#"$work_root"/}" >&2
  return 1
}

# _autopush: the post-commit, post-merge and post-rewrite hooks. Pushes the recorded branch; never fails the commit.
cmd_autopush() {
  local clone="$1" kind="${2:-}" gitdir
  # An amend fires post-commit and then post-rewrite: post-commit already pushed it.
  [ "$kind" != amend ] || return 0
  # Inside a rebase HEAD is detached and each picked commit fires post-commit: post-rewrite pushes at the end.
  git -C "$clone" symbolic-ref -q HEAD >/dev/null || return 0
  gitdir="$(git -C "$clone" rev-parse --absolute-git-dir)"
  if [ "$kind" != rebase ] && { [ -d "$gitdir/rebase-merge" ] || [ -d "$gitdir/rebase-apply" ]; }; then return 0; fi
  push_branch "$clone" || true
}

# Scans what the revisions "<sha> --not <sha>..." bring for company terms: every version of a file their commits add
# or change (merges against each parent), the paths of those files (renames included: git log --no-renames lists the
# new path), their messages, and their author and committer names and e-mails. A work clone never pushes a tag
# (pre-push refuses refs/tags/*), so no tag message leaves. Prints each match; returns 0 when none, 1 on a match, 2 when
# the scan failed.
scan_commits() {
  local clone="$1" patterns="$2" line commit="" meta path mode sha seen=" " rc found=0 paths=""
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
    paths+="${commit:0:12} $path"$'\n'
    [ "$mode" != 160000 ] || continue
    case "$seen" in *" $sha "*) continue ;; esac
    seen+="$sha "
    rc=0
    git -C "$clone" cat-file blob "$sha" | terms_scan "$patterns" "${commit:0:12}:$path" || rc=$?
    case "$rc" in 0) ;; 1) found=1 ;; *) return 2 ;; esac
  done < <(git -C "$clone" -c core.quotePath=false log --format='commit %H' --raw --no-abbrev --no-renames -m "$@")
  rc=0
  printf '%s' "$paths" | terms_scan "$patterns" "path" || rc=$?
  case "$rc" in 0) ;; 1) found=1 ;; *) return 2 ;; esac
  rc=0
  git -C "$clone" log --format='%h author %an <%ae> committer %cn <%ce>' "$@" | terms_scan "$patterns" "identity" || rc=$?
  case "$rc" in 0) ;; 1) found=1 ;; *) return 2 ;; esac
  while IFS= read -r commit; do
    rc=0
    git -C "$clone" log -1 --format=%B "$commit" | terms_scan "$patterns" "${commit:0:12}:message" || rc=$?
    case "$rc" in 0) ;; 1) found=1 ;; *) return 2 ;; esac
  done < <(git -C "$clone" rev-list "$@")
  return "$found"
}

# Records the patterns <new> (one per line) as accepted for the terms list <list>, in its private file
# <list>.accepted (terms_accepted_file), created 600: only the ones not there yet, never printed. Refuses a file inside
# this repository that git does not ignore, and a path that is not a regular file. Returns 1 when it could not record.
accept_terms() {
  local list="$1" new="$2" file dir existing p count=0 why=""
  file="$(terms_accepted_file "$list")"
  if ! dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd -P)"; then
    echo "caw-work: refused: the folder of the terms list cannot be read" >&2
    return 1
  fi
  file="$dir/$(basename "$file")"
  case "$file" in
    "$root"/*)
      git -C "$root" check-ignore -q -- "$file" 2>/dev/null ||
        why="the accepted terms would be written inside this repository, in a file git does not ignore (${file#"$root"/}); keep the terms list outside it (AIWP_TERMS_FILE)"
      ;;
  esac
  if [ -z "$why" ] && { [ -L "$file" ] || { [ -e "$file" ] && [ ! -f "$file" ]; }; }; then
    why="$file is not a regular file"
  fi
  if [ -z "$why" ] && [ ! -e "$file" ]; then
    (umask 077 && printf '# Company terms the owner kept after the warning of tests/caw-work.sh push --accept-terms: lines of\n# the terms list next to this file, skipped by the terms scans. Delete a line to be warned about it again.\n' >"$file") ||
      why="could not write $file"
  fi
  [ -n "$why" ] || chmod 600 "$file" || why="could not make $file private (600)"
  existing="$(terms_patterns "$file" 2>/dev/null)"
  while [ -z "$why" ] && IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ -n "$existing" ] && printf '%s\n' "$existing" | grep -qxF -e "$p"; then continue; fi
    printf '%s\n' "$p" >>"$file" || why="could not write $file"
    existing+=$'\n'"$p"
    count=$((count + 1))
  done <<<"$new"
  if [ -n "$why" ]; then
    echo "caw-work: refused: $why" >&2
    return 1
  fi
  echo "caw-work: accepted by the owner: $count company term(s) of the lines above, recorded in $file (not printed); no scan reports them again" >&2
}

# Scans what pushing <sha> to <remote> sends: the commits of <sha> the remote does not have (git ls-remote, never the
# tracking refs), against the terms list less the accepted terms (terms_active). With <also> (a remote name, for a
# scratch destination: origin), the commits that remote has count as already sent too, read the same way: they were
# scanned when they left; that remote unreadable only widens the scan. With <accept> 1, the terms that match
# are recorded as accepted (accept_terms) and it may leave. Returns 0 when it may leave (no match, only accepted terms,
# no terms list: SKIP), 1 when refused (AIWP_TERMS_FILE naming no file, the remote unreadable, the scan failed, the
# accepted terms not recorded), 3 when a company term would leave: the WARNING is printed, after the matching lines.
scan_leaving() {
  local clone="$1" remote="$2" local_sha="$3" accept="${4:-0}" also="${5:-}" list patterns remote_list known=() sha rc=0
  local p matched=""
  list="$(terms_list "$root")" || {
    echo "caw-work: refused: AIWP_TERMS_FILE names no file: $AIWP_TERMS_FILE" >&2
    return 1
  }
  if [ -z "$list" ]; then
    echo "SKIP terms scan: no terms list" >&2
    return 0
  fi
  if [ -z "$(terms_patterns "$list")" ]; then
    echo "SKIP terms scan: the terms list holds no term" >&2
    return 0
  fi
  patterns="$(terms_active "$list")"
  [ -n "$patterns" ] || return 0
  remote_list="$(with_timeout 60 git -C "$clone" ls-remote "$remote" 'refs/heads/*' 2>/dev/null)" || {
    echo "caw-work: refused: the remote cannot be read to know what is already there" >&2
    return 1
  }
  if [ -n "$also" ]; then
    if sha="$(with_timeout 60 git -C "$clone" ls-remote "$also" 'refs/heads/*' 2>/dev/null)"; then
      remote_list+=$'\n'"$sha"
    else
      echo "caw-work: $also cannot be read: the terms scan covers every commit this push sends" >&2
    fi
  fi
  while read -r sha _; do
    [ -n "$sha" ] && git -C "$clone" cat-file -e "$sha^{commit}" 2>/dev/null && known+=("$sha")
  done <<<"$remote_list"
  scan_commits "$clone" "$patterns" "$local_sha" --not ${known[@]+"${known[@]}"} >&2 || rc=$?
  case "$rc" in
    0) return 0 ;;
    1) ;;
    *)
      echo "caw-work: refused: the terms scan failed" >&2
      return 1
      ;;
  esac
  if [ "$accept" -ne 1 ]; then
    echo "WARNING: a company term in what this push would send (the lines above: <commit>:<path>, <commit>:message, path or identity, then :<line>:<text>; never paste them into an issue, a commit or a pull request) — this repository is public: once pushed, anyone can read it — keep it: bash tests/caw-work.sh push ${clone#"$work_root"/} --accept-terms (the owner confirms; that term is not asked again), or rewrite the commits not on the remote without it (git commit --amend, or git reset --soft to the pushed commit and commit again)" >&2
    return 3
  fi
  # The lines of the list that matched: each pattern scanned on its own, so only a term seen above is accepted.
  while IFS= read -r p; do
    rc=0
    scan_commits "$clone" "$p" "$local_sha" --not ${known[@]+"${known[@]}"} >/dev/null 2>&1 || rc=$?
    case "$rc" in
      0) ;;
      1) matched+="$p"$'\n' ;;
      *)
        echo "caw-work: refused: the terms scan failed" >&2
        return 1
        ;;
    esac
  done <<<"$patterns"
  accept_terms "$list" "$matched"
}

# Returns 0 when <remote>, as git gives it to the pre-push hook, is a scratch destination of <clone>: an absolute path
# (never a named remote, never a URL) to a folder strictly inside the clone's own tmp/, symbolic links resolved. The
# throwaway repository of tests/test-install.sh lives there; nothing pushed there leaves the machine.
scratch_destination() {
  local clone="$1" remote="$2" top real
  case "$remote" in /*) ;; *) return 1 ;; esac
  ! git -C "$clone" remote | grep -qxF -e "$remote" || return 1
  top="$(cd -P -- "$clone" 2>/dev/null && pwd -P)" || return 1
  real="$(cd -P -- "$remote" 2>/dev/null && pwd -P)" || return 1
  case "$real" in "$top"/tmp/?*) return 0 ;; esac
  return 1
}

# _prepush: the pre-push hook. Reads every "<local ref> <local sha> <remote ref> <remote sha>" line first, then refuses
# the whole push for a protected or non-branch target or a force push, and scans what leaves for company terms. To a
# scratch destination (scratch_destination: the throwaway repository of tests/test-install.sh) any branch passes,
# developer and main included; a tag, a ref outside refs/heads/ and a force push stay refused, and the scan still runs.
cmd_prepush() {
  local clone="$1" remote="${2:-origin}" line lines=() i local_sha remote_ref remote_sha sends=0 scratch=0
  while IFS= read -r line; do [ -z "$line" ] || lines+=("$line"); done
  ! scratch_destination "$clone" "$remote" || scratch=1
  for i in ${lines[@]+"${!lines[@]}"}; do
    read -r _ local_sha remote_ref remote_sha <<<"${lines[$i]}"
    case "$remote_ref" in
      refs/heads/developer | refs/heads/main)
        if [ "$scratch" -eq 0 ]; then
          echo "caw-work: refused: a work clone never pushes ${remote_ref#refs/heads/}; /caw-merge moves it" >&2
          return 1
        fi
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
  for i in ${lines[@]+"${!lines[@]}"}; do
    read -r _ local_sha _ <<<"${lines[$i]}"
    [[ "$local_sha" =~ $zero_re ]] && continue
    if [ "$scratch" -eq 1 ]; then
      scan_leaving "$clone" "$remote" "$local_sha" 0 origin || return 1
    else
      scan_leaving "$clone" "$remote" "$local_sha" || return 1
    fi
  done
  return 0
}

[ $# -ge 1 ] || { usage >&2; exit 2; }
command="$1"
shift
case "$command" in
  --help | -h | help) usage ;;
  start) cmd_start "$@" ;;
  open) cmd_open "$@" ;;
  run) cmd_run "$@" ;;
  status) cmd_status "$@" ;;
  publish) cmd_publish "$@" ;;
  close) cmd_close "$@" ;;
  push)
    accept=0
    case "$#:${2:-}" in
      1:) ;;
      2:--accept-terms) accept=1 ;;
      *) die 2 "usage: push <work>[/<clone>] [--accept-terms]" ;;
    esac
    clone="$(clone_path "$1")"
    push_branch "$clone" "$accept"
    ;;
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
