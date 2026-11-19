#!/usr/bin/env bash
# Tests of install.sh and scripts/aiwp.sh, fully offline: a temp HOME and XDG_DATA_HOME, a local bare repository built
# from fixture trees (v0.1.0, v0.2.0) through AIWP_REPO_URL, a stub claude. Never the real data folder or HOME.
# Run: bash scripts/tests/aiwp/test-aiwp.sh [--only <test_name>]
# shellcheck disable=SC2319  # check reads the status of the test right before it, on purpose
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AIWP="$(cd "$HERE/../.." && pwd)/aiwp.sh"
NOTICE="$(cd "$HERE/../.." && pwd)/release-notice.sh"
SETTINGS="$(cd "$HERE/../../.." && pwd)/rules/agents/settings.json"
INSTALLER="$(cd "$HERE/../../../.." && pwd)/install.sh"
# shellcheck source=scripts/tests/aiwp/fixture.sh
. "$HERE/fixture.sh"

export LC_ALL=C GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset AIWP_REF AIWP_OS AIWP_TEST_DIE_AFTER_SWAPS AIWP_WORKSPACE CLAUDE_PROJECT_DIR GIT_DIR GIT_WORK_TREE
# The suite may run inside a Claude Code session: aiwp would refuse most commands there. Each test that proves the
# refusal sets the session back on purpose.
unset CLAUDE_CODE_CHILD_SESSION CLAUDECODE
export AIWP_TEST_NO_ANCESTOR_CHECK=1
PY3="$(command -v python3)"

BASE="$(mktemp -d "${TMPDIR:-/tmp}/aiwp-tests.XXXXXX")"
# Installed workspaces are read-only: give write permission back before removing them.
trap 'chmod -R u+w "$BASE" 2>/dev/null; rm -rf "$BASE"' EXIT
REAL_PATH="$PATH"
FAILED=0
RUN=0
OUT=""
RC=0
T=""
CURRENT=""

build_fixture "$BASE" "$AIWP" "$INSTALLER" >/dev/null

# A fresh temp HOME, data folder, remote (v0.1.0 only) and stub bin folder for the current test.
fixture() {
  T="$BASE/t-$CURRENT"
  chmod -R u+w "$T" 2>/dev/null
  rm -rf "$T"
  mkdir -p "$T/home" "$T/xdg" "$T/stub"
  cp -R "$BASE/remote-v1.git" "$T/remote.git"
  cat >"$T/stub/claude" <<'STUB'
#!/usr/bin/env bash
echo "claude-stub cwd=$PWD args=$*"
STUB
  cat >"$T/stub/sudo" <<STUB
#!/usr/bin/env bash
touch "$T/sudo-called"
exit 1
STUB
  chmod 755 "$T/stub/claude" "$T/stub/sudo"
  export HOME="$T/home" XDG_DATA_HOME="$T/xdg" AIWP_REPO_URL="$T/remote.git"
  export PATH="$T/stub:$REAL_PATH"
  DATA="$T/xdg/claude-cli-agents-workspace"
  WS="$T/ws"
}

# Publishes v0.2.0 on the test's remote.
publish_v2() {
  git --git-dir="$T/remote.git" fetch -q "$BASE/remote-v2.git" "refs/tags/v0.2.0:refs/tags/v0.2.0" "+refs/heads/main:refs/heads/main"
}

# Makes the cached release check a day old, so the next check asks the remote.
age_cache() {
  local cache="$DATA/.git/aiwp/release-check"
  [ -f "$cache" ] || return 0
  sed 's/^checked=.*/checked=1/' "$cache" >"$cache.tmp" && mv "$cache.tmp" "$cache"
}

# Runs a command with no controlling terminal (a new session), so /dev/tty cannot be opened: the case of a pipe
# with no person behind it, whatever terminal runs the suite.
notty() {
  "$PY3" -I -c 'import os, sys
pid = os.fork()
if pid == 0:
    os.setsid()
    os.execvp(sys.argv[1], sys.argv[1:])
sys.exit(os.waitstatus_to_exitcode(os.waitpid(pid, 0)[1]))' "$@"
}

# Runs a command in folder $1 on a new pseudo-terminal, as a person would: $2 is a file of lines "<text to wait
# for><TAB><answer>", each answer typed once its text shows up. Sets OUT (everything the terminal showed) and RC.
in_pty() {
  local dir="$1" answers="$2"
  shift 2
  OUT="$("$PY3" -I - "$dir" "$answers" "$@" <<'PY' 2>&1
import os, pty, select, sys, time

cwd, script, cmd = sys.argv[1], sys.argv[2], sys.argv[3:]
with open(script, encoding="utf-8") as handle:
    pairs = [line.rstrip("\n").split("\t", 1) for line in handle if line.strip()]
pid, fd = pty.fork()
if pid == 0:
    os.chdir(cwd)
    os.execvp(cmd[0], cmd)
out, pos, deadline, done = b"", 0, time.time() + 120, False


def more():
    """Reads what the terminal shows within a second; False at the end of the output."""
    global out
    ready = select.select([fd], [], [], 1)[0]
    if not ready:
        return True
    try:
        data = os.read(fd, 4096)
    except OSError:
        data = b""
    out += data
    return bool(data)


for expect, answer in pairs:
    while expect.encode() not in out[pos:]:
        if done or time.time() > deadline:
            sys.stdout.write(out.decode(errors="replace").replace("\r\n", "\n"))
            print(f"\npty: never saw [{expect}]")
            sys.exit(125)
        done = not more()
    pos = out.index(expect.encode(), pos) + len(expect)
    os.write(fd, answer.encode() + b"\n")
while not done and time.time() < deadline:
    done = not more()
status = os.waitpid(pid, 0)[1]
sys.stdout.write(out.decode(errors="replace").replace("\r\n", "\n"))
sys.exit(os.waitstatus_to_exitcode(status))
PY
)"
  RC=$?
}

