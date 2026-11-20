"""UserPromptSubmit hook: names the session <project>-<n> when the human runs /request, records the human's /merge (the
order the gate needs to merge), and warns when a message names a project that is not a workspace project, is out of
date, or has a hotfix on main not merged into developer yet.

The model cannot run /rename, so the title comes from here, with the same effect (hookSpecificOutput.sessionTitle).
The request file is the one /request reads: tmp/request.md with no argument, custom/requests/<name> for a bare file name
(custom/requests/doing/<name> when only that one exists: a request in progress), else a path relative to the root. The
project is the "**Project:** <name>" line of that file (written by /new-request); a file without it gives the repo
that holds the first projects/<path> it names: the nearest folder of that path, itself included, that holds a .git (any
folder at any depth of projects/ may be a repo, inside another one too), else the last folder of the path. <n> is one
more than the highest <project>-<n> among the running sessions of the workspace (Claude Code's registry of running
sessions, plus the claims this hook keeps under the git-ignored .history/session-numbers/, for the names the registry
does not show yet). A session already named <project>-<n> keeps its name.
The warning: a message (and, on /request, its request file) that names a repo of projects/ or a POC of custom/pocs/, by
its folder name, by a path (projects/<path>, which names its nearest repo only; custom/pocs/<poc>;
tmp/work/<work>/<clone>) or by the "**Project:**" line, gets the state of each (scripts/aiwp-project-state.sh) added
to the context when it has no marker or is out of date, with the order to warn the person and ask for authorization to
run /normalize-projects, and when a hotfix on main is not merged into developer yet (the gate refuses /merge into
that developer and the release until it is), with the order to tell the person. It never blocks: the request goes on
either way. A message that runs /normalize-projects gets no warning.
The merge order: a message that runs /merge (any form: /merge, /merge <work>/<clone>, /merge --main ..., /merge
--hotfix ...), typed as is or in the expanded form Claude Code may pass (<command-name>/merge</command-name> first),
appends the line "order<TAB><UTC time>[<TAB><kind><TAB><target>]" to the git-ignored .history/merge-orders/<session
id>, in one write under a lock. The target is what the person typed: "work<TAB><work>" for /merge <work>[/<clone>],
"main<TAB><project>" or "hotfix<TAB><project>" for /merge --main|--hotfix <project>, "text<TAB>-" for an argument
that names neither (the gate refuses it); no argument, no target: the clone of the session, any work. Phase 2 of the
gate (scripts/aiwp-gate.sh gate --merge) runs inside Claude Code only after such an order newer than the session's last
merge, younger than its time limit, and for a clone of the target typed; it appends its own "merged" line there. Only
the person's prompt reaches this hook, so the model cannot give the order; text that only mentions /merge, or /mergex,
is no order.
Any failure stays silent and the time is bounded (a capped walk, a state script with a deadline): the prompt always
goes on.
Usage: python3 -I session-title.py <workspace-root>   (hook JSON on stdin)
"""

import collections
import fcntl
import json
import os
import re
import subprocess
import sys
import time

