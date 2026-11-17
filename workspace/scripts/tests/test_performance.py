"""Unit tests of scripts/performance/measure.py (the performance report read from the session transcripts)."""

import contextlib
import http.server
import importlib.util
import io
import json
import os
import re
import socket
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parent.parent / 'performance' / 'measure.py'
SPEC = importlib.util.spec_from_file_location('measure', MODULE_PATH)
measure = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(measure)


def stamp(minute, day=10):
    """Returns an ISO timestamp on 2026-11-<day> at 10:<minute> UTC."""
    return f'2026-11-{day:02d}T10:{minute:02d}:00Z'


def human(minute, text='faz isso', day=10):
    return {'type': 'user', 'timestamp': stamp(minute, day), 'origin': {'kind': 'human'}, 'message': {'content': text}}


def assistant(minute, key, tools=(), tokens=1000, model='claude-opus-5-5', day=10):
    content = [{'type': 'tool_use', 'id': f'{key}-{i}', 'name': n, 'input': inp} for i, (n, inp) in enumerate(tools)]
    usage = {'input_tokens': tokens, 'cache_read_input_tokens': tokens, 'output_tokens': 10}
    return {
        'type': 'assistant',
        'timestamp': stamp(minute, day),
        'message': {'id': key, 'model': model, 'usage': usage, 'content': content},
    }


def result(minute, ids, day=10):
    content = [{'type': 'tool_result', 'tool_use_id': i, 'content': 'ok'} for i in ids]
    return {'type': 'user', 'timestamp': stamp(minute, day), 'message': {'content': content}}


def session_lines(day=10):
    """A session with a prompt, a rules read, a workspace script, a work edit, a question, hooks and a compaction."""
    tools = [
        ('Read', {'file_path': '/ws/rules/git.md'}),
        ('Bash', {'command': 'bash scripts/aiwp-cmds.sh open 2026-11-10-x billing'}),
    ]
    return [
        {
            'type': 'attachment',
            'timestamp': stamp(0, day),
            'attachment': {
                'type': 'hook_success',
                'hookEvent': 'SessionStart',
                'command': 'bash "$X/scripts/setup-claude.sh" --quiet',
                'durationMs': 50,
            },
        },
        human(1, day=day),
        assistant(2, 'm1', tools, tokens=20000, day=day),
        result(3, ['m1-0', 'm1-1'], day=day),
        assistant(4, 'm2', [('Edit', {'file_path': '/ws/tmp/work/x/billing/a.py'})], day=day),
        result(5, ['m2-0'], day=day),
        assistant(6, 'm3', [('AskUserQuestion', {})], day=day),
        result(9, ['m3-0'], day=day),
        assistant(10, 'm4', day=day),
        {
            'type': 'attachment',
            'timestamp': stamp(11, day),
            'attachment': {'type': 'hook_success', 'hookEvent': 'PreToolUse', 'command': 'true', 'durationMs': 10},
        },
        {
            'type': 'attachment',
            'timestamp': stamp(11, day),
            'attachment': {'type': 'nested_memory', 'path': '/ws/projects/a/CLAUDE.md'},
        },
        {'type': 'system', 'subtype': 'compact_boundary', 'timestamp': stamp(12, day)},
        {'type': 'cost-state', 'totalCostUSD': 1.5},
    ]


def write_session(folder, name, lines):
    with open(os.path.join(folder, name + '.jsonl'), 'w', encoding='utf-8') as handle:
        for line in lines:
            handle.write((line if isinstance(line, str) else json.dumps(line)) + '\n')


class Health(http.server.BaseHTTPRequestHandler):
    body = b'{"database": "ok"}'

    def do_GET(self):  # noqa: N802 - name required by BaseHTTPRequestHandler
        self.send_response(200)
        self.end_headers()
        self.wfile.write(self.body)

    def log_message(self, *args):
        pass


class Stack:
    """A fake observability stack: a Grafana health endpoint and an open OTLP port."""

    def __enter__(self):
        self.http = http.server.HTTPServer(('127.0.0.1', 0), Health)
        threading.Thread(target=self.http.serve_forever, daemon=True).start()
        self.otlp = socket.socket()
        self.otlp.bind(('127.0.0.1', 0))
        self.otlp.listen(4)
        self.args = [
            '--grafana-health',
            f'http://127.0.0.1:{self.http.server_port}/api/health',
            '--otlp-port',
            str(self.otlp.getsockname()[1]),
        ]
        return self

    def __exit__(self, *exc):
        self.http.shutdown()
        self.http.server_close()
        self.otlp.close()


