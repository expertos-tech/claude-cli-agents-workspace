"""Unit tests of scripts/prompt-log.py (the prompt log per project and per week, read from the session transcripts)."""

import contextlib
import datetime
import fcntl
import importlib.util
import io
import json
import os
import re
import shutil
import stat
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parent.parent / 'prompt-log.py'
SPEC = importlib.util.spec_from_file_location('prompt_log', MODULE_PATH)
log = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(log)

SAVED_TZ = os.environ.get('TZ')


@contextlib.contextmanager
def local_tz(name):
    """Runs the block with another local timezone (a POSIX TZ string: no tz database needed), then back to UTC."""
    os.environ['TZ'] = name
    time.tzset()
    try:
        yield
    finally:
        os.environ['TZ'] = 'UTC'
        time.tzset()


SAVED_UMASK = os.umask(0o022)
os.umask(SAVED_UMASK)
REPO = Path(__file__).resolve().parent.parent.parent


def setUpModule():
    """Local time is UTC and the umask 022 here, so hours, days and file modes do not depend on the machine."""
    os.environ['TZ'] = 'UTC'
    time.tzset()
    os.umask(0o022)


def tearDownModule():
    os.umask(SAVED_UMASK)
    if SAVED_TZ is None:
        os.environ.pop('TZ', None)
    else:
        os.environ['TZ'] = SAVED_TZ
    time.tzset()


def stamp(minute, day=10, hour=10):
    """Returns an ISO timestamp on 2026-11-<day> at <hour>:<minute> UTC."""
    return f'2026-11-{day:02d}T{hour:02d}:{minute:02d}:00.000Z'


def epoch(minute, day=10, hour=10):
    return datetime.datetime(2026, 11, day, hour, minute, tzinfo=datetime.timezone.utc).timestamp()


def human(minute, text='do this', day=10):
    return {
        'type': 'user',
        'timestamp': stamp(minute, day),
        'origin': {'kind': 'human'},
        'isSidechain': False,
        'message': {'content': text},
    }


def tool_use(minute, ident, name, tool_input, day=10):
    content = [{'type': 'tool_use', 'id': ident, 'name': name, 'input': tool_input}]
    return {'type': 'assistant', 'timestamp': stamp(minute, day), 'message': {'content': content}}


def tool_result(minute, ident, error=False, day=10):
    content = [{'type': 'tool_result', 'tool_use_id': ident, 'is_error': error, 'content': 'ok'}]
    return {'type': 'user', 'timestamp': stamp(minute, day), 'message': {'content': content}}


def write_jsonl(path, records):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as handle:
        for record in records:
            handle.write((record if isinstance(record, str) else json.dumps(record, separators=(',', ':'))) + '\n')


def record(minute=1, day=10, project='billing', session='s1', commits=None, merge=False, text='do this', title='t1'):
    return {
        'session': session,
        'title': title,
        'timestamp': stamp(minute, day),
        'text': text,
        'project': project,
        'merge': merge,
        'until': epoch(minute, day) + 600,
        'commits': commits or [],
    }


def git_log_text(*commits):
    """Returns a git log in the agent-commit format: (author time, sha, subject, body)."""
    return ''.join(f'\x1e{at}\n{sha} {subject}\n{body}\x1f\n' for at, sha, subject, body in commits)


AGENT = '[#automatic-agent-commit]'


class Workspace:
    """A throwaway workspace root with custom/, projects/ and a Claude config folder for the transcripts."""

    def __enter__(self):
        self.temp = tempfile.TemporaryDirectory()
        base = os.path.realpath(self.temp.name)
        # [, * and ? in the path: the log must not take them for glob patterns.
        self.root = os.path.join(base, 'ws[1]*?')
        self.config = os.path.join(base, 'config')
        self.log = os.path.join(self.root, 'custom', 'prompts', 'log')
        os.makedirs(os.path.join(self.root, 'custom'))
        for repo in ('billing/.git', 'shop/api/.git', 'shop/web/.git'):
            os.makedirs(os.path.join(self.root, 'projects', repo))
        self.env = mock.patch.dict(os.environ, {'CLAUDE_CONFIG_DIR': self.config})
        self.env.start()
        return self

    def __exit__(self, *exc):
        self.env.stop()
        self.temp.cleanup()

    def transcripts(self, folder=None):
        return log.measure.transcripts_folder(folder or self.root)

    def session(self, name, records, folder=None):
        write_jsonl(os.path.join(self.transcripts(folder), f'{name}.jsonl'), records)

    def read(self, project, week='2026-W46'):
        with open(os.path.join(self.log, project, f'{week}.md'), encoding='utf-8') as handle:
            return handle.read()


def fake_git(outputs):
    """Returns a subprocess.run stand-in: git log answers from outputs by repo folder name."""

    def run(command, **kwargs):
        if command[0] == 'git' and command[3] == 'log':
            return mock.Mock(returncode=0, stdout=outputs.get(os.path.basename(command[2]), ''))
        raise AssertionError(command)

    return run


