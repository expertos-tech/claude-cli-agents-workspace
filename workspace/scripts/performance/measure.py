"""Measures how the workspace performs, from the Claude Code transcripts of its sessions, and writes a report.

Runs only with the observability stack of tools/observability/ up (Grafana healthy and the OTLP port open): the stack
is what keeps the telemetry of the same sessions, and a measurement without it has nothing to check the numbers against.
Reads the session transcripts of the workspace root (only aggregates leave the script: no prompt text, no file content),
classifies every tool call (work, validation and gate, workspace process, questions to the human) and writes
custom/performance/<date>-<name>.md. Each report covers the period since the previous one, compares with it and lays
out the last ones side by side; the numbers of each report travel inside it, in a comment, for the next comparison.
Usage: python3 -I -B scripts/performance/measure.py [--name <kebab>] [--since <date> | --all] [--compare <n>]
                                                [--transcripts <dir>] [--out <dir>]
"""

import argparse
import collections
import datetime
import glob
import json
import os
import re
import socket
import statistics
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
FORMAT = 1
DATA_BLOCK = re.compile(r'<!-- performance-data\n(.*?)\n-->', re.S)
KEBAB = re.compile(r'^[a-z0-9]+(?:-[a-z0-9]+)*$')
STEP_CAP_SECONDS = 3600
GRAFANA_HEALTH = 'http://127.0.0.1:3000/api/health'
OTLP_ADDRESS = ('127.0.0.1', 4317)
STACK_UP = 'docker compose -f tools/observability/compose.yaml up -d'

# Workspace scripts by what they are for; aiwp-cmds.sh is split by its first argument.
SCRIPT_CATEGORY = {
    'aiwp-gate': 'gate',
    'validate': 'validation',
    'check-workspace': 'validation',
    'check-ledger': 'validation',
    'heavy-run': 'validation',
    'sonar': 'validation',
    'setup-claude': 'process',
    'history': 'process',
    'init-repo': 'process',
    'aiwp-project-state': 'process',
    'sync-env': 'process',
    # Retired script names that transcripts may still hold, so a period that has them is classified the same way.
    'import-project': 'process',
    'session-board': 'process',
    'session-name': 'process',
    'scratch': 'process',
    'sweep': 'process',
    'single-agent': 'process',
    'next-decision': 'process',
    'review-session': 'gate',
    'git-gate': 'gate',
    'branch-flow': 'gate',
    'test-session-tools': 'validation',
}
GATE_COMMANDS = {'gate', 'release', 'apply'}
SCRIPT_RE = re.compile(r'scripts/([a-z-]+)\.(?:sh|py)(?:\s+([a-z_-]+))?')
TEST_RE = re.compile(
    r'(npm (run )?(test|lint|build|typecheck|check)|npx (vitest|playwright|tsc)|vitest|playwright|pytest|'
    r'go (test|build|vet)|dotnet (test|build)|unittest|scripts/tests/|\btsc\b|biome)'
)
HOOK_SCRIPT_RE = re.compile(r'([\w.-]+\.(?:sh|py))\b')
# Where a tool call says which project it works on: projects/<top>/..., a clone tmp/work/<work>/<repo>/... or a
# worktree tmp/worktrees/<repo>, a layout transcripts may still hold.
PROJECT_RE = re.compile(r'(projects|tmp/work/[^/\s"\']+|tmp/worktrees)/([A-Za-z0-9][\w.-]*)')
TURN_CAP_SECONDS = 4 * 3600
# A project with less agent time than this in the period shows no rate: a few minutes say nothing per hour.
MIN_PROJECT_HOURS = 0.5
AGENT_COMMIT = '[#automatic-agent-commit]'
GENERATED_RE = re.compile(
    r'(^|/)(dist|build|out|coverage|node_modules|vendor|\.next|\.astro)/|package-lock\.json$|yarn\.lock$|'
    r'pnpm-lock\.yaml$|go\.sum$|\.lock$|\.min\.(js|css)$|\.map$|'
    r'\.(png|jpe?g|gif|webp|ico|svg|pdf|woff2?|ttf|otf|mp3|wav|ogg|glb|gltf)$'
)
DOC_RE = re.compile(r'\.(md|mdx|txt|rst|adoc)$|(^|/)docs/')
GIT_RE = re.compile(r'(^|[;&|(]\s*|\s)git(\s|$)')
GROUPS = {
    'work': ('work-write', 'work-read', 'work-bash', 'work-delegate', 'git', 'skill', 'other'),
    'validation': ('validation', 'gate'),
    'process': ('workarea', 'process', 'rules-read', 'rules-write', 'prompt-write'),
    'questions': ('ask-human',),
}
GROUP_LABEL = {
    'work': 'Work',
    'validation': 'Validation and gate',
    'process': 'Workspace process',
    'questions': 'Questions to the human',
    'response': 'Response without tools',
}
# Other keys a stored report may give the groups; previous_reports reads them under the names above.
GROUP_KEYS = {
    'trabalho': 'work',
    'validacao': 'validation',
    'processo': 'process',
    'perguntas': 'questions',
    'resposta': 'response',
}