def closed_port():
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


class ClassifyTests(unittest.TestCase):
    def test_bash(self):
        cases = {
            'bash scripts/aiwp-cmds.sh open w billing': 'workarea',
            'bash scripts/aiwp-cmds.sh gate w/billing --test "npm test"': 'gate',
            'bash scripts/aiwp-cmds.sh release billing': 'gate',
            'bash scripts/aiwp-gate.sh x': 'gate',
            'bash scripts/validate.sh --all': 'validation',
            'bash scripts/session-board.sh': 'process',
            'bash scripts/unknown-thing.sh': 'work-bash',
            'cd x && npm run test': 'validation',
            'python3 -I -m unittest discover -s tests': 'validation',
            'git -C x status': 'git',
            'ls -la': 'work-bash',
        }
        for command, expected in cases.items():
            self.assertEqual(measure.classify('Bash', {'command': command}), expected, command)

    def test_files_and_tools(self):
        self.assertEqual(measure.classify('Read', {'file_path': '/ws/AGENTS.md'}), 'rules-read')
        self.assertEqual(measure.classify('Grep', {'path': '/ws/.claude/skills'}), 'rules-read')
        self.assertEqual(measure.classify('Read', {'file_path': '/ws/projects/a/rules/x.md'}), 'work-read')
        self.assertEqual(measure.classify('Read', {}), 'work-read')
        self.assertEqual(measure.classify('Write', {'file_path': '/ws/custom/prompts/a.md'}), 'prompt-write')
        self.assertEqual(measure.classify('Edit', {'file_path': '/ws/rules/git.md'}), 'rules-write')
        self.assertEqual(measure.classify('NotebookEdit', {'notebook_path': '/ws/tmp/work/a/b.ipynb'}), 'work-write')
        self.assertEqual(measure.classify('Agent', {'subagent_type': 'Reviewer'}), 'validation')
        self.assertEqual(measure.classify('Agent', {'subagent_type': 'Explore'}), 'work-delegate')
        self.assertEqual(measure.classify('SendMessage', {}), 'process')
        self.assertEqual(measure.classify('AskUserQuestion', {}), 'ask-human')
        self.assertEqual(measure.classify('Skill', {}), 'skill')
        self.assertEqual(measure.classify('WebFetch', {}), 'other')

    def test_groups_and_time(self):
        self.assertEqual(measure.group_of('gate'), 'validation')
        self.assertEqual(measure.group_of('respond'), 'response')
        self.assertIsNone(measure.parse_time(None))
        self.assertIsNone(measure.parse_time('yesterday'))
        self.assertEqual(measure.parse_time('2026-11-10T10:00:00Z'), measure.parse_time('2026-11-10T10:00:00+00:00'))

    def test_is_human(self):
        self.assertTrue(measure.is_human(human(1)))
        self.assertFalse(measure.is_human(human(1, '<command-name>/model x')))
        self.assertFalse(measure.is_human({'origin': {'kind': 'peer'}, 'message': {'content': 'x'}}))
        self.assertFalse(measure.is_human({'origin': 'human'}))
        self.assertTrue(measure.is_human({'origin': {'kind': 'human'}, 'message': {'content': [{'type': 'text'}]}}))


class MeasureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.folder = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def test_one_session(self):
        lines = session_lines() + [
            'not json',
            '{"type":"api-request","x":1}',
            '[1, 2]',
            {'type': 'user', 'timestamp': None},
            assistant(13, 'side', tokens=5, model='<synthetic>'),
            {'type': 'assistant', 'timestamp': stamp(14), 'isSidechain': True, 'message': {'id': 'z'}},
            result(15, ['unknown-id']),
        ]
        write_session(self.folder, 'a', lines)
        write_session(self.folder, 'empty', [human(1)])
        data = measure.measure(sorted(Path(self.folder).glob('*.jsonl')), float('-inf'), measure.parse_time(stamp(59)))
        counts = data['counts']
        self.assertEqual(counts['sessions'], 1)
        self.assertEqual(counts['prompts'], 1)
        self.assertEqual(counts['api_calls'], 5)
        self.assertEqual(counts['compactions'], 1)
        self.assertEqual(counts['nested_project_rules'], 1)
        self.assertEqual(data['categories'], {'rules-read': 1, 'workarea': 1, 'work-write': 1, 'ask-human': 1})
        self.assertEqual(data['groups']['process']['calls'], 2)
        self.assertEqual(data['groups']['questions']['time'], 0)
        self.assertEqual(data['first_edit_seconds_median'], 240)
        self.assertEqual(data['first_edit_calls_median'], 2)
        self.assertEqual(data['first_context_median'], 40000)
        self.assertEqual(data['cost_usd'], 1.5)
        self.assertEqual(data['hooks'], {'PreToolUse inline': [1, 10], 'SessionStart setup-claude.sh': [1, 50]})
        self.assertEqual(list(data['models']), ['claude-opus-5-5'])

    def test_period_cuts_and_old_sessions(self):
        write_session(self.folder, 'a', session_lines(day=9) + [human(30, day=11), assistant(31, 'late', day=11)])
        since = measure.parse_time(stamp(0, 11))
        data = measure.measure(sorted(Path(self.folder).glob('*.jsonl')), since, measure.parse_time(stamp(59, 11)))
        self.assertEqual(data['counts']['api_calls'], 1)
        self.assertEqual(data['counts']['prompts'], 1)
        # A session opened before the period gives no first context and no cost.
        self.assertIsNone(data['first_context_median'])
        self.assertEqual(data['cost_usd'], 0)
        self.assertNotIn('cost_sessions', data['counts'])
        self.assertIsNone(data['first_edit_seconds_median'])


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self.tmp.name, 'ws')
        self.transcripts = os.path.join(self.tmp.name, 'transcripts')
        self.out = os.path.join(self.root, 'custom', 'performance')
        os.makedirs(self.transcripts)
        os.makedirs(os.path.join(self.root, 'custom'))
        with open(os.path.join(self.root, 'VERSION'), 'w', encoding='utf-8') as handle:
            handle.write('0.6.0\n')
        write_session(self.transcripts, 'a', session_lines(day=10))
        write_session(self.transcripts, 'b', session_lines(day=12))

    def tearDown(self):
        self.tmp.cleanup()

    def run_measure(self, stack, *extra):
        argv = ['--root', self.root, '--transcripts', self.transcripts, *stack.args, *extra]
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = measure.main(argv)
        return code, out.getvalue(), err.getvalue()

    def read(self, name):
        return Path(self.out, name).read_text(encoding='utf-8')

    def test_first_then_compared(self):
        with Stack() as stack:
            code, out, _ = self.run_measure(stack, '--name', 'first', '--now', '2026-11-11T00:00:00Z')
            self.assertEqual(code, 0)
            self.assertTrue(out.strip().endswith('2026-11-11-first.md') or '2026-11-10-first.md' in out)
            first = Path(out.strip()).read_text(encoding='utf-8')
            self.assertIn('First measurement', first)
            self.assertIn('version 0.6.0', first)
            self.assertIn('start of the records', first)
            code, out, _ = self.run_measure(stack, '--name', 'second', '--now', '2026-11-13T00:00:00Z')
            self.assertEqual(code, 0)
            second = Path(out.strip()).read_text(encoding='utf-8')
        self.assertIn('## Comparison with the previous measurement', second)
        self.assertIn('## Last 2 measurements', second)
        self.assertIn('| Sessions | 1 | 1 | same |', second)
        data = json.loads(measure.DATA_BLOCK.search(second).group(1))
        # The second measurement starts where the first ended: only the session of day 12 counts.
        self.assertEqual(data['period']['start'], measure.parse_time('2026-11-11T00:00:00Z'))
        self.assertEqual(data['counts']['sessions'], 1)

    def test_last_five_and_all(self):
        os.makedirs(self.out)
        for index in range(6):
            data = {
                'format': 1,
                'name': f'm{index}',
                'date': f'2026-11-0{index + 1}',
                'period': {'end': index},
                'counts': {'sessions': index, 'prompts': 0},
                # A stored report may give the groups their other keys (measure.GROUP_KEYS).
                'groups': {'processo': {'calls': 2}} if index == 5 else {},
                'hooks': {},
            }
            Path(self.out, f'2026-11-0{index + 1}-m{index}.md').write_text(
                f'x\n<!-- performance-data\n{json.dumps(data)}\n-->\n', encoding='utf-8'
            )
        Path(self.out, 'notes.md').write_text('no data', encoding='utf-8')
        Path(self.out, 'broken.md').write_text('<!-- performance-data\n{x\n-->', encoding='utf-8')
        Path(self.out, 'other.md').write_text('<!-- performance-data\n{"format": 9}\n-->', encoding='utf-8')
        with Stack() as stack:
            code, out, _ = self.run_measure(stack, '--all', '--now', '2026-11-20T00:00:00Z')
        self.assertEqual(code, 0)
        report = Path(out.strip()).read_text(encoding='utf-8')
        self.assertIn('## Last 5 measurements', report)
        header = next(line for line in report.splitlines() if line.startswith('| Indicator | 2026'))
        self.assertEqual(re.findall(r'm\d', header), ['m2', 'm3', 'm4', 'm5'])
        self.assertIn('(2026-11-06-m5)', report)
        self.assertIn('| Sessions | 5 | 2 |', report)
        self.assertIn('| Workspace process tool calls (%) | — | — | — | 100.0 |', report)
        self.assertIn('start of the records', report)

    def test_refusals(self):
        with Stack() as stack:
            self.assertEqual(self.run_measure(stack, '--since', 'yesterday')[0], 2)
            code, out, _ = self.run_measure(stack, '--since', '2026-11-12', '--now', '2026-11-14T00:00:00Z')
            self.assertEqual(code, 0)
            code, _, err = self.run_measure(stack, '--since', '2026-11-12', '--now', '2026-11-14T00:00:00Z')
            self.assertEqual(code, 1)
            self.assertIn('already exists', err)
            code, _, err = self.run_measure(stack, '--transcripts', os.path.join(self.tmp.name, 'none'))
            self.assertEqual(code, 2)
            self.assertIn('no transcripts', err)
            no_custom = os.path.join(self.tmp.name, 'bare')
            os.makedirs(no_custom)
            argv = ['--root', no_custom, '--transcripts', self.transcripts, *stack.args]
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                self.assertEqual(measure.main(argv), 2)
            self.assertIn('no custom layer', err.getvalue())

    def test_projects_in_the_report(self):
        os.makedirs(os.path.join(self.root, 'projects', 'billing', '.git'))
        agent = 'x\n\n[#automatic-agent-commit]'
        log = git_log((int(measure.parse_time(stamp(4, 12))), 'feat: a', agent, ['30\t0\tsrc/a.py', '6\t0\tREADME.md']))
        write_session(
            self.transcripts,
            'p',
            [
                human(1, day=12),
                assistant(2, 'pa', [('Edit', {'file_path': '/ws/projects/billing/src/a.py'})], day=12),
                {
                    'type': 'system',
                    'subtype': 'turn_duration',
                    'timestamp': stamp(40, day=12),
                    'durationMs': 3600 * 1000,
                },
            ],
        )
        real_run = measure.subprocess.run

        def fake_run(command, **kwargs):
            if 'log' in command:
                return mock.Mock(stdout=log)
            return real_run(command, **kwargs)

        with Stack() as stack, mock.patch.object(measure.subprocess, 'run', side_effect=fake_run):
            code, out, _ = self.run_measure(stack, '--since', '2026-11-12', '--now', '2026-11-13T00:00:00Z')
        self.assertEqual(code, 0)
        report = Path(out.strip()).read_text(encoding='utf-8')
        self.assertIn('| `billing` | 1.0 | 1 | 30 | 6 | 30 | 6 | 36 | — |', report)

    def test_report_without_git(self):
        os.makedirs(os.path.join(self.root, 'projects', 'billing', '.git'))
        real_run = measure.subprocess.run

        def fake_run(command, **kwargs):
            if 'log' in command:
                raise FileNotFoundError('git')
            return real_run(command, **kwargs)

        with Stack() as stack, mock.patch.object(measure.subprocess, 'run', side_effect=fake_run):
            code, out, _ = self.run_measure(stack, '--all', '--now', '2026-11-13T00:00:00Z')
        self.assertEqual(code, 0)
        self.assertIn('No `git` on this machine', Path(out.strip()).read_text(encoding='utf-8'))

    def test_needs_the_stack(self):
        err = io.StringIO()
        argv = [
            '--root',
            self.root,
            '--transcripts',
            self.transcripts,
            '--grafana-health',
            f'http://127.0.0.1:{closed_port()}/api/health',
        ]
        with contextlib.redirect_stderr(err):
            self.assertEqual(measure.main(argv), 2)
        self.assertIn('observability stack', err.getvalue())
        self.assertIn('compose.yaml up -d', err.getvalue())
        self.assertFalse(os.path.exists(self.out))

    def test_stack_problems(self):
        with Stack() as stack:
            url = stack.args[1]
            self.assertIsNone(measure.observability_problem(url, ('127.0.0.1', int(stack.args[3]))))
            self.assertIn('OTLP port', measure.observability_problem(url, ('127.0.0.1', closed_port())))
            with mock.patch.object(Health, 'body', b'{"database": "failing"}'):
                self.assertIn('database is not ready', measure.observability_problem(url, ('127.0.0.1', 1)))
            with mock.patch.object(Health, 'body', b'not json'):
                self.assertIn('did not answer', measure.observability_problem(url, ('127.0.0.1', 1)))

    def test_arguments(self):
        err = io.StringIO()
        for argv in (['--name', 'With Space'], ['--compare', '1'], ['--since', 'x', '--all']):
            with contextlib.redirect_stderr(err), self.assertRaises(SystemExit):
                measure.parse_args(argv)

    def test_helpers(self):
        self.assertEqual(measure.show(None, 1), '—')
        self.assertEqual(measure.show(12345.678, 1), '12 345.7')
        self.assertEqual(measure.change(None, 1), '—')
        self.assertEqual(measure.change(0, 0), 'same')
        self.assertEqual(measure.change(0, 3), 'new')
        self.assertEqual(measure.change(2, 3), '+50.0%')
        self.assertEqual(measure.change(2, 2), 'same')
        self.assertIsNone(measure.ratio(1, 0))
        bare = os.path.join(self.tmp.name, 'bare-version')
        os.makedirs(bare)
        self.assertEqual(measure.workspace_version(bare)[0], '?')
        with mock.patch.object(measure.subprocess, 'run', side_effect=FileNotFoundError('git')):
            self.assertEqual(measure.workspace_version(bare), ('?', '?'))
        with mock.patch.dict(os.environ, {'CLAUDE_CONFIG_DIR': '/cfg'}):
            self.assertEqual(
                measure.transcripts_folder('/a/b.c'),
                '/cfg/projects/' + re.sub(r'[^A-Za-z0-9]', '-', os.path.realpath('/a/b.c')),
            )


