#!/usr/bin/env bash
# The shared part of the aiwp suites (tests/aiwp/, tests/aiwp-update/, tests/aiwp-update-list/): fully offline, a temp
# HOME and XDG_DATA_HOME, a local bare repository built from fixture trees (v0.1.0, v0.2.0) through AIWP_REPO_URL, a
# stub claude. Never the real data folder or HOME. Sourced by each suite, which defines its test_* functions and ends
# with: main <suite name> "$@".
# shellcheck disable=SC2319  # check reads the status of the test right before it, on purpose
# shellcheck disable=SC2034,SC2119,SC2120  # the suites read HOLDER and pass run_install its arguments

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AIWP="$(cd "$LIB_DIR/../.." && pwd)/aiwp.sh"
INSTALLER="$(cd "$LIB_DIR/../../../.." && pwd)/install.sh"
# shellcheck source=scripts/tests/aiwp/fixture.sh
. "$LIB_DIR/fixture.sh"

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

# Creates a second workspace, $WS2, at v0.1.0 (after setup_ws).
second_ws() {
  WS2="$T/ws2"
  run_aiwp_in "$T" new "$WS2"
  [ "$RC" -eq 0 ] || check "aiwp new ws2" 1
}

# Runs every test_* function (or the one given with --only) in a subshell; $1 names the suite in the summary.
main() {
  local suite="$1" only="" name
  shift
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
  echo "$suite tests: $RUN run, $FAILED failed checks"
  [ "$FAILED" -eq 0 ]
}