# Writes the answers file $1 for in_pty from the remaining arguments, in pairs: text to wait for, answer.
answers() {
  local file="$1"
  shift
  : >"$file"
  while [ $# -ge 2 ]; do
    printf '%s\t%s\n' "$1" "$2" >>"$file"
    shift 2
  done
}

# Runs install.sh with no terminal, with the arguments given.
run_install() {
  OUT="$(notty bash "$INSTALLER" "$@" 2>&1)"
  RC=$?
}

# Runs the installed aiwp (the link in ~/.local/bin) from folder $1 with the remaining arguments.
run_aiwp_in() {
  local dir="$1"
  shift
  OUT="$(cd "$dir" && "$HOME/.local/bin/aiwp" "$@" 2>&1)"
  RC=$?
}

# Installs and creates the workspace $WS at v0.1.0.
setup_ws() {
  run_install
  [ "$RC" -eq 0 ] || { check "install" 1; return 1; }
  run_aiwp_in "$T" new "$WS"
  [ "$RC" -eq 0 ] || { check "aiwp new" 1; return 1; }
}

check() { # description, status (0 = ok)
  if [ "$2" -ne 0 ]; then
    FAILED=$((FAILED + 1))
    echo "FAIL $CURRENT: $1 (rc=$RC out=[$OUT])"
  fi
}
has() { case "$OUT" in *"$1"*) ;; *) check "missing [$1]" 1 ;; esac; }
hasnt() { case "$OUT" in *"$1"*) check "unexpected [$1]" 1 ;; esac; }
rc_is() { [ "$RC" -eq "$1" ]; check "rc $1" $?; }
present() { [ -e "$1" ]; check "present: $1" $?; }
absent() { [ ! -e "$1" ] && [ ! -L "$1" ]; check "absent: $1" $?; }
mode_of() { python3 -I -c 'import os, sys; print(format(os.stat(sys.argv[1]).st_mode & 0o777, "o"))' "$1"; }
# The mode is read first: a command substitution in check's message would replace the status of the test.
mode_is() {
  local got
  got="$(mode_of "$1" 2>/dev/null)"
  [ "$got" = "$2" ]
  check "mode $2 of $1 (got $got)" $?
}
content_is() { [ "$(cat "$1" 2>/dev/null)" = "$2" ]; check "content of $1 is [$2]" $?; }
inode_mtime() { python3 -I -c 'import os, sys; s = os.stat(sys.argv[1]); print(s.st_ino, s.st_mtime_ns)' "$1"; }
manifest_field() { python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$WS/.aiwp/manifest.json" "$1"; }
version_of() { python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' "$1/.aiwp/manifest.json"; }
data_tag() { git -C "$DATA" describe --tags --exact-match HEAD 2>/dev/null; }
# Prints the registered paths, one per line.
registry_paths() { python3 -I -c 'import json, sys; [print(w["path"]) for w in json.load(open(sys.argv[1]))["workspaces"]]' "$DATA/workspaces.json"; }
manifest_paths() { python3 -I -c 'import json, sys; [print(f["path"]) for f in json.load(open(sys.argv[1]))["files"]]' "$WS/.aiwp/manifest.json"; }

# Opens core folder $1 for a change by hand, as a person would with chmod.
open_by_hand() { chmod u+w "$1"; }

# Every file of the workspace outside the writable folders and .aiwp/, relative and sorted.
core_files_on_disk() {
  (cd "$WS" && find . \( -path ./custom -o -path ./projects -o -path ./tmp -o -path ./logs -o -path ./.claude -o -path ./.history \
    -o -path ./.aiwp -o -path ./tools/observability/.data -o -path ./tools/container-console-colima/.data \
    -o -path ./tools/container-console-colima/web \) -prune -o -type f -print | sed 's|^\./||' | sort)
}

# --- install.sh

test_install_linux() {
  fixture
  run_install
  rc_is 0
  [ -d "$DATA/.git" ]; check "data folder cloned under XDG_DATA_HOME" $?
  [ "$(git -C "$DATA" describe --tags --exact-match HEAD 2>/dev/null)" = v0.1.0 ]; check "checked out v0.1.0" $?
  [ -L "$HOME/.local/bin/aiwp" ]; check "aiwp is a link" $?
  [ "$(readlink "$HOME/.local/bin/aiwp")" = "$DATA/workspace/scripts/aiwp.sh" ]; check "link target" $?
  has "is not on PATH"
  # shellcheck disable=SC2016  # the literal line the installer prints
  has 'export PATH="$HOME/.local/bin:$PATH"'
  has "Installed the data folder only"
  has "aiwp new ~/my-workspace"
  has "cd ~/my-workspace && aiwp"
  absent "$T/sudo-called"
  ! grep -qE '(^|[^a-z])sudo [a-z-]' "$INSTALLER"; check "the installer calls no sudo" $?
}

test_install_warns_about_docker_and_claude() {
  fixture
  local tool
  mkdir -p "$T/bin"
  for tool in git python3 mkdir dirname ls grep sed sort tail cat ln rm; do ln -s "$(command -v "$tool")" "$T/bin/$tool"; done
  OUT="$(PATH="$T/bin" AIWP_OS=linux notty "$(command -v bash)" "$INSTALLER" 2>&1)"
  RC=$?
  rc_is 0
  has "warning: docker not found"
  has "warning: claude not found"
  [ -L "$HOME/.local/bin/aiwp" ]; check "installed anyway" $?
}

test_install_again_updates_and_path_ok() {
  fixture
  run_install
  publish_v2
  PATH="$HOME/.local/bin:$PATH" run_install
  rc_is 0
  has "updating:"
  hasnt "is not on PATH"
  [ "$(git -C "$DATA" describe --tags --exact-match HEAD)" = v0.2.0 ]; check "moved to v0.2.0" $?
}

test_install_ref_override() {
  fixture
  publish_v2
  AIWP_REF=v0.1.0 run_install
  rc_is 0
  [ "$(git -C "$DATA" describe --tags --exact-match HEAD)" = v0.1.0 ]; check "AIWP_REF wins over the newest tag" $?
}

test_install_macos_data_folder() {
  fixture
  AIWP_OS=macos run_install
  rc_is 0
  [ -d "$HOME/Library/Application Support/claude-cli-agents-workspace/.git" ]; check "macOS data folder" $?
  absent "$DATA"
}

test_install_refuses_native_windows() {
  fixture
  AIWP_OS=windows run_install
  rc_is 1
  has "WSL2"
  absent "$DATA"
  absent "$HOME/.local/bin/aiwp"
}

test_install_missing_prerequisite() {
  fixture
  mkdir -p "$T/onlygit"
  ln -s "$(command -v git)" "$T/onlygit/git"
  OUT="$(PATH="$T/onlygit" AIWP_OS=linux notty "$(command -v bash)" "$INSTALLER" 2>&1)"
  RC=$?
  rc_is 1
  has "missing prerequisites: python3"
  absent "$DATA"
}

# --- install.sh creates the workspace

test_install_empty_folder_install_here() {
  fixture
  mkdir -p "$T/empty"
  answers "$T/answers" "Choose [1-2]:" 1 "custom layer repository" "" "Preferred language" portuguese
  in_pty "$T/empty" "$T/answers" bash "$INSTALLER"
  rc_is 0
  has "1) Install here: $T/empty"
  has "2) Give another path"
  has "created: $T/empty (version 0.1.0, v0.1.0)"
  [ "$(version_of "$T/empty")" = 0.1.0 ]; check "workspace created in the current folder" $?
  [ -d "$T/empty/custom/.git" ]; check "custom answered on the terminal: a local repository" $?
  [ "$(registry_paths)" = "$T/empty" ]; check "registered" $?
  # The language answered on the terminal, through the installer: the native setting of Claude Code.
  has "language: portuguese, in .claude/settings.local.json"
  content_is "$T/empty/.claude/settings.local.json" $'{\n  "language": "portuguese"\n}'
}

test_install_empty_folder_another_path() {
  fixture
  mkdir -p "$T/empty" "$T/full"
  echo mine >"$T/full/mine.txt"
  answers "$T/answers" "Choose [1-2]:" 3 "Answer 1 or 2." 2 "(a new or an empty folder):" "$T/full" \
    "give a new or an empty folder." "$T/ws-other" "custom layer repository" "" "Preferred language" ""
  in_pty "$T/empty" "$T/answers" bash "$INSTALLER"
  rc_is 0
  has "$T/full is not empty: give a new or an empty folder."
  has "created: $T/ws-other"
  absent "$T/ws-other/.claude/settings.local.json"
  [ "$(version_of "$T/ws-other")" = 0.1.0 ]; check "workspace created in the path given" $?
  [ -z "$(ls -A "$T/empty")" ]; check "the current folder stays empty" $?
  content_is "$T/full/mine.txt" mine
}

test_install_non_empty_folder_asks_only_the_path() {
  fixture
  mkdir -p "$T/cwd"
  echo mine >"$T/cwd/mine.txt"
  # shellcheck disable=SC2088  # the answer a person types: the installer expands the ~
  answers "$T/answers" "(a new or an empty folder):" "" "(a new or an empty folder):" "$T/cwd/mine.txt" \
    "not a folder: give a new or an empty folder." "~/ws-home" "custom layer repository" "" "Preferred language" ""
  # As curl | bash runs it: the script on stdin, the answers from the terminal.
  # shellcheck disable=SC2016  # $1 expands in the inner bash
  in_pty "$T/cwd" "$T/answers" bash -c 'cat "$1" | bash' _ "$INSTALLER"
  rc_is 0
  has "This folder is not empty ($T/cwd)"
  hasnt "Install here"
  has "created: $HOME/ws-home"
  absent "$HOME/ws-home/.claude/settings.local.json"
  [ "$(version_of "$HOME/ws-home")" = 0.1.0 ]; check "~ expands to HOME" $?
}

test_install_again_can_only_update_the_installation() {
  fixture
  run_install
  publish_v2
  mkdir -p "$T/empty" "$T/cwd"
  echo mine >"$T/cwd/mine.txt"
  answers "$T/answers" "Choose [1-3]:" 3
  in_pty "$T/empty" "$T/answers" bash "$INSTALLER"
  rc_is 0
  has "3) No new workspace: only update the installation"
  has "Updated the installation; no new workspace"
  [ "$(data_tag)" = v0.2.0 ]; check "the data folder moved" $?
  [ -z "$(ls -A "$T/empty")" ]; check "no workspace created" $?
  answers "$T/answers" "empty: only update the installation):" ""
  in_pty "$T/cwd" "$T/answers" bash "$INSTALLER"
  rc_is 0
  has "Updated the installation; no new workspace"
  # The installer and aiwp update share one lock: while one holds it, the other stops and names the pid.
  hold_lock "$DATA/.git/aiwp/update.lock"
  AIWP_WORKSPACE="$T/ws-locked" run_install
  rc_is 1
  has "an aiwp update is running (pid $HOLDER)"
  absent "$T/ws-locked"
  run_aiwp_in "$T" update --all
  rc_is 1
  has "another aiwp update is running (pid $HOLDER)"
  kill "$HOLDER" 2>/dev/null
  wait "$HOLDER" 2>/dev/null
  # A holder that is gone leaves no lock behind: the kernel drops it.
  AIWP_WORKSPACE="$T/ws-after" run_install
  rc_is 0
  run_aiwp_in "$T" update --all
  rc_is 0
}

# Holds the lock of file $1 from a background process, as an aiwp run would: sets HOLDER to its pid.
hold_lock() {
  mkdir -p "$(dirname "$1")"
  "$PY3" -I -c 'import fcntl, os, sys, time
handle = open(sys.argv[1], "a")
fcntl.flock(handle, fcntl.LOCK_EX)
with open(sys.argv[1], "w") as out:
    out.write(f"{os.getpid()}\n")
open(sys.argv[2], "w").close()
time.sleep(60)' "$1" "$T/held" &
  HOLDER=$!
  while [ ! -e "$T/held" ]; do sleep 0.1; done
  rm -f "$T/held"
}

test_git_children_never_hold_the_update_lock() {
  fixture
  run_install
  setup_ws || return
  publish_v2
  # A hook git runs in the data folder at each checkout: it records whether descriptor 9 (the lock) reached it.
  cat >"$DATA/.git/hooks/post-checkout" <<HOOK
#!/usr/bin/env bash
if { true >&9; } 2>/dev/null; then echo open >>"$T/fd9"; else echo closed >>"$T/fd9"; fi
HOOK
  chmod 755 "$DATA/.git/hooks/post-checkout"
  run_aiwp_in "$T" update --all
  rc_is 0
  [ "$(version_of "$WS")" = 0.2.0 ]; check "updated" $?
  AIWP_REF=v0.1.0 AIWP_WORKSPACE="$T/ws-again" run_install
  rc_is 0
  present "$T/fd9"
  ! grep -q open "$T/fd9"; check "no git child got the lock descriptor" $?
}

test_update_keeps_the_data_lock_until_the_end() {
  fixture
  setup_ws || return
  # A python3 that logs each flock of descriptor 9: taking it twice in one run means the lock was dropped between.
  cat >"$T/stub/python3" <<STUB
#!/usr/bin/env bash
case "\$*" in *fcntl.flock*) [ "\${!#}" != 9 ] || echo flock9 >>"$T/flocks" ;; esac
exec "$PY3" "\$@"
STUB
  chmod 755 "$T/stub/python3"
  run_aiwp_in "$T" update --all
  rc_is 0
  [ "$(grep -c flock9 "$T/flocks" 2>/dev/null)" = 1 ]; check "one flock of the data lock in a run with no data move" $?
  rm -f "$T/stub/python3"
}

test_a_busy_workspace_is_skipped_and_a_dead_run_leaves_no_lock() {
  fixture
  setup_ws || return
  second_ws
  publish_v2
  hold_lock "$WS/.aiwp/aiwp.lock"
  run_aiwp_in "$T" update --all
  rc_is 1
  has "another aiwp run is working on this workspace (pid $HOLDER)"
  [ "$(version_of "$WS")" = 0.1.0 ]; check "the busy one is left alone" $?
  [ "$(version_of "$WS2")" = 0.2.0 ]; check "the other one is updated" $?
  run_aiwp_in "$WS"
  rc_is 1
  has "another aiwp run is working on this workspace"
  kill -KILL "$HOLDER" 2>/dev/null
  wait "$HOLDER" 2>/dev/null
  run_aiwp_in "$T" update --all
  rc_is 0
  [ "$(version_of "$WS")" = 0.2.0 ]; check "updated once the holder died" $?
}

test_lock_folder_that_cannot_be_written_fails_fast() {
  fixture
  setup_ws || return
  publish_v2
  chmod 555 "$WS/.aiwp"
  local start
  start="$(date +%s)"
  run_aiwp_in "$T" update "$WS"
  chmod 755 "$WS/.aiwp"
  [ $(($(date +%s) - start)) -lt 30 ]; check "no endless retry" $?
  rc_is 1
  has "cannot take the lock"
}

test_version_and_list_read_a_large_manifest() {
  fixture
  setup_ws || return
  # A manifest of the size of the real product (hundreds of files): head -n 1 closes the pipe early.
  chmod u+w "$WS/.aiwp"
  python3 -I - "$WS/.aiwp/manifest.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data["files"] += [{"path": f"pad/{i:05d}-" + "x" * 150, "sha256": "0" * 64, "mode": "444"} for i in range(2000)]
import os
os.chmod(path, 0o644)
json.dump(data, open(path, "w"), indent=2)
PY
  run_aiwp_in "$WS" version
  rc_is 0
  has "workspace: 0.1.0"
  hasnt "Traceback"
  run_aiwp_in "$WS" list
  rc_is 0
  has "1  0.1.0"
  hasnt "Traceback"
}

test_install_no_tty_takes_the_folder_from_the_environment_or_the_argument() {
  fixture
  AIWP_WORKSPACE="$T/from-env" run_install
  rc_is 0
  has "created: $T/from-env"
  hasnt "Installed the data folder only"
  [ "$(version_of "$T/from-env")" = 0.1.0 ]; check "AIWP_WORKSPACE" $?
  [ -d "$T/from-env/custom/.git" ]; check "a local custom skeleton with no terminal" $?
  AIWP_WORKSPACE="$T/ignored" run_install "$T/from-arg"
  rc_is 0
  [ "$(version_of "$T/from-arg")" = 0.1.0 ]; check "the argument wins over AIWP_WORKSPACE" $?
  absent "$T/ignored"
  [ "$(registry_paths | tr '\n' ' ')" = "$T/from-env $T/from-arg " ]; check "both registered" $?
  # The form a pipe uses: bash -s -- <folder>, the script on stdin.
  OUT="$(notty bash -s -- "$T/from-pipe" <"$INSTALLER" 2>&1)"
  RC=$?
  rc_is 0
  [ "$(version_of "$T/from-pipe")" = 0.1.0 ]; check "curl | bash -s -- <folder>" $?
  # A folder with content: refused before anything is installed.
  mkdir -p "$T/full"
  echo mine >"$T/full/mine.txt"
  rm -rf "$DATA"
  AIWP_WORKSPACE="$T/full" run_install
  rc_is 1
  has "is not empty: the workspace goes into a new or an empty folder; nothing was installed"
  absent "$DATA"
  run_install --bogus
  rc_is 2
  run_install a b
  rc_is 2
}

# --- aiwp new

test_new_layout_and_modes() {
  fixture
  setup_ws || return
  has "created: $WS (version 0.1.0, v0.1.0)"
  has "setup-claude stub ran"
  has "cd $WS && aiwp"
  absent "$WS/.git"
  mode_is "$WS" 555
  mode_is "$WS/docs" 555
  mode_is "$WS/docs/gone" 555
  mode_is "$WS/scripts" 555
  mode_is "$WS/AGENTS.md" 444
  mode_is "$WS/docs/keep.md" 444
  mode_is "$WS/scripts/aiwp.sh" 555
  mode_is "$WS/scripts/setup-claude.sh" 555
  local d
  for d in custom projects tmp logs .claude .history tools/observability/.data; do
    [ -d "$WS/$d" ]; check "writable folder $d" $?
    [ -w "$WS/$d" ]; check "$d is writable" $?
  done
  mode_is "$WS/tmp" 755
  mode_is "$WS/logs" 755
  ! manifest_paths | grep -q '^logs/'; check "logs/ is never in the manifest" $?
  mode_is "$WS/tools/observability/.data" 755
  absent "$WS/projects/README.md"
  absent "$WS/logs/README.md"
  mode_is "$WS/tools/container-console-colima/internal/webui/dist" 755
  mode_is "$WS/tools/container-console-colima/internal/webui/dist/placeholder.html" 444
  absent "$WS/tools/azurite-console"
  present "$WS/.claude/setup-stamp"
  # No terminal: the language is never asked, and nothing is written.
  hasnt "Preferred language"
  absent "$WS/.claude/settings.local.json"
  # The product only: nothing of the repository root.
  content_is "$WS/README.md" "PRODUCT README"
  local f
  for f in CLAUDE.md LICENSE install.sh maintainers tests i18n .claude/settings.json; do absent "$WS/$f"; done
  [ "$(core_files_on_disk)" = "$(git --git-dir="$T/remote.git" ls-tree -r --name-only v0.1.0 -- workspace/ |
    sed 's|^workspace/||' | grep -Ev '^(projects|logs)/' | sort)" ]
  check "the core on disk is exactly the tracked files of workspace/" $?
  # The manifest.
  [ "$(manifest_field version)" = 0.1.0 ]; check "manifest version" $?
  [ "$(manifest_field tag)" = v0.1.0 ]; check "manifest tag" $?
  [ "$(manifest_field commit)" = "$(git -C "$DATA" rev-parse HEAD)" ]; check "manifest commit" $?
  [ "$(manifest_paths | sort)" = "$(git --git-dir="$T/remote.git" ls-tree -r --name-only v0.1.0 -- workspace/ |
    sed 's|^workspace/||' | grep -Ev '^(projects|logs)/' | sort)" ]
  check "manifest paths are exactly workspace/, without the user folders" $?
  python3 -I - "$WS" <<'PY'
import hashlib, json, os, sys
root = sys.argv[1]
m = json.load(open(os.path.join(root, ".aiwp/manifest.json")))
for f in m["files"]:
    p = os.path.join(root, f["path"])
    assert hashlib.sha256(open(p, "rb").read()).hexdigest() == f["sha256"], f["path"]
    assert format(os.stat(p).st_mode & 0o777, "o") == f["mode"], f["path"]
    assert f["mode"] in ("444", "555")
PY
  check "manifest hashes and modes match the files" $?
  # The custom skeleton, with no terminal.
  [ -d "$WS/custom/.git" ]; check "custom is a git repo" $?
  [ "$(git -C "$WS/custom" rev-list --count HEAD)" = 1 ]; check "custom skeleton committed" $?
  grep -qx 'env/' "$WS/custom/.gitignore"; check "custom ignores env/" $?
  ! grep -qv '^#' "$WS/custom/core-terms.txt"; check "core-terms.txt has comment lines only" $?
  present "$WS/custom/README.md"
  # The core cannot be changed in place.
  ! (echo x >>"$WS/AGENTS.md") 2>/dev/null; check "a core file cannot be written" $?
  ! touch "$WS/docs/new-file" 2>/dev/null; check "no file can be created in a core folder" $?
}

test_new_refuses_non_empty_folder() {
  fixture
  run_install
  mkdir -p "$WS"
  echo mine >"$WS/mine.txt"
  run_aiwp_in "$T" new "$WS"
  rc_is 1
  has "is not empty. Install into a new folder"
  has "/normalize-projects"
  content_is "$WS/mine.txt" mine
}

test_new_usage_errors() {
  fixture
  run_install
  run_aiwp_in "$T" new
  rc_is 2
  run_aiwp_in "$T" new "$WS" --bogus
  rc_is 2
  run_aiwp_in "$T" --help
  rc_is 0
  has "aiwp new <folder>"
}

test_new_custom_from_url() {
  fixture
  run_install
  git init -q --bare -b main "$T/custom-empty.git"
  run_aiwp_in "$T" new "$WS" --custom "$T/custom-empty.git"
  rc_is 0
  has "the repository was empty; a skeleton was committed"
  [ "$(git -C "$WS/custom" remote get-url origin)" = "$T/custom-empty.git" ]; check "custom cloned from the URL" $?
  present "$WS/custom/core-terms.txt"
  # A repository with content is cloned as it is.
  git clone -q "$T/custom-empty.git" "$T/c2" 2>/dev/null
  echo "my rules" >"$T/c2/notes.md"
  git -C "$T/c2" add notes.md && git -C "$T/c2" -c user.name=t -c user.email= commit -q -m notes
  git -C "$T/c2" push -q origin HEAD:refs/heads/main
  run_aiwp_in "$T" new "$T/ws2" --custom "$T/custom-empty.git"
  rc_is 0
  has "custom/: cloned from"
  present "$T/ws2/custom/notes.md"
}

test_new_failure_leaves_nothing() {
  fixture
  run_install
  run_aiwp_in "$T" new "$WS" --custom "$T/no-such-repo.git"
  rc_is 1
  has "could not clone the custom layer"
  absent "$WS"
}

# --- aiwp new: the preferred language of communication

# Runs subcommand $1 of the python helper embedded in aiwp.sh (its py function) with the remaining arguments: the
# helper's own code, read from the script under test. Sets OUT and RC.
aiwp_py() {
  OUT="$(awk "/<<'PY'\$/ && !seen { on = 1; seen = 1; next } /^PY\$/ { on = 0 } on" "$AIWP" | "$PY3" -I - "$@" 2>&1)"
  RC=$?
}

test_new_asks_the_language_on_a_terminal() {
  fixture
  run_install
  local long
  long="$(printf 'a%.0s' $(seq 1 41))"
  # Invalid answers are asked again; the valid one is stored trimmed, as typed.
  answers "$T/answers" "custom layer repository" "" "Preferred language" "portugu3se" "Preferred language" "português" \
    "Preferred language" "$long" "Preferred language" "( - )" "Preferred language" "  portuguese  "
  in_pty "$T" "$T/answers" "$HOME/.local/bin/aiwp" new "$WS"
  rc_is 0
  has "created: $WS"
  has "not a language name: use only English letters, spaces, hyphens and parentheses."
  has "not a language name: at most 40 characters."
  has "not a language name: give at least one letter."
  [ "$(grep -o 'Preferred language of communication with Claude' <<<"$OUT" | wc -l | tr -d ' ')" = 5 ]
  check "asked five times" $?
  has "language: portuguese, in .claude/settings.local.json"
  content_is "$WS/.claude/settings.local.json" $'{\n  "language": "portuguese"\n}'
  # The setup ran after the question, and the file stays where the person can edit it.
  present "$WS/.claude/setup-stamp"
  [ -w "$WS/.claude/settings.local.json" ]; check "settings.local.json is writable" $?
  # An empty answer writes nothing.
  answers "$T/answers" "custom layer repository" "" "Preferred language" ""
  in_pty "$T" "$T/answers" "$HOME/.local/bin/aiwp" new "$T/ws2"
  rc_is 0
  has "created: $T/ws2"
  hasnt "language: "
  absent "$T/ws2/.claude/settings.local.json"
  # The end of input (Ctrl-D) writes nothing, and the workspace is still created.
  answers "$T/answers" "custom layer repository" "" "Preferred language" $'\x04'
  in_pty "$T" "$T/answers" "$HOME/.local/bin/aiwp" new "$T/ws3"
  rc_is 0
  has "created: $T/ws3"
  absent "$T/ws3/.claude/settings.local.json"
  [ "$(version_of "$T/ws3")" = 0.1.0 ]; check "workspace created after the end of input" $?
}

test_settings_language_keeps_other_keys() {
  fixture
  mkdir -p "$T/s"
  local f="$T/s/settings.local.json"
  printf '{"model": "sonnet", "language": "spanish", "permissions": {"allow": ["Bash(ls)"]}}' >"$f"
  chmod 600 "$f"
  aiwp_py settings-language "$f" portuguese
  rc_is 0
  "$PY3" -I -c 'import json, sys
data = json.load(open(sys.argv[1]))
assert list(data) == ["model", "language", "permissions"], list(data)
assert data["language"] == "portuguese" and data["model"] == "sonnet", data
assert data["permissions"] == {"allow": ["Bash(ls)"]}, data' "$f"
  check "language replaced, every other key kept in its place" $?
  grep -q '^  "model": "sonnet",$' "$f"; check "2-space indent" $?
  mode_is "$f" 600
  [ "$(ls -A "$T/s")" = settings.local.json ]; check "no temp file left" $?
  # A missing file is created with the key alone.
  aiwp_py settings-language "$T/s/new.json" spanish
  rc_is 0
  content_is "$T/s/new.json" $'{\n  "language": "spanish"\n}'
  # A file that is not a JSON object, or not JSON, or not a regular file, is left as it is, with a warning.
  printf '["language"]\n' >"$T/s/list.json"
  cp "$T/s/list.json" "$T/s/list.orig"
  aiwp_py settings-language "$T/s/list.json" portuguese
  rc_is 1
  has "is not a JSON object; it was left as it is"
  cmp -s "$T/s/list.json" "$T/s/list.orig"; check "a JSON list is left as it is" $?
  printf '{"model": \n' >"$T/s/bad.json"
  cp "$T/s/bad.json" "$T/s/bad.orig"
  aiwp_py settings-language "$T/s/bad.json" portuguese
  rc_is 1
  has "cannot be read"
  cmp -s "$T/s/bad.json" "$T/s/bad.orig"; check "invalid JSON is left as it is" $?
  ln -s new.json "$T/s/link.json"
  aiwp_py settings-language "$T/s/link.json" portuguese
  rc_is 1
  [ -L "$T/s/link.json" ]; check "a link stays a link" $?
  content_is "$T/s/new.json" $'{\n  "language": "spanish"\n}'
}

test_update_and_opening_keep_the_language_setting() {
  fixture
  setup_ws || return
  local f="$WS/.claude/settings.local.json" before
  printf '{\n  "permissions": {"allow": ["Bash(ls)"]},\n  "language": "portuguese"\n}\n' >"$f"
  cp "$f" "$T/before.json"
  before="$(inode_mtime "$f")"
  publish_v2
  # update in a terminal: it never asks the language and never touches the file.
  answers "$T/answers" "Choose [1]:" ""
  in_pty "$T" "$T/answers" "$HOME/.local/bin/aiwp" update
  rc_is 0
  hasnt "Preferred language"
  [ "$(version_of "$WS")" = 0.2.0 ]; check "updated to 0.2.0" $?
  cmp -s "$T/before.json" "$f"; check "update: settings.local.json byte for byte the same" $?
  # The opening (which runs setup-claude.sh), rollback and repair do not touch it either.
  run_aiwp_in "$WS"
  rc_is 0
  run_aiwp_in "$WS" rollback
  rc_is 0
  run_aiwp_in "$WS" repair
  rc_is 0
  hasnt "Preferred language"
  cmp -s "$T/before.json" "$f"; check "opening, rollback, repair: byte for byte the same" $?
  [ "$(inode_mtime "$f")" = "$before" ]; check "never rewritten (same inode and mtime)" $?
}

# --- opening

test_open_runs_setup_and_claude_at_the_root() {
  fixture
  setup_ws || return
  run_aiwp_in "$WS/docs" -- --resume abc
  rc_is 0
  has "claude-stub cwd=$WS args=--resume abc"
  run_aiwp_in "$WS" -- --model sonnet
  has "args=--model sonnet"
  content_is "$WS/.claude/setup-stamp" "ran --quiet"
}

test_unknown_command_is_a_usage_error() {
  fixture
  setup_ws || return
  local word
  for word in --model sonnet updat --resume; do
    run_aiwp_in "$WS" "$word"
    rc_is 2
    has "unknown command: $word"
    hasnt "claude-stub"
  done
}

test_outside_a_workspace() {
  fixture
  run_install
  run_aiwp_in "$T"
  rc_is 1
  has "not inside a workspace"
  run_aiwp_in "$T" update now
  rc_is 1
  has "not a workspace: now"
  run_aiwp_in "$T" update a b
  rc_is 2
  run_aiwp_in "$T" update --all "$T"
  rc_is 2
}

test_release_check_cached_a_day_and_offline() {
  fixture
  setup_ws || return
  run_aiwp_in "$WS" check
  rc_is 0
  has "up to date: 0.1.0"
  publish_v2
  run_aiwp_in "$WS" check
  has "up to date: 0.1.0"
  hasnt "0.2.0"
  age_cache
  run_aiwp_in "$WS" check --quiet
  rc_is 0
  has "attention: Claude CLI Agents Workspace 0.2.0 is available (this workspace: 0.1.0); close every session of it and run aiwp update in a terminal"
  [ "$(git -C "$DATA" describe --tags --exact-match HEAD)" = v0.1.0 ]; check "check never updates" $?
  # Offline: one warning line, and the workspace still opens.
  mv "$T/remote.git" "$T/remote-away.git"
  age_cache
  run_aiwp_in "$WS" check --quiet
  rc_is 0
  [ -z "$OUT" ]; check "check --quiet says nothing offline" $?
  run_aiwp_in "$WS" check
  has "warning: could not check for a new release"
  age_cache
  run_aiwp_in "$WS"
  rc_is 0
  has "warning: could not check for a new release"
  has "claude-stub"
  [ "$(manifest_field version)" = 0.1.0 ]; check "offline keeps the version" $?
}

# Runs the release-notice hook of this repository for workspace $1, as Claude Code does (hook JSON on stdin).
run_notice() {
  OUT="$(echo '{"hook_event_name":"SessionStart","source":"startup"}' | CLAUDE_PROJECT_DIR="$1" bash "$NOTICE" 2>&1)"
  RC=$?
}

# Prints the additionalContext of the hook output, or fails when it is not the SessionStart hook JSON.
notice_context() {
  printf '%s' "$OUT" | python3 -I -c 'import json, sys
data = json.load(sys.stdin)["hookSpecificOutput"]
assert data["hookEventName"] == "SessionStart"
print(data["additionalContext"])'
}

test_release_notice_tells_the_session_and_never_updates() {
  fixture
  setup_ws || return
  run_notice "$WS"
  rc_is 0
  [ -z "$OUT" ]; check "nothing new: no output" $?
  publish_v2
  age_cache
  local before
  before="$(core_files_on_disk | (cd "$WS" && xargs cat) | cksum)"
  run_notice "$WS"
  rc_is 0
  OUT="$(notice_context)"; check "valid SessionStart JSON" $?
  has "A new workspace version 0.2.0 was detected (this workspace: 0.1.0). Tell the person to close this session and run \`aiwp update\` in a terminal."
  has "Never run aiwp update, rollback or repair yourself"
  [ "$(git -C "$DATA" describe --tags --exact-match HEAD)" = v0.1.0 ]; check "the hook never moves the data folder" $?
  [ "$(manifest_field version)" = 0.1.0 ]; check "the hook never updates the workspace" $?
  [ "$(core_files_on_disk | (cd "$WS" && xargs cat) | cksum)" = "$before" ]; check "the core is untouched" $?
  # The day's answer is kept: a second session start does not ask the remote again.
  mv "$T/remote.git" "$T/remote-away.git"
  run_notice "$WS"
  OUT="$(notice_context)"; check "cached answer still tells" $?
  has "A new workspace version 0.2.0 was detected"
  # A pinned workspace (aiwp rollback) is left alone: aiwp update would clear the pin.
  echo v0.1.0 >"$WS/.aiwp/pin"
  run_notice "$WS"
  rc_is 0
  [ -z "$OUT" ]; check "pinned: no output" $?
  rm -f "$WS/.aiwp/pin"
  # An update that died halfway is told too.
  : >"$WS/.aiwp/journal"
  run_notice "$WS"
  OUT="$(notice_context)"; check "journal: valid JSON" $?
  has "An aiwp update or rollback stopped halfway in this workspace"
  rm -f "$WS/.aiwp/journal"
}

test_release_notice_is_silent_offline_and_outside_a_workspace() {
  fixture
  setup_ws || return
  publish_v2
  mv "$T/remote.git" "$T/remote-away.git"
  age_cache
  run_notice "$WS"
  rc_is 0
  [ -z "$OUT" ]; check "offline: no output" $?
  # A folder without .aiwp/manifest.json (the product repository, any other folder): silent, even with a newer release.
  mv "$T/remote-away.git" "$T/remote.git"
  age_cache
  mkdir -p "$T/plain/scripts"
  cp "$AIWP" "$T/plain/scripts/aiwp.sh"
  run_notice "$T/plain"
  rc_is 0
  [ -z "$OUT" ]; check "not an installed workspace: no output" $?
  # No installation in the data folder: silent.
  mv "$DATA" "$DATA.away"
  run_notice "$WS"
  rc_is 0
  [ -z "$OUT" ]; check "not installed: no output" $?
  mv "$DATA.away" "$DATA"
}

test_release_notice_is_bounded_in_time() {
  fixture
  setup_ws || return
  age_cache
  # A remote that never answers: git hangs; the check gives up within its limits and the hook stays silent.
  cat >"$T/stub/git" <<STUB
#!/usr/bin/env bash
case "\$*" in *ls-remote*) sleep 30 ;; esac
exec "$(command -v git)" "\$@"
STUB
  chmod 755 "$T/stub/git"
  local start
  start="$(date +%s)"
  run_notice "$WS"
  rc_is 0
  [ -z "$OUT" ]; check "a hanging remote: no output" $?
  [ $(($(date +%s) - start)) -lt 15 ]; check "a hanging remote: done within 15 s" $?
  rm -f "$T/stub/git"
  # An aiwp.sh that hangs (and leaves children holding its output): the hook stops waiting at its limit.
  local fake="$T/hanging"
  mkdir -p "$fake/.aiwp" "$fake/scripts"
  echo '{}' >"$fake/.aiwp/manifest.json"
  printf '#!/usr/bin/env bash\n(sleep 30; echo "attention: late") &\nsleep 30\n' >"$fake/scripts/aiwp.sh"
  start="$(date +%s)"
  OUT="$(echo '{}' | RELEASE_NOTICE_LIMIT_SECONDS=2 CLAUDE_PROJECT_DIR="$fake" bash "$NOTICE" 2>&1)"
  RC=$?
  rc_is 0
  [ -z "$OUT" ]; check "a hanging aiwp.sh: no output" $?
  [ $(($(date +%s) - start)) -lt 6 ]; check "a hanging aiwp.sh: the hook ends at its limit" $?
}

