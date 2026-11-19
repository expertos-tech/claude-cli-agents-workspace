#!/usr/bin/env bash
# aiwp: creates, opens, updates, rolls back and repairs the work workspaces of Claude CLI Agents Workspace.
# The installer links ~/.local/bin/aiwp to this file in the data folder. Every line runs from main, on the last line:
# bash has read the whole file before main starts, so an update that rewrites this file never changes the running
# process, and after moving the data folder to a new release, aiwp re-executes the new copy to sync the workspace.
set -euo pipefail

# The closed list of writable folders of an installed workspace, the only place it is defined: guard-bash reads it
# through the hidden command "aiwp.sh _writable". Everything else the core holds is read-only: folders and
# executables 555, other files 444.
# 1. At the workspace root: the custom layer, the projects, scratch and work clones, the logs (the prompt log of
#    scripts/prompt-log.py in logs/prompts/), the generated .claude/ and the state of the hooks. They belong to the
#    person: a file the repository tracks under one of them (projects/README.md) is never installed, so no aiwp command
#    ever writes there.
AIWP_WRITABLE_ROOT="custom projects tmp logs .claude .history"
# 2. Outputs of the tools, created only when the tool's folder exists in the core version installed:
#    .data            Grafana data of observability; the console binaries built by make (.data/bin)
#    web/node_modules the front-end dependencies (npm ci)
#    internal/webui/dist  the front-end build the consoles embed (it keeps the tracked placeholder.html, 444)
#    web/dist         the front-end build of azurite-console
#    plugin/.claude-plugin/types  the types Claude Code writes when it validates the fable-alert plugin in place
AIWP_TOOL_OUTPUTS="
tools/observability/.data
tools/container-console-colima/.data
tools/container-console-colima/web/node_modules
tools/container-console-colima/internal/webui/dist
tools/container-console-docker-ce/.data
tools/container-console-docker-ce/web/node_modules
tools/container-console-docker-ce/internal/webui/dist
tools/azurite-console/web/node_modules
tools/azurite-console/web/dist
tools/fable-alert/plugin/.claude-plugin/types
"
AIWP_INSTALL_LINE="curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash"
AIWP_CHECK_TTL=86400
AIWP_REMOTE_TIMEOUT=5
AIWP_KEEP_BACKUPS=3

DATA=""
WS=""
WORK=""
LOCKED=0
DATA_LOCKED=0
SWAPS=0
RESTORED=0
RESTORE_FAILED=0
SYNC_RESULT=""
NEWEST=""
OFFLINE=0

# Prints the command reference.
usage() {
  cat <<'USAGE'
Usage: aiwp [-- <claude arguments>]
       aiwp new <folder> [--custom <git-url>]
       aiwp list | forget <folder>
       aiwp update [<folder> | --all] [--force]
       aiwp rollback | repair
       aiwp check [--quiet]
       aiwp version | --help

Works with the installation in the data folder (Linux and WSL: ${XDG_DATA_HOME:-~/.local/share}/
claude-cli-agents-workspace; macOS: ~/Library/Application Support/claude-cli-agents-workspace), the registry of the
installed workspaces there (workspaces.json), and the work workspace that holds the current folder (the nearest
folder above with .aiwp/manifest.json).

  (no command)  Open the workspace: check for a new release (at most once a day, 5 s limit, offline goes on) and,
                when there is one, say so; never update. Then run scripts/setup-claude.sh and start claude on the
                current version, with the arguments given after --. A workspace that is not in the registry yet is
                added to it.
  new <folder>  Create a workspace in a missing or empty folder and add it to the registry: copy the tracked files
                of workspace/ at the checked-out release (nothing else of the repository, and nothing under the
                writable folders custom/, projects/, tmp/, logs/, .claude/, .history/), write .aiwp/manifest.json,
                create the writable folders, make the core read-only, set up custom/ and run
                scripts/setup-claude.sh.
                custom/: --custom <url> clones that repository (an empty one gets a skeleton and a first commit);
                without it a terminal asks for the URL (empty: a new local repository); with no terminal a local
                skeleton is created.
                Language: a terminal then asks, once, the preferred language of communication with Claude, its
                English name (portuguese, spanish: English letters, spaces, hyphens and parentheses, at most 40;
                anything else is asked again), and writes it as "language", the native Claude Code setting, in
                .claude/settings.local.json, keeping its other keys. An empty answer or no terminal writes nothing:
                Claude replies in the language you write in. update, the opening and scripts/setup-claude.sh never
                ask it and never change that file.
  list          Print each registered workspace with its version and state: up to date, update available, core
                changed, folder missing, pinned, or stopped halfway.
  forget <folder>  Remove a workspace from the registry (a folder that is gone, or one you no longer update). The
                folder itself is never touched.
  update        In a terminal: list every registered workspace (number, path, version, state) and ask: [1] Update
                all (the default), [2] Choose which (by number), [3] Cancel. Then move the data folder to the newest
                release once and update each chosen workspace. Each one is first verified against its manifest; a
                workspace whose core changed (an edited file, a changed permission, a missing file) or whose folder
                is missing is skipped and reported, and the others go on. Each replaced or removed file is backed
                up in .aiwp/backup/<version>/ (the last 3 are kept), a journal is written, files are swapped by
                rename and unchanged files are not touched. A summary table ends the run. Before it swaps a
                workspace where claude is running, it names the process and asks.
                <folder>: update only that workspace, without asking which. --all: every registered workspace,
                without asking; pinned ones are left as they are, and one where claude is running is skipped unless
                --force. With no terminal, give --all or a folder. Updating a workspace clears its pin.
                A link ~/.local/bin/single-claude to the workspace's scripts/single-claude.sh, gone with the
                single-agent mode, is then removed and said; nothing else in ~/.local/bin is touched.
  rollback      Go back to the version of the newest backup and pin the workspace to it (.aiwp/pin), so aiwp
                update --all leaves it alone; aiwp update <folder>, or choosing it by number, updates it again.
  repair        Restore every core file and folder to the manifest's version and permission, from the data
                folder. Never touches custom/, projects/, tmp/, logs/, .claude/, .history/ or the tool outputs.
  check         Print one line when a newer release exists (one-day cache); never updates. --quiet: print only
                that line. Always exits 0.
  version       Print the installed and the workspace versions.

Inside a Claude Code session (the Bash tool, a hook) aiwp refuses update, rollback, repair, forget, the opening and a
new over a registered folder: they change the rules of the open session or start claude inside it. Close the
session and run them in a terminal. list, check, version and --help work anywhere.

A run that died during update or rollback leaves .aiwp/journal: the next aiwp update, rollback or repair restores
the manifest's version first, then goes on; the opening refuses until then.

Environment:
  AIWP_OS=linux|macos|windows  the platform to assume (tests)
  AIWP_TEST_DIE_AFTER_SWAPS=N  tests only: kill the run after N file swaps, to prove the journal recovery
  AIWP_TEST_NO_ANCESTOR_CHECK=1  tests only: detect a session by its environment alone, not by a claude ancestor

Exit codes: 0 success; 1 a failed check or step (update: a workspace skipped for a changed core, a running claude
or an error); 2 usage error (an unknown command included). With no command, claude's exit code.

Examples:
  aiwp new ~/my-workspace
  cd ~/my-workspace && aiwp
  aiwp -- --resume
  aiwp update
  aiwp update --all
  aiwp update ~/my-workspace
USAGE
}

# Stops with an error message (exit 1).
die() {
  echo "error: $*" >&2
  exit 1
}

# Stops with a usage error (exit 2).
die_usage() {
  echo "error: $*; see aiwp --help" >&2
  exit 2
}

# Removes the scratch folder and releases the workspace lock held by this process.
cleanup() {
  if [ -n "$WORK" ] && [ -d "$WORK" ]; then
    chmod -R u+w "$WORK" 2>/dev/null || true
    rm -rf "$WORK"
  fi
  WORK=""
  if [ "$LOCKED" -eq 1 ]; then
    exec 8>&-
    LOCKED=0
  fi
  if [ "$DATA_LOCKED" -eq 1 ]; then
    exec 9>&-
    DATA_LOCKED=0
  fi
}

# Prints the platform: linux (WSL included), macos or windows.
detect_os() {
  if [ -n "${AIWP_OS:-}" ]; then
    echo "$AIWP_OS"
    return 0
  fi
  case "$(uname -s)" in
    Linux) echo linux ;;
    Darwin) echo macos ;;
    MINGW* | MSYS* | CYGWIN*) echo windows ;;
    *) echo unknown ;;
  esac
}

# Sets DATA to the data folder of this platform.
set_data_dir() {
  case "$(detect_os)" in
    linux) DATA="${XDG_DATA_HOME:-$HOME/.local/share}/claude-cli-agents-workspace" ;;
    macos) DATA="$HOME/Library/Application Support/claude-cli-agents-workspace" ;;
    windows) die "native Windows shells are not supported; use WSL2" ;;
    *) die "unsupported platform: $(uname -s)" ;;
  esac
}

# Stops unless the data folder holds an installation.
require_data() {
  [ -d "$DATA/.git" ] || die "not installed: $DATA; install with: $AIWP_INSTALL_LINE"
}

# Runs git in the data folder, never asking for a password, without the lock descriptors.
dgit() {
  # Never with the lock descriptors: a child git leaves running (gc, maintenance, fsmonitor) would keep the lock.
  GIT_TERMINAL_PROMPT=0 git -C "$DATA" "$@" 8>&- 9>&-
}