def group_of(category):
    """Returns the group of a category; a response without tools is its own group."""
    for group, members in GROUPS.items():
        if category in members:
            return group
    return 'response'


def path_bucket(path):
    """Returns what a file path holds: work, rules or a request."""
    if re.search(r'/(tmp/work|projects|custom/pocs)/', path):
        return 'work'
    if '/custom/prompts/' in path:
        return 'prompt'
    name = os.path.basename(path)
    if name in ('AGENTS.md', 'CLAUDE.md') or re.search(r'/(rules|\.claude)/', path):
        return 'rules'
    return 'work'


def classify(name, tool_input):
    """Returns the category of one tool call."""
    if name == 'Bash':
        command = str(tool_input.get('command') or '')
        script = SCRIPT_RE.search(command)
        if script and script.group(1) == 'aiwp-cmds':
            return 'gate' if script.group(2) in GATE_COMMANDS else 'workarea'
        if script and script.group(1) in SCRIPT_CATEGORY:
            return SCRIPT_CATEGORY[script.group(1)]
        if TEST_RE.search(command):
            return 'validation'
        return 'git' if GIT_RE.search(command) else 'work-bash'
    if name in ('Read', 'Grep', 'Glob'):
        bucket = path_bucket(str(tool_input.get('file_path') or tool_input.get('path') or ''))
        return 'rules-read' if bucket == 'rules' else 'work-read'
    if name in ('Edit', 'Write', 'NotebookEdit', 'MultiEdit'):
        bucket = path_bucket(str(tool_input.get('file_path') or tool_input.get('notebook_path') or ''))
        return {'rules': 'rules-write', 'prompt': 'prompt-write'}.get(bucket, 'work-write')
    if name in ('Agent', 'Task'):
        kind = str(tool_input.get('subagent_type') or '').lower()
        return 'validation' if kind in ('reviewer', 'verifier') else 'work-delegate'
    if name in ('SendMessage', 'ListAgents'):
        return 'process'
    if name == 'AskUserQuestion':
        return 'ask-human'
    return 'skill' if name == 'Skill' else 'other'


def parse_time(value):
    """Returns epoch seconds from an ISO timestamp (naive means local time), or None."""
    if not isinstance(value, str) or not value:
        return None
    try:
        moment = datetime.datetime.fromisoformat(value.replace('Z', '+00:00'))
    except ValueError:
        return None
    return moment.timestamp()


def is_human(record):
    """True when a user record is a prompt the human typed (not a command echo, a peer or a notification)."""
    origin = record.get('origin')
    if not isinstance(origin, dict) or origin.get('kind') != 'human':
        return False
    content = (record.get('message') or {}).get('content')
    text = content if isinstance(content, str) else ''
    return not text.lstrip().startswith(('<local-command', '<bash-', '<command-name>/effort', '<command-name>/model'))


def new_session():
    """Returns the empty counters of one session."""
    return {
        'started': None,
        'human': 0,
        'usage': {},
        'calls': {},
        'events': [],
        'tools_of': collections.defaultdict(list),
        'hooks': collections.defaultdict(lambda: [0, 0]),
        'compactions': 0,
        'nested_project_rules': 0,
        'cost': None,
        'segments': [],
    }