test_release_notice_is_registered_at_session_start() {
  python3 -I - "$SETTINGS" <<'PY'
import json, sys
hooks = json.load(open(sys.argv[1]))["hooks"]["SessionStart"]
block = next(b for b in hooks if any("setup-claude.sh" in h["command"] for h in b["hooks"]))
notice = [h for h in block["hooks"] if "scripts/release-notice.sh" in h["command"]]
assert notice and notice[0].get("timeout", 600) <= 30, notice
assert "startup" in block["matcher"]
PY
  check "SessionStart runs release-notice.sh next to setup-claude.sh, with a short timeout" $?
  OUT="$(bash "$NOTICE" --help)"
  has "never runs aiwp update"
}

test_open_never_updates() {
  fixture
  setup_ws || return
  publish_v2
  age_cache
  local before
  before="$(core_files_on_disk | (cd "$WS" && xargs cat) | cksum)"
  run_aiwp_in "$WS"
  rc_is 0
  has "A new workspace version 0.2.0 was detected (this workspace: 0.1.0). Run \`aiwp update\` to update; opening this workspace on 0.1.0."
  has "claude-stub cwd=$WS"
  hasnt "updated:"
  [ "$(manifest_field version)" = 0.1.0 ]; check "opened at 0.1.0" $?
  [ "$(data_tag)" = v0.1.0 ]; check "the data folder did not move" $?
  [ "$(core_files_on_disk | (cd "$WS" && xargs cat) | cksum)" = "$before" ]; check "the core is untouched" $?
  # The release is in the data folder already (another workspace updated it): still detection only.
  git -C "$DATA" fetch -q --tags origin
  git -C "$DATA" checkout -q --detach v0.2.0
  run_aiwp_in "$WS"
  rc_is 0
  has "A new workspace version 0.2.0 was detected"
  [ "$(manifest_field version)" = 0.1.0 ]; check "still 0.1.0 with the data folder at 0.2.0" $?
}