class PromptTextTest(unittest.TestCase):
    def test_plain_list_and_command(self):
        self.assertEqual(log.prompt_text('  do this  '), 'do this')
        blocks = [{'type': 'text', 'text': '[Image #1]\nlook'}, {'type': 'image', 'source': {}}, 'x']
        self.assertEqual(log.prompt_text(blocks), '[Image #1]\nlook')
        command = '<command-message>prompt</command-message>\n<command-name>/prompt</command-name>\n'
        self.assertEqual(log.prompt_text(command + '<command-args>a.md</command-args>'), '/prompt a.md')
        self.assertEqual(log.prompt_text(command), '/prompt')
        self.assertEqual(log.prompt_text(None), '')

    def test_pastes(self):
        short = 'look:\n<pasted_content id="ab">\nline 1\nline 2\n</pasted_content id="ab">'
        self.assertEqual(log.prompt_text(short), 'look:\nline 1\nline 2')
        long = 'look:\n<pasted_content id="ab">\n' + '\n'.join(['x'] * 41) + '\n</pasted_content>'
        self.assertEqual(log.prompt_text(long), 'look:\n[pasted: 41 lines]')
        self.assertEqual(log.prompt_text('\n'.join(['y'] * 45)), '[pasted: 45 lines]')

    def test_scrub(self):
        cases = [
            # Built in pieces, so the secret scan of the repo does not take the fixtures for real keys.
            '-----BEGIN RSA ' + 'PRIVATE KEY-----\nabc\n-----END RSA ' + 'PRIVATE KEY-----',
            'AKIA' + 'ABCDEFGHIJKLMNOP',
            'ghp_' + 'a' * 36,
            'github_pat_' + 'b' * 30,
            'glpat-' + 'c' * 20,
            'xoxb-1234567890-abc',
            'https://hooks.slack.com/services/T000/B000/xyz',
            'AIza' + 'd' * 35,
            '.'.join(['eyJ' + 'hbGciOiJIUzI1NiJ9', 'eyJ' + 'zdWIiOiIxMjM0NSJ9', 'c2lnbmF0dXJl' + 'LXZhbHVl']),
        ]
        for secret in cases:
            self.assertEqual(log.scrub(f'key {secret} here'), f'key {log.REMOVED} here', secret)
        self.assertEqual(log.scrub('x -----BEGIN OPENSSH ' + 'PRIVATE KEY-----\nabc no end'), f'x {log.REMOVED}')
        self.assertEqual(log.scrub('Authorization: Bearer ' + 'e' * 30), f'Authorization: Bearer {log.REMOVED}')
        self.assertEqual(
            log.scrub('Server=x;AccountKey=abc/def==;Password=p4ss'),
            f'Server=x;AccountKey={log.REMOVED};Password={log.REMOVED}',
        )
        self.assertEqual(log.scrub('DB_PASSWORD="hunter2hunter2"'), f'DB_PASSWORD="{log.REMOVED}"')
        self.assertEqual(log.scrub('api_key: abcdefgh123'), f'api_key: {log.REMOVED}')
        tool = 'cu' + 'rl'
        kept = {
            'git clone https://deploy:' + 'pa55word@host/x.git': f'git clone https://deploy:{log.REMOVED}@host/x.git',
            'postgres://app:' + 'pw-1@db:5432/app': f'postgres://app:{log.REMOVED}@db:5432/app',
            tool + ' -u admin:' + 's3cretpass https://x': f'{tool} -u admin:{log.REMOVED} https://x',
            tool + ' --user admin:' + 's3cretpass x': f'{tool} --user admin:{log.REMOVED} x',
            'docker run -u 1000:1000 img': 'docker run -u 1000:1000 img',
            'docker run -u "$(id -u):$(id -g)" img': 'docker run -u "$(id -u):$(id -g)" img',
            'key sk-ant-' + 'api03-' + 'f' * 30 + ' end': f'key {log.REMOVED} end',
            'key sk-proj-' + 'g' * 30: f'key {log.REMOVED}',
            'key sk_live_' + 'h' * 20: f'key {log.REMOVED}',
            'key rk_live_' + 'i' * 20: f'key {log.REMOVED}',
            'key npm_' + 'j' * 36: f'key {log.REMOVED}',
            'https://acct.blob.core.windows.net/c?sv=2024&sig=' + 'k' * 20 + '%3D': (
                f'https://acct.blob.core.windows.net/c?sv=2024&sig={log.REMOVED}'
            ),
            'git@ssh.dev.example.com:v3/org/repo': 'git@ssh.dev.example.com:v3/org/repo',
            'redis://:' + 'Cache-pass-1@cache:6379': f'redis://:{log.REMOVED}@cache:6379',
            'postgres://admin:' + 'aB3/xY9+z@db/app': f'postgres://admin:{log.REMOVED}@db/app',
            'mongodb://root:' + 'p@ss-w0rd@mongo/admin': f'mongodb://root:{log.REMOVED}@mongo/admin',
        }
        for text, expected in kept.items():
            self.assertEqual(log.scrub(text), expected, text)
        for text in [*cases, *kept, 'token=abcdefgh123', 'Password=p4ss;AccountKey=x', tool + ' -u a:bcdefgh']:
            once = log.scrub(text)
            self.assertEqual(log.scrub(once), once, text)
        self.assertEqual(log.scrub('we spent too many tokens: 500'), 'we spent too many tokens: 500')