def read_record(session, record, since, until):
    """Adds one transcript record to the session counters, when it falls in the period."""
    kind = record.get('type')
    if kind == 'cost-state':
        session['cost'] = record
        return
    moment = parse_time(record.get('timestamp'))
    if moment is None:
        return
    if session['started'] is None or moment < session['started']:
        session['started'] = moment
    if moment <= since or moment > until or record.get('isSidechain'):
        return
    if kind == 'system' and record.get('subtype') == 'compact_boundary':
        session['compactions'] += 1
    elif kind == 'system' and record.get('subtype') == 'turn_duration' and session['segments']:
        seconds = min((record.get('durationMs') or 0) / 1000, TURN_CAP_SECONDS)
        session['segments'][-1]['turns'].append((moment - seconds, moment))
    elif kind == 'attachment':
        read_attachment(session, record.get('attachment') or {})
    elif kind == 'user':
        read_user(session, record, moment)
    elif kind == 'assistant':
        read_assistant(session, record, moment)


def read_attachment(session, attachment):
    """Counts hook runs and the instruction files of projects loaded on their own."""
    if attachment.get('type') == 'hook_success':
        script = HOOK_SCRIPT_RE.search(str(attachment.get('command') or ''))
        name = script.group(1) if script else 'inline'
        hook = session['hooks'][f'{attachment.get("hookEvent") or "?"} {name}']
        hook[0] += 1
        hook[1] += attachment.get('durationMs') or 0
    elif attachment.get('type') == 'nested_memory' and '/projects/' in str(attachment.get('path') or ''):
        session['nested_project_rules'] += 1


def read_user(session, record, moment):
    """Records the human prompts and the tool results, which close each tool call."""
    content = (record.get('message') or {}).get('content')
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get('type') == 'tool_result':
                session['events'].append((moment, 'result', block.get('tool_use_id')))
    if is_human(record):
        session['human'] += 1
        session['events'].append((moment, 'human', None))
        session['segments'].append({'projects': collections.Counter(), 'turns': []})


def read_assistant(session, record, moment):
    """Records one API response: its tokens and the tool calls it made."""
    message = record.get('message') or {}
    key = message.get('id') or record.get('uuid')
    usage = message.get('usage') or {}
    tokens_in = sum(
        usage.get(k) or 0 for k in ('input_tokens', 'cache_creation_input_tokens', 'cache_read_input_tokens')
    )
    session['usage'][key] = (moment, tokens_in, usage.get('output_tokens') or 0, message.get('model') or '?')
    for block in message.get('content') or []:
        if isinstance(block, dict) and block.get('type') == 'tool_use':
            category = classify(block.get('name'), block.get('input') or {})
            session['calls'][block.get('id')] = category
            session['tools_of'][key].append(category)
            if session['segments']:
                session['segments'][-1]['projects'].update(projects_named(block.get('input') or {}))


def projects_named(tool_input):
    """Returns the folder names a tool call names after projects/, a clone of tmp/work/ or tmp/worktrees/."""
    text = ' '.join(str(tool_input.get(k) or '') for k in ('file_path', 'path', 'notebook_path', 'command'))
    return [found.group(2) for found in PROJECT_RE.finditer(text)]


def union_seconds(intervals):
    """Returns the seconds covered by a list of (start, end), counting overlaps once."""
    total, end = 0.0, None
    for start, stop in sorted(intervals):
        if end is None or start > end:
            total += stop - start
            end = stop
        elif stop > end:
            total += stop - end
            end = stop
    return total


def read_session(path, since, until):
    """Returns the counters of one transcript, limited to the period (since, until]."""
    session = new_session()
    with open(path, encoding='utf-8', errors='replace') as handle:
        for line in handle:
            if line.startswith('{"type":"api-request'):
                continue
            try:
                record = json.loads(line)
            except ValueError:
                continue
            if isinstance(record, dict):
                read_record(session, record, since, until)
    return session


def walk_events(session, totals):
    """Adds the step time of each category and the path to the first work edit after each human prompt."""
    last = None
    prompt_at = None
    calls_before = 0
    for moment, kind, ref in sorted(session['events'], key=lambda e: e[0]):
        if kind == 'human':
            last, prompt_at, calls_before = moment, moment, 0
            continue
        category = session['calls'].get(ref)
        if category is None:
            continue
        totals['calls'][category] += 1
        if last is not None and category != 'ask-human':
            totals['time'][category] += min(moment - last, STEP_CAP_SECONDS)
        last = moment
        if prompt_at is None:
            continue
        if category == 'work-write':
            totals['first_edit'].append((moment - prompt_at, calls_before))
            prompt_at = None
        else:
            calls_before += 1