# Succeeds when $1 is a release version (X.Y.Z, with or without a leading v).
semver_valid() {
  [[ "$1" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Succeeds when version $1 is newer than version $2 (both X.Y.Z, a leading v ignored); invalid ones are never newer.
semver_gt() {
  local a1 a2 a3 b1 b2 b3
  semver_valid "$1" && semver_valid "$2" || return 1
  IFS=. read -r a1 a2 a3 <<<"${1#v}"
  IFS=. read -r b1 b2 b3 <<<"${2#v}"
  if [ "$((10#$a1))" -ne "$((10#$b1))" ]; then [ "$((10#$a1))" -gt "$((10#$b1))" ]; return; fi
  if [ "$((10#$a2))" -ne "$((10#$b2))" ]; then [ "$((10#$a2))" -gt "$((10#$b2))" ]; return; fi
  [ "$((10#$a3))" -gt "$((10#$b3))" ]
}

# Prints the newest release tag vX.Y.Z among the lines of stdin, or nothing.
semver_max() {
  local best="" tag
  while IFS= read -r tag; do
    [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || continue
    if [ -z "$best" ] || semver_gt "$tag" "$best"; then best="$tag"; fi
  done
  echo "$best"
}

# The helper for what bash does badly: reading git trees with hashes, JSON, verification, the remote tags.
# Subcommands: tree, manifest-read, manifest-write, verify, ls-remote, changelog, reg-list, reg-set, reg-del,
# reg-has for the registry of workspaces, and settings-language (see each function below).
py() {
  AIWP_USER_FOLDERS="$AIWP_WRITABLE_ROOT" python3 -I - "$@" <<'PY'
"""Helper of aiwp.sh; each subcommand prints tab-separated lines for bash."""

import hashlib
import json
import os
import re
import stat
import subprocess
import sys

TAG = re.compile(r'^v(\d+)\.(\d+)\.(\d+)$')
# The root writable folders belong to the person: a file the repository tracks there is never installed.
USER_FOLDERS = set(os.environ.get('AIWP_USER_FOLDERS', '').split())


def fail(message):
    """Prints an error and exits 1."""
    print(f'error: {message}', file=sys.stderr)
    sys.exit(1)


def tree(data, commit, dest=None, wanted_file=None):
    """Prints mode, sha256 and path of every file under workspace/ at the commit; extracts the wanted ones to dest."""
    listing = subprocess.run(
        ['git', '-C', data, 'ls-tree', '-r', '-z', '--full-tree', commit, '--', 'workspace/'],
        capture_output=True,
        check=False,
    )
    if listing.returncode:
        fail(f'cannot list workspace/ at {commit}: {listing.stderr.decode(errors="replace").strip()}')
    entries = []
    for record in listing.stdout.split(b'\0'):
        if not record:
            continue
        meta, raw = record.split(b'\t', 1)
        mode, kind, obj = meta.split()
        path = raw.decode('utf-8')
        rel = path[len('workspace/') :]
        if kind != b'blob' or mode not in (b'100644', b'100755'):
            fail(f'unsupported entry in the core (a link or a submodule): {path}')
        if any(ch in rel for ch in '\t\n\r') or rel.split('/')[0] == '.aiwp':
            fail(f'unsupported path in the core: {path!r}')
        if rel.split('/')[0] in USER_FOLDERS:
            continue
        entries.append((rel, obj.decode(), '555' if mode == b'100755' else '444'))
    wanted = None
    if wanted_file:
        with open(wanted_file, encoding='utf-8') as handle:
            wanted = {line.rstrip('\n') for line in handle if line.strip()}
    batch = subprocess.run(
        ['git', '-C', data, 'cat-file', '--batch'],
        input=''.join(f'{obj}\n' for _, obj, _ in entries).encode(),
        capture_output=True,
        check=False,
    )
    if batch.returncode:
        fail('git cat-file failed in the data folder')
    out = batch.stdout
    pos = 0
    for rel, _obj, mode in entries:
        end = out.index(b'\n', pos)
        size = int(out[pos:end].split()[2])
        content = out[end + 1 : end + 1 + size]
        pos = end + 1 + size + 1
        print(f'{mode}\t{hashlib.sha256(content).hexdigest()}\t{rel}')
        if dest and (wanted is None or rel in wanted):
            target = os.path.join(dest, rel)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, 'wb') as handle:
                handle.write(content)


def manifest_read(path):
    """Prints the header (#, version, tag, commit) and one line per file: mode, sha256, path."""
    with open(path, encoding='utf-8') as handle:
        data = json.load(handle)
    print('\t'.join(['#', data['version'], data.get('tag') or '-', data['commit']]))
    for item in data['files']:
        print('\t'.join([item['mode'], item['sha256'], item['path']]))


def manifest_write(out, version, tag, commit, tsv):
    """Writes the manifest JSON from the tab-separated lines (mode, sha256, path) of the tsv file."""
    files = []
    with open(tsv, encoding='utf-8') as handle:
        for line in handle:
            mode, sha, rel = line.rstrip('\n').split('\t', 2)
            files.append({'path': rel, 'sha256': sha, 'mode': mode})
    files.sort(key=lambda item: item['path'])
    data = {
        'product': 'claude-cli-agents-workspace',
        'format': 1,
        'version': version,
        'tag': None if tag in ('', '-') else tag,
        'commit': commit,
        'files': files,
    }
    with open(out, 'w', encoding='utf-8') as handle:
        json.dump(data, handle, indent=2)
        handle.write('\n')


def verify(root, tsv, writable_file):
    """Prints each difference of the core from the tsv: missing, notfile, changed, mode, notdir and dirmode lines."""
    with open(writable_file, encoding='utf-8') as handle:
        writable = {line.rstrip('\n') for line in handle if line.strip()}
    folders = {''}
    with open(tsv, encoding='utf-8') as handle:
        rows = [line.rstrip('\n').split('\t', 2) for line in handle if line.strip()]
    for _mode, _sha, rel in rows:
        parts = rel.split('/')
        folders.update('/'.join(parts[:i]) for i in range(1, len(parts)))
    # A folder of the core that is a link or a file: what is under it is never read or written through it.
    broken = set()
    for folder in sorted(folders):
        try:
            if folder and not stat.S_ISDIR(os.lstat(os.path.join(root, folder)).st_mode):
                broken.add(folder)
        except FileNotFoundError:
            pass
    for mode, sha, rel in rows:
        parts = rel.split('/')
        if any('/'.join(parts[:i]) in broken for i in range(1, len(parts))):
            continue
        path = os.path.join(root, rel)
        try:
            info = os.lstat(path)
        except FileNotFoundError:
            print(f'missing\t{rel}')
            continue
        if not stat.S_ISREG(info.st_mode):
            print(f'notfile\t{rel}')
            continue
        actual = format(info.st_mode & 0o777, 'o')
        try:
            with open(path, 'rb') as handle:
                digest = hashlib.sha256(handle.read()).hexdigest()
        except OSError:
            digest = ''
        if digest != sha:
            print(f'changed\t{rel}')
        if actual != mode:
            print(f'mode\t{rel}\t{actual}\t{mode}')
    for folder in sorted(folders):
        path = os.path.join(root, folder) if folder else root
        try:
            info = os.lstat(path)
        except FileNotFoundError:
            continue
        if not stat.S_ISDIR(info.st_mode):
            print(f'notdir\t{folder}')
        elif folder in writable:
            continue
        elif info.st_mode & 0o777 != 0o555:
            print(f'dirmode\t{folder or "."}\t{format(info.st_mode & 0o777, "o")}')


def ls_remote(url, timeout):
    """Prints the newest release tag of the remote; exits 1 when it cannot be reached in time."""
    env = dict(os.environ, GIT_TERMINAL_PROMPT='0')
    env.setdefault('GIT_SSH_COMMAND', 'ssh -o BatchMode=yes')
    try:
        result = subprocess.run(
            ['git', 'ls-remote', '--tags', '--refs', url],
            capture_output=True,
            text=True,
            timeout=float(timeout),
            env=env,
            check=False,
        )
    except (subprocess.TimeoutExpired, OSError):
        sys.exit(1)
    if result.returncode:
        sys.exit(1)
    best = None
    for line in result.stdout.splitlines():
        name = line.rsplit('refs/tags/', 1)[-1]
        match = TAG.match(name)
        if match:
            key = tuple(int(part) for part in match.groups())
            if best is None or key > best[0]:
                best = (key, name)
    print(best[1] if best else '')


def version_key(text):
    """Returns the comparable tuple of X.Y.Z, or None."""
    match = re.match(r'^v?(\d+)\.(\d+)\.(\d+)$', text)
    return tuple(int(part) for part in match.groups()) if match else None


def changelog(path, old, new):
    """Prints the CHANGELOG sections of the versions newer than old, up to new."""
    low, high = version_key(old), version_key(new)
    printing = False
    with open(path, encoding='utf-8') as handle:
        for line in handle:
            heading = re.match(r'^## \[(\d+\.\d+\.\d+)\]', line)
            if heading:
                key = version_key(heading.group(1))
                printing = bool(low and high and low < key <= high)
            elif line.startswith('## '):
                printing = False
            if printing:
                sys.stdout.write(line)


def registry_load(path):
    """Returns the entries of the registry file (an empty list when it does not exist); exits 1 when it is invalid."""
    try:
        with open(path, encoding='utf-8') as handle:
            data = json.load(handle)
    except FileNotFoundError:
        return []
    except (OSError, ValueError) as error:
        fail(f'the registry {path} cannot be read ({error}); fix it or move it away, then run aiwp in each workspace')
    entries = data.get('workspaces') if isinstance(data, dict) else None
    if not isinstance(entries, list) or not all(
        isinstance(item, dict) and isinstance(item.get('path'), str) and item['path'].startswith('/')
        for item in entries
    ):
        fail(
            f'the registry {path} is not in the expected form; fix it or move it away, then run aiwp in each workspace'
        )
    return entries


def registry_save(path, entries):
    """Writes the registry atomically: a temp file in the same folder, flushed, then renamed over the old one."""
    tmp = f'{path}.tmp.{os.getpid()}'
    with open(tmp, 'w', encoding='utf-8') as handle:
        json.dump({'product': 'claude-cli-agents-workspace', 'format': 1, 'workspaces': entries}, handle, indent=2)
        handle.write('\n')
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp, path)


def registry_locked(path, change):
    """Runs change(entries) under an exclusive lock of the registry (a lock file next to it, released when this
    process ends, even when it dies), and saves the entries it returns; None saves nothing."""
    import fcntl
    import time

    lock_path = os.path.join(os.path.dirname(path), '.git', 'aiwp', 'workspaces.lock')
    os.makedirs(os.path.dirname(lock_path), exist_ok=True)
    with open(lock_path, 'a', encoding='utf-8') as lock:
        deadline = time.monotonic() + 30
        while True:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() > deadline:
                    fail(f'another aiwp run holds the registry lock {lock_path}')
                time.sleep(0.1)
        entries = change(registry_load(path))
        if entries is not None:
            registry_save(path, entries)


def now_utc():
    """Returns the current UTC time as YYYY-MM-DDTHH:MM:SSZ."""
    import datetime

    return datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def reg_list(path):
    """Prints one line per registered workspace: path, version, created, updated."""
    for item in registry_load(path):
        fields = [item['path'], str(item.get('version') or '-'), str(item.get('created') or '-')]
        fields.append(str(item.get('updated') or '-'))
        if not any(ch in ''.join(fields) for ch in '\t\n\r'):
            print('\t'.join(fields))


def reg_set(path, folder, version):
    """Adds the workspace at folder to the registry, or updates its version and update time."""
    if not folder.startswith('/') or any(ch in folder for ch in '\t\n\r'):
        fail(f'unsupported workspace path: {folder!r}')

    def change(entries):
        """Updates the entry of folder, or appends a new one."""
        stamp = now_utc()
        for item in entries:
            if item['path'] == folder:
                item['version'] = version
                item['updated'] = stamp
                return entries
        entries.append({'path': folder, 'version': version, 'created': stamp, 'updated': stamp})
        return entries

    registry_locked(path, change)


def reg_del(path, folder):
    """Removes the workspace at folder (as given, absolute, or with its links resolved); exits 1 when not found."""
    wanted = {folder, os.path.abspath(folder), os.path.realpath(folder)}
    found = []

    def change(entries):
        """Drops the matching entries; saves nothing when there is none."""
        kept = [item for item in entries if item['path'] not in wanted]
        found.extend(item['path'] for item in entries if item['path'] in wanted)
        return kept if found else None

    registry_locked(path, change)
    if not found:
        fail(f'not in the registry: {folder} (aiwp list shows the registered workspaces)')
    print('\n'.join(found))


def reg_has(path, folder):
    """Exits 0 when the workspace at folder (as given, absolute, or with its links resolved) is registered, else 1."""
    wanted = {folder, os.path.abspath(folder), os.path.realpath(folder)}
    sys.exit(0 if any(item['path'] in wanted for item in registry_load(path)) else 1)


def settings_language(path, value):
    """Sets "language" to value in the Claude Code settings file at path (created when missing), keeping every other
    key; written atomically (a temp file in the same folder, then renamed), 2-space indent. A file that is not a
    regular file holding a JSON object is left as it is: prints a warning and exits 1."""
    data, mode = {}, None
    if os.path.lexists(path):
        try:
            info = os.lstat(path)
            if not stat.S_ISREG(info.st_mode):
                raise ValueError('not a regular file')
            with open(path, encoding='utf-8') as handle:
                data = json.load(handle)
        except (OSError, ValueError) as error:
            print(f'warning: {path} cannot be read ({error}); it was left as it is', file=sys.stderr)
            sys.exit(1)
        if not isinstance(data, dict):
            print(f'warning: {path} is not a JSON object; it was left as it is', file=sys.stderr)
            sys.exit(1)
        mode = stat.S_IMODE(info.st_mode)
    data['language'] = value
    tmp = f'{path}.tmp.{os.getpid()}'
    try:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o666 if mode is None else mode)
        with os.fdopen(fd, 'w', encoding='utf-8') as handle:
            json.dump(data, handle, indent=2)
            handle.write('\n')
            handle.flush()
            os.fsync(handle.fileno())
        if mode is not None:
            os.chmod(tmp, mode)
        os.replace(tmp, path)
    except OSError as error:
        if os.path.lexists(tmp):
            os.unlink(tmp)
        print(f'warning: cannot write {path} ({error})', file=sys.stderr)
        sys.exit(1)


COMMANDS = {
    'settings-language': settings_language,
    'reg-list': reg_list,
    'reg-set': reg_set,
    'reg-del': reg_del,
    'reg-has': reg_has,
    'tree': tree,
    'manifest-read': manifest_read,
    'manifest-write': manifest_write,
    'verify': verify,
    'ls-remote': ls_remote,
    'changelog': changelog,
}

if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
    fail('unknown helper command')
try:
    COMMANDS[sys.argv[1]](*sys.argv[2:])
    sys.stdout.flush()
except BrokenPipeError:
    # The reader took what it wanted (head -n 1) and closed the pipe: not an error.
    os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
    sys.exit(0)
PY
}

# Prints the root of the workspace holding the current folder, or fails.
find_workspace() {
  local dir
  dir="$(pwd -P)"
  while :; do
    if [ -f "$dir/.aiwp/manifest.json" ]; then
      echo "$dir"
      return 0
    fi
    [ "$dir" != "/" ] || return 1
    dir="$(dirname "$dir")"
  done
}

# Sets WS to the workspace holding the current folder, or stops.
require_workspace() {
  WS="$(find_workspace)" || die "not inside a workspace (no .aiwp/manifest.json in this folder or above); create one with: aiwp new <folder>"
}

# What aiwp refuses inside a Claude Code session, with the same words guard-bash gives: each one would change the rules
# of the open session, or start claude inside it.
MSG_OPEN="Opening the workspace starts claude inside this session. Close the session and run \`aiwp\` in a terminal."
MSG_UPDATE="Updating the workspace changes the rules of this open session. Close the session and run \`aiwp update\` in a terminal."
MSG_ROLLBACK="Rolling the workspace back changes the rules of this open session. Close the session and run \`aiwp rollback\` in a terminal."
MSG_REPAIR="Repairing the workspace rewrites the rules of this open session. Close the session and run \`aiwp repair\` in a terminal."
MSG_SYNC="Syncing the workspace changes the rules of this open session. Close the session and run \`aiwp update\` in a terminal."
MSG_FORGET="Forgetting a workspace changes the registry of the installed workspaces. Close the session and run \`aiwp forget\` in a terminal."
MSG_NEW="That folder is a registered workspace: creating it again replaces its entry. Close the session and run \`aiwp new\` in a terminal."

# Succeeds when aiwp runs inside a Claude Code session: CLAUDE_CODE_CHILD_SESSION, which Claude Code sets in what its
# Bash tool and hooks run (CLAUDECODE is not enough: IDE extensions set it in their own terminals too), or a claude
# process among the ancestors.
in_claude_session() {
  local pid="$PPID" depth=0 line ppid comm
  [ -z "${CLAUDE_CODE_CHILD_SESSION:-}" ] || return 0
  [ "${AIWP_TEST_NO_ANCESTOR_CHECK:-}" != 1 ] || return 1
  while [ "${pid:-0}" -gt 1 ] && [ "$depth" -lt 64 ]; do
    line="$(ps -o ppid= -o comm= -p "$pid" 2>/dev/null)" || return 1
    read -r ppid comm <<<"$line"
    [ "$(basename -- "${comm:-none}")" != claude ] || return 0
    pid="$ppid"
    depth=$((depth + 1))
  done
  return 1
}

# Stops (exit 1) with message $1 when aiwp runs inside a Claude Code session.
refuse_in_session() {
  in_claude_session || return 0
  echo "error: refused inside a Claude Code session. $1" >&2
  exit 1
}

# Succeeds when a person can answer: stdin and stdout are a terminal.
has_tty() {
  [ -t 0 ] && [ -t 1 ]
}

# The registry of the installed workspaces, in the data folder.
registry() {
  echo "$DATA/workspaces.json"
}

# Prints the real path of folder $1, or fails when it does not exist.
real_dir() {
  (cd "$1" 2>/dev/null && pwd -P)
}

# Adds workspace $1 (a real path) to the registry with version $2, or updates its version.
register() {
  py reg-set "$(registry)" "$1" "$2"
}

# Succeeds when workspace $1 (a real path) is in the registry.
registered() {
  py reg-has "$(registry)" "$1" 2>/dev/null
}

# Adds the workspace that holds the current folder to the registry when it is not there yet (a workspace created
# before the registry existed). Never inside a session; a failure only warns.
register_here() {
  local here version
  in_claude_session && return 0
  here="$(find_workspace)" || return 0
  registered "$here" && return 0
  version="$(py manifest-read "$here/.aiwp/manifest.json" 2>/dev/null | head -n 1 | cut -f 2)" || version=""
  if register "$here" "${version:--}"; then
    echo "registered: $here (aiwp list shows every workspace)"
  else
    echo "warning: could not add $here to the registry $(registry)" >&2
  fi
}

# Prints the pids of the claude processes whose current folder is workspace $1 or a folder under it. Linux reads
# /proc; macOS asks lsof; elsewhere, or when that fails, nothing (best effort).
claude_pids_in() {
  local ws="$1" proc pid comm argv0 cwd
  case "$(detect_os)" in
    linux)
      for proc in /proc/[0-9]*; do
        pid="${proc#/proc/}"
        [ "$pid" != "$$" ] || continue
        comm=""
        argv0=""
        IFS= read -r comm 2>/dev/null <"$proc/comm" || true
        IFS= read -r -d "" argv0 2>/dev/null <"$proc/cmdline" || true
        [ "$comm" = claude ] || [ "${argv0##*/}" = claude ] || continue
        cwd="$(readlink "$proc/cwd" 2>/dev/null)" || continue
        case "$cwd/" in "$ws/"*) echo "$pid" ;; esac
      done ;;
    macos)
      command -v lsof >/dev/null 2>&1 || return 0
      lsof -a -d cwd -c claude -Fpn 2>/dev/null | awk -v ws="$ws/" '
        /^p/ { pid = substr($0, 2) }
        /^n/ { if (index(substr($0, 2) "/", ws) == 1) print pid }' ;;
  esac
  return 0
}