REQUEST_COMMAND = re.compile(r'^\s*/request(?:\s+(\S+))?\s*$')
PROJECT_LINE = re.compile(r'^\s*\*\*Project:\*\*\s*`?([^`\s]+)`?\s*$', re.M)
PROJECT_PATH = re.compile(r'(?<![\w./-])projects/((?:[a-z0-9]+(?:-[a-z0-9]+)*/)*[a-z0-9]+(?:-[a-z0-9]+)*)')
KEBAB = re.compile(r'^[a-z0-9]+(?:-[a-z0-9]+)*$')
MAX_READ = 200_000
NORMALIZE_COMMAND = re.compile(r'^\s*/normalize-projects\b')
POC_PATH = re.compile(r'(?<![\w./-])custom/pocs/([a-z0-9]+(?:-[a-z0-9]+)*)')
# A clone's folder is its repo path relative to projects/ with each '/' written as '--' (scripts/aiwp-cmds.sh open).
CLONE_PATH = re.compile(r'(?<![\w./-])tmp/work/[^/\s]+/([a-z0-9]+(?:--?[a-z0-9]+)*)')
# The walk of projects/ for the warning, breadth first so the shallow repos come first: how deep a repo may sit (a repo
# inside another one included), how many folders it reads at most, and the folder names it never enters (dependencies
# and build outputs, never a project's own repo).
WALK_DEPTH = 6
WALK_BUDGET = 2000
WALK_SKIP = frozenset({'node_modules', 'vendor', 'target', 'dist', 'build', '__pycache__'})
MAX_NAMED = 5
# A folder name counts as named by itself only when it is distinctive: with a hyphen or a digit, or this long. A short
# plain name (api, web, docs) is named only by a path or the **Project:** line, never by an ordinary word.
MIN_PLAIN_NAME = 7
STATE_TIMEOUT_SECONDS = 4
# Without the session registry, a claim counts for this long.
CLAIM_TTL_SECONDS = 12 * 3600
# The person's order to merge: /merge as typed, or the expanded form of a slash command (its first <command-name>).
MERGE_COMMAND = re.compile(r'^\s*/merge(?:\s|$)')
COMMAND_NAME = re.compile(r'<command-name>\s*(\S*?)\s*</command-name>')
COMMAND_ARGS = re.compile(r'<command-args>(.*?)</command-args>', re.S)
# The target of a /merge: <work> or <work>/<clone>, or a project of projects/ after --main or --hotfix.
MERGE_WORK = re.compile(r'([0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9]+(?:-[a-z0-9]+)*)(?:/[A-Za-z0-9][A-Za-z0-9._-]*)?/?')
MERGE_PROJECT = re.compile(r'[A-Za-z0-9][A-Za-z0-9._-]*(?:/[A-Za-z0-9][A-Za-z0-9._-]*)*/?')
# A session id names the file of its orders: a plain name only (the same pattern as scripts/aiwp-gate.sh).
SESSION_ID = re.compile(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}')


def request_file(root, argument):
    """Returns the file /request reads: tmp/request.md, custom/requests/<name> (else custom/requests/doing/<name>, a
    request in progress, when only that one exists), or a path relative to the root."""
    if not argument:
        return os.path.join(root, 'tmp', 'request.md')
    if '/' not in argument:
        pending = os.path.join(root, 'custom', 'requests', argument)
        doing = os.path.join(root, 'custom', 'requests', 'doing', argument)
        return doing if not os.path.lexists(pending) and os.path.isfile(doing) else pending
    return os.path.join(root, argument)


def nearest_repo(root, path):
    """Returns the folder of projects/ that holds projects/<path>: the nearest one, the path itself included, with a
    .git entry; None when none has one (or there is no root)."""
    parts = path.split('/')
    for end in range(len(parts), 0, -1):
        folder = '/'.join(parts[:end])
        if root and os.path.lexists(os.path.join(root, 'projects', folder, '.git')):
            return folder
    return None


def project_of(text, root=None):
    """Returns the project name of a request text, or None: the **Project:** line, else the repo that holds the first
    projects/<path> it names (the nearest .git under root), else the last folder of that path."""
    found = PROJECT_LINE.search(text)
    if found:
        name = found.group(1).strip().rstrip('/').split('/')[-1].lower()
        return name if KEBAB.match(name) else None
    found = PROJECT_PATH.search(text)
    if not found:
        return None
    return (nearest_repo(root, found.group(1)) or found.group(1)).split('/')[-1]


def registry_folder():
    """Returns the folder where Claude Code keeps one file per running session (not a documented interface)."""
    base = os.environ.get('CLAUDE_CONFIG_DIR') or os.path.join(os.path.expanduser('~'), '.claude')
    return os.path.join(base, 'sessions')


def pid_alive(pid):
    """True when a process with that pid runs."""
    try:
        os.kill(int(pid), 0)
    except (OSError, ValueError, TypeError):
        return False
    return True


def active_sessions(root):
    """Returns {session id: name} of the running Claude Code sessions opened in the workspace, or None when the
    registry cannot be read."""
    folder = registry_folder()
    if not os.path.isdir(folder):
        return None
    base = os.path.realpath(root)
    sessions = {}
    for entry in os.listdir(folder):
        if not entry.endswith('.json'):
            continue
        try:
            with open(os.path.join(folder, entry), encoding='utf-8') as handle:
                info = json.load(handle)
        except (OSError, ValueError):
            continue
        if not isinstance(info, dict) or not pid_alive(info.get('pid')):
            continue
        if os.path.realpath(str(info.get('cwd') or '')) != base:
            continue
        sessions[str(info.get('sessionId') or '')] = str(info.get('name') or '')
    return sessions