def measure(paths, since, until):
    """Returns the data of one measurement over the transcripts, limited to the period (since, until]."""
    totals = {
        'calls': collections.Counter(),
        'time': collections.Counter(),
        'api': collections.Counter(),
        'tokens_in': collections.Counter(),
        'first_edit': [],
    }
    hooks = collections.defaultdict(lambda: [0, 0])
    project_turns = collections.defaultdict(list)
    models = collections.Counter()
    counts = collections.Counter()
    first_contexts = []
    cost = 0.0
    for path in paths:
        session = read_session(path, since, until)
        if not session['usage']:
            continue
        counts['sessions'] += 1
        counts['prompts'] += session['human']
        counts['compactions'] += session['compactions']
        counts['nested_project_rules'] += session['nested_project_rules']
        walk_events(session, totals)
        for segment in session['segments']:
            if segment['projects'] and segment['turns']:
                project_turns[segment['projects'].most_common(1)[0][0]].extend(segment['turns'])
        responses = sorted(session['usage'].items(), key=lambda item: item[1][0])
        new_session_here = session['started'] is not None and session['started'] > since
        if new_session_here:
            first_contexts.append(responses[0][1][1])
        for key, (_, tokens_in, tokens_out, model) in responses:
            counts['api_calls'] += 1
            counts['tokens_in'] += tokens_in
            counts['tokens_out'] += tokens_out
            if not model.startswith('<'):
                models[model] += tokens_in
            categories = session['tools_of'].get(key) or ['respond']
            for category in categories:
                totals['api'][group_of(category)] += 1 / len(categories)
                totals['tokens_in'][group_of(category)] += tokens_in / len(categories)
        for name, (runs, millis) in session['hooks'].items():
            hooks[name][0] += runs
            hooks[name][1] += millis
        record = session['cost']
        if new_session_here and record and isinstance(record.get('totalCostUSD'), (int, float)):
            cost += record['totalCostUSD']
            counts['cost_sessions'] += 1
    groups = {}
    for group in list(GROUPS) + ['response']:
        members = GROUPS.get(group, ('respond',))
        groups[group] = {
            'calls': sum(totals['calls'][c] for c in members),
            'time': round(sum(totals['time'][c] for c in members), 1),
            'api': round(totals['api'][group], 2),
            'tokens_in': round(totals['tokens_in'][group]),
        }
    edits = totals['first_edit']
    return {
        'counts': dict(counts),
        'categories': dict(totals['calls']),
        'groups': groups,
        'hooks': {name: values for name, values in sorted(hooks.items())},
        'models': dict(models.most_common()),
        'cost_usd': round(cost, 2),
        'first_context_median': statistics.median(first_contexts) if first_contexts else None,
        'first_edit_seconds_median': round(statistics.median(e[0] for e in edits)) if edits else None,
        'first_edit_calls_median': statistics.median(e[1] for e in edits) if edits else None,
        'project_hours': {name: round(union_seconds(t) / 3600, 2) for name, t in sorted(project_turns.items())},
    }


def project_repos(projects_dir):
    """Returns {repo path: top project name} for every git repo under projects/, at any depth."""
    repos = {}
    for current, folders, _ in os.walk(projects_dir):
        folders[:] = [f for f in folders if f not in ('node_modules', '.git')]
        if os.path.exists(os.path.join(current, '.git')) and current != projects_dir:
            repos[current] = os.path.relpath(current, projects_dir).split(os.sep)[0]
    return repos


def parse_git_log(text):
    """Returns the agent commits of a `git log --numstat` output: (author time, subject, [(added, path)])."""
    commits = []
    for chunk in text.split('\x1e')[1:]:
        header, _, numstat = chunk.partition('\x1f')
        stamp, _, rest = header.partition('\n')
        subject, _, body = rest.partition('\n')
        if AGENT_COMMIT not in body and AGENT_COMMIT not in subject:
            continue
        files = []
        for row in numstat.strip().splitlines():
            parts = row.split('\t')
            if len(parts) == 3 and parts[0].isdigit():
                files.append((int(parts[0]), parts[2]))
        commits.append((int(stamp), subject, files))
    return commits