# Takes the update lock of the data folder (.git/aiwp/update.lock, descriptor 9): one aiwp update at a time moves
# the data folder and the workspaces; install.sh takes the same lock. After the re-exec into the new release the
# descriptor is still open (AIWP_DATA_LOCK names its file), and locking it again is the same lock.
take_data_lock() {
  local file="$DATA/.git/aiwp/update.lock"
  # Held already by this process (aiwp update going on to the sync): reopening the file would drop the lock.
  [ "$DATA_LOCKED" -ne 1 ] || return 0
  mkdir -p "$DATA/.git/aiwp" 2>/dev/null || true
  local rc=0
  # The re-exec passes AIWP_DATA_LOCK only to the new aiwp; descriptor 9 must be that very file.
  if [ "${AIWP_DATA_LOCK:-}" = "$file" ] && same_file 9 "$file"; then
    :
  else
    exec 9>>"$file" || die "cannot take the lock $file (is its folder writable?)"
  fi
  unset AIWP_DATA_LOCK
  flock_fd 9 || rc=$?
  if [ "$rc" -ne 0 ]; then
    exec 9>&-
    [ "$rc" -eq 1 ] || die "cannot lock $file"
    die "another aiwp update is running (pid $(lock_holder "$file"))"
  fi
  echo "$$" >"$file"
  DATA_LOCKED=1
}

# Succeeds when open descriptor $1 is file $2 (same device and inode).
same_file() {
  python3 -I -c 'import os, sys
a, b = os.fstat(int(sys.argv[1])), os.stat(sys.argv[2])
sys.exit(0 if (a.st_dev, a.st_ino) == (b.st_dev, b.st_ino) else 1)' "$1" "$2" 2>/dev/null
}