class TranscriptTest(unittest.TestCase):
    def test_session_records(self):
        with Workspace() as ws:
            merge_cmd = 'bash scripts/aiwp-cmds.sh gate --merge 2026-11-10-x/billing abc123'
            ws.session(
                'sess-0001-long-id',
                [
                    {'type': 'custom-title', 'customTitle': 'stale', 'sessionId': 'x'},
                    tool_use(0, 'early', 'Bash', {'command': 'ls projects/shop'}),
                    human(1, 'primeiro'),
                    tool_use(2, 'a1', 'Edit', {'file_path': '/ws/tmp/work/2026-11-10-x/billing/a.py'}),
                    tool_use(3, 'a2', 'Bash', {'command': merge_cmd}),
                    tool_result(4, 'a2'),
                    tool_use(5, 'a3', 'Bash', {'command': merge_cmd}),
                    tool_result(5, 'a3', error=True),
                    {'type': 'user', 'isSidechain': True, 'timestamp': stamp(50), 'origin': {'kind': 'human'}},
                    human(6, '<local-command-stdout>x</local-command-stdout>'),
                    human(10, 'segundo'),
                    tool_use(11, 'b1', 'Read', {'file_path': 'projects/README.md'}),
                    tool_use(11, 'b2', 'Read', {'file_path': '/ws/projects/shop/web/x.ts'}),
                    tool_use(12, 'b3', 'Agent', 'not a dict'),
                    tool_use(12, 'b4', 'Bash', {'command': merge_cmd}),
                    {'type': 'assistant', 'timestamp': stamp(13), 'message': {'content': ['tool_use', None]}},
                    {'type': 'user', 'timestamp': 'nunca', 'origin': {'kind': 'human'}, 'message': {}},
                    '{"type":"tool_use" broken',
                    '["tool_use"]',
                    {'type': 'custom-title', 'customTitle': 'billing-1', 'sessionId': 'x'},
                    {'type': 'custom-title', 'customTitle': '  ', 'sessionId': 'x'},
                    {'type': 'system', 'timestamp': stamp(20)},
                ],
            )
            repos = log.measure.project_repos(os.path.join(ws.root, 'projects'))
            aliases = {os.path.basename(r): top for r, top in repos.items()}
            aliases.update({top: top for top in repos.values()})
            path = os.path.join(ws.transcripts(), 'sess-0001-long-id.jsonl')
            first, second = log.session_records(path, aliases, 'workspace')
        self.assertEqual((first['title'], first['project'], first['merge']), ('billing-1', 'billing', True))
        self.assertEqual((first['text'], first['until']), ('primeiro', epoch(5) + 1))
        self.assertEqual((second['project'], second['merge'], second['until']), ('shop', False, epoch(13) + 1))
        self.assertEqual(second['session'], 'sess-0001-long-id')

    def test_window_ends_with_the_turn(self):
        with Workspace() as ws:
            ws.session(
                'resumed',
                [
                    human(56, 'primeiro', day=9),
                    tool_use(57, 'a', 'Edit', {'file_path': '/x/projects/billing/a.py'}, day=9),
                    tool_result(58, 'a', day=9),
                    {'type': 'attachment', 'timestamp': stamp(0, day=14), 'attachment': {'type': 'hook_success'}},
                    {'type': 'system', 'timestamp': stamp(1, day=14), 'subtype': 'turn_duration'},
                    human(2, 'retomada dias depois', day=14),
                    tool_use(3, 'b', 'Edit', {'file_path': '/x/projects/billing/a.py'}, day=14),
                    tool_result(4, 'b', day=14),
                    {'type': 'assistant', 'timestamp': '2026-11-14T18:00:00Z', 'message': {'content': []}},
                ],
            )
            commits = git_log_text(
                (int(epoch(57, day=9)), 'aaa1111', 'feat: in the first turn', AGENT),
                (int(epoch(0, day=12)), 'bbb2222', 'feat: while the session slept', AGENT),
                (int(epoch(30, day=14, hour=13)), 'ccc3333', 'feat: three hours into the second turn', AGENT),
                (int(epoch(30, day=14, hour=15)), 'ddd4444', 'feat: past the 4 h cap', AGENT),
            )
            with mock.patch.object(log.subprocess, 'run', side_effect=fake_git({'billing': commits})):
                fresh = log.collect(ws.root, ws.log)
        first, second = sorted(fresh.values(), key=lambda r: r['timestamp'])
        self.assertEqual(first['until'], epoch(58, day=9) + 1)
        self.assertEqual(first['commits'], [['aaa1111', 'feat: in the first turn']])
        self.assertEqual(second['until'], epoch(2, day=14) + log.measure.TURN_CAP_SECONDS + 1)
        self.assertEqual(second['commits'], [['ccc3333', 'feat: three hours into the second turn']])

    def test_untitled_session_and_fallback(self):
        with Workspace() as ws:
            ws.session('abcdef123456', [human(1, 'just a question')])
            path = os.path.join(ws.transcripts(), 'abcdef123456.jsonl')
            (only,) = log.session_records(path, {}, 'claude-cli')
        self.assertEqual((only['title'], only['project'], only['until']), ('abcdef12', 'claude-cli', epoch(1) + 1))


class SourcesTest(unittest.TestCase):
    def test_sources(self):
        with Workspace() as ws:
            os.makedirs(ws.log)
            self.assertEqual(log.read_sources(ws.root, ws.log), [(ws.transcripts(), 'workspace')])
            path = os.path.join(ws.log, 'sources.json')
            Path(path).write_text(json.dumps({'/other/place': 'claude-cli', ws.root: 'dup'}), encoding='utf-8')
            sources = log.read_sources(ws.root, ws.log)
            self.assertEqual(sources, [(ws.transcripts(), 'workspace'), (ws.transcripts('/other/place'), 'claude-cli')])
            for bad in ('{', '[]', '{"/x": "../evil"}', '{"/x": 3}'):
                Path(path).write_text(bad, encoding='utf-8')
                with self.assertRaises(log.LogError):
                    log.read_sources(ws.root, ws.log)