def project_lines(projects_dir, since, until):
    """Returns {project: {'commits', 'code', 'docs'}} of the agent commits in the period, or None without git.

    A commit seen twice (the same subject and author time in two refs, as after a rebase) counts once. Generated files
    (lock files, build output, images, fonts) do not count; documentation counts apart from code.
    """
    found = collections.defaultdict(collections.Counter)
    seen = set()
    for repo, project in sorted(project_repos(projects_dir).items()):
        command = ['git', '-C', repo, 'log', '--all', '--no-merges', '--format=%x1e%at%n%s%n%b%x1f', '--numstat']
        try:
            result = subprocess.run(command, capture_output=True, text=True, errors='replace')
        except OSError:
            return None
        for stamp, subject, files in parse_git_log(result.stdout):
            if not since < stamp <= until or (project, subject, stamp) in seen:
                continue
            seen.add((project, subject, stamp))
            counts = found[project]
            counts['commits'] += 1
            for added, path in files:
                if GENERATED_RE.search(path):
                    continue
                counts['docs' if DOC_RE.search(path) else 'code'] += added
    return {name: dict(values) for name, values in sorted(found.items())}


def project_table(hours, lines, aliases):
    """Returns {project: {'hours', 'commits', 'code', 'docs'}} joining agent hours and delivered lines.

    The hours come by the folder a tool call named, which for a clone of a nested repo is the repo's own name;
    aliases maps it to its top project. A name that is no project of projects/ is left out.
    """
    merged = collections.Counter()
    for name, value in hours.items():
        if name in aliases:
            merged[aliases[name]] += value
    hours = {name: round(value, 2) for name, value in merged.items()}
    table = {}
    for name in sorted(set(hours) | set(lines or {})):
        row = {'hours': hours.get(name, 0), 'commits': 0, 'code': 0, 'docs': 0}
        row.update((lines or {}).get(name, {}))
        table[name] = row
    return table


def ratio(numerator, denominator, scale=1.0):
    """Returns numerator / denominator * scale, or None when there is no denominator."""
    return numerator * scale / denominator if denominator else None


def indicators(data):
    """Returns the comparable indicators of one measurement: (label, value, decimals)."""
    counts = data.get('counts', {})
    groups = data.get('groups', {})
    prompts = counts.get('prompts', 0)
    sessions = counts.get('sessions', 0)
    calls = sum(g.get('calls', 0) for g in groups.values())
    hook_runs = sum(v[0] for v in data.get('hooks', {}).values())
    hook_ms = sum(v[1] for v in data.get('hooks', {}).values())
    first_context = data.get('first_context_median')
    projects = data.get('projects') or {}
    project_hours = sum(p.get('hours', 0) for p in projects.values())
    project_lines_total = sum(p.get('code', 0) + p.get('docs', 0) for p in projects.values())
    return [
        ('Sessions', sessions, 0),
        ('Human prompts', prompts, 0),
        ('API calls per prompt', ratio(counts.get('api_calls', 0), prompts), 1),
        ('Input tokens per prompt (thousands)', ratio(counts.get('tokens_in', 0), prompts, 0.001), 0),
        (
            'Context of the first call (thousand tokens, median)',
            None if first_context is None else first_context / 1000,
            1,
        ),
        ('Workspace process tool calls (%)', ratio(groups.get('process', {}).get('calls', 0), calls, 100), 1),
        ('Validation and gate tool calls (%)', ratio(groups.get('validation', {}).get('calls', 0), calls, 100), 1),
        ('Questions to the human per 10 prompts', ratio(groups.get('questions', {}).get('calls', 0), prompts, 10), 1),
        ('Seconds to the first edit (median)', data.get('first_edit_seconds_median'), 0),
        ('Tool calls to the first edit (median)', data.get('first_edit_calls_median'), 1),
        ('Compactions per session', ratio(counts.get('compactions', 0), sessions), 2),
        ('Project instructions loaded on their own', counts.get('nested_project_rules', 0), 0),
        ('Milliseconds per hook run', ratio(hook_ms, hook_runs), 0),
        ('Cost per prompt (USD, sessions opened in the period)', ratio(data.get('cost_usd', 0), prompts), 2),
        (
            'Lines delivered per agent hour in the projects (code and docs)',
            ratio(project_lines_total, project_hours),
            0,
        ),
    ]


def show(value, decimals):
    """Formats one indicator value; a missing one is a dash."""
    if value is None:
        return '—'
    return f'{value:,.{decimals}f}'.replace(',', ' ')


def change(before, after):
    """Formats the change between two values, as a percentage when possible."""
    if before is None or after is None:
        return '—'
    if before == 0:
        return 'same' if after == 0 else 'new'
    percent = (after - before) * 100 / before
    return 'same' if abs(percent) < 0.05 else f'{percent:+.1f}%'