test_open_offline_after_a_cached_release_still_opens() {
  fixture
  setup_ws || return
  publish_v2
  age_cache
  run_aiwp_in "$WS" check
  has "0.2.0 is available"
  mv "$T/remote.git" "$T/remote-away.git"
  run_aiwp_in "$WS"
  rc_is 0
  has "A new workspace version 0.2.0 was detected"
  has "claude-stub"
  [ "$(manifest_field version)" = 0.1.0 ]; check "still 0.1.0" $?
  [ "$(data_tag)" = v0.1.0 ]; check "data folder not moved" $?
  run_aiwp_in "$WS" update "$WS"
  rc_is 1
  has "could not fetch v0.2.0"
  has "nothing was updated"
  [ "$(data_tag)" = v0.1.0 ]; check "data folder still not moved" $?
}

# --- update

test_update_swaps_only_what_changed() {
  fixture
  setup_ws || return
  echo mine >"$WS/custom/mine.txt"
  echo mine >"$WS/projects/mine.txt"
  echo mine >"$WS/tmp/mine.txt"
  echo mine >"$WS/logs/mine.txt"
  local keep_before agents_before custom_before
  keep_before="$(inode_mtime "$WS/docs/keep.md")"
  agents_before="$(inode_mtime "$WS/AGENTS.md")"
  custom_before="$(inode_mtime "$WS/custom/mine.txt")"
  sleep 1
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 0
  has "update: 0.1.0 -> 0.2.0"
  has "Second release of the fixture"
  hasnt "First release of the fixture"
  has "updated: 0.1.0 -> 0.2.0 (4 changed, 2 added, 2 removed)"
  [ "$(inode_mtime "$WS/docs/keep.md")" = "$keep_before" ]; check "unchanged file keeps inode and mtime" $?
  [ "$(inode_mtime "$WS/AGENTS.md")" = "$agents_before" ]; check "unchanged AGENTS.md untouched" $?
  [ "$(inode_mtime "$WS/custom/mine.txt")" = "$custom_before" ]; check "custom untouched" $?
  content_is "$WS/projects/mine.txt" mine
  content_is "$WS/tmp/mine.txt" mine
  content_is "$WS/logs/mine.txt" mine
  content_is "$WS/docs/change.md" "change v2"
  mode_is "$WS/docs/change.md" 444
  content_is "$WS/docs/new.md" "new in v0.2.0"
  mode_is "$WS/docs/new.md" 444
  mode_is "$WS/scripts/new-tool.sh" 555
  absent "$WS/docs/old.md"
  absent "$WS/docs/gone"
  mode_is "$WS/docs" 555
  mode_is "$WS" 555
  absent "$WS/.aiwp/journal"
  [ -z "$(find "$WS" -name '.aiwp-tmp.*')" ]; check "no temp file left" $?
  [ "$(manifest_field version)" = 0.2.0 ]; check "manifest at 0.2.0" $?
  [ "$(manifest_field tag)" = v0.2.0 ]; check "manifest tag v0.2.0" $?
  content_is "$WS/.aiwp/backup/0.1.0/files/docs/change.md" "change v1"
  present "$WS/.aiwp/backup/0.1.0/files/docs/old.md"
  absent "$WS/.aiwp/backup/0.1.0/files/docs/keep.md"
  absent "$WS/README.md.orig"
  absent "$WS/maintainers"
  run_aiwp_in "$WS" repair
  rc_is 0
  has "nothing to repair"
  run_aiwp_in "$WS" update --all
  rc_is 0
  has "up to date: 0.2.0"
}