class CommitsTest(unittest.TestCase):
    def test_git_log(self):
        with mock.patch.object(log.subprocess, 'run', side_effect=FileNotFoundError('git')):
            self.assertIsNone(log.git_log('/r', 0))
        with mock.patch.object(log.subprocess, 'run', return_value=mock.Mock(returncode=128, stdout='x')):
            self.assertIsNone(log.git_log('/r', 0))
        with mock.patch.object(log.subprocess, 'run', return_value=mock.Mock(returncode=0, stdout='log')) as run:
            self.assertEqual(log.git_log('/r', 0), 'log')
        self.assertIn('--since=1970-01-01 00:00:00 +0000', run.call_args[0][0])

    def test_agent_commits_dedup_and_windows(self):
        start = int(epoch(1))
        outputs = {
            'api': git_log_text(
                (start + 60, 'aaa1111', 'feat(api): add billing export', AGENT),
                (start + 61, 'bbb2222', 'chore: human commit', 'no marker'),
            ),
            'web': git_log_text(
                (start + 60, 'ccc3333', 'feat(api): add billing export', AGENT),
                (start + 700, 'ddd4444', 'fix: late', AGENT),
            ),
        }
        repos = {'/p/shop/api': 'shop', '/p/shop/web': 'shop', '/p/billing': 'billing'}
        records = [record(project='shop'), record(project='workspace')]
        with mock.patch.object(log.subprocess, 'run', side_effect=fake_git(outputs)):
            log.attach_commits(records, repos)
        self.assertEqual(records[0]['commits'], [['aaa1111', 'feat(api): add billing export']])
        self.assertEqual(records[1]['commits'], [])
        fresh = [{k: v for k, v in record(project='shop').items() if k != 'commits'}]
        with mock.patch.object(log.subprocess, 'run', side_effect=FileNotFoundError('git')):
            log.attach_commits(fresh, repos)
        self.assertNotIn('commits', fresh[0])
        # git failing on one repo of a project (exit 128) leaves the project's stored commits alone, not the others.
        both = [{k: v for k, v in record(project=p).items() if k != 'commits'} for p in ('shop', 'billing')]
        failing = mock.Mock(returncode=128, stdout='')
        with mock.patch.object(log.subprocess, 'run', side_effect=[mock.Mock(returncode=0, stdout=''), failing]):
            log.attach_commits(both, repos)
        self.assertEqual(['commits' in r for r in both], [False, True])
        stored = {('s1', stamp(1)): record(commits=[['aaa1111', 'feat: kept']])}
        merged, _ = log.merge(stored, {('s1', stamp(1)): both[0]})
        self.assertEqual(merged[('s1', stamp(1))]['commits'], [['aaa1111', 'feat: kept']])


class LogFileTest(unittest.TestCase):
    def test_load_merge_render_write(self):
        with Workspace() as ws:
            today = datetime.date(2026, 11, 11)
            first = record(minute=1, commits=[['aaa1111', 'feat(api): add export'], ['bbb2222', 'refactor: x']])
            first['text'] = 'line 1\n\nline 3 with --> in the middle'
            second = record(minute=5, session='s2', title='billing-2', merge=True)
            third = record(minute=1, day=11, commits=[['ccc3333', 'Merge stuff'], ['ddd4444', 'wip: odd type']])
            records = {log.key_of(r): r for r in (first, second, third)}
            written = log.write_log(ws.log, records, today)
            self.assertEqual(written, [os.path.join(ws.log, 'billing', '2026-W46.md')])
            text = ws.read('billing')
            self.assertTrue(text.startswith('# billing · week 2026-W46 (2026-11-09 to 2026-11-15)\n'))
            self.assertNotIn('## Week summary', text)
            self.assertIn(
                '## 2026-11-10 (Tuesday)\n\n### Day summary\n\n- 2 prompts in 2 sessions: t1, billing-2.', text
            )
            self.assertIn('- Merges into developer through the gate: 1.\n- Agent commits: 2.\n  - feat (1)\n', text)
            self.assertIn('  - refactor (1)\n    - refactor: x', text)
            self.assertIn('## 2026-11-11 (Wednesday)\n\n### 10:01 · t1', text)
            self.assertEqual(text.count('### Day summary'), 1)
            self.assertIn('> line 1\n>\n> line 3 with --> in the middle', text)
            self.assertIn('**Result:**\n\n- `aaa1111` feat(api): add export\n- `bbb2222` refactor: x', text)
            self.assertIn('### 10:05 · billing-2\n\n> do this\n\n**Result:**\n\n- no commits\n- merge into', text)
            self.assertNotIn('"--> no', text)
            self.assertEqual(log.load_log(ws.log), records)
            self.assertEqual(log.write_log(ws.log, records, today), [])

            # A sync keeps the stored text, refreshes the rest and adds the new; a record that moves leaves its file.
            moved = dict(first, text='new text', project='shop', title='renamed')
            fresh = {log.key_of(moved): moved, log.key_of(record(minute=9)): record(minute=9)}
            merged, added = log.merge(records, fresh)
            self.assertEqual(added, 1)
            self.assertEqual(merged[log.key_of(first)]['text'], first['text'])
            self.assertEqual(merged[log.key_of(first)]['title'], 'renamed')
            later = datetime.date(2026, 11, 20)
            log.write_log(ws.log, merged, later)
            self.assertIn('## Week summary\n\n- 3 prompts in 2 sessions: billing-2, t1.', ws.read('billing'))
            self.assertIn('### 10:01 · renamed', ws.read('shop'))
            self.assertIn('  - wip (1)\n    - wip: odd type\n  - other (1)\n    - Merge stuff', ws.read('billing'))
            del merged[log.key_of(first)]
            log.write_log(ws.log, merged, later)
            self.assertFalse(os.path.exists(os.path.join(ws.log, 'shop', '2026-W46.md')))

    def test_load_refuses_unreadable_data(self):
        with Workspace() as ws:
            folder = os.path.join(ws.log, 'billing')
            os.makedirs(folder)
            Path(folder, 'notes.md').write_text('free text', encoding='utf-8')
            self.assertEqual(log.load_log(ws.log), {})
            data = {'format': 1, 'records': [record(), {'session': 1}, 'x']}
            Path(folder, '2026-W46.md').write_text(f'x\n<!-- prompt-log-data\n{json.dumps(data)}\n-->\n', 'utf-8')
            self.assertEqual(list(log.load_log(ws.log)), [('s1', stamp(1))])
            for bad in ('no block', '<!-- prompt-log-data\n{bad\n-->', '<!-- prompt-log-data\n{"format": 2}\n-->'):
                Path(folder, '2026-W46.md').write_text(bad, encoding='utf-8')
                with self.assertRaises(log.LogError):
                    log.load_log(ws.log)