def when(epoch):
    """Formats an epoch as local date and time; None is the start of the records."""
    if epoch is None:
        return 'start of the records'
    return datetime.datetime.fromtimestamp(epoch).strftime('%Y-%m-%d %H:%M')


def render(data, previous):
    """Returns the report text: summary, comparison with the previous report, the last ones, the breakdown."""
    counts = data['counts']
    lines = [
        f'# Performance measurement: {data["name"]}',
        '',
        f'- Date: {data["date"]}',
        f'- Period: {when(data["period"]["start"])} to {when(data["period"]["end"])}',
        f'- Workspace: version {data["version"]}, commit `{data["core"]}`',
        f'- Sessions: {counts.get("sessions", 0)}; human prompts: {counts.get("prompts", 0)}; '
        f'API calls: {counts.get("api_calls", 0)}',
        '',
    ]
    now = indicators(data)
    if previous:
        last = previous[-1]
        before = indicators(last)
        lines += [
            f'## Comparison with the previous measurement ({last["date"]}-{last["name"]})',
            '',
            '| Indicator | Previous | Now | Change |',
            '| --- | ---: | ---: | ---: |',
        ]
        for (label, old, digits), (_, new, _) in zip(before, now):
            lines.append(f'| {label} | {show(old, digits)} | {show(new, digits)} | {change(old, new)} |')
        lines.append('')
        series = previous + [data]
        lines += [f'## Last {len(series)} measurements', '']
        lines.append('| Indicator | ' + ' | '.join(f'{d["date"]} {d["name"]}' for d in series) + ' |')
        lines.append('| --- |' + ' ---: |' * len(series))
        table = [indicators(d) for d in series]
        for row, (label, _, digits) in enumerate(now):
            lines.append(f'| {label} | ' + ' | '.join(show(t[row][1], digits) for t in table) + ' |')
        lines.append('')
    else:
        lines += ['## Indicators', '', 'First measurement: nothing to compare with yet.', '']
        lines += ['| Indicator | Value |', '| --- | ---: |']
        lines += [f'| {label} | {show(value, digits)} |' for label, value, digits in now]
        lines.append('')
    lines += projects_section(data, previous)
    lines += breakdown(data)
    lines += [
        '## How to read',
        '',
        '- Each measurement covers the period since the previous one. Compare rates and medians; '
        'counts depend on the length of the period.',
        '- The classification of tool calls is heuristic (`scripts/performance/measure.py`, `classify`). '
        'Subagents are left out: only the main session counts.',
        '- Hooks: only the runs the transcript records (those that returned something); the count is not the total.',
        '- Projects: each request counts for the project its tools touched most; the hours are the union of its turns '
        '(a turn counts at most 4 h). With less than half an hour in the period, the rate is left blank. '
        'Lines are not value: read them together with commits and questions.',
        '- Claude Code deletes the transcripts after `cleanupPeriodDays` (30 days by default): measure before that.',
        '- To follow in real time and per model, use the Grafana of `tools/observability/`.',
        '',
        '<!-- performance-data',
        json.dumps(data, ensure_ascii=False, sort_keys=True),
        '-->',
        '',
    ]
    return '\n'.join(lines)


def rate(lines, hours):
    """Returns lines per hour, or None when the hours are too few to divide by."""
    return ratio(lines, hours) if hours >= MIN_PROJECT_HOURS else None


def projects_section(data, previous):
    """Returns the table of lines delivered per hour of agent work, per project and in total."""
    projects = data.get('projects')
    if projects is None:
        return ['## Projects', '', 'No `git` on this machine: the delivered lines were not counted.', '']
    if not projects:
        return []
    before = (previous[-1].get('projects') or {}) if previous else {}
    lines = [
        '## Projects',
        '',
        'Lines added in the agent commits of each project, per hour of agent work on it.',
        '',
        '| Project | Agent hours | Commits | Code | Docs | Code/h | Docs/h | Total/h | Previous total/h |',
        '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |',
    ]
    totals = collections.Counter()
    for name, row in projects.items():
        hours = row['hours']
        totals.update({k: row[k] for k in ('hours', 'commits', 'code', 'docs')})
        old = before.get(name) or {}
        lines.append(
            f'| `{name}` | {show(hours, 1)} | {row["commits"]} | {row["code"]} | {row["docs"]} | '
            f'{show(rate(row["code"], hours), 0)} | {show(rate(row["docs"], hours), 0)} | '
            f'{show(rate(row["code"] + row["docs"], hours), 0)} | '
            f'{show(rate(old.get("code", 0) + old.get("docs", 0), old.get("hours", 0)), 0)} |'
        )
    hours = totals['hours']
    lines.append(
        f'| **Total** | {show(hours, 1)} | {totals["commits"]} | {totals["code"]} | {totals["docs"]} | '
        f'{show(ratio(totals["code"], hours), 0)} | {show(ratio(totals["docs"], hours), 0)} | '
        f'{show(ratio(totals["code"] + totals["docs"], hours), 0)} | |'
    )
    lines.append('')
    return lines