def numbers_of(project, names):
    """Returns the numbers n of the names that are exactly <project>-<n>."""
    pattern = re.compile(re.escape(project) + r'-(\d+)')
    return {int(found.group(1)) for found in map(pattern.fullmatch, names) if found}


def next_number(root, project, session_id):
    """Returns the next number of a project: one more than the highest in use among the running sessions of the
    workspace, counting the names this hook gave that the registry may not show yet. Records the claim under a lock,
    so two sessions starting together get different numbers."""
    folder = os.path.join(root, '.history', 'session-numbers')
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, project + '.json'), 'a+', encoding='utf-8') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        handle.seek(0)
        try:
            claims = json.loads(handle.read() or '{}')
        except ValueError:
            claims = {}
        claims = claims if isinstance(claims, dict) else {}
        active = active_sessions(root)
        now = time.time()
        if active is None:
            # No registry: a claim counts while it is younger than the longest a session is expected to run.
            claims = {k: v for k, v in claims.items() if isinstance(v, list) and now - v[1] < CLAIM_TTL_SECONDS}
        else:
            claims = {k: v for k, v in claims.items() if k in active and k != session_id and isinstance(v, list)}
        taken = {v[0] for v in claims.values() if isinstance(v[0], int)}
        if active:
            taken |= numbers_of(project, [name for key, name in active.items() if key != session_id])
        number = max(taken, default=0) + 1
        claims[session_id or f'unknown-{now}'] = [number, now]
        handle.seek(0)
        handle.truncate()
        json.dump(claims, handle)
    return number


def title_for(data, root):
    """Returns the hook output for one UserPromptSubmit input, or None to leave the title as it is."""
    command = REQUEST_COMMAND.match(data.get('prompt') or '')
    if not command:
        return None
    path = os.path.realpath(request_file(root, command.group(1)))
    if not path.startswith(os.path.realpath(root) + os.sep) or not os.path.isfile(path):
        return None
    with open(path, encoding='utf-8', errors='replace') as handle:
        project = project_of(handle.read(MAX_READ), root)
    if not project:
        return None
    current = data.get('session_title') or ''
    if re.fullmatch(re.escape(project) + r'-\d+', current):
        return None
    name = f'{project}-{next_number(root, project, str(data.get("session_id") or ""))}'
    return {
        'hookSpecificOutput': {
            'hookEventName': 'UserPromptSubmit',
            'sessionTitle': name,
            'additionalContext': f'session-title: this session is now named {name} (set by the hook, like /rename).',
        }
    }


def runs_merge(prompt):
    """True when a prompt runs /merge: it starts with /merge followed by its end or a space, or it is the expanded form
    of a slash command (it starts with a <command-...> tag) whose first command name is /merge."""
    if not isinstance(prompt, str):
        return False
    if MERGE_COMMAND.match(prompt):
        return True
    found = COMMAND_NAME.search(prompt[:MAX_READ])
    return bool(found) and prompt.lstrip().startswith('<command-') and found.group(1) == '/merge'


def merge_target(prompt):
    """Returns the target the person typed with /merge as (kind, value): ('work', <work>) for <work>[/<clone>],
    ('main' or 'hotfix', <project>) for --main or --hotfix <project>, ('', '') for no argument (any work), and
    ('text', '-') for an argument that names neither, which the gate refuses."""
    if MERGE_COMMAND.match(prompt):
        args = prompt.lstrip()[len('/merge') :]
    else:
        found = COMMAND_ARGS.search(prompt[:MAX_READ])
        args = found.group(1) if found else ''
    words = args.split()
    if words and words[0] in ('--main', '--hotfix'):
        project = words[1] if len(words) > 1 else ''
        if MERGE_PROJECT.fullmatch(project) and '..' not in project.split('/'):
            return words[0][2:], project.rstrip('/')
        return 'text', '-'
    if not words:
        return '', ''
    found = MERGE_WORK.fullmatch(words[0])
    return ('work', found.group(1)) if found else ('text', '-')