class ContextTest(unittest.TestCase):
    def test_context(self):
        today = datetime.date(2026, 11, 16)
        self.assertEqual(log.context([record(day=16)], today), '')
        commits = [[f's{i}', f'feat: thing {i}'] for i in range(10)]
        records = [
            record(day=10, project='old'),
            record(minute=1, day=13, commits=commits, merge=True),
            record(minute=2, day=13, session='s2', commits=commits[:1]),
            record(minute=3, day=13, project='workspace'),
            record(day=16, project='today'),
        ]
        text = log.context(records, today).splitlines()
        self.assertEqual(text[0], 'Prompt log: the last day with activity before today was 2026-11-13 (Friday).')
        self.assertEqual(text[1], '- billing: 2 prompts in 2 sessions, 10 agent commits, 1 merge through the gate.')
        self.assertEqual(text[2:4], ['  - feat: thing 0', '  - feat: thing 1'])
        self.assertEqual(text[10], '  - and 2 more')
        self.assertEqual(text[11], '- workspace: 1 prompt in 1 session, no commits.')
        self.assertEqual(text[-1], 'Details, only if the human asks: custom/prompts/log/<project>/2026-W46.md.')
        many = [record(day=13, project=f'p{i:02d}', commits=commits[:3]) for i in range(30)]
        text = log.context(many, today).splitlines()
        self.assertEqual(len(text), log.CONTEXT_LINES)
        self.assertEqual(text[-2], '- (cut; the rest is in the files)')


