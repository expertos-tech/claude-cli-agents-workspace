"""Keeps the prompt log of the workspace: every human prompt, per project and per ISO week, with what it produced.

Reads the Claude Code transcripts of the sessions opened at the workspace root, plus the folders listed in
custom/prompts/log/sources.json ({"<folder whose sessions to read>": "<project>"}, for adjustment sessions opened
elsewhere). Each human prompt of a main session becomes a record: the session and its title, the time, the text (a
paste over 40 lines becomes "[pasted: N lines]", known secret patterns become "[secret removed]"), the project its
tool calls named most until the next prompt (else the project of the source folder, else "workspace"), whether that
part ran the gate merge, and the agent commits the project received during that turn (from the prompt to the last
response or tool result before the next prompt, at most 4 h).
Records live in custom/prompts/log/<project>/<year>-W<week>.md, inside a prompt-log-data comment that a sync only
adds to: a transcript that expires never takes its records along. The day and week summaries are built from the data.
--context (the SessionStart hook) prints the last day with records before today; any failure there prints nothing and
exits 0. --commit scans the changed log files with gitleaks in Docker, removes what it finds and commits them in
custom/ (never pushes); without Docker or with a failed scan the files stay written and uncommitted. Each file is
written whole (temporary file and rename), under a lock on .history/prompt-log.lock (local state, never in custom/);
--context never waits for it.
Usage: python3 -I -B scripts/prompt-log.py sync [--context | --commit]
"""

import argparse
import collections
import contextlib
import datetime
import fcntl
import importlib.util
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile

# The module this script loads from scripts/performance/ must leave no __pycache__ behind.
sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FORMAT = 1
DATA_RE = re.compile(r'^<!-- prompt-log-data\n(.*?)\n-->$', re.S | re.M)
WEEK_FILE = re.compile(r'^\d{4}-W\d{2}\.md$')
PROJECT_NAME = re.compile(r'^[A-Za-z0-9][\w.-]*$')
DEFAULT_PROJECT = 'workspace'
PASTE_LINES = 40
REMOVED = '[secret removed]'
CONTEXT_LINES = 60
CONTEXT_COMMITS = 8
SCAN_TIMEOUT_SECONDS = 300
# gitleaks.toml plus the credentials of a URL; only this scan uses it (tool fixtures elsewhere hold such URLs).
GITLEAKS_CONFIG = '/work/docker/config/gitleaks-prompt-log.toml'
WEEKDAYS = ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')
COMMIT_TYPES = ('feat', 'fix', 'perf', 'refactor', 'docs', 'test', 'build', 'ci', 'chore', 'style', 'revert')
COMMIT_TYPE_RE = re.compile(r'^([a-z]+)(?:\([^)]*\))?!?:')
# Lines worth decoding; the rest of a transcript (tool results, plain answers) is skipped unread.
MARKERS = (b'"tool_use"', b'"human"', b'"custom-title"')
TIMESTAMP_RE = re.compile(rb'"timestamp":\s*"([^"]+)"')
# A record that belongs to the turn of a prompt: a response, or the result of a tool call.
TURN_RE = re.compile(rb'"type":\s*"(?:assistant|tool_result)"')
MERGE_RE = re.compile(r'aiwp-cmds\.sh["\']?\s+gate\s+--merge\b')
COMMAND_NAME_RE = re.compile(r'<command-name>(.*?)</command-name>', re.S)
COMMAND_ARGS_RE = re.compile(r'<command-args>(.*?)</command-args>', re.S)
PASTE_RE = re.compile(r'<pasted_content[^>]*>\n?(.*?)\n?</pasted_content[^>]*>', re.S)
# High-signal secret patterns: (pattern, replacement). The generic ones keep the name and drop the value.
SECRET_PATTERNS = (
    (re.compile(r'-----BEGIN [A-Z ]*PRIVATE KEY-----(?:.*?-----END [A-Z ]*PRIVATE KEY-----|.*)', re.S), REMOVED),
    (re.compile(r'\b(?:AKIA|ASIA|ABIA|ACCA)[0-9A-Z]{16}\b'), REMOVED),
    (re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9]{36,255}|github_pat_[A-Za-z0-9_]{22,255})\b'), REMOVED),
    (re.compile(r'\bglpat-[A-Za-z0-9_-]{20,}'), REMOVED),
    (re.compile(r'\bxox[abposr]-[A-Za-z0-9-]{10,}'), REMOVED),
    (re.compile(r'https://hooks\.slack\.com/services/[A-Za-z0-9/_-]+'), REMOVED),
    (re.compile(r'\bAIza[0-9A-Za-z_-]{35}'), REMOVED),
    (re.compile(r'\bsk-(?:ant-|proj-)?[A-Za-z0-9_-]{20,}'), REMOVED),
    (re.compile(r'\b[rs]k_(?:live|test)_[A-Za-z0-9]{10,}'), REMOVED),
    (re.compile(r'\bnpm_[A-Za-z0-9]{36}\b'), REMOVED),
    # The password of a URL runs to the last @ of the token: it may hold / or @ itself, and the user may be empty.
    (re.compile(r'(\b[A-Za-z][A-Za-z0-9+.-]*://[^/\s:@]*:)(?!\[secret removed)[^\s"\'<>]*@'), r'\1' + REMOVED + '@'),
    (
        re.compile(r'((?:^|\s)(?:-u|--user)[\s=]*["\']?[\w.@+-]+:)(?!\d+\b|\[secret removed|\$)[^\s"\']+'),
        r'\1' + REMOVED,
    ),
    (re.compile(r'(\bsig=)[A-Za-z0-9%+/=]{10,}'), r'\1' + REMOVED),
    (re.compile(r'\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'), REMOVED),
    (re.compile(r'\b(Bearer\s+)[A-Za-z0-9._~+/-]{20,}=*'), r'\1' + REMOVED),
    (
        re.compile(r'(?i)\b((?:AccountKey|SharedAccessKey|Password|Pwd)\s*=\s*)(?!\[secret removed)[^;\s"\']+'),
        r'\1' + REMOVED,
    ),
    (
        re.compile(
            r'(?i)\b([\w.-]*(?:password|passwd|secret|token|api[_-]?key)[\w.-]*["\']?\s*[:=]\s*["\']?)'
            r'(?!\[secret removed)[^\s"\'`,;\[\]]{8,}'
        ),
        r'\1' + REMOVED,
    ),
)