def record_merge_order(data, root):
    """Appends 'order<TAB><UTC time>[<TAB><kind><TAB><target>]' to .history/merge-orders/<session id> when the prompt
    runs /merge (merge_target gives the target): one write in append mode, under a lock, never through a link. Returns
    True when it recorded the order."""
    session_id = str(data.get('session_id') or '')
    if not runs_merge(data.get('prompt')) or not SESSION_ID.fullmatch(session_id):
        return False
    folder = os.path.join(root, '.history', 'merge-orders')
    os.makedirs(folder, exist_ok=True)
    kind, value = merge_target(data['prompt'])
    target = f'\t{kind}\t{value}' if kind else ''
    line = f'order\t{time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}{target}\n'.encode()
    flags = os.O_WRONLY | os.O_APPEND | os.O_CREAT | getattr(os, 'O_NOFOLLOW', 0)
    descriptor = os.open(os.path.join(folder, session_id), flags, 0o600)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        os.write(descriptor, line)
    finally:
        os.close(descriptor)
    return True


def workspace_projects(root):
    """Returns {folder name: [targets]}: each repo of projects/ as 'projects/<path>' and each POC folder as
    'custom/pocs/<name>'. The walk is breadth first, up to WALK_DEPTH and at most WALK_BUDGET folders; it goes on inside
    a repo (a repo inside another one is a repo too) and never enters a hidden folder, a link, a WALK_SKIP folder or a
    folder it cannot read."""
    found = {}
    budget = WALK_BUDGET
    queue = collections.deque([(os.path.join(root, 'projects'), 'projects', 1)])
    while queue and budget > 0:
        folder, rel, depth = queue.popleft()
        try:
            with os.scandir(folder) as entries:
                children = sorted(entries, key=lambda entry: entry.name)
        except OSError:
            continue
        for entry in children:
            if budget <= 0:
                break
            if entry.name.startswith('.') or not entry.is_dir(follow_symlinks=False):
                continue
            budget -= 1
            path = f'{rel}/{entry.name}'
            if os.path.lexists(os.path.join(entry.path, '.git')):
                found.setdefault(entry.name, []).append(path)
            if depth < WALK_DEPTH and entry.name not in WALK_SKIP:
                queue.append((entry.path, path, depth + 1))
    pocs = os.path.join(root, 'custom', 'pocs')
    if os.path.isdir(pocs):
        with os.scandir(pocs) as entries:
            for entry in entries:
                if not entry.name.startswith('.') and entry.is_dir(follow_symlinks=False):
                    found.setdefault(entry.name, []).append(f'custom/pocs/{entry.name}')
    return found


def named_targets(text, projects):
    """Returns the targets of the projects a text names, in order, at most MAX_NAMED: by the **Project:** line, by a
    path (projects/<path>, its nearest repo only; custom/pocs/<poc>; tmp/work/<work>/<clone>) or by a distinctive
    folder name as a word, in the same case."""
    every = [target for targets in projects.values() for target in targets]
    named = []

    def add(targets):
        """Adds targets not named yet."""
        named.extend(target for target in targets if target not in named)

    for found in PROJECT_LINE.finditer(text):
        add(projects.get(found.group(1).strip().rstrip('/').split('/')[-1].lower(), []))
    for found in PROJECT_PATH.finditer(text):
        path = f'projects/{found.group(1)}/'
        holders = [target for target in every if path.startswith(target + '/')]
        add(sorted(holders, key=len)[-1:])
    for found in POC_PATH.finditer(text):
        add([target for target in every if target == f'custom/pocs/{found.group(1)}'])
    for found in CLONE_PATH.finditer(text):
        clone = found.group(1)
        if '--' in clone:
            add([target for target in every if target == 'projects/' + clone.replace('--', '/')])
        else:
            add(projects.get(clone, []))
    for name, targets in projects.items():
        distinctive = len(name) >= MIN_PLAIN_NAME or re.search(r'[-0-9]', name)
        if distinctive and re.search(r'(?<![\w./-])' + re.escape(name) + r'(?![\w-])', text):
            add(targets)
    return named[:MAX_NAMED]