class ScanAndCommitTest(unittest.TestCase):
    def test_changed_log_files(self):
        with mock.patch.object(log.subprocess, 'run', side_effect=FileNotFoundError('git')):
            self.assertIsNone(log.changed_log_files('/c'))
        with mock.patch.object(log.subprocess, 'run', return_value=mock.Mock(returncode=128, stdout='')):
            self.assertIsNone(log.changed_log_files('/c'))
        out = '?? prompts/log/shop/2026-W46.md\0 M prompts/log/sources.json\0R  prompts/log/a/2026-W45.md\0old\0\0x'
        with mock.patch.object(log.subprocess, 'run', return_value=mock.Mock(returncode=0, stdout=out)):
            self.assertEqual(log.changed_log_files('/c'), ['prompts/log/a/2026-W45.md', 'prompts/log/shop/2026-W46.md'])

    def test_run_gitleaks(self):
        with mock.patch.object(log.subprocess, 'run', side_effect=FileNotFoundError('docker')):
            self.assertEqual(log.run_gitleaks('/ws', 'custom/prompts/log', '/tmp/r'), (None, 'docker'))
        with mock.patch.object(log.subprocess, 'run', return_value=mock.Mock(returncode=1, stderr=' leaks \n')) as run:
            self.assertEqual(log.run_gitleaks('/ws', 'custom/prompts/log', '/tmp/r'), (1, 'leaks'))
        command = run.call_args[0][0]
        self.assertEqual(command[:6], ['docker', 'compose', '--progress', 'quiet', '-f', '/ws/docker/compose.yaml'])
        self.assertIn('/tmp/r:/report', command)
        self.assertIn('/work/custom/prompts/log', command)
        self.assertNotIn('--redact', command)
        self.assertEqual(command[command.index('--config') + 1], log.GITLEAKS_CONFIG)
        self.assertEqual(run.call_args[1]['env']['WORKSPACE_DIR'], '/ws')

    def test_gitleaks_config_of_the_log(self):
        """The config run_gitleaks names exists, extends gitleaks.toml and catches what scrub removes from URLs."""
        config = (REPO / log.GITLEAKS_CONFIG[len('/work/') :]).read_text(encoding='utf-8')
        self.assertIn('path = "/work/docker/config/gitleaks.toml"', config)
        rule = re.compile(re.search(r"^regex = '''(.*)'''$", config, re.M).group(1))
        for url, secret in (
            ('redis://:' + 'Cache-pass-1@cache', 'Cache-pass-1'),
            ('postgres://admin:' + 'aB3/xY9+z@db/app', 'aB3/xY9+z'),
            ('mongodb://root:' + 'p@ss-w0rd@mongo', 'p@ss-w0rd'),
        ):
            self.assertEqual(rule.search(url).group(1), secret, url)
            self.assertIsNone(rule.search(log.scrub(url)), url)
        self.assertIsNone(rule.search('git@ssh.dev.example.com:v3/org/repo'))

    def test_scan_refuses_files_it_may_not_read(self):
        with tempfile.TemporaryDirectory() as root:
            path = os.path.join(root, 'custom', 'prompts', 'log', 'billing', '2026-W46.md')
            log.write_whole(path, 'x')
            self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o644)
            files = {'custom/prompts/log/billing/2026-W46.md'}
            os.chmod(path, 0o600)
            with mock.patch.object(log, 'run_gitleaks') as run:
                with self.assertRaisesRegex(log.LogError, 'would not read custom/prompts/log/billing/2026-W46.md'):
                    log.scan(root, files)
            run.assert_not_called()
            os.chmod(path, 0o644)

            def skipping(root_dir, target, report_dir):
                Path(report_dir, 'gitleaks.json').write_text('[]', encoding='utf-8')
                return 0, 'INF x\nWRN skipping file: permission denied path=/work/a'

            with mock.patch.object(log, 'run_gitleaks', side_effect=skipping):
                with self.assertRaisesRegex(log.LogError, 'skipped files unread'):
                    log.scan(root, files)
            previous = os.umask(0o077)
            try:
                log.write_whole(path, 'y')
            finally:
                os.umask(previous)
            self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o600)

    def gitleaks(self, findings, code=1):
        """Returns a run_gitleaks stand-in that writes each report of findings in turn."""
        reports = iter(findings)

        def run(root, target, report_dir):
            report = next(reports)
            if report is not None:
                Path(report_dir, 'gitleaks.json').write_text(report, encoding='utf-8')
            return code, ''

        return run

    def test_scan(self):
        files = {'custom/prompts/log/billing/2026-W46.md'}
        found = json.dumps(
            [
                {'File': '/work/custom/prompts/log/billing/2026-W46.md', 'Secret': 's3cr3t'},
                {'File': 'custom/prompts/log/billing/2026-W46.md', 'Match': 'm4tch'},
                {'File': '/work/custom/prompts/log/other/2026-W46.md', 'Secret': 'x'},
                {'File': '/work/custom/prompts/log/billing/2026-W46.md'},
                'odd',
            ]
        )
        with mock.patch.object(log, 'run_gitleaks', side_effect=self.gitleaks([found])):
            self.assertEqual(log.scan('/ws', files), {'custom/prompts/log/billing/2026-W46.md': ['s3cr3t', 'm4tch']})
        with mock.patch.object(log, 'run_gitleaks', return_value=(None, 'no docker')):
            with self.assertRaisesRegex(log.LogError, 'no Docker'):
                log.scan('/ws', files)
        with mock.patch.object(log, 'run_gitleaks', side_effect=self.gitleaks([None])):
            with self.assertRaisesRegex(log.LogError, 'failed'):
                log.scan('/ws', files)
        with mock.patch.object(log, 'run_gitleaks', side_effect=self.gitleaks(['{}'], code=0)):
            with self.assertRaisesRegex(log.LogError, 'failed'):
                log.scan('/ws', files)
        with mock.patch.object(log, 'run_gitleaks', side_effect=self.gitleaks(['[]'], code=2)):
            with self.assertRaisesRegex(log.LogError, 'failed'):
                log.scan('/ws', files)

    def test_redact(self):
        records = {('s', 't'): record(text='a "q\\"x" e plain', commits=[['a', 'fix: plain']], title='plain')}
        self.assertEqual(log.redact(records, ['plain', 'q\\\\\\"x', '\\']), 1)
        only = records[('s', 't')]
        self.assertEqual(only['text'], f'a "{log.REMOVED}" e {log.REMOVED}')
        self.assertEqual((only['title'], only['commits']), (log.REMOVED, [['a', f'fix: {log.REMOVED}']]))
        self.assertEqual(log.redact(records, ['ausente']), 0)

    def test_git_commit(self):
        with mock.patch.object(log.subprocess, 'run', return_value=mock.Mock(returncode=0)) as run:
            self.assertEqual(log.git_commit('/c', ['a.md'], ['-m', 'x']), (True, ''))
        self.assertEqual(run.call_args[0][0], ['git', '-C', '/c', 'commit', '-q', '-m', 'x', '--', 'a.md'])
        with mock.patch.object(log.subprocess, 'run', return_value=mock.Mock(returncode=1, stderr='', stdout='no')):
            self.assertEqual(log.git_commit('/c', ['a.md'], []), (False, 'no'))
        with mock.patch.object(log.subprocess, 'run', side_effect=FileNotFoundError('git')):
            self.assertEqual(log.git_commit('/c', ['a.md'], []), (False, 'git'))

    def commit(self, ws, changed, scans, commit=(True, '')):
        """Runs commit_log over one billing record with the git and gitleaks stand-ins; returns (code, out, err)."""
        records = {('s1', stamp(1)): record(text='password s3cr3t-value here')}
        log.write_log(ws.log, records, datetime.date(2026, 11, 11))
        out, err = io.StringIO(), io.StringIO()
        with contextlib.ExitStack() as stack:
            stack.enter_context(mock.patch.object(log, 'changed_log_files', return_value=changed))
            stack.enter_context(mock.patch.object(log, 'scan', side_effect=scans))
            git_commit = stack.enter_context(mock.patch.object(log, 'git_commit', return_value=commit))
            stack.enter_context(contextlib.redirect_stdout(out))
            stack.enter_context(contextlib.redirect_stderr(err))
            code = log.commit_log(ws.root, ws.log, records, datetime.date(2026, 11, 11))
        self.git_commit = git_commit
        return code, out.getvalue(), err.getvalue()

    def test_commit_log(self):
        path = 'custom/prompts/log/billing/2026-W46.md'
        with Workspace() as ws:
            self.assertEqual(self.commit(ws, None, [])[0], 1)
            self.assertEqual(self.commit(ws, [], [])[1], 'prompt-log: nothing new to commit\n')
            changed = ['prompts/log/billing/2026-W46.md']
            code, _, err = self.commit(ws, changed, log.LogError('no Docker for gitleaks (x)'))
            self.assertEqual(code, 1)
            self.assertIn('no commit: no Docker', err)
            code, _, err = self.commit(ws, changed, [{path: ['s3cr3t-value']}, {path: ['another']}])
            self.assertEqual(code, 1)
            self.assertIn('still finds a secret', err)
            code, out, _ = self.commit(ws, changed, [{path: ['s3cr3t-value']}, {}])
            self.assertEqual(code, 0)
            self.assertIn('secret removed from ' + path, out)
            self.assertNotIn('s3cr3t-value', ws.read('billing'))
            message = self.git_commit.call_args[0][2]
            self.assertEqual(message[1], 'docs(prompts): record the prompt log')
            self.assertEqual(message[-1], AGENT)
            code, _, err = self.commit(ws, changed, [{}], commit=(False, 'hook said no'))
            self.assertEqual(code, 1)
            self.assertIn('git refused (hook said no)', err)