test_update_keeps_the_last_three_backups() {
  fixture
  setup_ws || return
  local v
  chmod u+w "$WS/.aiwp"
  for v in 0.0.1 0.0.2 0.0.3; do
    mkdir -p "$WS/.aiwp/backup/$v/files"
    touch -t "20260101000${v##*.}" "$WS/.aiwp/backup/$v"
  done
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 0
  [ "$(find "$WS/.aiwp/backup" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 3 ]; check "three backups kept" $?
  present "$WS/.aiwp/backup/0.1.0"
  absent "$WS/.aiwp/backup/0.0.1"
}

test_edited_core_stops_update_and_repair_fixes() {
  fixture
  setup_ws || return
  chmod u+w "$WS/docs/change.md"
  echo "edited by hand" >"$WS/docs/change.md"
  chmod 444 "$WS/docs/change.md"
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 1
  has "changed: docs/change.md"
  has "aiwp repair"
  has "skipped: the core changed"
  [ "$(manifest_field version)" = 0.1.0 ]; check "nothing updated" $?
  [ "$(data_tag)" = v0.2.0 ]; check "the data folder moved once" $?
  absent "$WS/docs/new.md"
  run_aiwp_in "$WS" repair
  rc_is 0
  has "fixed: docs/change.md (changed)"
  content_is "$WS/docs/change.md" "change v1"
  mode_is "$WS/docs/change.md" 444
  run_aiwp_in "$WS" update --all
  rc_is 0
  has "updated: 0.1.0 -> 0.2.0"
}

test_chmod_by_hand_stops_update_and_repair_fixes() {
  fixture
  setup_ws || return
  chmod 644 "$WS/AGENTS.md"
  chmod 755 "$WS/docs"
  chmod 444 "$WS/scripts/aiwp.sh"
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 1
  has "permission: AGENTS.md is 644, expected 444"
  has "permission: docs/ is 755, expected 555"
  has "permission: scripts/aiwp.sh is 444, expected 555"
  run_aiwp_in "$WS" repair
  rc_is 0
  has "fixed: AGENTS.md (permission 644 -> 444)"
  has "fixed: docs/ (permission 755 -> 555)"
  mode_is "$WS/AGENTS.md" 444
  mode_is "$WS/docs" 555
  mode_is "$WS/scripts/aiwp.sh" 555
}

test_repair_restores_missing_files_and_folders() {
  fixture
  setup_ws || return
  echo mine >"$WS/custom/mine.txt"
  echo mine >"$WS/logs/mine.txt"
  open_by_hand "$WS/docs"
  rm -f "$WS/docs/keep.md"
  chmod -R u+w "$WS/docs/gone"
  rm -rf "$WS/docs/gone"
  chmod 555 "$WS/docs"
  open_by_hand "$WS/tools/observability"
  rmdir "$WS/tools/observability/.data"
  chmod 555 "$WS/tools/observability"
  run_aiwp_in "$WS" repair
  rc_is 0
  has "fixed: docs/keep.md (missing)"
  has "fixed: docs/gone/only.md (missing)"
  content_is "$WS/docs/keep.md" "kept in every version"
  mode_is "$WS/docs/gone" 555
  mode_is "$WS/tools/observability/.data" 755
  mode_is "$WS/tools/observability" 555
  content_is "$WS/custom/mine.txt" mine
  content_is "$WS/logs/mine.txt" mine
  run_aiwp_in "$WS" repair
  has "nothing to repair"
}

test_symlinked_output_folder_is_never_followed() {
  fixture
  setup_ws || return
  local dist="$WS/tools/container-console-colima/internal/webui/dist"
  mkdir -p "$T/elsewhere"
  echo mine >"$T/elsewhere/mine.txt"
  chmod u+w "$(dirname "$dist")"
  rm -rf "$dist"
  ln -s "$T/elsewhere" "$dist"
  chmod 555 "$(dirname "$dist")"
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 1
  has "not a folder: tools/container-console-colima/internal/webui/dist"
  run_aiwp_in "$WS" repair
  rc_is 1
  has "not fixed: tools/container-console-colima/internal/webui/dist is not a folder"
  [ "$(ls "$T/elsewhere")" = mine.txt ]; check "nothing written through the link" $?
  # A core folder replaced by a link to a folder with a subfolder: repair changes nothing there.
  mkdir -p "$T/ext/sub"
  chmod 700 "$T/ext"
  chmod u+w "$WS" "$WS/docs"
  mv "$WS/docs" "$T/docs-away"
  ln -s "$T/ext" "$WS/docs"
  chmod 555 "$WS"
  run_aiwp_in "$WS" repair
  rc_is 1
  has "not fixed: docs is not a folder"
  hasnt "fixed: docs/"
  mode_is "$T/ext" 700
  [ "$(cd "$T/ext" && find . | sort | tr '\n' ' ')" = ". ./sub " ]; check "the link target is unchanged" $?
}

test_crash_mid_update_is_undone_by_the_next_run() {
  fixture
  setup_ws || return
  publish_v2
  AIWP_TEST_DIE_AFTER_SWAPS=2 run_aiwp_in "$WS" update --all
  [ "$RC" -ne 0 ]; check "the run was killed" $?
  present "$WS/.aiwp/journal"
  [ "$(manifest_field version)" = 0.1.0 ]; check "manifest still 0.1.0 after the crash" $?
  run_aiwp_in "$WS" version
  has "attention: an aiwp update or rollback stopped halfway"
  present "$WS/.aiwp/journal"
  # The opening never swaps a file: it refuses and names the way out.
  run_aiwp_in "$WS"
  rc_is 1
  has "stopped halfway in this workspace; run aiwp repair"
  hasnt "claude-stub"
  present "$WS/.aiwp/journal"
  run_aiwp_in "$WS" repair
  rc_is 0
  has "recovering: the last aiwp update stopped halfway; restoring version 0.1.0"
  has "recovered: version 0.1.0 restored"
  absent "$WS/.aiwp/journal"
  absent "$WS/docs/new.md"
  absent "$WS/scripts/new-tool.sh"
  content_is "$WS/docs/change.md" "change v1"
  content_is "$WS/docs/old.md" "removed in v0.2.0"
  mode_is "$WS/docs" 555
  mode_is "$WS/scripts" 555
  mode_is "$WS" 555
  [ -z "$(find "$WS" -name '.aiwp-tmp.*')" ]; check "no temp file left" $?
  run_aiwp_in "$WS" repair
  has "nothing to repair"
  run_aiwp_in "$WS" update --all
  rc_is 0
  has "updated: 0.1.0 -> 0.2.0"
}

test_rollback_pins_and_update_clears_the_pin() {
  fixture
  setup_ws || return
  run_aiwp_in "$WS" rollback
  rc_is 1
  has "nothing to roll back to"
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 0
  echo mine >"$WS/projects/mine.txt"
  run_aiwp_in "$WS" rollback
  rc_is 0
  has "rolled back: 0.2.0 -> 0.1.0; pinned at 0.1.0"
  [ "$(manifest_field version)" = 0.1.0 ]; check "manifest back at 0.1.0" $?
  content_is "$WS/.aiwp/pin" 0.1.0
  content_is "$WS/docs/change.md" "change v1"
  content_is "$WS/docs/old.md" "removed in v0.2.0"
  content_is "$WS/docs/gone/only.md" "removed with its folder in v0.2.0"
  absent "$WS/docs/new.md"
  absent "$WS/scripts/new-tool.sh"
  mode_is "$WS/docs/old.md" 444
  mode_is "$WS/docs/gone" 555
  mode_is "$WS" 555
  content_is "$WS/projects/mine.txt" mine
  run_aiwp_in "$WS" repair
  has "nothing to repair"
  run_aiwp_in "$WS"
  rc_is 0
  has "this workspace is pinned at 0.1.0"
  has "claude-stub"
  [ "$(manifest_field version)" = 0.1.0 ]; check "a pinned workspace does not update on open" $?
  run_aiwp_in "$WS" version
  has "pinned at: 0.1.0"
  run_aiwp_in "$WS" list
  has "pinned at 0.1.0"
  # Update all leaves a pinned workspace alone; naming it updates it.
  run_aiwp_in "$WS" update --all
  rc_is 0
  has "skipped: pinned"
  [ "$(manifest_field version)" = 0.1.0 ]; check "update --all keeps the pin" $?
  run_aiwp_in "$T" update "$WS"
  rc_is 0
  has "updated: 0.1.0 -> 0.2.0"
  absent "$WS/.aiwp/pin"
}

test_crash_mid_rollback_is_undone_by_the_next_run() {
  fixture
  setup_ws || return
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 0
  AIWP_TEST_DIE_AFTER_SWAPS=3 run_aiwp_in "$WS" rollback
  [ "$RC" -ne 0 ]; check "the rollback was killed" $?
  present "$WS/.aiwp/journal"
  run_aiwp_in "$WS" repair
  rc_is 0
  has "recovering: the last aiwp rollback stopped halfway; restoring version 0.2.0"
  absent "$WS/.aiwp/journal"
  absent "$WS/.aiwp/pin"
  content_is "$WS/docs/change.md" "change v2"
  content_is "$WS/docs/new.md" "new in v0.2.0"
  absent "$WS/docs/old.md"
  absent "$WS/docs/gone"
  mode_is "$WS/docs" 555
  [ -z "$(find "$WS" -name '.aiwp-tmp.*' -o -name 'work.*' -path '*/.aiwp/*')" ]; check "no leftovers" $?
  run_aiwp_in "$WS" repair
  has "nothing to repair"
}

# --- registry

test_registry_add_list_forget_and_missing_folder() {
  fixture
  setup_ws || return
  run_aiwp_in "$T" new "$T/ws2"
  rc_is 0
  [ "$(registry_paths | tr '\n' ' ')" = "$WS $T/ws2 " ]; check "aiwp new registers both" $?
  python3 -I - "$DATA/workspaces.json" <<'PY'
import json, re, sys
data = json.load(open(sys.argv[1]))
assert data["format"] == 1, data
for item in data["workspaces"]:
    assert set(item) == {"path", "version", "created", "updated"}, item
    assert item["version"] == "0.1.0", item
    assert re.match(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$", item["created"]), item
PY
  check "registry entries: path, version, created, updated" $?
  run_aiwp_in "$T" list
  rc_is 0
  has "1  0.1.0      up to date                    $WS"
  has "2  0.1.0      up to date                    $T/ws2"
  publish_v2
  age_cache
  chmod u+w "$WS/docs/change.md"
  echo edited >"$WS/docs/change.md"
  chmod -R u+w "$T/ws2"
  rm -rf "$T/ws2"
  run_aiwp_in "$T" list
  rc_is 0
  has "core changed                  $WS"
  has "folder missing                $T/ws2"
  run_aiwp_in "$T" forget "$T/ws2"
  rc_is 0
  has "forgotten: $T/ws2"
  [ "$(registry_paths)" = "$WS" ]; check "forget removes only that entry" $?
  run_aiwp_in "$T" forget "$T/ws2"
  rc_is 1
  has "not in the registry"
  run_aiwp_in "$T" forget
  rc_is 2
  present "$WS/AGENTS.md"
}

test_registry_parallel_writes_keep_every_entry() {
  fixture
  run_install
  local i
  for i in 1 2 3 4 5 6; do
    (cd "$T" && "$HOME/.local/bin/aiwp" new "$T/p$i" >/dev/null 2>&1) &
  done
  wait
  [ "$(registry_paths | sort | tr '\n' ' ')" = "$T/p1 $T/p2 $T/p3 $T/p4 $T/p5 $T/p6 " ]
  check "six aiwp new at once: six entries" $?
  absent "$DATA/workspaces.json.tmp."*
}

test_registry_corrupt_is_never_overwritten() {
  fixture
  setup_ws || return
  echo '{"workspaces": [' >"$DATA/workspaces.json"
  run_aiwp_in "$T" list
  rc_is 1
  has "cannot be read"
  run_aiwp_in "$T" new "$T/ws2"
  rc_is 1
  absent "$T/ws2"
  content_is "$DATA/workspaces.json" '{"workspaces": ['
  echo '{"workspaces": [{"path": "relative"}]}' >"$DATA/workspaces.json"
  run_aiwp_in "$T" list
  rc_is 1
  has "not in the expected form"
}

test_registry_registers_an_existing_workspace() {
  fixture
  setup_ws || return
  rm -f "$DATA/workspaces.json"
  run_aiwp_in "$WS" version
  absent "$DATA/workspaces.json"
  run_aiwp_in "$WS/docs" list
  rc_is 0
  has "registered: $WS"
  [ "$(registry_paths)" = "$WS" ]; check "list inside it registers it" $?
  rm -f "$DATA/workspaces.json"
  run_aiwp_in "$WS"
  rc_is 0
  has "registered: $WS"
  has "claude-stub"
  [ "$(registry_paths)" = "$WS" ]; check "opening registers it" $?
  # Inside a session nothing is written: list only says so.
  rm -f "$DATA/workspaces.json"
  CLAUDE_CODE_CHILD_SESSION=1 run_aiwp_in "$WS" list
  rc_is 0
  has "this workspace is not registered yet"
  absent "$DATA/workspaces.json"
}

# --- update: the list, the choice, the summary

# Creates a second workspace, $WS2, at v0.1.0 (after setup_ws).
second_ws() {
  WS2="$T/ws2"
  run_aiwp_in "$T" new "$WS2"
  [ "$RC" -eq 0 ] || check "aiwp new ws2" 1
}

test_update_lists_and_updates_all_by_default() {
  fixture
  setup_ws || return
  second_ws
  publish_v2
  answers "$T/answers" "Choose [1]:" ""
  in_pty "$T" "$T/answers" "$HOME/.local/bin/aiwp" update
  rc_is 0
  has "1  0.1.0      update available (0.2.0)      $WS"
  has "2  0.1.0      update available (0.2.0)      $WS2"
  has "[1] Update all (default)"
  has "[2] Choose which (numbers)"
  has "[3] Cancel"
  has "Summary (data folder at 0.2.0):"
  [ "$(version_of "$WS")" = 0.2.0 ] && [ "$(version_of "$WS2")" = 0.2.0 ]; check "both updated" $?
  [ "$(python3 -I -c 'import json, sys; print(" ".join(w["version"] for w in json.load(open(sys.argv[1]))["workspaces"]))' "$DATA/workspaces.json")" = "0.2.0 0.2.0" ]
  check "the registry records the new versions" $?
}

test_update_choose_numbers() {
  fixture
  setup_ws || return
  second_ws
  publish_v2
  answers "$T/answers" "Choose [1]:" 9 "Answer 1, 2 or 3." 2 "(for example: 1 3):" "5 x" "Not a number of the list: x" 2
  in_pty "$T" "$T/answers" "$HOME/.local/bin/aiwp" update
  rc_is 0
  has "Not a number of the list: 5"
  [ "$(version_of "$WS")" = 0.1.0 ]; check "the first one was not chosen" $?
  [ "$(version_of "$WS2")" = 0.2.0 ]; check "the second one was updated" $?
}

test_update_cancel_changes_nothing() {
  fixture
  setup_ws || return
  publish_v2
  answers "$T/answers" "Choose [1]:" 3
  in_pty "$WS" "$T/answers" "$HOME/.local/bin/aiwp" update
  rc_is 0
  has "cancelled: nothing was changed"
  [ "$(version_of "$WS")" = 0.1.0 ]; check "not updated" $?
  [ "$(data_tag)" = v0.1.0 ]; check "the data folder did not move" $?
}

test_update_needs_a_terminal_or_a_target() {
  fixture
  setup_ws || return
  publish_v2
  run_aiwp_in "$WS" update
  rc_is 2
  has "with no terminal, aiwp update needs --all or a workspace folder"
  [ "$(data_tag)" = v0.1.0 ]; check "nothing moved" $?
}

test_update_one_folder_only() {
  fixture
  setup_ws || return
  second_ws
  publish_v2
  run_aiwp_in "$T" update "$WS2"
  rc_is 0
  has "Summary (data folder at 0.2.0):"
  [ "$(version_of "$WS")" = 0.1.0 ]; check "the other one stays" $?
  [ "$(version_of "$WS2")" = 0.2.0 ]; check "the one named is updated" $?
  # The other one, behind the data folder, is updated by a later run without moving the data folder again.
  run_aiwp_in "$T" update --all
  rc_is 0
  [ "$(version_of "$WS")" = 0.2.0 ]; check "caught up with the data folder" $?
  has "up to date (0.2.0)"
}

test_update_all_skips_a_changed_core_and_a_missing_folder_without_blocking() {
  fixture
  setup_ws || return
  second_ws
  run_aiwp_in "$T" new "$T/ws3"
  chmod u+w "$WS/docs/change.md"
  echo edited >"$WS/docs/change.md"
  chmod -R u+w "$T/ws3"
  rm -rf "$T/ws3"
  publish_v2
  run_aiwp_in "$T" update --all
  rc_is 1
  has "skipped: the core changed (aiwp repair in it, then aiwp update)"
  has "skipped: folder missing (aiwp forget $T/ws3)"
  has "updated 0.1.0 -> 0.2.0"
  [ "$(version_of "$WS")" = 0.1.0 ]; check "the changed one is left as it is" $?
  content_is "$WS/docs/change.md" edited
  [ "$(version_of "$WS2")" = 0.2.0 ]; check "the other one is updated" $?
}

test_update_asks_or_skips_when_claude_runs_in_the_workspace() {
  fixture
  setup_ws || return
  second_ws
  publish_v2
  # A process named claude whose current folder is inside the workspace.
  (cd "$WS/docs" && exec -a claude sleep 120) &
  local fake=$!
  sleep 0.3
  run_aiwp_in "$T" update --all
  rc_is 1
  has "claude is running in this workspace (pid $fake)"
  has "skipped: claude is running (pid $fake)"
  [ "$(version_of "$WS")" = 0.1.0 ]; check "not swapped under the running claude" $?
  [ "$(version_of "$WS2")" = 0.2.0 ]; check "the other one is updated" $?
  answers "$T/answers" "Update it anyway? [y/N]" n
  in_pty "$T" "$T/answers" "$HOME/.local/bin/aiwp" update "$WS"
  rc_is 1
  [ "$(version_of "$WS")" = 0.1.0 ]; check "answered no" $?
  answers "$T/answers" "Update it anyway? [y/N]" y
  in_pty "$T" "$T/answers" "$HOME/.local/bin/aiwp" update "$WS"
  rc_is 0
  [ "$(version_of "$WS")" = 0.2.0 ]; check "answered yes" $?
  kill "$fake" 2>/dev/null
  wait "$fake" 2>/dev/null
}

test_update_up_to_date_with_claude_running_is_not_a_skip() {
  fixture
  setup_ws || return
  (cd "$WS" && exec -a claude sleep 120) &
  local fake=$!
  sleep 0.3
  run_aiwp_in "$T" update --all
  rc_is 0
  has "up to date (0.1.0)"
  hasnt "claude is running"
  kill "$fake" 2>/dev/null
  wait "$fake" 2>/dev/null
}

test_update_force_goes_on_with_claude_running() {
  fixture
  setup_ws || return
  publish_v2
  (cd "$WS" && exec -a claude sleep 120) &
  local fake=$!
  sleep 0.3
  run_aiwp_in "$T" update --all --force
  rc_is 0
  [ "$(version_of "$WS")" = 0.2.0 ]; check "--force updates anyway" $?
  kill "$fake" 2>/dev/null
  wait "$fake" 2>/dev/null
}

# --- inside a Claude Code session

test_session_refuses_what_changes_state() {
  fixture
  setup_ws || return
  publish_v2
  local args
  while IFS= read -r args; do
    # shellcheck disable=SC2086  # the words of each case
    CLAUDE_CODE_CHILD_SESSION=1 run_aiwp_in "$WS" $args
    rc_is 1
    has "refused inside a Claude Code session"
    has "in a terminal"
  done <<'CASES'

-- --resume
update
update --all
rollback
repair
_sync -- /tmp
forget /tmp/x
CASES
  CLAUDE_CODE_CHILD_SESSION=1 run_aiwp_in "$T" new "$WS"
  rc_is 1
  has "That folder is a registered workspace"
  # Another spelling of a registered folder that is gone.
  chmod -R u+w "$WS"
  mv "$WS" "$T/ws-away"
  CLAUDE_CODE_CHILD_SESSION=1 run_aiwp_in "$T" new "$T/docs/..//ws"
  rc_is 1
  has "That folder is a registered workspace"
  absent "$WS"
  mv "$T/ws-away" "$WS"
  hasnt "claude-stub"
  [ "$(version_of "$WS")" = 0.1.0 ]; check "nothing updated from a session" $?
  [ "$(data_tag)" = v0.1.0 ]; check "the data folder did not move" $?
  for args in list check version --help; do
    CLAUDE_CODE_CHILD_SESSION=1 run_aiwp_in "$WS" "$args"
    rc_is 0
    hasnt "refused"
  done
  # A new folder is fine from a session.
  CLAUDE_CODE_CHILD_SESSION=1 run_aiwp_in "$T" new "$T/ws-session"
  rc_is 0
  # A claude ancestor is a session too, with no variable: a parent process named claude.
  mkdir -p "$T/anc"
  printf '#!/bin/bash\n"$@"\nexit $?\n' >"$T/anc/claude"
  chmod 755 "$T/anc/claude"
  OUT="$(cd "$WS" && env -u AIWP_TEST_NO_ANCESTOR_CHECK "$T/anc/claude" "$HOME/.local/bin/aiwp" update --all 2>&1)"
  RC=$?
  rc_is 1
  has "refused inside a Claude Code session"
}

# --- self-update

test_self_update_runs_the_new_code() {
  fixture
  setup_ws || return
  publish_v2
  run_aiwp_in "$WS" update "$WS"
  rc_is 0
  has "fixture: running the aiwp of v0.2.0"
  has "updated: 0.1.0 -> 0.2.0"
  [ "$(manifest_field version)" = 0.2.0 ]; check "synced by the new code" $?
}

test_running_aiwp_is_immune_to_a_rewrite() {
  fixture
  setup_ws || return
  # A git that rewrites the running aiwp in place (same inode) the first time it is called.
  local running="$DATA/workspace/scripts/aiwp.sh" real_git
  real_git="$(command -v git)"
  cat >"$T/stub/git" <<STUB
#!/usr/bin/env bash
if [ ! -e "$T/rewritten" ]; then
  touch "$T/rewritten"
  for i in \$(seq 1 3000); do echo 'echo CORRUPTED-READ; exit 99'; done >"$running"
fi
exec "$real_git" "\$@"
STUB
  chmod 755 "$T/stub/git"
  run_aiwp_in "$WS" version
  rc_is 0
  present "$T/rewritten"
  has "workspace: 0.1.0"
  hasnt "CORRUPTED-READ"
  rm -f "$T/stub/git"
}

# Runs every test_* function (or the one given with --only) in a subshell.
main() {
  local only="" name
  if [ "${1:-}" = "--only" ]; then only="${2:-}"; fi
  [ -f "$INSTALLER" ] || echo "note: $INSTALLER not found: the fixture carries a stub installer, the install tests fail"
  for name in $(declare -F | awk '{print $3}' | grep '^test_'); do
    [ -z "$only" ] || [ "$name" = "$only" ] || continue
    CURRENT="$name"
    RUN=$((RUN + 1))
    local before="$FAILED"
    FAILED=0
    (
      "$name"
      exit "$FAILED"
    )
    local rc=$?
    FAILED=$((before + rc))
    [ "$rc" -eq 0 ] && echo "ok $name" || echo "FAILED $name ($rc checks)"
  done
  echo "aiwp tests: $RUN run, $FAILED failed checks"
  [ "$FAILED" -eq 0 ]
}

main "$@"