def breakdown(data):
    """Returns the tables of where the work went, the hooks and the models."""
    groups = data['groups']
    totals = {key: sum(g[key] for g in groups.values()) for key in ('calls', 'api', 'tokens_in', 'time')}
    lines = [
        '## Where the work went',
        '',
        '| Group | Tool calls | % tool calls | % API calls | % input tokens | % time |',
        '| --- | ---: | ---: | ---: | ---: | ---: |',
    ]
    for group, values in groups.items():
        shares = [show(ratio(values[k], totals[k], 100), 1) for k in ('calls', 'api', 'tokens_in', 'time')]
        lines.append(f'| {GROUP_LABEL[group]} | {values["calls"]} | ' + ' | '.join(shares) + ' |')
    lines.append('')
    if data['hooks']:
        lines += ['## Hooks', '', '| Hook | Recorded runs | ms per run |', '| --- | ---: | ---: |']
        for name, (runs, millis) in data['hooks'].items():
            lines.append(f'| `{name}` | {runs} | {show(ratio(millis, runs), 0)} |')
        lines.append('')
    if data['models']:
        total = sum(data['models'].values())
        lines += ['## Models', '', '| Model | % input tokens |', '| --- | ---: |']
        lines += [f'| `{m}` | {show(ratio(t, total, 100), 1)} |' for m, t in data['models'].items()]
        lines.append('')
    return lines


def previous_reports(folder):
    """Returns the data of the earlier reports in the folder, oldest first; files without data are skipped."""
    found = []
    for path in glob.glob(os.path.join(folder, '*.md')):
        with open(path, encoding='utf-8', errors='replace') as handle:
            block = DATA_BLOCK.search(handle.read())
        if not block:
            continue
        try:
            data = json.loads(block.group(1))
        except ValueError:
            continue
        if isinstance(data, dict) and data.get('format') == FORMAT:
            if isinstance(data.get('groups'), dict):
                data['groups'] = {GROUP_KEYS.get(key, key): value for key, value in data['groups'].items()}
            found.append(data)
    return sorted(found, key=lambda d: (d['period']['end'], d['date'], d['name']))


def observability_problem(health_url, otlp_address, timeout=3.0):
    """Returns why the observability stack is not usable, or None when Grafana is healthy and the OTLP port is open."""
    try:
        with urllib.request.urlopen(health_url, timeout=timeout) as response:
            health = json.loads(response.read().decode('utf-8', 'replace') or '{}')
    except (urllib.error.URLError, OSError, ValueError) as error:
        return f'Grafana did not answer at {health_url} ({error})'
    if not isinstance(health, dict) or health.get('database') != 'ok':
        return f'Grafana answered at {health_url}, but its database is not ready'
    try:
        socket.create_connection(otlp_address, timeout=timeout).close()
    except OSError as error:
        return f'the OTLP port {otlp_address[0]}:{otlp_address[1]} refused the connection ({error})'
    return None


def transcripts_folder(root):
    """Returns the folder where Claude Code keeps the transcripts of sessions opened at root."""
    base = os.environ.get('CLAUDE_CONFIG_DIR') or os.path.join(os.path.expanduser('~'), '.claude')
    return os.path.join(base, 'projects', re.sub(r'[^A-Za-z0-9]', '-', os.path.realpath(root)))


def workspace_version(root):
    """Returns (version, short commit) of the core; unknown parts are '?'."""
    version = '?'
    try:
        with open(os.path.join(root, 'VERSION'), encoding='utf-8') as handle:
            version = handle.read().strip() or '?'
    except OSError:
        pass
    try:
        result = subprocess.run(['git', '-C', root, 'rev-parse', '--short', 'HEAD'], capture_output=True, text=True)
    except OSError:
        return version, '?'
    return version, result.stdout.strip() or '?'