# Locks open descriptor $1 (flock, exclusive, no wait): exit 1 when another process holds it, 2 on any other error
# (printed). The lock belongs to the open file, so it holds while this
# process or a process it execs keeps the descriptor, and the system drops it when they end, even killed: there is no
# stale lock to take over.
flock_fd() {
  python3 -I -c 'import fcntl, sys
try:
    fcntl.flock(int(sys.argv[1]), fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    sys.exit(1)
except OSError as error:
    print(f"error: flock failed: {error}", file=sys.stderr)
    sys.exit(2)' "$1"
}

# Prints the pid written in lock file $1 by its holder, or "unknown".
lock_holder() {
  local pid
  pid="$(head -n 1 "$1" 2>/dev/null | tr -cd '0-9')" || pid=""
  echo "${pid:-unknown}"
}

# Takes the workspace lock (.aiwp/aiwp.lock, descriptor 8), held until cleanup or the end of the process.
take_lock() {
  local file="$WS/.aiwp/aiwp.lock"
  local rc=0
  exec 8>>"$file" || die "cannot take the lock $file (is .aiwp/ writable?)"
  flock_fd 8 || rc=$?
  if [ "$rc" -ne 0 ]; then
    exec 8>&-
    [ "$rc" -eq 1 ] || die "cannot lock $file"
    die "another aiwp run is working on this workspace (pid $(lock_holder "$file"))"
  fi
  echo "$$" >"$file"
  LOCKED=1
}

# Creates the scratch folder of this run: in .aiwp/ of the workspace (once the lock is held, the scratch folders of
# runs that died are removed first), else in the data folder. Nothing is written outside them.
make_work() {
  local base old
  [ -z "$WORK" ] || return 0
  if [ "$LOCKED" -eq 1 ]; then
    base="$WS/.aiwp"
    for old in "$base"/work.*; do
      [ -d "$old" ] || continue
      chmod -R u+w "$old" 2>/dev/null || true
      rm -rf "$old"
    done
  else
    base="$DATA/.git/aiwp"
    mkdir -p "$base"
  fi
  WORK="$(mktemp -d "$base/work.XXXXXX")"
}

# Writes the manifest's lines (mode, sha256, path) to $2 and prints "version<TAB>tag<TAB>commit" of manifest $1.
read_manifest() {
  local all="$WORK/manifest.all"
  py manifest-read "$1" >"$all" || die "cannot read the manifest $1"
  tail -n +2 "$all" >"$2"
  head -n 1 "$all" | cut -f 2-
}

# Prints every folder that holds a core file of tsv $1 (the root excluded), one per line, sorted.
core_dirs() {
  awk -F'\t' '{ n = split($3, a, "/"); p = ""; for (i = 1; i < n; i++) { p = (p == "" ? a[i] : p "/" a[i]); print p } }' "$1" | LC_ALL=C sort -u
}

# Prints the writable folders for the core of tsv $1: the root ones, and each tool output whose tool folder exists.
writable_dirs() {
  local dirs="$WORK/dirs.$$" d
  core_dirs "$1" >"$dirs"
  for d in $AIWP_WRITABLE_ROOT; do echo "$d"; done
  for d in $AIWP_TOOL_OUTPUTS; do
    if grep -qxF -- "$(echo "$d" | cut -d/ -f1-2)" "$dirs"; then echo "$d"; fi
  done
  rm -f "$dirs"
}

# Succeeds when folder $1 (relative) is writable in the target core (WRITABLE file of this run).
is_writable_dir() {
  grep -qxF -- "$1" "$WORK/writable"
}

# Gives write permission on core folder $1 (relative; "." is the root) for one change.
open_dir() {
  chmod u+w "$WS/$1"
}

# Takes write permission back from core folder $1, unless it is a writable folder.
close_dir() {
  [ "$1" != "." ] && is_writable_dir "$1" && return 0
  chmod 555 "$WS/$1"
}

# Creates core folder $1 (relative) and its missing parents, opening each parent only for the creation.
ensure_dir() {
  local rel="$1" parent
  [ "$rel" != "." ] && [ ! -d "$WS/$rel" ] || return 0
  parent="$(dirname "$rel")"
  ensure_dir "$parent"
  open_dir "$parent"
  mkdir "$WS/$rel"
  close_dir "$parent"
}

# Counts one swap; the test hook kills the run after AIWP_TEST_DIE_AFTER_SWAPS swaps.
count_swap() {
  SWAPS=$((SWAPS + 1))
  if [ -n "${AIWP_TEST_DIE_AFTER_SWAPS:-}" ] && [ "$SWAPS" -ge "$AIWP_TEST_DIE_AFTER_SWAPS" ]; then
    # The whole run dies: the workspace's subshell and the aiwp process around it.
    kill -KILL "$$" "$BASHPID"
  fi
}

# Puts file $2 at core path $1 with mode $3: written next to the old one and renamed over it, the folder open only
# during the swap. A running script keeps reading the old file until it ends.
swap_in() {
  local rel="$1" src="$2" mode="$3" dir tmp
  dir="$(dirname "$rel")"
  ensure_dir "$dir"
  tmp="$WS/$dir/.aiwp-tmp.$(basename "$rel").$$"
  open_dir "$dir"
  cp "$src" "$tmp"
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$WS/$rel"
  close_dir "$dir"
  count_swap
}

# Removes core file $1, the folder open only during the removal.
remove_core_file() {
  local rel="$1" dir
  dir="$(dirname "$rel")"
  [ -e "$WS/$rel" ] || [ -L "$WS/$rel" ] || return 0
  open_dir "$dir"
  rm -f "$WS/$rel"
  close_dir "$dir"
  count_swap
}

# Removes the folders listed in file $1 that the core of tsv $2 no longer has, when they are empty, deepest first.
prune_dirs() {
  local keep="$WORK/keep-dirs" d
  core_dirs "$2" >"$keep"
  LC_ALL=C sort -ru "$1" | while IFS= read -r d; do
    [ -n "$d" ] && [ "$d" != "." ] && [ -d "$WS/$d" ] || continue
    grep -qxF -- "$d" "$keep" && continue
    grep -qxF -- "$d" "$WORK/writable" && continue
    if [ -z "$(ls -A "$WS/$d")" ]; then
      open_dir "$(dirname "$d")"
      rmdir "$WS/$d"
      close_dir "$(dirname "$d")"
    else
      echo "warning: left in place, not empty: $d"
    fi
  done
}

# Creates the missing writable folders (mode 755).
ensure_writable_dirs() {
  local d
  while IFS= read -r d; do
    [ -d "$WS/$d" ] && continue
    ensure_dir "$(dirname "$d")"
    open_dir "$(dirname "$d")"
    mkdir -m 755 "$WS/$d"
    close_dir "$(dirname "$d")"
  done <"$WORK/writable"
}

# Applies the core permissions of tsv $1: files 444 or 555, core folders 555 (the root last), writable ones untouched.
apply_modes() {
  local mode sha rel d linked="$WORK/linked-dirs"
  local -a files444=() files555=() dirs=()
  # A core folder replaced by a link is never followed: nothing under it is changed (verify reports it).
  core_dirs "$1" | while IFS= read -r d; do [ ! -L "$WS/$d" ] || echo "$d/"; done >"$linked"
  while IFS=$'\t' read -r mode sha rel; do
    : "$sha"
    if [ -s "$linked" ] && awk -v p="$rel" 'index(p, $0) == 1 { found = 1 } END { exit !found }' "$linked"; then continue; fi
    if [ "$mode" = 555 ]; then files555+=("$WS/$rel"); else files444+=("$WS/$rel"); fi
  done <"$1"
  [ "${#files444[@]}" -eq 0 ] || chmod 444 "${files444[@]}"
  [ "${#files555[@]}" -eq 0 ] || chmod 555 "${files555[@]}"
  while IFS= read -r d; do
    [ ! -L "$WS/$d" ] || continue
    is_writable_dir "$d" || dirs+=("$WS/$d")
  done < <(core_dirs "$1")
  [ "${#dirs[@]}" -eq 0 ] || chmod 555 "${dirs[@]}"
  chmod 555 "$WS"
}

# Verifies the core against tsv $1; prints each difference in words and fails when there is any.
verify_core() {
  local out="$WORK/verify" kind a b c
  py verify "$WS" "$1" "$WORK/writable" >"$out" || die "cannot verify the core"
  [ -s "$out" ] || return 0
  while IFS=$'\t' read -r kind a b c; do
    case "$kind" in
      missing) echo "  missing: $a" ;;
      notfile) echo "  not a regular file: $a" ;;
      changed) echo "  changed: $a (differs from the installed version)" ;;
      mode) echo "  permission: $a is $b, expected $c" ;;
      notdir) echo "  not a folder: $a" ;;
      dirmode) echo "  permission: $a/ is $b, expected 555" ;;
    esac
  done <"$out"
  return 1
}

# Writes the manifest atomically from tsv $4: version $1, tag $2, commit $3.
write_manifest() {
  local tmp="$WS/.aiwp/.manifest.json.tmp.$$"
  py manifest-write "$tmp" "$1" "$2" "$3" "$4"
  chmod 444 "$tmp"
  mv -f "$tmp" "$WS/.aiwp/manifest.json"
}

# Prints the product version at commit $1 of the data folder.
version_at() {
  dgit cat-file blob "$1:workspace/VERSION" 2>/dev/null | tr -d '[:space:]'
}

# Prints the release tag that points at commit $1 (the newest when several do), or "-".
tag_at() {
  local tag
  tag="$(dgit tag --points-at "$1" | semver_max)"
  echo "${tag:--}"
}

# Prints the newest release known: the remote's (checked at most once a day unless $1 is "fresh", 5 s limit) and the
# data folder's own tags. Offline, says so in one line on stderr and uses what the data folder knows.
latest_release() {
  local mode="$1" cache="$DATA/.git/aiwp/release-check" url now checked="" latest="" cached_url="" remote="" local_tags
  url="$(dgit remote get-url origin 2>/dev/null || true)"
  now="$(date +%s)"
  if [ "$mode" != fresh ] && [ -f "$cache" ]; then
    cached_url="$(sed -n 's/^url=//p' "$cache")"
    checked="$(sed -n 's/^checked=//p' "$cache")"
    latest="$(sed -n 's/^latest=//p' "$cache")"
  fi
  if [ -n "$url" ] && [ "$cached_url" = "$url" ] && [[ "$checked" =~ ^[0-9]+$ ]] && [ $((now - checked)) -lt "$AIWP_CHECK_TTL" ]; then
    remote="$latest"
  elif [ -n "$url" ] && remote="$(py ls-remote "$url" "$AIWP_REMOTE_TIMEOUT")"; then
    mkdir -p "$(dirname "$cache")"
    printf 'url=%s\nchecked=%s\nlatest=%s\n' "$url" "$now" "$remote" >"$cache.tmp.$$"
    mv -f "$cache.tmp.$$" "$cache"
  else
    remote=""
    [ -z "$WORK" ] || : >"$WORK/offline"
    echo "warning: could not check for a new release (offline or no answer in ${AIWP_REMOTE_TIMEOUT}s); going on with the version installed" >&2
  fi
  local_tags="$(dgit tag -l 'v*' 2>/dev/null || true)"
  printf '%s\n%s\n' "$remote" "$local_tags" | semver_max
}

# Moves the data folder to tag $1, fetching it when missing. Prints why and returns 1 when it cannot (offline, local
# changes in the data folder, another run moving it at the same time); nothing is changed then.
data_checkout() {
  local tag="$1"
  if ! dgit rev-parse -q --verify "refs/tags/$tag^{commit}" >/dev/null; then
    dgit fetch --quiet --tags --force origin 2>/dev/null || { echo "could not fetch $tag into $DATA (offline?)"; return 1; }
  fi
  if [ -n "$(dgit status --porcelain --untracked-files=no)" ]; then
    echo "the data folder has local changes, and nobody edits it: $DATA; discard them (git -C \"$DATA\" checkout -- .) or run the installer again"
    return 1
  fi
  dgit checkout --quiet --detach "refs/tags/$tag" 2>/dev/null || { echo "could not check out $tag in $DATA"; return 1; }
}

# Prints the changelog entries from version $2 (excluded) to $3 (included) at commit $1.
show_changelog() {
  local file="$WORK/CHANGELOG.md"
  dgit cat-file blob "$1:workspace/CHANGELOG.md" >"$file" 2>/dev/null || return 0
  py changelog "$file" "$2" "$3" | sed 's/^/  /'
}