def load_measure():
    """Returns scripts/performance/measure.py as a module: the transcript and git helpers it shares with this log."""
    spec = importlib.util.spec_from_file_location('measure', os.path.join(HERE, 'performance', 'measure.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


try:
    measure = load_measure()
    MEASURE_ERROR = None
except Exception as problem:  # noqa: BLE001 - reported by main, so the SessionStart hook never prints a traceback
    measure = None
    MEASURE_ERROR = problem


class LogError(Exception):
    """A problem that stops the sync, with a message for the human."""


def scrub(text):
    """Returns the text with the known secret patterns replaced by [secret removed]."""
    for pattern, replacement in SECRET_PATTERNS:
        text = pattern.sub(replacement, text)
    return text


def paste(found):
    """Returns a pasted block as it goes to the log: itself, or a note of its size when it is long."""
    content = found.group(1)
    lines = content.count('\n') + 1
    return f'[pasted: {lines} lines]' if lines > PASTE_LINES else content


def prompt_text(content):
    """Returns the text of a human prompt as it goes to the log: commands with their argument, long pastes cut."""
    if isinstance(content, list):
        text = '\n'.join(
            str(block.get('text') or '') for block in content if isinstance(block, dict) and block.get('type') == 'text'
        )
    else:
        text = content if isinstance(content, str) else ''
    command = COMMAND_NAME_RE.search(text)
    if command and text.lstrip().startswith('<command-'):
        argument = COMMAND_ARGS_RE.search(text)
        text = f'{command.group(1).strip()} {argument.group(1).strip() if argument else ""}'
    text = PASTE_RE.sub(paste, text).strip()
    lines = text.count('\n') + 1
    if lines > PASTE_LINES:
        text = f'[pasted: {lines} lines]'
    return scrub(text)


def read_transcript(path):
    """Returns (title, prompts) of a main-session transcript.

    Each prompt is {'timestamp', 'at', 'end', 'text', 'names': Counter of the project folders its tool calls named,
    'merge': whether a gate merge ran and did not fail}; 'end' is the time of the last response or tool result of its
    turn, so a session resumed days later does not stretch it. The title is the last custom-title record, or None.
    """
    title = None
    prompts = []
    pending = {}
    with open(path, 'rb') as handle:
        for raw in handle:
            if b'"isSidechain":true' in raw:
                continue
            stamp = TIMESTAMP_RE.search(raw) if prompts and TURN_RE.search(raw) else None
            moment = measure.parse_time(stamp.group(1).decode('utf-8', 'replace')) if stamp else None
            if moment is not None and moment > prompts[-1]['end']:
                prompts[-1]['end'] = moment
            if not any(marker in raw for marker in MARKERS) and not any(key in raw for key in pending):
                continue
            try:
                record = json.loads(raw)
            except ValueError:
                continue
            if not isinstance(record, dict) or record.get('isSidechain'):
                continue
            if record.get('type') == 'custom-title':
                title = str(record.get('customTitle') or '').strip() or title
            elif record.get('type') == 'user':
                read_user(record, prompts, pending)
            elif record.get('type') == 'assistant' and prompts:
                read_tools(record, prompts[-1], pending, len(prompts) - 1)
    return title, prompts


def read_user(record, prompts, pending):
    """Adds a human prompt, or marks the gate merge whose result this record carries as done."""
    content = (record.get('message') or {}).get('content')
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get('type') == 'tool_result':
                index = pending.pop(str(block.get('tool_use_id') or '').encode(), None)
                if index is not None and not block.get('is_error'):
                    prompts[index]['merge'] = True
    moment = measure.parse_time(record.get('timestamp'))
    if moment is None or not measure.is_human(record):
        return
    prompts.append(
        {
            'timestamp': record['timestamp'],
            'at': moment,
            'end': moment,
            'text': prompt_text(content),
            'names': collections.Counter(),
            'merge': False,
        }
    )


def read_tools(record, prompt, pending, index):
    """Counts the project folders the tool calls of one response name and notes its gate merges."""
    for block in (record.get('message') or {}).get('content') or []:
        if not isinstance(block, dict) or block.get('type') != 'tool_use':
            continue
        tool_input = block.get('input') if isinstance(block.get('input'), dict) else {}
        prompt['names'].update(measure.projects_named(tool_input))
        if block.get('name') == 'Bash' and MERGE_RE.search(str(tool_input.get('command') or '')):
            pending[str(block.get('id') or '').encode()] = index


def project_of(names, aliases, fallback):
    """Returns the project the named folders point to most, through the aliases of projects/; else the fallback."""
    tops = collections.Counter()
    for name, count in names.items():
        if name in aliases:
            tops[aliases[name]] += count
    return tops.most_common(1)[0][0] if tops else fallback


def session_records(path, aliases, fallback):
    """Returns the records of the human prompts of one transcript, each with the end of its window for commits:
    the end of its turn, at most TURN_CAP_SECONDS after the prompt, plus a second (author times are whole seconds)."""
    title, prompts = read_transcript(path)
    session = os.path.splitext(os.path.basename(path))[0]
    records = []
    for prompt in prompts:
        until = min(prompt['end'], prompt['at'] + measure.TURN_CAP_SECONDS) + 1
        records.append(
            {
                'session': session,
                'title': scrub(title or session[:8]),
                'timestamp': prompt['timestamp'],
                'text': prompt['text'],
                'project': project_of(prompt['names'], aliases, fallback),
                'merge': prompt['merge'],
                'until': until,
            }
        )
    return records


def key_of(record):
    """Returns the identity of a record: its session and the timestamp of its prompt."""
    return record['session'], record['timestamp']


def moment_of(record):
    """Returns the local datetime of a record's prompt."""
    return datetime.datetime.fromtimestamp(measure.parse_time(record['timestamp']))


def read_sources(root, folder):
    """Returns [(transcripts folder, fallback project)]: the workspace root, then the folders of sources.json."""
    sources = [(measure.transcripts_folder(root), DEFAULT_PROJECT)]
    path = os.path.join(folder, 'sources.json')
    if not os.path.exists(path):
        return sources
    try:
        with open(path, encoding='utf-8') as handle:
            listed = json.load(handle)
    except (OSError, ValueError) as error:
        raise LogError(f'{path}: not readable JSON ({error})') from error
    if not isinstance(listed, dict):
        raise LogError(f'{path}: must be an object {{"<folder>": "<project>"}}')
    for source, project in sorted(listed.items()):
        if not isinstance(project, str) or not PROJECT_NAME.match(project):
            raise LogError(f'{path}: invalid project name for {source}: {project!r}')
        transcripts = measure.transcripts_folder(os.path.expanduser(source))
        if transcripts not in (s[0] for s in sources):
            sources.append((transcripts, project))
    return sources


def git_log(repo, since):
    """Returns the git log of the agent-commit format for one repo since an epoch, or None when git cannot run."""
    moment = datetime.datetime.fromtimestamp(since, datetime.timezone.utc).strftime('%Y-%m-%d %H:%M:%S +0000')
    command = ['git', '-C', repo, 'log', '--all', '--no-merges', f'--since={moment}', '--format=%x1e%at%n%h %s%n%b%x1f']
    try:
        result = subprocess.run(command, capture_output=True, text=True, errors='replace')
    except OSError:
        return None
    return result.stdout if result.returncode == 0 else None


def agent_commits(repos, since):
    """Returns [(author time, short sha, subject)] of the agent commits of the repos, or None when git failed on one.

    A commit seen twice (the same subject and author time, as after a rebase) counts once, as in measure.py.
    """
    found = []
    seen = set()
    for repo in sorted(repos):
        text = git_log(repo, since)
        if text is None:
            return None
        for stamp, line, _ in measure.parse_git_log(text):
            sha, _, subject = line.partition(' ')
            if (subject, stamp) not in seen:
                seen.add((subject, stamp))
                found.append((stamp, sha, scrub(subject)))
    return sorted(found)


def attach_commits(records, repos):
    """Sets 'commits' on each record whose project has repos and git answered for all of them: the commits in its
    window. A project git failed on keeps the commits its records already have."""
    by_project = collections.defaultdict(list)
    for record in records:
        by_project[record['project']].append(record)
    for project, items in sorted(by_project.items()):
        own = [repo for repo, top in repos.items() if top == project]
        if not own:
            continue
        starts = [measure.parse_time(r['timestamp']) for r in items]
        commits = agent_commits(own, min(starts) - 86400)
        if commits is None:
            continue
        for record, start in zip(items, starts):
            record['commits'] = [[sha, subject] for stamp, sha, subject in commits if start <= stamp < record['until']]


def collect(root, folder):
    """Returns {key: record} of the prompts the transcripts still keep, with their commits when git runs."""
    projects_dir = os.path.join(root, 'projects')
    repos = measure.project_repos(projects_dir) if os.path.isdir(projects_dir) else {}
    aliases = {os.path.basename(repo): top for repo, top in repos.items()}
    aliases.update({top: top for top in repos.values()})
    fresh = {}
    for transcripts, fallback in read_sources(root, folder):
        for path in listed(transcripts, lambda name: name.endswith('.jsonl')):
            for record in session_records(path, aliases, fallback):
                fresh[key_of(record)] = record
    attach_commits(list(fresh.values()), repos)
    return fresh


def listed(folder, wanted):
    """Returns the sorted paths of the files in a folder whose name passes wanted; none when it is missing.

    os.listdir, not glob: a folder whose path holds [, * or ? must not look empty.
    """
    if not os.path.isdir(folder):
        return []
    return [os.path.join(folder, name) for name in sorted(os.listdir(folder)) if wanted(name)]


def week_files(folder):
    """Returns the week files of the log, sorted."""
    projects = listed(folder, lambda name: os.path.isdir(os.path.join(folder, name)))
    return [path for project in projects for path in listed(project, WEEK_FILE.match)]


def load_log(folder):
    """Returns {key: record} of every week file; a file whose data cannot be read stops the sync."""
    records = {}
    for path in week_files(folder):
        with open(path, encoding='utf-8') as handle:
            blocks = DATA_RE.findall(handle.read())
        try:
            data = json.loads(blocks[-1]) if blocks else None
        except ValueError:
            data = None
        if not isinstance(data, dict) or data.get('format') != FORMAT or not isinstance(data.get('records'), list):
            raise LogError(f'{path}: no readable prompt-log-data block; fix or move the file before the sync')
        for record in data['records']:
            if isinstance(record, dict) and isinstance(record.get('session'), str) and record.get('timestamp'):
                records[key_of(record)] = record
    return records


def merge(stored, fresh):
    """Returns (records, new count): the stored ones, refreshed where the transcript still has them, plus the new ones.

    The text of a stored record never changes; project, merge, window and, when git ran, commits follow the transcript
    and the repos. A title or a commit subject with a secret removed keeps the stored version: a raw re-import never
    undoes a redaction.
    """
    merged = dict(stored)
    added = 0
    for key, record in fresh.items():
        if key in stored:
            old = stored[key]
            updated = dict(old)
            updated.update({k: v for k, v in record.items() if k not in ('text', 'title', 'commits')})
            if REMOVED not in str(old.get('title') or ''):
                updated['title'] = record['title']
            if 'commits' in record:
                kept = {sha: subject for sha, subject in old.get('commits') or [] if REMOVED in subject}
                updated['commits'] = [[sha, kept.get(sha, subject)] for sha, subject in record['commits']]
            merged[key] = updated
        else:
            merged[key] = record
            added += 1
    return merged, added


def plural(count, one, many):
    """Returns '<count> <word>' in the right number."""
    return f'{count} {one if count == 1 else many}'


def unique_commits(records):
    """Returns the commits of the records once each, in order: [sha, subject]."""
    seen = set()
    found = []
    for record in records:
        for sha, subject in record.get('commits') or []:
            if sha not in seen:
                seen.add(sha)
                found.append((sha, subject))
    return found


def commit_type(subject):
    """Returns the Conventional Commit type of a subject, or 'other'."""
    found = COMMIT_TYPE_RE.match(subject)
    return found.group(1) if found else 'other'


def summary(records):
    """Returns the summary lines of a group of records: prompts, sessions, merges, commits by type."""
    titles = list(dict.fromkeys(r['title'] for r in records))
    sessions = len({r['session'] for r in records})
    lines = [
        f'- {plural(len(records), "prompt", "prompts")} in {plural(sessions, "session", "sessions")}: '
        + ', '.join(titles)
        + '.'
    ]
    merges = sum(1 for r in records if r.get('merge'))
    if merges:
        lines.append(f'- Merges into developer through the gate: {merges}.')
    commits = unique_commits(records)
    if not commits:
        lines.append('- No agent commits.')
        return lines
    lines.append(f'- Agent commits: {len(commits)}.')
    groups = collections.defaultdict(list)
    for _, subject in commits:
        groups[commit_type(subject)].append(subject)
    order = [t for t in COMMIT_TYPES if t in groups] + sorted(set(groups) - set(COMMIT_TYPES) - {'other'})
    for kind in order + (['other'] if 'other' in groups else []):
        lines.append(f'  - {kind} ({len(groups[kind])})')
        lines += [f'    - {subject}' for subject in groups[kind]]
    return lines


def quote(text):
    """Returns the text as blockquote lines."""
    return [f'> {line}'.rstrip() for line in (text or '(empty)').splitlines()]


def result_lines(record):
    """Returns the result lines of one prompt: its commits, the gate merge, or none."""
    lines = [f'- `{sha}` {subject}' for sha, subject in record.get('commits') or []]
    if not lines:
        lines.append('- no commits')
    if record.get('merge'):
        lines.append('- merge into developer through the gate')
    return lines


def render(project, year, week, records, today):
    """Returns the text of one week file: summaries of what is over, each prompt with its result, then the data."""
    monday = datetime.date.fromisocalendar(year, week, 1)
    sunday = monday + datetime.timedelta(days=6)
    records = sorted(records, key=lambda r: (moment_of(r), r['session']))
    lines = [f'# {project} · week {year}-W{week:02d} ({monday} to {sunday})', '']
    if today > sunday:
        lines += ['## Week summary', ''] + summary(records) + ['']
    days = collections.defaultdict(list)
    for record in records:
        days[moment_of(record).date()].append(record)
    for day in sorted(days):
        lines += [f'## {day} ({WEEKDAYS[day.weekday()]})', '']
        if today > day:
            lines += ['### Day summary', ''] + summary(days[day]) + ['']
        for record in days[day]:
            title = ' '.join(str(record['title']).split())
            lines += [f'### {moment_of(record):%H:%M} · {title}', '']
            lines += quote(record['text']) + ['', '**Result:**', ''] + result_lines(record) + ['']
    data = json.dumps({'format': FORMAT, 'records': records}, ensure_ascii=False, sort_keys=True)
    lines += ['<!-- prompt-log-data', data.replace('-->', '--\\u003e'), '-->', '']
    return '\n'.join(lines)


def week_of(record):
    """Returns (project, ISO year, ISO week) of a record."""
    calendar = moment_of(record).date().isocalendar()
    return record['project'], calendar[0], calendar[1]


def file_mode():
    """Returns the mode a new file gets from open(): 0o666 without the bits of the umask."""
    mask = os.umask(0o022)
    os.umask(mask)
    return 0o666 & ~mask


def write_whole(path, text):
    """Writes a file through a temporary file in the same folder and a rename: a reader never sees half of it.

    The file gets the mode of a plain open() (mkstemp makes it 0600, which the gitleaks container may not read).
    """
    folder = os.path.dirname(path)
    os.makedirs(folder, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix=f'.{os.path.basename(path)}.', suffix='.tmp', dir=folder)
    try:
        with os.fdopen(handle, 'w', encoding='utf-8') as out:
            out.write(text)
        os.chmod(temporary, file_mode())
        os.replace(temporary, path)
    except BaseException:
        with contextlib.suppress(OSError):
            os.remove(temporary)
        raise


def write_log(folder, records, today):
    """Writes every week file from the records and removes those left empty; returns the paths that changed."""
    weeks = collections.defaultdict(list)
    for record in records.values():
        weeks[week_of(record)].append(record)
    changed = []
    targets = set()
    for (project, year, week), items in sorted(weeks.items()):
        path = os.path.join(folder, project, f'{year}-W{week:02d}.md')
        targets.add(path)
        text = render(project, year, week, items, today)
        if os.path.exists(path):
            with open(path, encoding='utf-8') as handle:
                if handle.read() == text:
                    continue
        write_whole(path, text)
        changed.append(path)
    for path in week_files(folder):
        if path not in targets:
            os.remove(path)
            changed.append(path)
    return changed


def context(records, today):
    """Returns the SessionStart context: the last day with records before today, per project; '' when none."""
    days = {moment_of(r).date() for r in records}
    earlier = sorted(day for day in days if day < today)
    if not earlier:
        return ''
    day = earlier[-1]
    chosen = collections.defaultdict(list)
    for record in records:
        if moment_of(record).date() == day:
            chosen[record['project']].append(record)
    calendar = day.isocalendar()
    week = f'{calendar[0]}-W{calendar[1]:02d}'
    lines = [f'Prompt log: the last day with activity before today was {day} ({WEEKDAYS[day.weekday()]}).']
    for project, items in sorted(chosen.items(), key=lambda item: (-len(item[1]), item[0])):
        sessions = len({r['session'] for r in items})
        merges = sum(1 for r in items if r.get('merge'))
        commits = unique_commits(items)
        head = f'- {project}: {plural(len(items), "prompt", "prompts")} in {plural(sessions, "session", "sessions")}'
        head += f', {plural(len(commits), "agent commit", "agent commits")}' if commits else ', no commits'
        head += f', {plural(merges, "merge", "merges")} through the gate.' if merges else '.'
        lines.append(head)
        lines += [f'  - {subject}' for _, subject in commits[:CONTEXT_COMMITS]]
        if len(commits) > CONTEXT_COMMITS:
            lines.append(f'  - and {len(commits) - CONTEXT_COMMITS} more')
    if len(lines) > CONTEXT_LINES - 1:
        lines = lines[: CONTEXT_LINES - 2] + ['- (cut; the rest is in the files)']
    lines.append(f'Details, only if the human asks: custom/prompts/log/<project>/{week}.md.')
    return '\n'.join(lines)


def changed_log_files(custom):
    """Returns the week files of the log that git shows as changed in custom/, relative to it; None without git."""
    command = ['git', '-C', custom, 'status', '--porcelain', '-z', '--untracked-files=all', '--', 'prompts/log']
    try:
        result = subprocess.run(command, capture_output=True, text=True, errors='replace')
    except OSError:
        return None
    if result.returncode != 0:
        return None
    paths = []
    entries = iter(result.stdout.split('\0'))
    for entry in entries:
        if len(entry) < 4:
            continue
        if entry[0] in 'RC':
            next(entries, None)
        path = entry[3:]
        if WEEK_FILE.match(os.path.basename(path)):
            paths.append(path)
    return sorted(paths)


def run_gitleaks(root, target, report_dir):
    """Runs gitleaks in Docker on a folder of the root, writing a JSON report in report_dir.

    Returns (exit code, error text); the code is None when Docker could not run at all.
    """
    command = [
        'docker',
        'compose',
        '--progress',
        'quiet',
        '-f',
        os.path.join(root, 'docker', 'compose.yaml'),
        'run',
        '--rm',
        '-T',
        '--user',
        f'{os.getuid()}:{os.getgid()}',
        '-v',
        f'{report_dir}:/report',
        'gitleaks',
        'dir',
        f'/work/{target}',
        '--no-banner',
        '--config',
        GITLEAKS_CONFIG,
        '--report-format',
        'json',
        '--report-path',
        '/report/gitleaks.json',
    ]
    env = dict(os.environ, WORKSPACE_DIR=root)
    try:
        result = subprocess.run(
            command,
            env=env,
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            errors='replace',
            timeout=SCAN_TIMEOUT_SECONDS,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        return None, str(error)
    return result.returncode, result.stderr.strip()


def readable(path):
    """True when the file can be read here and by other users, as the gitleaks container may be."""
    return os.access(path, os.R_OK) and bool(os.stat(path).st_mode & stat.S_IROTH)


def scan(root, files):
    """Returns the secrets gitleaks finds in the files (root-relative paths): {path: [secret]}.

    Raises LogError when the scan does not run, its report cannot be read, or a file may go unread: one without read
    permission for others (rootless Docker, userns-remap and Docker Desktop read as another user) or one gitleaks
    reports skipping.
    """
    unreadable = [path for path in sorted(files) if os.path.exists(os.path.join(root, path))]
    unreadable = [path for path in unreadable if not readable(os.path.join(root, path))]
    if unreadable:
        raise LogError(
            'gitleaks would not read ' + ', '.join(unreadable) + ' (no read permission for others; chmod a+r)'
        )
    report_dir = tempfile.mkdtemp(prefix='prompt-log-scan-')
    try:
        code, error = run_gitleaks(root, 'custom/prompts/log', report_dir)
        if code is None:
            raise LogError(f'no Docker for gitleaks ({error})')
        try:
            with open(os.path.join(report_dir, 'gitleaks.json'), encoding='utf-8') as handle:
                findings = json.load(handle)
        except (OSError, ValueError) as problem:
            raise LogError(f'the gitleaks scan failed (exit {code}: {error or problem})') from problem
    finally:
        shutil.rmtree(report_dir, ignore_errors=True)
    if code not in (0, 1) or not isinstance(findings, list):
        raise LogError(f'the gitleaks scan failed (exit {code}: {error})')
    skipped = [line.strip() for line in error.splitlines() if 'skipping file' in line.lower()]
    if skipped:
        raise LogError(f'gitleaks skipped files unread ({skipped[0]})')
    found = collections.defaultdict(list)
    for finding in findings:
        if not isinstance(finding, dict):
            continue
        path = str(finding.get('File') or '')
        path = path[len('/work/') :] if path.startswith('/work/') else path
        secret = str(finding.get('Secret') or finding.get('Match') or '')
        if path in files and secret:
            found[path].append(secret)
    return dict(found)


def redact(records, secrets):
    """Replaces each secret in the text, title and commit subjects of the records; returns how many records changed."""
    variants = set()
    for secret in secrets:
        variants.add(secret)
        try:
            variants.add(json.loads(f'"{secret}"'))
        except ValueError:
            pass
    changed = 0
    for record in records.values():
        before = json.dumps(record, sort_keys=True)
        for secret in sorted(variants, key=len, reverse=True):
            record['text'] = record['text'].replace(secret, REMOVED)
            record['title'] = str(record['title']).replace(secret, REMOVED)
            record['commits'] = [
                [sha, subject.replace(secret, REMOVED)] for sha, subject in record.get('commits') or []
            ]
        changed += json.dumps(record, sort_keys=True) != before
    return changed


def git_commit(custom, files, message):
    """Stages and commits only the files in custom/; returns (ok, error text)."""
    for command in (
        ['git', '-C', custom, 'add', '--', *files],
        ['git', '-C', custom, 'commit', '-q', *message, '--', *files],
    ):
        try:
            result = subprocess.run(command, capture_output=True, text=True, errors='replace')
        except OSError as error:
            return False, str(error)
        if result.returncode != 0:
            return False, (result.stderr or result.stdout).strip()
    return True, ''


def commit_log(root, folder, records, today):
    """Scans the changed week files, removes what gitleaks finds, rescans and commits them; returns the exit code."""
    custom = os.path.join(root, 'custom')
    changed = changed_log_files(custom)
    if changed is None:
        print('prompt-log: log written, no commit: custom/ is not a readable git repository', file=sys.stderr)
        return 1
    if not changed:
        print('prompt-log: nothing new to commit')
        return 0
    files = {os.path.join('custom', path) for path in changed}
    try:
        found = scan(root, files)
        if found:
            redact(records, [secret for secrets in found.values() for secret in secrets])
            write_log(folder, records, today)
            again = scan(root, files)
            if again:
                raise LogError('gitleaks still finds a secret in ' + ', '.join(sorted(again)) + '; review by hand')
            print(f'prompt-log: secret removed from {", ".join(sorted(found))}')
            # With the secret gone a file may equal its committed version again: commit only what still differs.
            changed = changed_log_files(custom)
            if changed is None:
                raise LogError('custom/ is not a readable git repository')
    except LogError as error:
        print(f'prompt-log: log written, no commit: {error}', file=sys.stderr)
        return 1
    if not changed:
        print('prompt-log: nothing new to commit')
        return 0
    message = [
        '-m',
        'docs(prompts): record the prompt log',
        '-m',
        'Adds the prompts of the sessions and what each one produced to the weekly files of the prompt log.',
        '-m',
        measure.AGENT_COMMIT,
    ]
    ok, error = git_commit(custom, changed, message)
    if not ok:
        print(f'prompt-log: log written, no commit: git refused ({error})', file=sys.stderr)
        return 1
    print('prompt-log: committed in custom/: ' + ', '.join(changed))
    return 0


def parse_args(argv):
    """Returns the parsed command line."""
    parser = argparse.ArgumentParser(
        prog='prompt-log.py',
        description='Records the human prompts per project and week in custom/prompts/log/, with the result of each.',
    )
    commands = parser.add_subparsers(dest='command', required=True)
    sync = commands.add_parser('sync', help='records what the log is missing from the transcripts')
    mode = sync.add_mutually_exclusive_group()
    mode.add_argument('--context', action='store_true', help='prints the summary of the last day (SessionStart hook)')
    mode.add_argument('--commit', action='store_true', help='scans with gitleaks and commits in custom/')
    sync.add_argument('--root', default=ROOT, help=argparse.SUPPRESS)
    sync.add_argument('--today', type=datetime.date.fromisoformat, help=argparse.SUPPRESS)
    return parser.parse_args(argv)


def lock(handle, wait):
    """Takes the lock of the log on an open file; returns False when it is busy and wait is False."""
    try:
        fcntl.flock(handle, fcntl.LOCK_EX | (0 if wait else fcntl.LOCK_NB))
    except BlockingIOError:
        return False
    return True


def run(args):
    """Syncs the log under its lock and does what the mode asks; returns the exit code.

    --context does not wait: with another sync running it prints the context from what is on disk. --commit keeps the
    lock until the commit is done.
    """
    root = os.path.realpath(args.root)
    if not os.path.isdir(os.path.join(root, 'custom')):
        raise LogError('no custom layer (custom/)')
    today = args.today or datetime.date.today()
    folder = os.path.join(root, 'custom', 'prompts', 'log')
    os.makedirs(folder, exist_ok=True)
    state = os.path.join(root, '.history')
    os.makedirs(state, exist_ok=True)
    with open(os.path.join(state, 'prompt-log.lock'), 'a', encoding='utf-8') as handle:
        if not lock(handle, wait=not args.context):
            records, added, written = load_log(folder), 0, []
        else:
            records, added = merge(load_log(folder), collect(root, folder))
            written = write_log(folder, records, today)
        if args.context:
            text = context(list(records.values()), today)
            if text:
                print(text)
            return 0
        print(
            f'prompt-log: {plural(added, "new prompt", "new prompts")}; '
            f'{plural(len(written), "file", "files")} updated'
            + ''.join(f'\n  {os.path.relpath(p, root)}' for p in written)
        )
        return commit_log(root, folder, records, today) if args.commit else 0


def main(argv=None):
    """Entry point. In --context mode nothing fails the session: any error, a bad command line included, prints one
    line to stderr, nothing to stdout, and exits 0."""
    argv = sys.argv[1:] if argv is None else argv
    hook = '--context' in argv
    try:
        if measure is None:
            raise LogError(f'scripts/performance/measure.py did not load ({MEASURE_ERROR})')
        return run(parse_args(argv))
    except LogError as error:
        print(f'prompt-log: {error}', file=sys.stderr)
        return 0 if hook else 1
    except SystemExit:
        if not hook:
            raise
        return 0
    except Exception as error:  # noqa: BLE001 - the SessionStart hook must never block the session
        if not hook:
            raise
        print(f'prompt-log: failed ({type(error).__name__}: {error})', file=sys.stderr)
        return 0


if __name__ == '__main__':
    sys.exit(main())