def parse_args(argv):
    """Returns the parsed command line."""
    parser = argparse.ArgumentParser(
        prog='measure.py',
        description='Measures the performance of the workspace from the transcripts and writes '
        'custom/performance/<date>-<name>.md, comparing with the previous measurements.',
    )
    parser.add_argument('--name', default='measurement', help='name of the report, kebab-case (default: measurement)')
    period = parser.add_mutually_exclusive_group()
    period.add_argument(
        '--since', help='start of the period (YYYY-MM-DD or ISO); default: the end of the previous measurement'
    )
    period.add_argument('--all', action='store_true', help='the whole period the transcripts still keep')
    parser.add_argument(
        '--compare', type=int, default=5, help='how many measurements the side-by-side table shows (default: 5)'
    )
    parser.add_argument(
        '--transcripts', help='folder of the transcripts (default: the Claude Code one for the workspace root)'
    )
    parser.add_argument('--out', help='folder of the reports (default: custom/performance)')
    parser.add_argument('--root', default=ROOT, help=argparse.SUPPRESS)
    parser.add_argument('--now', help=argparse.SUPPRESS)
    parser.add_argument('--grafana-health', default=GRAFANA_HEALTH, help=argparse.SUPPRESS)
    parser.add_argument('--otlp-port', type=int, default=OTLP_ADDRESS[1], help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if not KEBAB.match(args.name):
        parser.error(f'--name must be kebab-case: {args.name}')
    if args.compare < 2:
        parser.error('--compare must be 2 or more')
    return args


def run(args):
    """Measures and writes the report; returns the exit code."""
    problem = observability_problem(args.grafana_health, (OTLP_ADDRESS[0], args.otlp_port))
    if problem:
        print(f'measure: the observability stack must be up: {problem}. Start it with: {STACK_UP}', file=sys.stderr)
        return 2
    out = args.out or os.path.join(args.root, 'custom', 'performance')
    if not args.out and not os.path.isdir(os.path.join(args.root, 'custom')):
        print('measure: no custom layer (custom/); pass --out <folder>', file=sys.stderr)
        return 2
    folder = args.transcripts or transcripts_folder(args.root)
    paths = sorted(glob.glob(os.path.join(folder, '*.jsonl')))
    if not paths:
        print(f'measure: no transcripts in {folder}', file=sys.stderr)
        return 2
    now = parse_time(args.now) if args.now else datetime.datetime.now().timestamp()
    previous = previous_reports(out) if os.path.isdir(out) else []
    if args.since:
        since = parse_time(args.since)
        if since is None:
            print(f'measure: invalid date in --since: {args.since}', file=sys.stderr)
            return 2
    elif args.all or not previous:
        since = None
    else:
        since = previous[-1]['period']['end']
    date = datetime.datetime.fromtimestamp(now).strftime('%Y-%m-%d')
    target = os.path.join(out, f'{date}-{args.name}.md')
    if os.path.exists(target):
        print(f'measure: {target} already exists; use another --name', file=sys.stderr)
        return 1
    version, core = workspace_version(args.root)
    start = float('-inf') if since is None else since
    data = measure(paths, start, now)
    projects_dir = os.path.join(args.root, 'projects')
    repos = project_repos(projects_dir) if os.path.isdir(projects_dir) else {}
    aliases = {os.path.basename(repo): top for repo, top in repos.items()}
    aliases.update({top: top for top in repos.values()})
    lines = project_lines(projects_dir, start, now) if repos else {}
    hours = data.pop('project_hours')
    data['projects'] = None if lines is None else project_table(hours, lines, aliases)
    data.update(
        {
            'format': FORMAT,
            'name': args.name,
            'date': date,
            'version': version,
            'core': core,
            'period': {'start': since, 'end': now},
        }
    )
    os.makedirs(out, exist_ok=True)
    with open(target, 'w', encoding='utf-8') as handle:
        handle.write(render(data, previous[-(args.compare - 1) :]))
    print(target)
    return 0


def main(argv=None):
    """Entry point."""
    return run(parse_args(sys.argv[1:] if argv is None else argv))


if __name__ == '__main__':
    sys.exit(main())
