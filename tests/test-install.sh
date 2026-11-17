#!/usr/bin/env bash
# shellcheck disable=SC2319  # check reads the status of the test right before it, on purpose
# Test installation from the current tree: snapshots the tree (commits and working changes, git-ignored files left
# out) into a throwaway bare repository tagged v$(cat workspace/VERSION), runs install.sh with a temp HOME and data
# folder and AIWP_WORKSPACE, with no terminal (the installer creates the workspace), and checks it. Writes only under tmp/test-install/<timestamp>/.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: bash tests/test-install.sh [--help]

Builds tmp/test-install/<timestamp>/ (git-ignored):
  remote.git/   a bare repository holding one commit: the current tree, committed and working changes, without the
                git-ignored files; tagged v<workspace/VERSION>
  home/, xdg/   the HOME and XDG_DATA_HOME of the installation (the data folder is xdg/claude-cli-agents-workspace)
  workspace/    the workspace the installer creates (AIWP_WORKSPACE, no terminal), with a local custom/ skeleton
Then checks: no .git at the workspace root; core files 444, executables 555, core folders 555; the writable folders
present and writable; the manifest lists exactly the files of workspace/ in the snapshot, with their sha256 and mode;
no file from outside workspace/ in the workspace; the workspace is in the registry; a project made by init-repo.sh
carries the marker and the UserPromptSubmit hook warns about one without it; aiwp repair finds nothing to repair.
It keeps this repository's CLAUDE.md and .claude/ out of a session there (.claude/settings.local.json) and prints
the command that opens one: the person's own HOME (the Claude Code login), the installation's data folder and a git
ceiling at the installation folder. Remove an installation with chmod -R u+w <dir> && rm -rf <dir>.

Exit codes: 0 every check passed; 1 a check failed; 2 usage error.
USAGE
}

case "${1:-}" in
  --help | -h) usage; exit 0 ;;
  "") ;;
  *) echo "error: unknown argument: $1; see --help" >&2; exit 2 ;;
esac

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
version="$(tr -d '[:space:]' <"$repo/workspace/VERSION")"
dir="$repo/tmp/test-install/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$dir"
echo "test installation: $dir"

# The snapshot: a temporary index over HEAD plus every change that git does not ignore.
index="$dir/snapshot.index"
GIT_INDEX_FILE="$index" git -C "$repo" read-tree HEAD
GIT_INDEX_FILE="$index" git -C "$repo" add -A
tree="$(GIT_INDEX_FILE="$index" git -C "$repo" write-tree)"
rm -f "$index"
commit="$(git -C "$repo" -c user.name=test-install -c user.email= commit-tree "$tree" -p HEAD -m "test installation snapshot")"
git init -q --bare "$dir/remote.git"
git -C "$repo" push -q "$dir/remote.git" "$commit:refs/heads/main"
git --git-dir="$dir/remote.git" tag "v$version" "$commit"
echo "snapshot: $commit tagged v$version"

ws="$dir/workspace"
export HOME="$dir/home" XDG_DATA_HOME="$dir/xdg" AIWP_REPO_URL="$dir/remote.git" AIWP_WORKSPACE="$ws"
mkdir -p "$HOME"
unset AIWP_REF AIWP_OS AIWP_TEST_DIE_AFTER_SWAPS
# With no controlling terminal (a new session), as under a pipe with nobody behind it: the installer asks nothing
# and creates the workspace in AIWP_WORKSPACE.
python3 -I -c 'import os, sys
pid = os.fork()
if pid == 0:
    os.setsid()
    os.execvp(sys.argv[1], sys.argv[1:])
sys.exit(os.waitstatus_to_exitcode(os.waitpid(pid, 0)[1]))' bash "$repo/install.sh" </dev/null
data="$XDG_DATA_HOME/claude-cli-agents-workspace"

# The checks: each records PASS or FAIL and the run goes on.
set +e
failed=0
# Records one check result: description, status.
check() {
  if [ "$2" -eq 0 ]; then echo "PASS $1"; else echo "FAIL $1"; failed=1; fi
}

[ "$(git -C "$data" describe --tags --exact-match HEAD)" = "v$version" ]; check "data folder at v$version" $?
[ -L "$HOME/.local/bin/aiwp" ]; check "aiwp linked in ~/.local/bin" $?
[ ! -e "$ws/.git" ]; check "no .git at the workspace root" $?
python3 -I -c 'import json, sys; sys.exit(0 if [w["path"] for w in json.load(open(sys.argv[1]))["workspaces"]] == [sys.argv[2]] else 1)' \
  "$data/workspaces.json" "$(cd "$ws" && pwd -P)"
check "the workspace is in the registry" $?
if ! python3 -I - "$ws" "$data" "$commit" <<'PY'
"""Checks modes, the manifest and that nothing from outside workspace/ reached the workspace."""
import hashlib
import json
import os
import subprocess
import sys

ws, data, commit = sys.argv[1:4]
writable_root = {"custom", "projects", "tmp", "logs", ".claude", ".history"}
failed = False


def report(name, ok, detail=""):
    """Prints one check result."""
    global failed
    print(("PASS " if ok else "FAIL ") + name + (f": {detail}" if detail and not ok else ""))
    failed = failed or not ok