# Brings the core to the tree at commit $1 of the data folder. Verifies first and stops on any difference (exit 3);
# backs up what it replaces or removes, writes the journal, swaps only what changed, then the manifest. Sets
# SYNC_RESULT to what it did, for the summary.
sync_core() {
  local commit="$1" header old_version new_version tag op rel mode backup changes
  local old="$WORK/old.tsv" new="$WORK/new.tsv" plan="$WORK/plan" stage="$WORK/stage" wanted="$WORK/wanted"
  header="$(read_manifest "$WS/.aiwp/manifest.json" "$old")"
  old_version="$(echo "$header" | cut -f 1)"
  new_version="$(version_at "$commit")"
  [ -n "$new_version" ] || die "no workspace/VERSION at $commit in the data folder"
  tag="$(tag_at "$commit")"
  writable_dirs "$old" >"$WORK/writable"
  if ! verify_core "$old"; then
    echo "error: the core differs from the manifest of $old_version: this workspace was not updated and nothing in it changed." >&2
    echo "Restore it with: aiwp repair in it (your changes to core files are lost; keep a copy first), then aiwp update" >&2
    exit 3
  fi
  py tree "$DATA" "$commit" >"$new"
  awk -F'\t' 'NR == FNR { om[$3] = $1; os[$3] = $2; next }
    { seen[$3] = 1
      if (!($3 in os)) print "add\t" $3
      else if (os[$3] != $2) print "write\t" $3
      else if (om[$3] != $1) print "chmod\t" $3 }
    END { for (p in os) if (!(p in seen)) print "remove\t" p }' "$old" "$new" | LC_ALL=C sort -t "$(printf '\t')" -k2 >"$plan"
  writable_dirs "$new" >"$WORK/writable"
  if [ ! -s "$plan" ] && [ "$old_version" = "$new_version" ]; then
    echo "up to date: $new_version"
    ensure_writable_dirs
    rm -f "$WS/.aiwp/pin"
    SYNC_RESULT="up to date ($new_version)"
    return 0
  fi
  echo "update: $old_version -> $new_version"
  show_changelog "$commit" "$old_version" "$new_version"
  awk -F'\t' '$1 == "add" || $1 == "write" { print $2 }' "$plan" >"$wanted"
  mkdir -p "$stage"
  py tree "$DATA" "$commit" "$stage" "$wanted" >/dev/null

  backup="$WS/.aiwp/backup/$old_version"
  rm -rf "$backup"
  mkdir -p "$backup/files"
  cp "$WS/.aiwp/manifest.json" "$backup/manifest.json"
  while IFS=$'\t' read -r op rel; do
    case "$op" in
      write | remove)
        mkdir -p "$backup/files/$(dirname "$rel")"
        cp "$WS/$rel" "$backup/files/$rel" ;;
    esac
  done <"$plan"
  touch "$backup"

  {
    printf 'op=update\nfrom=%s\nto=%s\nbackup=%s\n' "$old_version" "$new_version" "$old_version"
    awk -F'\t' '$1 == "add" { print "add\t" $2 }' "$plan"
  } >"$WS/.aiwp/journal.tmp"
  mv -f "$WS/.aiwp/journal.tmp" "$WS/.aiwp/journal"

  while IFS=$'\t' read -r op rel; do
    case "$op" in
      add | write)
        mode="$(awk -F'\t' -v p="$rel" '$3 == p { print $1; exit }' "$new")"
        swap_in "$rel" "$stage/$rel" "$mode" ;;
      chmod)
        mode="$(awk -F'\t' -v p="$rel" '$3 == p { print $1; exit }' "$new")"
        chmod "$mode" "$WS/$rel" ;;
      remove) remove_core_file "$rel" ;;
    esac
  done <"$plan"
  core_dirs "$old" >"$WORK/old-dirs"
  prune_dirs "$WORK/old-dirs" "$new"
  ensure_writable_dirs
  apply_modes "$new"
  write_manifest "$new_version" "$tag" "$commit" "$new"
  rm -f "$WS/.aiwp/journal" "$WS/.aiwp/pin"
  prune_backups
  changes="$(awk -F'\t' '{ n[$1]++ } END { printf "%d changed, %d added, %d removed", n["write"] + n["chmod"], n["add"], n["remove"] }' "$plan")"
  echo "updated: $old_version -> $new_version ($changes); backup in .aiwp/backup/$old_version/"
  SYNC_RESULT="updated $old_version -> $new_version"
}

# Keeps the newest AIWP_KEEP_BACKUPS backups.
prune_backups() {
  local dir="$WS/.aiwp/backup" old
  [ -d "$dir" ] || return 0
  # shellcheck disable=SC2012  # the names are versions, never odd characters
  ls -1t "$dir" | tail -n +"$((AIWP_KEEP_BACKUPS + 1))" | while IFS= read -r old; do
    [ -n "$old" ] || continue
    chmod -R u+w "${dir:?}/$old"
    rm -rf "${dir:?}/$old"
  done
}

# Restores every core file and folder to tsv $1 (from manifest commit $2). Content comes from backup folder $3 when
# it holds the right version, else from the data folder. Prints each fix; sets RESTORED to the number of fixes and
# RESTORE_FAILED to 1 when something could not be fixed. Always returns 0, so errexit stays on inside.
restore_core() {
  local tsv="$1" commit="$2" backup="${3:-}" kind rel a b mode sha src fixed=0 rc=0 d f
  local out="$WORK/verify" want="$WORK/restore"
  # A core folder replaced by a link or a file: change nothing at all, so nothing is written through the link.
  py verify "$WS" "$tsv" "$WORK/writable" >"$out" || die "cannot verify the core"
  if grep -q '^notdir' "$out"; then
    awk -F'\t' '$1 == "notdir" { print "not fixed: " $2 " is not a folder (a link?); move it away and run aiwp repair again" }' "$out"
    RESTORED=0
    RESTORE_FAILED=1
    return 0
  fi
  while IFS= read -r d; do ensure_dir "$d"; done < <(core_dirs "$tsv")
  ensure_writable_dirs
  py verify "$WS" "$tsv" "$WORK/writable" >"$out" || die "cannot verify the core"
  awk -F'\t' '$1 == "missing" || $1 == "changed" || $1 == "notfile" { print $2 }' "$out" | LC_ALL=C sort -u >"$want"
  if [ -s "$want" ]; then
    mkdir -p "$WORK/repair"
    py tree "$DATA" "$commit" "$WORK/repair" "$want" >/dev/null 2>&1 || true
  fi
  while IFS=$'\t' read -r kind rel a b; do
    : "$b"
    case "$kind" in
      missing | changed | notfile)
        mode="$(awk -F'\t' -v p="$rel" '$3 == p { print $1; exit }' "$tsv")"
        sha="$(awk -F'\t' -v p="$rel" '$3 == p { print $2; exit }' "$tsv")"
        src=""
        if [ -n "$backup" ] && [ -f "$backup/files/$rel" ] && [ "$(file_sha "$backup/files/$rel")" = "$sha" ]; then
          src="$backup/files/$rel"
        elif [ -f "$WORK/repair/$rel" ] && [ "$(file_sha "$WORK/repair/$rel")" = "$sha" ]; then
          src="$WORK/repair/$rel"
        fi
        if [ -z "$src" ]; then
          echo "not fixed: $rel (the data folder lacks its version; reinstall, then run aiwp repair)"
          rc=1
          continue
        fi
        if [ -d "$WS/$rel" ] && [ ! -L "$WS/$rel" ]; then
          echo "not fixed: $rel is a folder; move it away and run aiwp repair again"
          rc=1
          continue
        fi
        if [ "$kind" = notfile ]; then remove_core_file "$rel"; fi
        swap_in "$rel" "$src" "$mode"
        echo "fixed: $rel ($kind)"
        fixed=$((fixed + 1)) ;;
      mode)
        chmod "$b" "$WS/$rel"
        echo "fixed: $rel (permission $a -> $b)"
        fixed=$((fixed + 1)) ;;
      dirmode)
        echo "fixed: $rel/ (permission $a -> 555)"
        fixed=$((fixed + 1)) ;;
      notdir)
        echo "not fixed: $rel is not a folder; move it away and run aiwp repair again"
        rc=1 ;;
    esac
  done <"$out"
  # Leftovers of a swap that died halfway.
  while IFS= read -r d; do
    for f in "$WS/$d"/.aiwp-tmp.*; do
      [ -e "$f" ] || continue
      open_dir "$d"
      rm -f "$f"
      close_dir "$d"
    done
  done < <({ echo .; core_dirs "$tsv"; })
  apply_modes "$tsv"
  RESTORED="$fixed"
  RESTORE_FAILED="$rc"
}

# Prints the sha256 of file $1.
file_sha() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$1" | cut -d ' ' -f 1
  else
    shasum -a 256 -- "$1" | cut -d ' ' -f 1
  fi
}

# When .aiwp/journal exists, the last update or rollback died halfway: restores the manifest's version (from the
# backup, else from the data folder), removes what the dead run added, and deletes the journal.
recover_if_needed() {
  local journal="$WS/.aiwp/journal" header version commit backup_name backup="" op rel tsv="$WORK/recover.tsv"
  [ -f "$journal" ] || return 0
  header="$(read_manifest "$WS/.aiwp/manifest.json" "$tsv")"
  version="$(echo "$header" | cut -f 1)"
  commit="$(echo "$header" | cut -f 3)"
  op="$(sed -n 's/^op=//p' "$journal")"
  echo "recovering: the last aiwp ${op:-run} stopped halfway; restoring version $version"
  backup_name="$(sed -n 's/^backup=//p' "$journal")"
  if [ -n "$backup_name" ] && [ -d "$WS/.aiwp/backup/$backup_name" ]; then backup="$WS/.aiwp/backup/$backup_name"; fi
  writable_dirs "$tsv" >"$WORK/writable"
  : >"$WORK/added-dirs"
  while IFS=$'\t' read -r op rel; do
    [ "$op" = add ] || continue
    if awk -F'\t' -v p="$rel" '$3 == p { found = 1 } END { exit !found }' "$tsv"; then continue; fi
    remove_core_file "$rel"
    rm -f "$WS/$(dirname "$rel")"/.aiwp-tmp.* 2>/dev/null || true
    dirname "$rel" >>"$WORK/added-dirs"
  done < <(grep "^add	" "$journal" || true)
  # The parents of what was added, up to the root.
  while IFS= read -r rel; do
    while [ "$rel" != "." ] && [ -n "$rel" ]; do echo "$rel"; rel="$(dirname "$rel")"; done
  done <"$WORK/added-dirs" >"$WORK/added-tree"
  prune_dirs "$WORK/added-tree" "$tsv"
  restore_core "$tsv" "$commit" "$backup"
  [ "$RESTORE_FAILED" -eq 0 ] || die "the recovery could not restore every file; run aiwp repair"
  rm -f "$journal"
  echo "recovered: version $version restored ($RESTORED files fixed)"
}

# Runs the workspace's scripts/setup-claude.sh, which builds .claude/.
run_setup() {
  if [ -f "$WS/scripts/setup-claude.sh" ]; then
    (cd "$WS" && AIWP_DATA_LOCK="" bash scripts/setup-claude.sh "$@" 8>&- 9>&-) || {
      echo "attention: scripts/setup-claude.sh failed; run it again: bash scripts/setup-claude.sh" >&2
      return 1
    }
  fi
}

# Writes the skeleton of a new custom layer into $1 (an empty git repo) and commits it.
custom_skeleton() {
  local dir="$1"
  cat >"$dir/README.md" <<'EOF'
# Custom layer

The private layer of this workspace: what belongs to you or your company and never goes into the product.
It is a git repository of its own. Put here:

- `my-rules/`: your own rules (`<name>.md`), skills (`skills/<name>/`) and agents (`agents/<name>.md`); each one
  reaches the next sessions as `custom-<name>` in `.claude/`.
- `rules-config.json`: the core rules, skills and agents this workspace turns off, and the core rules it replaces
  with its own (`/rules`).
- `core-terms.txt`: terms that must never reach a public repository (company and customer names).
- `projects.md`: the list of your projects.
- `requests/`: your requests: pending at its root, `qa/<project>/` once on `developer`, `done/<project>/` once released.
- `config/prompt-log/sources.json`: other folders whose sessions the prompt log reads (the log itself is in `logs/`).
- `env/<tool>.env`: the filled `.env` files of the tools. Git ignores `env/`: they are never committed.
EOF
  cat >"$dir/core-terms.txt" <<'EOF'
# Terms that must never reach a public repository: one extended regular expression per line, matched in any case.
# Blank lines and lines starting with # are ignored. Example (remove the leading # to use it):
# acme-corp
EOF
  cat >"$dir/.gitignore" <<'EOF'
# Filled .env files: never committed.
env/
*.env
.env
EOF
  git -C "$dir" add -A
  if [ -n "$(git -C "$dir" config user.name || true)" ]; then
    git -C "$dir" commit -q -m "chore: start the custom layer"
  else
    git -C "$dir" -c user.name=aiwp -c user.email= commit -q -m "chore: start the custom layer"
  fi
}