class MainTest(unittest.TestCase):
    def main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = log.main(['sync', *argv])
        return code, out.getvalue(), err.getvalue()

    def test_sync_and_context(self):
        with Workspace() as ws:
            ws.session('s-today', [human(1, 'today', day=16)])
            self.assertEqual(self.main('--context', '--root', ws.root, '--today', '2026-11-16'), (0, '', ''))
            other = os.path.join(ws.root, '..', 'review')
            Path(ws.log, 'sources.json').write_text(json.dumps({other: 'claude-cli'}), encoding='utf-8')
            ws.session('s-old', [human(1, 'tweak', day=13)], folder=other)
            ws.session(
                's-shop',
                [
                    human(1, 'change the shop', day=13),
                    tool_use(2, 'a', 'Edit', {'file_path': '/x/projects/shop/web/a'}, day=13),
                ],
            )
            outputs = {'web': git_log_text((int(epoch(2, day=13)), 'abc1234', 'feat(web): new cart', AGENT))}
            with mock.patch.object(log.subprocess, 'run', side_effect=fake_git(outputs)):
                code, out, err = self.main('--root', ws.root, '--today', '2026-11-16')
            self.assertEqual((code, err), (0, ''))
            self.assertIn('prompt-log: 2 new prompts; 2 files updated', out)
            self.assertIn('custom/prompts/log/shop/2026-W46.md', out)
            self.assertIn('- `abc1234` feat(web): new cart', ws.read('shop'))
            self.assertIn('### 10:01 · s-old', ws.read('claude-cli'))
            self.assertIn('> today', ws.read('workspace', '2026-W47'))
            with mock.patch.object(log.subprocess, 'run', side_effect=fake_git(outputs)):
                code, out, err = self.main('--context', '--root', ws.root, '--today', '2026-11-16')
            self.assertEqual((code, err), (0, ''))
            self.assertTrue(out.startswith('Prompt log: the last day with activity before today was 2026-11-13'))
            self.assertIn('- shop: 1 prompt in 1 session, 1 agent commit.\n  - feat(web): new cart\n', out)
            with mock.patch.object(log.subprocess, 'run', side_effect=fake_git(outputs)):
                code, out, _ = self.main('--root', ws.root, '--today', '2026-11-16')
            self.assertIn('0 new prompts; 0 files updated', out)
            with mock.patch.object(log, 'commit_log', return_value=0) as commit_log:
                self.assertEqual(self.main('--commit', '--root', ws.root, '--today', '2026-11-16')[0], 0)
            commit_log.assert_called_once()

    def test_errors(self):
        with Workspace() as ws:
            os.makedirs(ws.log)
            Path(ws.log, 'sources.json').write_text('{', encoding='utf-8')
            code, out, err = self.main('--context', '--root', ws.root)
            self.assertEqual((code, out), (0, ''))
            self.assertRegex(err, r'^prompt-log: .*sources.json: not readable JSON')
            self.assertEqual(self.main('--root', ws.root)[0], 1)
            os.remove(os.path.join(ws.log, 'sources.json'))
            with mock.patch.object(log, 'collect', side_effect=RuntimeError('boom')):
                code, out, err = self.main('--context', '--root', ws.root)
                self.assertEqual((code, out, err), (0, '', 'prompt-log: failed (RuntimeError: boom)\n'))
                with self.assertRaises(RuntimeError):
                    self.main('--root', ws.root)
            code, _, err = self.main('--root', os.path.join(ws.root, 'projects'))
            self.assertEqual((code, err), (1, 'prompt-log: no custom layer (custom/)\n'))


class TimeTest(unittest.TestCase):
    def test_local_timezone_and_iso_year(self):
        with Workspace() as ws:
            late = dict(record(), timestamp='2026-11-17T01:30:00Z')
            with local_tz('BRT3'):
                self.assertEqual(log.week_of(late), ('billing', 2026, 47))
                log.write_log(ws.log, {log.key_of(late): late}, datetime.date(2026, 11, 20))
                text = ws.read('billing', '2026-W47')
            self.assertIn('## 2026-11-16 (Monday)', text)
            self.assertIn('### 22:30 · t1', text)
            new_year = dict(record(project='shop'), timestamp='2027-01-01T12:00:00Z')
            self.assertEqual(log.week_of(new_year), ('shop', 2026, 53))
            log.write_log(ws.log, {log.key_of(new_year): new_year}, datetime.date(2027, 1, 1))
            text = ws.read('shop', '2026-W53')
            self.assertTrue(text.startswith('# shop · week 2026-W53 (2026-12-28 to 2027-01-03)'))
            self.assertIn('## 2027-01-01 (Friday)', text)
            self.assertFalse(os.path.exists(os.path.join(ws.log, 'billing', '2026-W47.md')))


class Processes:
    """Stands in for the git and docker processes of a --commit run; the rest of the code runs for real.

    git status answers from statuses in turn; each gitleaks run writes the next report into its mounted folder.
    """

    def __init__(self, statuses, reports):
        self.statuses = iter(statuses)
        self.reports = iter(reports)
        self.commands = []

    def __call__(self, command, **kwargs):
        self.commands.append(command)
        if command[0] == 'docker':
            folder = command[command.index('-v') + 1].rsplit(':', 1)[0]
            findings = next(self.reports)
            Path(folder, 'gitleaks.json').write_text(json.dumps(findings), encoding='utf-8')
            return mock.Mock(returncode=1 if findings else 0, stderr='')
        if command[3] == 'status':
            return mock.Mock(returncode=0, stdout=next(self.statuses))
        if command[3] == 'log':
            return mock.Mock(returncode=0, stdout='')
        return mock.Mock(returncode=0, stdout='', stderr='')