def git_log(*commits):
    """Builds a `git log --format=%x1e%at%n%s%n%b%x1f --numstat` output from (time, subject, body, numstat rows)."""
    out = ''
    for stamp, subject, body, rows in commits:
        out += f'\x1e{stamp}\n{subject}\n{body}\x1f\n' + ''.join(f'{r}\n' for r in rows) + '\n'
    return out


class ProjectTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.projects = os.path.join(self.tmp.name, 'projects')
        for repo in ('billing', 'shop/api', 'shop/web'):
            os.makedirs(os.path.join(self.projects, repo, '.git'))
        os.makedirs(os.path.join(self.projects, 'billing', 'node_modules', 'dep', '.git'))
        os.makedirs(os.path.join(self.projects, 'notes'))

    def tearDown(self):
        self.tmp.cleanup()

    def test_projects_named(self):
        command = {'command': 'cd /ws/projects/billing && git -C tmp/work/2026-x/api status; ls tmp/worktrees/old'}
        self.assertEqual(measure.projects_named(command), ['billing', 'api', 'old'])
        self.assertEqual(measure.projects_named({'file_path': '/ws/rules/git.md'}), [])

    def test_union_seconds(self):
        self.assertEqual(measure.union_seconds([]), 0)
        self.assertEqual(measure.union_seconds([(0, 10), (5, 20), (30, 40), (32, 35)]), 30)

    def test_session_hours_by_project(self):
        lines = [
            human(0),
            assistant(1, 'a', [('Edit', {'file_path': '/ws/projects/billing/a.py'})]),
            {'type': 'system', 'subtype': 'turn_duration', 'timestamp': stamp(10), 'durationMs': 600_000},
            human(20),
            assistant(21, 'b', [('Bash', {'command': 'ls'})]),
            {'type': 'system', 'subtype': 'turn_duration', 'timestamp': stamp(30), 'durationMs': 60_000},
            human(40),
            assistant(41, 'c', [('Read', {'file_path': '/ws/tmp/work/w/api/x.go'})]),
            {'type': 'system', 'subtype': 'turn_duration', 'timestamp': stamp(50), 'durationMs': 10 * 3600 * 1000},
        ]
        folder = os.path.join(self.tmp.name, 't')
        os.makedirs(folder)
        write_session(folder, 's', [{'type': 'system', 'subtype': 'turn_duration', 'timestamp': stamp(0)}] + lines)
        data = measure.measure([os.path.join(folder, 's.jsonl')], float('-inf'), measure.parse_time(stamp(59)))
        # The turn with no project is left out; the 10 h turn counts as 4 h.
        self.assertEqual(data['project_hours'], {'api': 4.0, 'billing': round(600 / 3600, 2)})

    def test_repos_and_aliases(self):
        repos = measure.project_repos(self.projects)
        names = {os.path.relpath(r, self.projects): top for r, top in repos.items()}
        self.assertEqual(names, {'billing': 'billing', 'shop/api': 'shop', 'shop/web': 'shop'})
        aliases = {'api': 'shop', 'web': 'shop', 'billing': 'billing', 'shop': 'shop'}
        table = measure.project_table(
            {'api': 1.0, 'web': 0.5, 'old': 3}, {'billing': {'commits': 2, 'code': 9}}, aliases
        )
        self.assertEqual(table['shop'], {'hours': 1.5, 'commits': 0, 'code': 0, 'docs': 0})
        self.assertEqual(table['billing'], {'hours': 0, 'commits': 2, 'code': 9, 'docs': 0})
        self.assertNotIn('old', table)
        self.assertEqual(
            measure.project_table({'api': 1.0}, None, aliases),
            {'shop': {'hours': 1.0, 'commits': 0, 'code': 0, 'docs': 0}},
        )

    def test_parse_git_log(self):
        text = git_log(
            (100, 'feat: a', 'body\n\n[#automatic-agent-commit]', ['10\t2\tsrc/a.py', '-\t-\timg.png', 'bad row']),
            (200, 'fix: human', 'no marker', ['5\t0\tb.py']),
            (300, 'chore: x [#automatic-agent-commit]', '', []),
        )
        self.assertEqual(
            measure.parse_git_log(text),
            [(100, 'feat: a', [(10, 'src/a.py')]), (300, 'chore: x [#automatic-agent-commit]', [])],
        )

    def test_project_lines(self):
        agent = 'x\n\n[#automatic-agent-commit]'
        outputs = {
            'billing': git_log(
                (150, 'feat: code', agent, ['10\t1\tsrc/a.py', '4\t0\tdocs/guide.md', '900\t0\tpackage-lock.json']),
                (150, 'feat: code', agent, ['10\t1\tsrc/a.py']),
                (50, 'feat: old', agent, ['7\t0\tsrc/b.py']),
            ),
            'api': git_log((160, 'feat: api', agent, ['3\t0\tmain.go', '2\t0\tREADME.md', '50\t0\tdist/app.js'])),
            'web': '',
        }

        def fake_run(command, **_):
            return mock.Mock(stdout=outputs[os.path.basename(command[2])])

        with mock.patch.object(measure.subprocess, 'run', side_effect=fake_run):
            found = measure.project_lines(self.projects, 100, 200)
        self.assertEqual(
            found, {'billing': {'commits': 1, 'code': 10, 'docs': 4}, 'shop': {'commits': 1, 'code': 3, 'docs': 2}}
        )
        with mock.patch.object(measure.subprocess, 'run', side_effect=FileNotFoundError('git')):
            self.assertIsNone(measure.project_lines(self.projects, 0, 1))

    def test_projects_section(self):
        self.assertIn('No `git`', measure.projects_section({'projects': None}, [])[2])
        self.assertEqual(measure.projects_section({'projects': {}}, []), [])
        data = {
            'projects': {
                'billing': {'hours': 2.0, 'commits': 3, 'code': 300, 'docs': 100},
                'shop': {'hours': 0.1, 'commits': 1, 'code': 50, 'docs': 0},
            }
        }
        previous = [{'projects': {'billing': {'hours': 1.0, 'commits': 1, 'code': 100, 'docs': 0}}}]
        text = '\n'.join(measure.projects_section(data, previous))
        self.assertIn('| `billing` | 2.0 | 3 | 300 | 100 | 150 | 50 | 200 | 100 |', text)
        self.assertIn('| `shop` | 0.1 | 1 | 50 | 0 | — | — | — | — |', text)
        self.assertIn('| **Total** | 2.1 | 4 | 350 | 100 | 167 | 48 | 214 | |', text)
        rate = dict((label, value) for label, value, _ in measure.indicators(data))
        self.assertAlmostEqual(rate['Lines delivered per agent hour in the projects (code and docs)'], 450 / 2.1)
        self.assertIsNone(
            dict((label, value) for label, value, _ in measure.indicators({}))[
                'Lines delivered per agent hour in the projects (code and docs)'
            ]
        )


if __name__ == '__main__':
    unittest.main()