# Sets up custom/ of new workspace $1: clones $2 when given, else asks on a terminal, else a local skeleton.
setup_custom() {
  local ws="$1" url="$2"
  if [ -z "$url" ] && [ -t 0 ] && [ -t 1 ]; then
    printf 'Git URL of your custom layer repository (empty: a new local repository): '
    IFS= read -r url || url=""
  fi
  if [ -n "$url" ]; then
    git clone -q -- "$url" "$ws/custom" || die "could not clone the custom layer from $url"
    if git -C "$ws/custom" rev-parse -q --verify HEAD >/dev/null; then
      echo "custom/: cloned from $url"
    elif [ -n "$(git -C "$ws/custom" for-each-ref refs/remotes)" ]; then
      echo "attention: custom/: the remote's default branch does not exist; check out one: git -C custom switch <branch>"
    else
      custom_skeleton "$ws/custom"
      echo "custom/: the repository was empty; a skeleton was committed. Push it: git -C custom push -u origin HEAD"
    fi
  else
    mkdir -p "$ws/custom"
    git init -q "$ws/custom"
    custom_skeleton "$ws/custom"
    echo "custom/: a new local repository with a skeleton; give it a remote later (git -C custom remote add origin <url>)"
  fi
}

# Prints why $1 is not a language name (English letters, spaces, hyphens and parentheses, at most 40 characters);
# prints nothing when it is one. The letters are listed, never a range: a range depends on the locale.
language_problem() {
  local value="$1" letters='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
  case "$value" in
    *[!"$letters"' ()-']*) echo "use only English letters, spaces, hyphens and parentheses" ;;
    *) [ "${#value}" -le 40 ] || echo "at most 40 characters" ;;
  esac
}