manifest = json.load(open(os.path.join(ws, ".aiwp/manifest.json"), encoding="utf-8"))
listing = subprocess.run(
    ["git", "-C", data, "ls-tree", "-r", "--name-only", "-z", commit, "--", "workspace/"],
    capture_output=True, check=True,
).stdout.decode().split("\0")
writable_root = {"custom", "projects", "tmp", "logs", ".claude", ".history"}
# A file the repository tracks under a writable root folder (projects/README.md) is never installed.
expected = sorted(p[len("workspace/"):] for p in listing if p and p[len("workspace/"):].split("/")[0] not in writable_root)
paths = [f["path"] for f in manifest["files"]]
report("manifest lists exactly the files of workspace/ outside the writable folders", sorted(paths) == expected)
report("manifest commit is the snapshot", manifest["commit"] == commit)
bad = []
for f in manifest["files"]:
    p = os.path.join(ws, f["path"])
    digest = hashlib.sha256(open(p, "rb").read()).hexdigest()
    mode = format(os.stat(p).st_mode & 0o777, "o")
    if digest != f["sha256"] or mode != f["mode"] or mode not in ("444", "555"):
        bad.append(f["path"])
report("every core file matches its sha256 and is 444 or 555", not bad, ", ".join(bad[:5]))
executables = [f["path"] for f in manifest["files"] if f["mode"] == "555"]
report("executables are 555", all(os.access(os.path.join(ws, p), os.X_OK) for p in executables) and bool(executables))
folders = {""}
for p in paths:
    parts = p.split("/")
    folders.update("/".join(parts[:i]) for i in range(1, len(parts)))
writable = {d for d in folders if d in writable_root}
open_dirs = []
for d in sorted(folders):
    mode = os.stat(os.path.join(ws, d)).st_mode & 0o777
    if d not in writable and mode != 0o555:
        open_dirs.append(f"{d or '.'}={format(mode, 'o')}")
# The tool outputs of the closed list are writable folders inside core folders; they are not core folders.
outputs = [
    "tools/observability/.data",
    "tools/container-console-colima/internal/webui/dist",
    "tools/container-console-docker-ce/internal/webui/dist",
]
open_dirs = [d for d in open_dirs if d.split("=")[0] not in outputs]
report("core folders are 555, the root included", not open_dirs, ", ".join(open_dirs[:5]))
for d in sorted(writable_root) + [o for o in outputs if os.path.isdir(os.path.join(ws, os.path.dirname(o)))]:
    report(f"writable folder {d}", os.path.isdir(os.path.join(ws, d)) and os.access(os.path.join(ws, d), os.W_OK))
skip = {os.path.join(ws, d) for d in writable_root | {".aiwp"}} | {os.path.join(ws, o) for o in outputs}
extra = []
for top, dirs, files in os.walk(ws):
    dirs[:] = [d for d in dirs if os.path.join(top, d) not in skip and "node_modules" not in d]
    for name in files:
        rel = os.path.relpath(os.path.join(top, name), ws)
        if rel not in set(paths):
            extra.append(rel)
report("no file from outside workspace/ in the workspace", not extra, ", ".join(extra[:5]))
sys.exit(1 if failed else 0)
PY
then
  failed=1
fi
# The project state in the read-only installation: a new project carries the marker, and the UserPromptSubmit hook
# warns about a project without it. Both write only in projects/.
out="$(cd "$ws" && bash scripts/init-repo.sh --type project --name marked-app >/dev/null 2>&1 && bash scripts/aiwp-project-state.sh marked-app 2>&1)"
case "$out" in *"projects/marked-app: up to date (marker $version, workspace $version)"*) true ;; *) false ;; esac
check "a project made by init-repo.sh carries the marker" $?
mkdir -p "$ws/projects/plain-app" && printf '# plain-app\n' >"$ws/projects/plain-app/README.md" &&
  git -C "$ws/projects/plain-app" init -q -b main &&
  git -C "$ws/projects/plain-app" add -A &&
  git -C "$ws/projects/plain-app" -c user.name=test-install -c user.email=test@example.com commit -q -m base
out="$(printf '{"prompt": "fix the login of plain-app"}' | python3 -I -B "$ws/scripts/session-title.py" "$ws" 2>&1)"
case "$out" in *"/normalize-projects plain-app"*) true ;; *) false ;; esac
check "the hook warns about a project without the marker" $?
# This script usually runs from a maintenance session, where aiwp refuses repair; the test installation is not that
# session's workspace, so the check runs as from a terminal.
out="$(cd "$ws" && env -u CLAUDE_CODE_CHILD_SESSION AIWP_TEST_NO_ANCESTOR_CHECK=1 "$HOME/.local/bin/aiwp" repair 2>&1)" && case "$out" in *"nothing to repair"*) true ;; *) false ;; esac
check "aiwp repair finds nothing to repair" $?

# A session opened in the installation must see only the product: this repository's own CLAUDE.md and .claude/ sit
# above it and would load as instructions. settings.local.json is the person's file, which setup-claude.sh never
# touches.
python3 -I - "$ws/.claude/settings.local.json" "$repo" <<'PY'
"""Writes the claudeMdExcludes that keep the maintenance instructions out of a session in the installation."""
import json
import sys

path, repo = sys.argv[1:3]
with open(path, "w", encoding="utf-8") as out:
    json.dump({"claudeMdExcludes": [f"{repo}/CLAUDE.md", f"{repo}/.claude/**"]}, out, indent=2)
    out.write("\n")
PY
check "the maintenance CLAUDE.md is excluded from a session in the installation" $?

echo
echo "workspace: $ws"
echo "HOME of the installation: $HOME (aiwp is $HOME/.local/bin/aiwp)"
# The session runs with the person's own HOME (the Claude Code login lives there); the data folder and the git
# ceiling keep aiwp on this installation and git off this repository.
echo "open a session: cd $ws && XDG_DATA_HOME=$XDG_DATA_HOME GIT_CEILING_DIRECTORIES=$dir $HOME/.local/bin/aiwp"
if [ "$failed" -eq 0 ]; then echo "result: PASS"; else echo "result: FAIL"; fi
exit "$failed"