def project_states(root, targets):
    """Returns the porcelain rows of scripts/aiwp-project-state.sh for the targets, as lists of fields; [] when it
    fails or passes its deadline."""
    script = os.path.join(root, 'scripts', 'aiwp-project-state.sh')
    if not targets or not os.path.isfile(script):
        return []
    try:
        done = subprocess.run(
            ['bash', script, '--porcelain', '--', *targets],
            capture_output=True,
            text=True,
            timeout=STATE_TIMEOUT_SECONDS,
            cwd=root,
            stdin=subprocess.DEVNULL,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    # Ten fields at least: the script only ever adds fields at the end (hotfix is the eleventh).
    return [line.split('\t') for line in done.stdout.splitlines() if line.count('\t') >= 9]


def hotfix_text(rows):
    """Returns the context to add for the projects with a hotfix on main not merged into developer yet, or None."""
    notes = []
    for kind, name, path, *rest in rows:
        if kind != 'project' or rest[7:8] != ['yes']:
            continue
        target = path[len('projects/') :]
        notes.append(
            f'`{name}` ({path}) has a hotfix on main that is not merged into developer yet: /merge into its developer '
            f'and its release (/merge --main) are refused until `bash scripts/aiwp-cmds.sh hotfix-down {target}` '
            'merges it down (or, when that conflicts, a fix/<slug>-developer clone of developer through /merge).'
        )
    if not notes:
        return None
    return (
        'Hotfix pending (scripts/aiwp-project-state.sh): '
        + ' '.join(notes)
        + ' If the request is about this project, tell the person this before working on it and offer to merge the '
        'hotfix down first. Nothing is blocked here; this note comes back at the next message that names the project.'
    )


def warning_text(rows):
    """Returns the context to add for the rows that need normalizing or have a hotfix pending, or None."""
    parts = [normalize_text(rows), hotfix_text(rows)]
    return '\n'.join(part for part in parts if part) or None


def normalize_text(rows):
    """Returns the context to add for the rows that need normalizing, or None."""
    notes, commands = [], []
    for kind, name, path, state, marker, version, pending, *_ in rows:
        target = path[len('projects/') :] if kind == 'project' else path
        if state == 'none':
            notes.append(
                f'`{name}` ({path}) has no AI-WORKSPACE-PROJECT marker in its README.md: it is not a Claude CLI Agents '
                'Workspace project yet and needs normalizing.'
            )
        elif state == 'outdated':
            notes.append(
                f'`{name}` ({path}) is on workspace version {marker}; the workspace is on {version}, with the '
                f'migrations {pending.replace(",", ", ")} pending.'
            )
        else:
            continue
        commands.append(f'`/normalize-projects {target}`')
    if not notes:
        return None
    return (
        'Project state (scripts/aiwp-project-state.sh): '
        + ' '.join(notes)
        + ' If the request is about this project, tell the person this before working on it and ask for '
        'authorization to run '
        + ', '.join(commands)
        + '. Yes: run it before the request. No: go on with the request as asked; nothing is blocked, and this '
        'warning comes back at the next message that names the project. If the name only matched an ordinary word, '
        'ignore this note.'
    )


def project_warning(data, root):
    """Returns the warning for the projects a prompt names (and, on /request, its request file), or None."""
    prompt = data.get('prompt') or ''
    if not isinstance(prompt, str) or NORMALIZE_COMMAND.match(prompt):
        return None
    text = prompt[:MAX_READ]
    command = REQUEST_COMMAND.match(prompt)
    if command:
        path = os.path.realpath(request_file(root, command.group(1)))
        if path.startswith(os.path.realpath(root) + os.sep) and os.path.isfile(path):
            with open(path, encoding='utf-8', errors='replace') as handle:
                text += '\n' + handle.read(MAX_READ)
    targets = named_targets(text, workspace_projects(root))
    return warning_text(project_states(root, targets)) if targets else None


def hook_output(data, root):
    """Returns the hook output: the session title and the project warning, each one left out when it fails. Records
    the person's /merge first, silently."""
    try:
        record_merge_order(data, root)
    except Exception:  # noqa: BLE001 - a record failure must never stop the human's prompt
        pass
    try:
        output = title_for(data, root)
    except Exception:  # noqa: BLE001 - a naming failure must never stop the human's prompt
        output = None
    try:
        warning = project_warning(data, root)
    except Exception:  # noqa: BLE001 - a warning failure must never stop the human's prompt
        warning = None
    if warning:
        output = output or {'hookSpecificOutput': {'hookEventName': 'UserPromptSubmit'}}
        spec = output['hookSpecificOutput']
        spec['additionalContext'] = '\n'.join(filter(None, [spec.get('additionalContext'), warning]))
    return output


def main():
    """Entry point: prints the hook output, or nothing; never fails the prompt."""
    try:
        data = json.loads(sys.stdin.read() or '{}')
        output = hook_output(data if isinstance(data, dict) else {}, sys.argv[1])
    except Exception:  # noqa: BLE001 - a hook failure must never stop the human's prompt
        return
    if output:
        print(json.dumps(output))


if __name__ == '__main__':
    main()