# Asks once, on a terminal, the preferred language of communication with Claude, and writes it as "language", the
# native Claude Code setting, in .claude/settings.local.json of new workspace $1, keeping the file's other keys. An
# invalid answer is asked again; an empty answer, the end of input or no terminal writes nothing. A file that cannot
# take it only warns: the workspace is still created.
ask_language() {
  local ws="$1" answer problem
  has_tty || return 0
  while :; do
    printf 'Preferred language of communication with Claude, its English name (e.g. portuguese, spanish; empty: the language you write in): '
    IFS= read -r answer || { echo; return 0; }
    answer="${answer#"${answer%%[![:space:]]*}"}"
    answer="${answer%"${answer##*[![:space:]]}"}"
    [ -n "$answer" ] || return 0
    problem="$(language_problem "$answer")"
    [ -z "$problem" ] && break
    echo "not a language name: $problem."
  done
  if py settings-language "$ws/.claude/settings.local.json" "$answer"; then
    echo "language: $answer, in .claude/settings.local.json (change it there, key \"language\")"
  else
    echo "warning: the language was not written; add \"language\": \"$answer\" to .claude/settings.local.json" >&2
  fi
}

# aiwp new <folder> [--custom <url>]
cmd_new() {
  local target="" url="" commit tag version created=0 d
  while [ $# -gt 0 ]; do
    case "$1" in
      --custom)
        [ $# -ge 2 ] || die_usage "--custom needs a URL"
        url="$2"
        shift ;;
      --help | -h) usage; exit 0 ;;
      -*) die_usage "unknown option: $1" ;;
      *)
        [ -z "$target" ] || die_usage "one folder only"
        target="$1" ;;
    esac
    shift
  done
  [ -n "$target" ] || die_usage "aiwp new needs a folder"
  case "$target" in /*) ;; *) target="$PWD/$target" ;; esac
  case "$target" in *$'\t'* | *$'\n'* | *$'\r'*) die_usage "a folder name with a tab or a line break is not supported" ;; esac
  require_data
  if in_claude_session && registered "$target"; then refuse_in_session "$MSG_NEW"; fi
  if [ -e "$target" ]; then
    [ -d "$target" ] || die "$target exists and is not a folder"
    [ -z "$(ls -A "$target")" ] ||
      die "$target is not empty. Install into a new folder, then move your projects into its projects/ and your POCs into custom/pocs/, and run /normalize-projects in a session there"
  fi
  local parent
  parent="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P || true)"
  if [ -n "$parent" ]; then
    case "$parent/" in "$(cd "$DATA" && pwd -P)/"*) die "a workspace cannot live inside the data folder" ;; esac
    if (cd "$parent" && find_workspace >/dev/null); then die "$target is inside another workspace"; fi
  fi
  make_work
  commit="$(dgit rev-parse HEAD)"
  version="$(version_at "$commit")"
  [ -n "$version" ] || die "the data folder has no workspace/VERSION at $commit"
  tag="$(tag_at "$commit")"
  if [ ! -e "$target" ]; then mkdir -p "$target"; created=1; fi
  WS="$(cd "$target" && pwd -P)"
  # On a failure, remove what was created: the folder was missing or empty.
  NEW_CREATED="$created"
  trap 'new_failed' EXIT

  py tree "$DATA" "$commit" "$WS" >"$WORK/new.tsv"
  writable_dirs "$WORK/new.tsv" >"$WORK/writable"
  while IFS= read -r d; do mkdir -p "$WS/$d"; chmod 755 "$WS/$d"; done <"$WORK/writable"
  mkdir -p "$WS/.aiwp"
  write_manifest "$version" "$tag" "$commit" "$WORK/new.tsv"
  setup_custom "$WS" "$url"
  ask_language "$WS"
  apply_modes "$WORK/new.tsv"
  verify_core "$WORK/new.tsv" || die "the new workspace does not match its manifest"
  register "$WS" "$version" || die "could not add $WS to the registry $(registry)"
  trap cleanup EXIT
  echo "created: $WS (version $version${tag:+, $tag})"
  run_setup || exit 1
  cat <<NEXT

Next step:
  cd $WS && aiwp
NEXT
}

# Undoes a failed aiwp new: the target was missing or empty, so everything in it was created by this run.
# shellcheck disable=SC2329  # run by the EXIT trap of cmd_new
new_failed() {
  local rc=$?
  if [ "$rc" -ne 0 ] && [ -n "$WS" ] && [ -d "$WS" ]; then
    chmod -R u+w "$WS" 2>/dev/null || true
    if [ "${NEW_CREATED:-0}" -eq 1 ]; then
      rm -rf "$WS"
    else
      find "$WS" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    fi
    echo "aiwp new failed; nothing was left in $WS" >&2
  fi
  WS=""
  cleanup
  exit "$rc"
}

# Sets NEWEST to the newest release version known, X.Y.Z without the v: the remote's ($1: fresh asks it now, cached
# at most once a day), the data folder's tags and the data folder's own version. Offline, a fresh check falls back to
# the cached answer. Sets OFFLINE=1 when the remote did not answer.
newest_version() {
  local mode="$1" tag cached="" best
  OFFLINE=0
  tag="$(latest_release "$mode")"
  if [ -f "$WORK/offline" ]; then
    OFFLINE=1
    cached="$(sed -n 's/^latest=//p' "$DATA/.git/aiwp/release-check" 2>/dev/null || true)"
  fi
  best="$(printf '%s\n%s\nv%s\n' "$tag" "$cached" "$(version_at HEAD)" | semver_max)"
  NEWEST="${best#v}"
}

# Prints the state of workspace $1 against the newest version $2: folder missing, stopped halfway, core changed,
# pinned at X, update available (X) or up to date. Reads only.
ws_state() {
  local ws="$1" newest="$2" tsv="$WORK/state.tsv" version
  [ -f "$ws/.aiwp/manifest.json" ] || { echo "folder missing"; return 0; }
  [ ! -f "$ws/.aiwp/journal" ] || { echo "stopped halfway (aiwp update restores it)"; return 0; }
  version="$(py manifest-read "$ws/.aiwp/manifest.json" 2>/dev/null >"$tsv.all" && head -n 1 "$tsv.all" | cut -f 2)" ||
    { echo "manifest unreadable"; return 0; }
  tail -n +2 "$tsv.all" >"$tsv"
  writable_dirs "$tsv" >"$WORK/state.writable"
  if [ -n "$(py verify "$ws" "$tsv" "$WORK/state.writable" 2>/dev/null | head -n 1)" ]; then
    echo "core changed"
  elif [ -f "$ws/.aiwp/pin" ]; then
    echo "pinned at $version"
  elif [ -n "$newest" ] && semver_gt "$newest" "$version"; then
    echo "update available ($newest)"
  else
    echo "up to date"
  fi
}

# Prints the version in the manifest of workspace $1, or "-".
ws_version() {
  local v
  v="$(py manifest-read "$1/.aiwp/manifest.json" 2>/dev/null | head -n 1 | cut -f 2)" || v=""
  echo "${v:--}"
}

# Prints the registered workspaces as a numbered table against the newest version $1; fills REG_PATHS and REG_STATES.
print_registry() {
  local newest="$1" path version created updated state n=0
  REG_PATHS=()
  REG_STATES=()
  py reg-list "$(registry)" >"$WORK/registry" || die "cannot read the registry $(registry)"
  if [ ! -s "$WORK/registry" ]; then
    echo "No workspace is registered. Create one with: aiwp new <folder>"
    return 0
  fi
  printf '%3s  %-9s  %-28s  %s\n' "#" VERSION STATE PATH
  while IFS=$'\t' read -r path version created updated; do
    : "$created" "$updated"
    n=$((n + 1))
    state="$(ws_state "$path" "$newest")"
    [ "$state" = "folder missing" ] || version="$(ws_version "$path")"
    REG_PATHS+=("$path")
    REG_STATES+=("$state")
    printf '%3s  %-9s  %-28s  %s\n' "$n" "$version" "$state" "$path"
  done <"$WORK/registry"
}

# aiwp list
cmd_list() {
  local newest here
  [ $# -eq 0 ] || { [ "$1" = --help ] || [ "$1" = -h ] && { usage; exit 0; }; die_usage "list takes no argument"; }
  require_data
  register_here
  make_work
  newest_version cached
  newest="$NEWEST"
  echo "installed: $(version_at HEAD) ($DATA); newest release known: ${newest:-unknown}"
  print_registry "$newest"
  if here="$(find_workspace)" && ! registered "$here"; then
    echo "note: this workspace is not registered yet: $here; run aiwp in it, in a terminal, to add it"
  fi
}

# aiwp forget <folder>
cmd_forget() {
  local target="" removed
  while [ $# -gt 0 ]; do
    case "$1" in
      --help | -h) usage; exit 0 ;;
      -*) die_usage "unknown option for forget: $1" ;;
      *) [ -z "$target" ] || die_usage "forget takes one folder"; target="$1" ;;
    esac
    shift
  done
  [ -n "$target" ] || die_usage "aiwp forget needs a folder"
  refuse_in_session "$MSG_FORGET"
  require_data
  case "$target" in /*) ;; *) target="$PWD/$target" ;; esac
  removed="$(py reg-del "$(registry)" "$target")" || exit 1
  echo "forgotten: $removed (the folder itself was not touched)"
}

# Asks which of the listed workspaces to update; fills CHOSEN (indexes into REG_PATHS) or exits 0 on cancel.
choose_workspaces() {
  local answer word ok i
  CHOSEN=()
  echo
  echo "  [1] Update all (default)"
  echo "  [2] Choose which (numbers)"
  echo "  [3] Cancel"
  while :; do
    printf 'Choose [1]: '
    IFS= read -r answer || answer=3
    case "$answer" in
      "" | 1) for i in "${!REG_PATHS[@]}"; do CHOSEN+=("$i"); done; CHOSE_ALL=1; return 0 ;;
      2) break ;;
      3) echo "cancelled: nothing was changed"; exit 0 ;;
      *) echo "Answer 1, 2 or 3." ;;
    esac
  done
  while :; do
    printf 'Numbers of the workspaces to update (for example: 1 3): '
    IFS= read -r answer || { echo; echo "cancelled: nothing was changed"; exit 0; }
    CHOSEN=()
    ok=1
    for word in ${answer//,/ }; do
      if [[ "$word" =~ ^[0-9]+$ ]] && [ "$((10#$word))" -ge 1 ] && [ "$((10#$word))" -le "${#REG_PATHS[@]}" ]; then
        CHOSEN+=("$((10#$word - 1))")
      else
        echo "Not a number of the list: $word"
        ok=0
      fi
    done
    [ "$ok" -eq 1 ] && [ "${#CHOSEN[@]}" -gt 0 ] && return 0
    [ "${#CHOSEN[@]}" -gt 0 ] || [ "$ok" -eq 0 ] || echo "Give at least one number."
  done
}

# aiwp update [<folder> | --all] [--force]
cmd_update() {
  local all=0 force=0 target="" newest data_version tag head_commit tag_commit why i path
  local -a paths=() skipped=()
  CHOSEN=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --all) all=1 ;;
      --force) force=1 ;;
      --help | -h) usage; exit 0 ;;
      -*) die_usage "unknown option for update: $1" ;;
      *) [ -z "$target" ] || die_usage "update takes one folder"; target="$1" ;;
    esac
    shift
  done
  [ "$all" -eq 0 ] || [ -z "$target" ] || die_usage "give --all or a folder, not both"
  refuse_in_session "$MSG_UPDATE"
  require_data
  if [ -n "$target" ]; then
    path="$(real_dir "$target")" && [ -f "$path/.aiwp/manifest.json" ] ||
      die "not a workspace: $target (no .aiwp/manifest.json there); aiwp list shows the registered workspaces"
    target="$path"
  elif [ "$all" -eq 0 ] && ! has_tty; then
    die_usage "with no terminal, aiwp update needs --all or a workspace folder"
  fi
  take_data_lock
  make_work
  register_here
  if [ -n "$target" ] && ! registered "$target"; then
    register "$target" "$(ws_version "$target")" || die "could not add $target to the registry"
  fi
  newest_version fresh
  newest="$NEWEST"
  [ "$OFFLINE" -eq 0 ] || echo "going on with the newest release known: ${newest:-none}"
  data_version="$(version_at HEAD)"
  echo "Registered workspaces (newest release: ${newest:-unknown}):"
  print_registry "$newest"
  CHOSE_ALL=0
  if [ -n "$target" ]; then
    paths=("$target")
  else
    if [ "$all" -eq 1 ]; then
      for i in "${!REG_PATHS[@]}"; do CHOSEN+=("$i"); done
      CHOSE_ALL=1
    elif [ "${#REG_PATHS[@]}" -gt 0 ]; then
      choose_workspaces
    fi
    for i in "${CHOSEN[@]+"${CHOSEN[@]}"}"; do
      # Update all leaves a pinned workspace (aiwp rollback) as it is; choosing it by number updates it.
      if [ "$CHOSE_ALL" -eq 1 ] && [[ "${REG_STATES[$i]}" == "pinned at "* ]]; then
        skipped+=("${REG_PATHS[$i]}")
        continue
      fi
      paths+=("${REG_PATHS[$i]}")
    done
  fi
  : >"$DATA/.git/aiwp/update-results"
  for path in "${skipped[@]+"${skipped[@]}"}"; do
    printf '%s\tnote\tskipped: pinned (aiwp update %s updates it)\n' "$path" "$path" >>"$DATA/.git/aiwp/update-results"
  done
  local -a flags=()
  [ "$force" -eq 0 ] || flags+=(--force)
  { [ "$all" -eq 0 ] && has_tty; } || flags+=(--batch)
  # The data folder moves once, to the newest release; then the new release's aiwp updates the workspaces.
  tag="v$newest"
  if [ -n "$newest" ] && semver_gt "$newest" "$data_version"; then
    head_commit="$(dgit rev-parse HEAD)"
    tag_commit="$(dgit rev-parse -q --verify "refs/tags/$tag^{commit}" || true)"
    if [ "$head_commit" != "$tag_commit" ]; then
      why="$(data_checkout "$tag")" || die "$why; nothing was updated"
      echo "data folder: $data_version -> $newest"
      rm -rf "$WORK"
      WORK=""
      AIWP_DATA_LOCK="$DATA/.git/aiwp/update.lock" exec bash "$DATA/workspace/scripts/aiwp.sh" _sync "${flags[@]+"${flags[@]}"}" -- "${paths[@]+"${paths[@]}"}"
    fi
  fi
  cmd_sync "${flags[@]+"${flags[@]}"}" -- "${paths[@]+"${paths[@]}"}"
}

# The body of sync_one, run in its own subshell: workspace $1, batch $2, force $3, results file $4.
sync_in_subshell() {
  local answer pids results="$4"
  WS="$1"
  WORK=""
  LOCKED=0
  DATA_LOCKED=0
  trap cleanup EXIT
  take_lock
  make_work
  # Only a run that will swap files asks about a running claude: a journal to recover, or another release.
  pids=""
  if [ -f "$WS/.aiwp/journal" ] || [ "$(py manifest-read "$WS/.aiwp/manifest.json" 2>/dev/null | head -n 1 | cut -f 4)" != "$(dgit rev-parse HEAD)" ]; then
    pids="$(claude_pids_in "$WS" | tr '\n' ' ' | sed 's/ $//')"
  fi
  if [ -n "$pids" ] && [ "$3" -ne 1 ]; then
    if [ "$2" -eq 1 ]; then
      echo "claude is running in this workspace (pid $pids): not updated (--force updates it anyway)"
      printf '%s\tfail\tskipped: claude is running (pid %s)\n' "$WS" "$pids" >>"$results"
      exit 0
    fi
    printf 'claude is running in this workspace (pid %s): updating changes the rules under that session.\nUpdate it anyway? [y/N] ' "$pids"
    IFS= read -r answer || answer=""
    case "$answer" in
      y | Y | yes | YES) ;;
      *)
        printf '%s\tfail\tskipped: claude is running (pid %s)\n' "$WS" "$pids" >>"$results"
        exit 0 ;;
    esac
  fi
  recover_if_needed
  sync_core "$(dgit rev-parse HEAD)"
  run_setup --quiet || true
  register "$WS" "$(ws_version "$WS")" || echo "warning: could not record the new version in the registry" >&2
  remove_single_claude_link || true
  printf '%s\tok\t%s\n' "$WS" "$SYNC_RESULT" >>"$results"
}

# Removes ~/.local/bin/single-claude, the link the docs of the single-agent mode had people create, only when it is
# a symbolic link to scripts/single-claude.sh of this workspace ($WS) and that file no longer exists. Anything else
# there (a link to another folder or to a file that exists, a regular file) is left alone, silently. Touches nothing
# else in ~/.local/bin and never fails: a failed removal prints a warning.
remove_single_claude_link() {
  local link="$HOME/.local/bin/single-claude" target dir ws_scripts
  [ -L "$link" ] || return 0
  [ ! -e "$link" ] || return 0
  target="$(readlink "$link")" || return 0
  case "$target" in
    /*) ;;
    *) target="$HOME/.local/bin/$target" ;;
  esac
  if [ -e "$target" ] || [ -L "$target" ]; then return 0; fi
  [ "$(basename "$target")" = single-claude.sh ] || return 0
  # The same file however the workspace path is spelled: the folder of the target, resolved, is this workspace's
  # scripts/ (a core folder that exists after the update).
  if [ "$target" != "$WS/scripts/single-claude.sh" ]; then
    dir="$(real_dir "$(dirname "$target")")" || return 0
    ws_scripts="$(real_dir "$WS/scripts")" || return 0
    if [ -z "$dir" ] || [ "$dir" != "$ws_scripts" ]; then return 0; fi
  fi
  if rm -- "$link" 2>/dev/null; then
    echo "removed ~/.local/bin/single-claude: the single-agent mode no longer exists"
  else
    echo "warning: could not remove the link ~/.local/bin/single-claude to $target, which no longer exists; remove it by hand" >&2
  fi
}

# Updates workspace $1 to the data folder's release, in a subshell: its own lock, journal recovery, the check for a
# running claude ($2: 1 never asks; $3: 1 goes on anyway), the sync and setup-claude. Appends one line (path, level,
# result) to the results file $4.
sync_one() {
  local path="$1" batch="$2" force="$3" results="$4" rc lines version data_version
  if [ ! -f "$path/.aiwp/manifest.json" ]; then
    printf '%s\tnote\tskipped: folder missing (aiwp forget %s)\n' "$path" "$path" >>"$results"
    return 0
  fi
  version="$(ws_version "$path")"
  data_version="$(version_at HEAD)"
  if semver_gt "$version" "$data_version"; then
    printf '%s\tnote\tskipped: at %s, newer than the data folder (%s)\n' "$path" "$version" "$data_version" >>"$results"
    return 0
  fi
  lines="$(wc -l <"$results")"
  echo
  echo "== $path"
  # The workspace's own subshell: a failure there (exit 1, or 3 for a changed core) ends only that workspace.
  set +e
  (
    set -e
    sync_in_subshell "$path" "$batch" "$force" "$results"
  )
  rc=$?
  set -e
  if [ "$(wc -l <"$results")" -eq "$lines" ]; then
    if [ "$rc" -eq 3 ]; then
      printf '%s\tfail\tskipped: the core changed (aiwp repair in it, then aiwp update)\n' "$path" >>"$results"
    else
      printf '%s\tfail\tfailed (see the messages above)\n' "$path" >>"$results"
    fi
  fi
}

# aiwp _sync [--batch] [--force] -- <folder>...: updates each folder to the data folder's release and prints the
# summary. Run by aiwp update, by this release's code or by the previous one's right after it moved the data folder.
cmd_sync() {
  local batch=0 force=0 path results failed=0 level result
  while [ $# -gt 0 ]; do
    case "$1" in
      --batch) batch=1 ;;
      --force) force=1 ;;
      --) shift; break ;;
      *) die_usage "unknown option for _sync: $1" ;;
    esac
    shift
  done
  refuse_in_session "$MSG_SYNC"
  require_data
  take_data_lock
  make_work
  results="$DATA/.git/aiwp/update-results"
  [ -f "$results" ] || : >"$results"
  for path in "$@"; do
    sync_one "$path" "$batch" "$force" "$results"
  done
  echo
  if [ ! -s "$results" ]; then
    echo "Summary: no workspace to update (data folder at $(version_at HEAD))."
    rm -f "$results"
    return 0
  fi
  echo "Summary (data folder at $(version_at HEAD)):"
  printf '  %-40s  %s\n' RESULT WORKSPACE
  while IFS=$'\t' read -r path level result; do
    printf '  %-40s  %s\n' "$result" "$path"
    [ "$level" != fail ] || failed=1
  done <"$results"
  rm -f "$results"
  return "$failed"
}

# Starts claude in the workspace with the arguments given.
open_claude() {
  command -v claude >/dev/null 2>&1 || die "claude not found on PATH; install the Claude Code CLI"
  cleanup
  cd "$WS"
  exec claude "$@"
}

# aiwp (open): detection only. Says when a newer release exists, runs setup-claude and starts claude on the current
# version; never updates or swaps a core file.
cmd_open() {
  local current newest
  refuse_in_session "$MSG_OPEN"
  require_workspace
  require_data
  take_lock
  make_work
  if [ -f "$WS/.aiwp/journal" ]; then
    die "an aiwp update or rollback stopped halfway in this workspace; run aiwp repair (or aiwp update) in a terminal first, which restores it"
  fi
  register_here
  current="$(ws_version "$WS")"
  newest_version cached
  newest="$NEWEST"
  if [ -n "$newest" ] && semver_gt "$newest" "$current"; then
    if [ -f "$WS/.aiwp/pin" ]; then
      echo "Workspace version $newest is available; this workspace is pinned at $current (aiwp update $WS updates it). Opening this workspace on $current."
    else
      echo "A new workspace version $newest was detected (this workspace: $current). Run \`aiwp update\` to update; opening this workspace on $current."
    fi
  fi
  run_setup --quiet || true
  open_claude "$@"
}

# aiwp rollback: back to the version of the newest backup, pinned.
cmd_rollback() {
  local header current backup="" name target cur plan t_header t_version t_commit op rel mode sha
  refuse_in_session "$MSG_ROLLBACK"
  require_workspace
  require_data
  register_here
  take_lock
  make_work
  target="$WORK/target.tsv"
  cur="$WORK/current.tsv"
  plan="$WORK/plan"
  recover_if_needed
  header="$(read_manifest "$WS/.aiwp/manifest.json" "$cur")"
  current="$(echo "$header" | cut -f 1)"
  if [ -d "$WS/.aiwp/backup" ]; then
    # shellcheck disable=SC2012,SC2045  # the names are versions, never odd characters
    for name in $(ls -1t "$WS/.aiwp/backup"); do
      [ -f "$WS/.aiwp/backup/$name/manifest.json" ] && [ "$name" != "$current" ] || continue
      backup="$WS/.aiwp/backup/$name"
      break
    done
  fi
  [ -n "$backup" ] || die "no backup of an earlier version in .aiwp/backup/; nothing to roll back to"
  t_header="$(read_manifest "$backup/manifest.json" "$target")"
  t_version="$(echo "$t_header" | cut -f 1)"
  t_commit="$(echo "$t_header" | cut -f 3)"
  writable_dirs "$cur" >"$WORK/writable"
  if ! verify_core "$cur"; then
    echo "error: the core differs from the manifest of $current: the rollback stopped and changed nothing." >&2
    echo "Restore it with: aiwp repair" >&2
    exit 1
  fi
  awk -F'\t' 'NR == FNR { om[$3] = $1; os[$3] = $2; next }
    { seen[$3] = 1
      if (!($3 in os)) print "add\t" $3
      else if (os[$3] != $2) print "write\t" $3
      else if (om[$3] != $1) print "chmod\t" $3 }
    END { for (p in os) if (!(p in seen)) print "remove\t" p }' "$cur" "$target" | LC_ALL=C sort -t "$(printf '\t')" -k2 >"$plan"
  # Stage every file first: nothing is touched unless all the content of the old version is at hand.
  awk -F'\t' '$1 == "add" || $1 == "write" { print $2 }' "$plan" >"$WORK/wanted"
  mkdir -p "$WORK/stage"
  py tree "$DATA" "$t_commit" "$WORK/stage" "$WORK/wanted" >/dev/null 2>&1 || true
  while IFS=$'\t' read -r op rel; do
    case "$op" in add | write) ;; *) continue ;; esac
    sha="$(awk -F'\t' -v p="$rel" '$3 == p { print $2; exit }' "$target")"
    if [ -f "$backup/files/$rel" ] && [ "$(file_sha "$backup/files/$rel")" = "$sha" ]; then
      mkdir -p "$WORK/stage/$(dirname "$rel")"
      cp "$backup/files/$rel" "$WORK/stage/$rel"
    fi
    [ -f "$WORK/stage/$rel" ] && [ "$(file_sha "$WORK/stage/$rel")" = "$sha" ] ||
      die "the version $t_version of $rel is neither in the backup nor in the data folder; nothing was changed"
  done <"$plan"
  writable_dirs "$target" >"$WORK/writable.target"
  cat "$WORK/writable" "$WORK/writable.target" | LC_ALL=C sort -u >"$WORK/writable.both"
  mv "$WORK/writable.both" "$WORK/writable"
  {
    printf 'op=rollback\nfrom=%s\nto=%s\nbackup=\n' "$current" "$t_version"
    awk -F'\t' '$1 == "add" { print "add\t" $2 }' "$plan"
  } >"$WS/.aiwp/journal.tmp"
  mv -f "$WS/.aiwp/journal.tmp" "$WS/.aiwp/journal"
  while IFS=$'\t' read -r op rel; do
    mode="$(awk -F'\t' -v p="$rel" '$3 == p { print $1; exit }' "$target")"
    case "$op" in
      add | write) swap_in "$rel" "$WORK/stage/$rel" "$mode" ;;
      chmod) chmod "$mode" "$WS/$rel" ;;
      remove) remove_core_file "$rel" ;;
    esac
  done <"$plan"
  writable_dirs "$target" >"$WORK/writable"
  core_dirs "$cur" >"$WORK/old-dirs"
  prune_dirs "$WORK/old-dirs" "$target"
  ensure_writable_dirs
  apply_modes "$target"
  write_manifest "$t_version" "$(echo "$t_header" | cut -f 2)" "$t_commit" "$target"
  echo "$t_version" >"$WS/.aiwp/pin.tmp"
  mv -f "$WS/.aiwp/pin.tmp" "$WS/.aiwp/pin"
  rm -f "$WS/.aiwp/journal"
  echo "rolled back: $current -> $t_version; pinned at $t_version (aiwp update $WS updates it again)"
  register "$WS" "$t_version" || echo "warning: could not record the version in the registry" >&2
  run_setup --quiet || true
}

# aiwp repair: restores the core to the manifest.
cmd_repair() {
  local header version commit tsv
  refuse_in_session "$MSG_REPAIR"
  require_workspace
  require_data
  register_here
  take_lock
  make_work
  recover_if_needed
  tsv="$WORK/current.tsv"
  header="$(read_manifest "$WS/.aiwp/manifest.json" "$tsv")"
  version="$(echo "$header" | cut -f 1)"
  commit="$(echo "$header" | cut -f 3)"
  if ! dgit cat-file -e "$commit^{commit}" 2>/dev/null; then
    dgit fetch --quiet --tags --force origin || true
    dgit cat-file -e "$commit^{commit}" 2>/dev/null || die "the data folder lacks commit $commit of version $version; reinstall"
  fi
  writable_dirs "$tsv" >"$WORK/writable"
  restore_core "$tsv" "$commit" ""
  [ "$RESTORE_FAILED" -eq 0 ] || exit 1
  if [ "$RESTORED" -eq 0 ]; then echo "nothing to repair: the core matches version $version"; else echo "repaired: $RESTORED fixes (version $version)"; fi
}

# aiwp check [--quiet]: one line when a newer release exists.
cmd_check() {
  local quiet=0 current="" latest header
  while [ $# -gt 0 ]; do
    case "$1" in
      --quiet) quiet=1 ;;
      *) die_usage "unknown option for check: $1" ;;
    esac
    shift
  done
  if [ ! -d "$DATA/.git" ]; then
    [ "$quiet" -eq 1 ] || echo "not installed: $DATA"
    return 0
  fi
  if WS="$(find_workspace)"; then
    header="$(py manifest-read "$WS/.aiwp/manifest.json" 2>/dev/null | head -n 1 || true)"
    current="$(echo "$header" | cut -f 2)"
  else
    WS=""
    current="$(tr -d '[:space:]' <"$DATA/workspace/VERSION" 2>/dev/null || true)"
  fi
  if [ "$quiet" -eq 1 ]; then latest="$(latest_release cached 2>/dev/null || true)"; else latest="$(latest_release cached || true)"; fi
  journal_note
  if [ -n "$latest" ] && [ -n "$current" ] && semver_gt "$latest" "$current"; then
    echo "attention: Claude CLI Agents Workspace ${latest#v} is available (this workspace: $current); close every session of it and run aiwp update in a terminal"
  elif [ "$quiet" -eq 0 ]; then
    echo "up to date: ${current:-unknown}"
  fi
  return 0
}

# Prints one line when workspace $WS holds the journal of a run that died.
journal_note() {
  if [ -n "$WS" ] && [ -f "$WS/.aiwp/journal" ]; then
    echo "attention: an aiwp update or rollback stopped halfway in this workspace; the next aiwp update, rollback or repair restores it"
  fi
}

# aiwp version
cmd_version() {
  local commit header
  if [ -d "$DATA/.git" ]; then
    commit="$(dgit rev-parse HEAD)"
    echo "installed: $(version_at "$commit") ($(tag_at "$commit"), $DATA)"
  else
    echo "installed: none ($DATA)"
  fi
  if WS="$(find_workspace)"; then
    header="$(py manifest-read "$WS/.aiwp/manifest.json" | head -n 1)"
    echo "workspace: $(echo "$header" | cut -f 2) ($(echo "$header" | cut -f 3), $WS)"
    if [ -f "$WS/.aiwp/pin" ]; then echo "pinned at: $(cat "$WS/.aiwp/pin")"; fi
    journal_note
  fi
}

# Prints every writable path of an installed workspace, relative to its root, one per line: the root folders, .aiwp/
# (written only by aiwp) and the tool outputs. guard-bash reads this list (aiwp.sh _writable), so it is defined once.
print_writable() {
  local d
  for d in $AIWP_WRITABLE_ROOT .aiwp $AIWP_TOOL_OUTPUTS; do echo "$d"; done
}

# Dispatches the command. An unknown command is a usage error: arguments for claude come after --.
main() {
  trap cleanup EXIT
  local cmd="${1:-}"
  case "$cmd" in
    --help | -h | help) usage; return 0 ;;
    _writable) [ $# -eq 1 ] || die_usage "_writable takes no argument"; print_writable; return 0 ;;
    "" | -- | new | list | forget | update | rollback | repair | check | version | --version | _sync) ;;
    *) die_usage "unknown command: $cmd (to pass arguments to claude: aiwp -- <arguments>)" ;;
  esac
  set_data_dir
  case "$cmd" in
    "") cmd_open ;;
    --) shift; cmd_open "$@" ;;
    new) shift; cmd_new "$@" ;;
    list) shift; cmd_list "$@" ;;
    forget) shift; cmd_forget "$@" ;;
    update) shift; cmd_update "$@" ;;
    rollback) shift; [ $# -eq 0 ] || { [ "$1" = --help ] && { usage; return 0; }; die_usage "rollback takes no argument"; }; cmd_rollback ;;
    repair) shift; [ $# -eq 0 ] || { [ "$1" = --help ] && { usage; return 0; }; die_usage "repair takes no argument"; }; cmd_repair ;;
    check) shift; cmd_check "$@" ;;
    version | --version) cmd_version ;;
    _sync) shift; cmd_sync "$@" ;;
  esac
}

main "$@"; exit "$?"