class CommitFlowTest(unittest.TestCase):
    def main(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = log.main(['sync', *argv])
        return code, out.getvalue(), err.getvalue()

    def test_redaction_survives_resync_and_equal_head_exits_zero(self):
        secret = 'hunter' + '-value-9'
        week = 'prompts/log/workspace/2026-W46.md'
        finding = [{'File': f'/work/custom/{week}', 'Secret': secret}]
        with Workspace() as ws:
            ws.session('s-x', [{'type': 'custom-title', 'customTitle': f'deploy {secret}'}, human(1, 'hi')])
            args = ('--root', ws.root, '--today', '2026-11-16')
            # The title has a secret no pattern knows: only gitleaks finds it. Once removed, the file equals what
            # git already has (stand-in: an empty status), so there is nothing to commit and the run succeeds.
            processes = Processes([f'?? {week}\0', ''], [finding, []])
            with mock.patch.object(log.subprocess, 'run', side_effect=processes):
                code, out, err = self.main('--commit', *args)
            self.assertEqual((code, err), (0, ''))
            self.assertIn('nothing new to commit', out)
            self.assertNotIn(secret, ws.read('workspace'))
            self.assertIn(f'### 10:01 · deploy {log.REMOVED}', ws.read('workspace'))
            self.assertFalse([c for c in processes.commands if c[3:4] in (['add'], ['commit'])])
            # A new sync re-reads the raw title from the transcript and must keep the redacted one.
            self.assertEqual(self.main(*args)[0], 0)
            self.assertNotIn(secret, ws.read('workspace'))
            # With something left after the redaction, the commit runs on the files still changed.
            ws.session('s-y', [human(5, 'one more')])
            processes = Processes([f'?? {week}\0', f' M {week}\0'], [[], []])
            with mock.patch.object(log.subprocess, 'run', side_effect=processes):
                code, out, _ = self.main('--commit', *args)
            self.assertEqual(code, 0)
            self.assertEqual(processes.commands[-1][3:5], ['commit', '-q'])
            self.assertEqual(processes.commands[-1][-1], week)
            # A second status that git cannot give stops before the commit.
            processes = Processes([f'?? {week}\0'], [finding, []])
            with mock.patch.object(log, 'changed_log_files', side_effect=[[week], None]):
                with mock.patch.object(log.subprocess, 'run', side_effect=processes):
                    code, _, err = self.main('--commit', *args)
            self.assertEqual(code, 1)
            self.assertIn('is not a readable git repository', err)

    def test_truncated_week_file_is_never_overwritten(self):
        with Workspace() as ws:
            ws.session('s-x', [human(1, 'hi')])
            folder = os.path.join(ws.log, 'workspace')
            os.makedirs(folder)
            cut = '# workspace\n\n<!-- prompt-log-data\n{"format": 1, "records": [{"session": "a", "tim'
            Path(folder, '2026-W46.md').write_text(cut, encoding='utf-8')
            code, out, err = self.main('--root', ws.root)
            self.assertEqual((code, out), (1, ''))
            self.assertIn('no readable prompt-log-data block', err)
            self.assertEqual(self.main('--context', '--root', ws.root)[:2], (0, ''))
            self.assertEqual(ws.read('workspace'), cut)

    def test_busy_lock_and_atomic_write(self):
        with Workspace() as ws:
            done = record(day=13, project='workspace')
            log.write_log(ws.log, {log.key_of(done): done}, datetime.date(2026, 11, 16))
            ws.session('s-new', [human(1, 'fresh-prompt', day=15)])
            os.makedirs(os.path.join(ws.root, '.history'), exist_ok=True)
            with open(os.path.join(ws.root, '.history', 'prompt-log.lock'), 'a', encoding='utf-8') as other:
                fcntl.flock(other, fcntl.LOCK_EX)
                code, out, err = self.main('--context', '--root', ws.root, '--today', '2026-11-16')
            self.assertEqual((code, err), (0, ''))
            self.assertIn('was 2026-11-13 (Friday)', out)
            self.assertNotIn('fresh-prompt', ws.read('workspace'))
            self.assertFalse(os.path.exists(os.path.join(ws.log, '.lock')))
            path = os.path.join(ws.log, 'workspace', '2026-W46.md')
            with mock.patch.object(log.os, 'replace', side_effect=OSError('disk full')):
                with self.assertRaises(OSError):
                    log.write_whole(path, 'new')
            self.assertEqual(sorted(os.listdir(os.path.dirname(path))), ['2026-W46.md'])
            self.assertIn('do this', ws.read('workspace'))

    def test_bad_command_line_in_hook_mode(self):
        code, out, _ = self.main('--context', '--nope')
        self.assertEqual((code, out), (0, ''))
        with self.assertRaises(SystemExit):
            self.main('--nope')


class ScriptTest(unittest.TestCase):
    def test_loads_measure_without_writing_bytecode(self):
        """The real measure.py loads (the error comes after it) and no __pycache__ appears next to it."""
        with tempfile.TemporaryDirectory() as folder:
            os.makedirs(os.path.join(folder, 'performance'))
            shutil.copy(MODULE_PATH, os.path.join(folder, 'prompt-log.py'))
            shutil.copy(REPO / 'scripts' / 'performance' / 'measure.py', os.path.join(folder, 'performance'))
            command = ['python3', '-I', os.path.join(folder, 'prompt-log.py'), 'sync', '--context', '--root', folder]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(os.listdir(os.path.join(folder, 'performance')), ['measure.py'])
        self.assertEqual((result.returncode, result.stdout), (0, ''))
        self.assertEqual(result.stderr, 'prompt-log: no custom layer (custom/)\n')

    def test_missing_measure_never_breaks_the_hook(self):
        with tempfile.TemporaryDirectory() as folder:
            copy = os.path.join(folder, 'prompt-log.py')
            Path(copy).write_text(MODULE_PATH.read_text(encoding='utf-8'), encoding='utf-8')
            hook = subprocess.run(['python3', '-I', copy, 'sync', '--context'], capture_output=True, text=True)
            plain = subprocess.run(['python3', '-I', copy, 'sync'], capture_output=True, text=True)
        self.assertEqual((hook.returncode, hook.stdout), (0, ''))
        self.assertIn('measure.py did not load', hook.stderr)
        self.assertNotIn('Traceback', hook.stderr)
        self.assertEqual(plain.returncode, 1)

    def test_runs_isolated_without_custom(self):
        with tempfile.TemporaryDirectory() as folder:
            result = subprocess.run(
                ['python3', '-I', str(MODULE_PATH), 'sync', '--context', '--root', folder],
                capture_output=True,
                text=True,
            )
        self.assertEqual((result.returncode, result.stdout), (0, ''))
        self.assertTrue(re.match(r'prompt-log: no custom layer', result.stderr))


if __name__ == '__main__':
    unittest.main()
