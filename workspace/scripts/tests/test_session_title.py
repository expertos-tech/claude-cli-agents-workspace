"""Unit tests of scripts/session-title.py (the UserPromptSubmit hook that names a session <project>-<n>)."""

import contextlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

MODULE_PATH = Path(__file__).resolve().parent.parent / 'session-title.py'
SPEC = importlib.util.spec_from_file_location('session_title', MODULE_PATH)
title = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(title)


class SessionTitleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        os.makedirs(os.path.join(self.root, 'custom', 'requests'))
        os.makedirs(os.path.join(self.root, 'tmp'))
        self.config = os.path.join(self.root, 'claude-config')
        os.makedirs(os.path.join(self.config, 'sessions'))
        self.env = mock.patch.dict(os.environ, {'CLAUDE_CONFIG_DIR': self.config})
        self.env.start()
        finished = subprocess.Popen(['true'])
        finished.wait()
        self.dead_pid = finished.pid

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()

    def session(self, session_id, name, pid=None, cwd=None):
        """Registers a running session in the fake Claude Code registry."""
        info = {'pid': pid or os.getpid(), 'sessionId': session_id, 'cwd': cwd or self.root, 'name': name}
        with open(os.path.join(self.config, 'sessions', f'{session_id}.json'), 'w', encoding='utf-8') as handle:
            json.dump(info, handle)

    def write(self, relative, text):
        path = os.path.join(self.root, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8') as handle:
            handle.write(text)

    def name(self, prompt, session_title=None, session_id='me'):
        data = {'prompt': prompt, 'session_id': session_id}
        if session_title is not None:
            data['session_title'] = session_title
        output = title.title_for(data, self.root)
        return output['hookSpecificOutput']['sessionTitle'] if output else None

    def test_the_number_follows_the_running_sessions_of_the_project(self):
        self.write('custom/requests/a.md', '# A\n\n**Project:** billing-api\n\ntext\n')
        self.write('custom/requests/b.md', '# B\n\n**Project:** `shop-web`\n')
        self.assertEqual(self.name('/request a.md', session_id='s1'), 'billing-api-1')
        self.session('s1', 'billing-api-1')
        self.session('s2', 'billing-api-2')
        self.session('s3', 'shop-web-7')
        self.session('dead', 'billing-api-9', pid=self.dead_pid)
        self.session('elsewhere', 'billing-api-8', cwd='/other/folder')
        self.session('s4', 'review-workspace-29')
        for session_id in ('s5', 's6', 's7'):
            self.session(session_id, 'not-named-yet')
        self.assertEqual(self.name('/request a.md', session_id='s5'), 'billing-api-3')
        self.assertEqual(self.name('/request b.md', session_id='s6'), 'shop-web-8')
        self.assertEqual(self.name('  /request a.md  ', session_id='s7'), 'billing-api-4')

    def test_a_claim_counts_until_its_session_ends(self):
        self.write('custom/requests/a.md', '**Project:** app\n')
        self.session('s1', 'derived-name')
        self.assertEqual(self.name('/request a.md', session_id='s1'), 'app-1')
        self.session('s2', 'other')
        self.assertEqual(self.name('/request a.md', session_id='s2'), 'app-2')
        os.remove(os.path.join(self.config, 'sessions', 's1.json'))
        os.remove(os.path.join(self.config, 'sessions', 's2.json'))
        self.session('s3', 'x')
        self.assertEqual(self.name('/request a.md', session_id='s3'), 'app-1')

    def test_without_the_registry_recent_claims_count(self):
        self.write('custom/requests/a.md', '**Project:** app\n')
        os.rmdir(os.path.join(self.config, 'sessions'))
        self.assertEqual(self.name('/request a.md', session_id='s1'), 'app-1')
        self.assertEqual(self.name('/request a.md', session_id='s2'), 'app-2')
        claims = os.path.join(self.root, '.history', 'session-numbers', 'app.json')
        with open(claims, encoding='utf-8') as handle:
            data = json.load(handle)
        data['s1'][1] -= title.CLAIM_TTL_SECONDS + 1
        data['s2'][1] -= title.CLAIM_TTL_SECONDS + 1
        with open(claims, 'w', encoding='utf-8') as handle:
            json.dump(data, handle)
        self.assertEqual(self.name('/request a.md', session_id='s3'), 'app-1')

    def test_a_damaged_registry_entry_or_claims_file_is_skipped(self):
        self.write('custom/requests/a.md', '**Project:** app\n')
        with open(os.path.join(self.config, 'sessions', 'bad.json'), 'w', encoding='utf-8') as handle:
            handle.write('{not json')
        with open(os.path.join(self.config, 'sessions', 'list.json'), 'w', encoding='utf-8') as handle:
            handle.write('[1, 2]')
        with open(os.path.join(self.config, 'sessions', 'notes.txt'), 'w', encoding='utf-8') as handle:
            handle.write('x')
        self.write('.history/session-numbers/app.json', 'garbage')
        self.assertEqual(self.name('/request a.md', session_id='s1'), 'app-1')
        self.write('.history/session-numbers/app.json', '[1]')
        self.assertEqual(self.name('/request a.md', session_id='s2'), 'app-1')

    def test_output_shape(self):
        self.write('custom/requests/a.md', '**Project:** app\n')
        output = title.title_for({'prompt': '/request a.md'}, self.root)['hookSpecificOutput']
        self.assertEqual(output['hookEventName'], 'UserPromptSubmit')
        self.assertIn('app-1', output['additionalContext'])

    def test_a_session_already_named_for_the_project_keeps_its_name(self):
        self.write('custom/requests/a.md', '**Project:** app\n')
        self.assertIsNone(self.name('/request a.md', 'app-4'))
        self.assertEqual(self.name('/request a.md', 'other-2'), 'app-1')
        self.assertEqual(self.name('/request a.md', 'app-x', session_id='me'), 'app-1')

    def test_where_the_file_is_read_from(self):
        self.write('tmp/request.md', '**Project:** scratch\n')
        self.write('docs/req.md', '**Project:** by-path\n')
        self.assertEqual(self.name('/request'), 'scratch-1')
        self.assertEqual(self.name('/request docs/req.md', session_id='other'), 'by-path-1')
        self.assertIsNone(self.name('/request missing.md'))
        self.assertIsNone(self.name('/request ../outside.md'))

    def test_a_request_without_the_project_line_uses_the_first_project_path(self):
        self.write('custom/requests/no-line.md', 'Resume `projects/acme/billing-web` and then projects/other.\n')
        self.write('custom/requests/none.md', 'No project here, only tools/x and xprojects/y.\n')
        self.assertEqual(self.name('/request no-line.md'), 'billing-web-1')
        self.assertIsNone(self.name('/request none.md'))

    def test_a_request_without_the_project_line_names_the_nearest_repo_of_its_path(self):
        for repo in ('platform', 'platform/services/billing-api'):
            os.makedirs(os.path.join(self.root, 'projects', repo, '.git'))
        self.write('custom/requests/nested.md', 'Fix projects/platform/services/billing-api/src/app first.\n')
        self.write('custom/requests/parent.md', 'Fix projects/platform/src/app first.\n')
        self.write('custom/requests/repo.md', 'Fix projects/platform/services/billing-api.\n')
        self.assertEqual(self.name('/request nested.md', session_id='s1'), 'billing-api-1')
        self.assertEqual(self.name('/request parent.md', session_id='s2'), 'platform-1')
        self.assertEqual(self.name('/request repo.md', session_id='s3'), 'billing-api-1')

    def test_the_request_file_is_tmp_request_md_or_custom_requests(self):
        self.write('tmp/prompt.md', '**Project:** old-default\n')
        self.write('custom/prompts/a.md', '**Project:** old-folder\n')
        self.assertIsNone(self.name('/request'))
        self.assertIsNone(self.name('/request a.md'))
        self.write('tmp/request.md', '**Project:** new-default\n')
        self.write('custom/requests/qa/billing-api/a.md', '**Project:** in-qa\n')
        self.assertEqual(self.name('/request'), 'new-default-1')
        self.assertEqual(self.name('/request custom/requests/qa/billing-api/a.md', session_id='s2'), 'in-qa-1')

    def test_a_bad_project_line_names_nothing(self):
        self.write('custom/requests/bad.md', '**Project:** Not_Kebab\n')
        self.write('custom/requests/path.md', '**Project:** projects/acme/billing/\n')
        self.assertIsNone(self.name('/request bad.md'))
        self.assertEqual(self.name('/request path.md'), 'billing-1')

    def test_other_prompts_are_left_alone(self):
        self.write('custom/requests/a.md', '**Project:** app\n')
        for prompt in (
            '',
            'fix the readme',
            '/requestx a.md',
            '/request a.md and more',
            '/draft-request ideas',
            '/prompt a.md',
            '/prompt',
        ):
            self.assertIsNone(self.name(prompt), prompt)
        self.assertIsNone(title.title_for({}, self.root))

    def test_sessions_starting_together_get_different_numbers(self):
        self.write('custom/requests/a.md', '**Project:** app\n')
        ids = [f's{n}' for n in range(8)]
        for session_id in ids:
            self.session(session_id, 'unnamed')
        names = []
        threads = [
            threading.Thread(target=lambda i=i: names.append(self.name('/request a.md', session_id=i))) for i in ids
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        self.assertEqual(sorted(names, key=lambda n: int(n.split('-')[-1])), [f'app-{n}' for n in range(1, 9)])

    def run_main(self, stdin, argv):
        out = io.StringIO()
        with (
            mock.patch('sys.stdin', io.StringIO(stdin)),
            mock.patch('sys.argv', argv),
            contextlib.redirect_stdout(out),
        ):
            title.main()
        return out.getvalue()

    def test_main_prints_the_output_and_never_fails(self):
        self.write('custom/requests/a.md', '**Project:** app\n')
        printed = self.run_main(json.dumps({'prompt': '/request a.md'}), ['x', self.root])
        self.assertEqual(json.loads(printed)['hookSpecificOutput']['sessionTitle'], 'app-1')
        self.assertEqual(self.run_main(json.dumps({'prompt': 'hello'}), ['x', self.root]), '')
        self.assertEqual(self.run_main('not json', ['x', self.root]), '')
        self.assertEqual(self.run_main('', ['x']), '')


SCRIPTS = Path(__file__).resolve().parent.parent
MARK = '<!-- AI-WORKSPACE-PROJECT {} -->'
GIT_ENV = {
    'GIT_CONFIG_GLOBAL': '/dev/null',
    'GIT_CONFIG_NOSYSTEM': '1',
    'GIT_AUTHOR_NAME': 't',
    'GIT_AUTHOR_EMAIL': 't@example.com',
    'GIT_COMMITTER_NAME': 't',
    'GIT_COMMITTER_EMAIL': 't@example.com',
}


def porcelain(kind, path, state, marker='-', version='0.2.0', pending='-', hotfix=None):
    """One line of scripts/aiwp-project-state.sh --porcelain; hotfix None leaves out the eleventh field (an older
    script)."""
    developer, checkout = ('yes', 'developer') if kind == 'project' else ('-', '-')
    source = 'developer' if kind == 'project' else 'file'
    name = path.rsplit('/', 1)[-1]
    fields = [kind, name, path, state, marker, version, pending, source, developer, checkout]
    return '\t'.join(fields + ([] if hotfix is None else [hotfix]))


class ProjectWarningTests(unittest.TestCase):
    """The warning about the projects a prompt names, with the state script replaced by its porcelain output."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        for folder in ('scripts', 'projects', 'custom/pocs', 'custom/requests'):
            os.makedirs(os.path.join(self.root, folder))
        self.write('scripts/aiwp-project-state.sh', '# replaced by the stub of subprocess.run\n')
        self.rows = {}
        self.calls = []
        self.run = mock.patch.object(title.subprocess, 'run', side_effect=self.fake_run)
        self.run.start()

    def tearDown(self):
        self.run.stop()
        self.tmp.cleanup()

    def fake_run(self, argv, **kwargs):
        """Answers like the state script: one porcelain line per known target."""
        self.calls.append((argv, kwargs))
        targets = argv[argv.index('--') + 1 :]
        out = ''.join(self.rows[t] + '\n' for t in targets if t in self.rows)
        return subprocess.CompletedProcess(argv, 0, out, '')

    def write(self, relative, text):
        path = os.path.join(self.root, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8') as handle:
            handle.write(text)

    def repo(self, relative, state, **fields):
        """A folder of projects/ that holds a .git, and the state the script reports for it."""
        os.makedirs(os.path.join(self.root, 'projects', relative, '.git'))
        self.rows[f'projects/{relative}'] = porcelain('project', f'projects/{relative}', state, **fields)

    def warning(self, prompt):
        return title.project_warning({'prompt': prompt}, self.root)

    def test_a_project_without_marker_named_by_folder_name_gets_the_warning(self):
        self.repo('billing-api', 'none')
        text = self.warning('fix the login of billing-api please')
        self.assertIn('`billing-api` (projects/billing-api) has no AI-WORKSPACE-PROJECT marker', text)
        self.assertIn('If the request is about this project', text)
        self.assertIn('ask for authorization to run `/normalize-projects billing-api`', text)
        self.assertIn('No: go on with the request as asked', text)
        argv, kwargs = self.calls[-1]
        self.assertEqual(argv[:3], ['bash', os.path.join(self.root, 'scripts', 'aiwp-project-state.sh'), '--porcelain'])
        self.assertEqual(kwargs['timeout'], title.STATE_TIMEOUT_SECONDS)
        self.assertIsNone(self.warning('fix the login of billing-apis'))
        self.assertIsNone(self.warning('fix the login of Billing-API'))
        self.assertIsNone(self.warning('nothing named here'))

    def test_a_short_plain_name_is_named_only_by_a_path_or_the_project_line(self):
        self.repo('acme/api', 'none')
        self.repo('ledger2', 'none')
        self.assertIsNone(self.warning('the api returns 500'))
        self.assertIn('`/normalize-projects acme/api`', self.warning('see projects/acme/api/src'))
        self.assertIn('`/normalize-projects acme/api`', self.warning('**Project:** api'))
        self.assertIn('`/normalize-projects ledger2`', self.warning('fix ledger2'))

    def test_an_out_of_date_project_named_by_path_or_clone(self):
        self.repo('acme/shop-web', 'outdated', marker='0.1.0', pending='0.2.0,0.3.0')
        self.repo('acme/current', 'current', marker='0.2.0')
        text = self.warning('look at projects/acme/shop-web/src/app and tmp/work/2026-11-16-x/current')
        self.assertIn('`shop-web` (projects/acme/shop-web) is on workspace version 0.1.0', text)
        self.assertIn('the workspace is on 0.2.0, with the migrations 0.2.0, 0.3.0 pending', text)
        self.assertIn('`/normalize-projects acme/shop-web`', text)
        self.assertNotIn('acme/current', text)
        self.assertEqual(self.calls[-1][0][4:], ['projects/acme/shop-web', 'projects/acme/current'])
        self.assertIsNone(self.warning('the current state of things'))

    def test_a_nested_clone_name_maps_to_its_repo(self):
        """A clone of a nested repo is named after its path with '--' (billing--billing-api), never its first part."""
        self.repo('billing', 'current', marker='0.2.0')
        self.repo('billing/billing-api', 'outdated', marker='0.1.0', pending='0.2.0')
        text = self.warning('see tmp/work/2026-11-17-x/billing--billing-api/src')
        self.assertIn('(projects/billing/billing-api)', text)
        self.assertEqual(self.calls[-1][0][4:], ['projects/billing/billing-api'])

    def test_poc_project_line_and_the_request_file_of_request(self):
        os.makedirs(os.path.join(self.root, 'custom/pocs/cache-test'))
        self.rows['custom/pocs/cache-test'] = porcelain('poc', 'custom/pocs/cache-test', 'none')
        self.repo('ledger-app', 'none')
        self.assertIn('/normalize-projects custom/pocs/cache-test', self.warning('see custom/pocs/cache-test'))
        self.write('custom/requests/a.md', '# A\n\n**Project:** ledger-app\n')
        self.assertIn('`/normalize-projects ledger-app`', self.warning('/request a.md'))
        self.assertIn('`/normalize-projects ledger-app`', self.warning('**Project:** `ledger-app`'))

    def test_normalize_command_own_repository_and_up_to_date_stay_silent(self):
        self.repo('billing-api', 'none')
        self.repo('claude-cli-agents-workspace', 'workspace')
        self.repo('done', 'current', marker='0.2.0')
        self.repo('ahead', 'newer', marker='0.9.0')
        self.assertIsNone(self.warning('/normalize-projects billing-api'))
        self.assertIsNone(self.warning('change claude-cli-agents-workspace, done and ahead'))

    def test_a_hotfix_not_merged_into_developer_gets_the_warning(self):
        self.repo('billing-api', 'current', marker='0.2.0', hotfix='yes')
        self.repo('ledger-app', 'current', marker='0.2.0', hotfix='no')
        self.repo('shop-web', 'none', hotfix='yes')
        text = self.warning('fix the login of billing-api')
        self.assertIn('Hotfix pending', text)
        self.assertIn(
            '`billing-api` (projects/billing-api) has a hotfix on main that is not merged into developer', text
        )
        self.assertIn('`bash scripts/aiwp-cmds.sh hotfix-down billing-api`', text)
        self.assertIn('fix/<slug>-developer', text)
        self.assertNotIn('normalize', text)
        self.assertIsNone(self.warning('see ledger-app'))
        text = self.warning('see shop-web')
        self.assertIn('/normalize-projects shop-web', text)
        self.assertIn('hotfix-down shop-web', text)
        self.assertLess(text.index('normalize-projects'), text.index('Hotfix pending'))
        self.rows['custom/pocs/cache-test'] = porcelain('poc', 'custom/pocs/cache-test', 'current', hotfix='yes')
        os.makedirs(os.path.join(self.root, 'custom/pocs/cache-test'))
        self.assertIsNone(self.warning('see custom/pocs/cache-test'))

    def test_rows_with_more_fields_are_read(self):
        self.repo('billing-api', 'none', hotfix='no')
        self.rows['projects/billing-api'] += '\tlater-field'
        self.assertIn('/normalize-projects billing-api', self.warning('billing-api'))

    def test_the_hook_output_joins_the_title_and_the_warning(self):
        self.repo('ledger-app', 'none')
        self.write('custom/requests/a.md', '**Project:** ledger-app\n')
        with mock.patch.dict(os.environ, {'CLAUDE_CONFIG_DIR': os.path.join(self.root, 'cfg')}):
            os.makedirs(os.path.join(self.root, 'cfg', 'sessions'))
            output = title.hook_output({'prompt': '/request a.md', 'session_id': 's1'}, self.root)
        spec = output['hookSpecificOutput']
        self.assertEqual(spec['sessionTitle'], 'ledger-app-1')
        self.assertIn('session-title: this session is now named ledger-app-1', spec['additionalContext'])
        self.assertIn('/normalize-projects ledger-app', spec['additionalContext'])
        spec = title.hook_output({'prompt': 'ledger-app'}, self.root)['hookSpecificOutput']
        self.assertEqual(spec['hookEventName'], 'UserPromptSubmit')
        self.assertNotIn('sessionTitle', spec)

    def test_failures_stay_silent_and_time_is_bounded(self):
        self.repo('ledger-app', 'none')
        with mock.patch.object(title, 'title_for', side_effect=RuntimeError('boom')):
            spec = title.hook_output({'prompt': 'ledger-app'}, self.root)['hookSpecificOutput']
            self.assertIn('ledger-app', spec['additionalContext'])
        with mock.patch.object(title, 'project_warning', side_effect=RuntimeError('boom')):
            self.assertIsNone(title.hook_output({'prompt': 'ledger-app'}, self.root))
        timeout = subprocess.TimeoutExpired('bash', title.STATE_TIMEOUT_SECONDS)
        with mock.patch.object(title.subprocess, 'run', side_effect=timeout):
            self.assertIsNone(self.warning('ledger-app'))
        self.rows['projects/ledger-app'] = 'garbage without tabs'
        self.assertIsNone(self.warning('ledger-app'))
        os.remove(os.path.join(self.root, 'scripts', 'aiwp-project-state.sh'))
        self.assertIsNone(self.warning('ledger-app'))
        self.assertEqual(title.project_states(self.root, []), [])
        self.assertIsNone(title.project_warning({'prompt': ['not', 'text']}, self.root))
        printed = io.StringIO()
        with (
            mock.patch('sys.stdin', io.StringIO('[1, 2]')),
            mock.patch('sys.argv', ['x', self.root]),
            contextlib.redirect_stdout(printed),
        ):
            title.main()
        self.assertEqual(printed.getvalue(), '')

    def test_a_repo_inside_another_repo_is_named_by_its_nearest_path(self):
        self.repo('platform', 'none')
        self.repo('platform/services/billing-api', 'outdated', marker='0.1.0', pending='0.2.0')
        os.makedirs(os.path.join(self.root, 'projects', 'platform', 'node_modules', 'dep', '.git'))
        self.assertEqual(
            title.workspace_projects(self.root),
            {'platform': ['projects/platform'], 'billing-api': ['projects/platform/services/billing-api']},
        )
        text = self.warning('see projects/platform/services/billing-api/src/app.ts')
        self.assertIn('`billing-api` (projects/platform/services/billing-api) is on workspace version 0.1.0', text)
        self.assertIn('`/normalize-projects platform/services/billing-api`', text)
        self.assertEqual(self.calls[-1][0][4:], ['projects/platform/services/billing-api'])
        text = self.warning('see projects/platform/docs/setup.md')
        self.assertIn('`platform` (projects/platform) has no AI-WORKSPACE-PROJECT marker', text)
        self.assertEqual(self.calls[-1][0][4:], ['projects/platform'])
        self.warning('billing-api and platform')
        self.assertEqual(self.calls[-1][0][4:], ['projects/platform', 'projects/platform/services/billing-api'])

    @unittest.skipIf(os.geteuid() == 0, 'root reads every folder')
    def test_a_folder_the_walk_cannot_read_is_skipped(self):
        self.repo('zeta', 'none')
        closed = os.path.join(self.root, 'projects', 'closed')
        os.makedirs(os.path.join(closed, 'inner', '.git'))
        os.chmod(closed, 0)
        try:
            self.assertEqual(title.workspace_projects(self.root), {'zeta': ['projects/zeta']})
        finally:
            os.chmod(closed, 0o755)

    def test_the_walk_is_capped(self):
        for n in range(4):
            os.makedirs(
                os.path.join(
                    self.root, 'projects', f'group-{n}', 'deeper', 'deepest', 'deeper-still', 'x', 'y', 'z', '.git'
                )
            )
        self.repo('zeta', 'none')
        self.repo('group-0/deeper/kept', 'none')
        os.makedirs(os.path.join(self.root, 'projects', '.hidden', '.git'))
        with open(os.path.join(self.root, 'projects', 'file.txt'), 'w', encoding='utf-8') as handle:
            handle.write('x')
        os.symlink(os.path.join(self.root, 'projects', 'zeta'), os.path.join(self.root, 'projects', 'link'))
        os.makedirs(os.path.join(self.root, 'custom', 'pocs', '.hidden'))
        self.assertEqual(
            title.workspace_projects(self.root), {'zeta': ['projects/zeta'], 'kept': ['projects/group-0/deeper/kept']}
        )
        with mock.patch.object(title, 'WALK_BUDGET', 2):
            self.assertEqual(title.workspace_projects(self.root), {})
        self.assertEqual(
            title.named_targets('a-1 b-1 c-1 d-1 e-1 f-1', {f'{n}-1': [f'projects/{n}-1'] for n in 'abcdef'}),
            [f'projects/{n}-1' for n in 'abcde'],
        )
        self.assertEqual(title.workspace_projects(os.path.join(self.root, 'nothing')), {})


@unittest.skipUnless(shutil.which('git') and shutil.which('bash'), 'needs git and bash')
class ProjectWarningWithTheStateScriptTests(unittest.TestCase):
    """The warning end to end, with the real scripts/aiwp-project-state.sh on real repositories."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        for folder in ('scripts/lib', 'projects', 'migrations', 'custom/pocs'):
            os.makedirs(os.path.join(self.root, folder))
        for name in ('aiwp-project-state.sh', 'lib/projects.sh'):
            shutil.copy(SCRIPTS / name, os.path.join(self.root, 'scripts', name))
        for name, text in (
            ('VERSION', '0.2.0\n'),
            ('migrations/0.1.0.md', '# 0.1.0\n'),
            ('migrations/0.2.0.md', '# 0.2.0\n'),
        ):
            with open(os.path.join(self.root, name), 'w', encoding='utf-8') as handle:
                handle.write(text)
        self.env = mock.patch.dict(os.environ, GIT_ENV)
        self.env.start()
        subprocess.run(['git', 'init', '-q', 'custom'], cwd=self.root, check=True)

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()

    def project(self, relative, readme):
        """A repo at projects/<relative> with that README.md committed on main and developer."""
        folder = os.path.join(self.root, 'projects', relative)
        os.makedirs(folder)
        with open(os.path.join(folder, 'README.md'), 'w', encoding='utf-8') as handle:
            handle.write(readme)
        for argv in (
            ['init', '-q', '-b', 'main'],
            ['add', '-A'],
            ['commit', '-q', '-m', 'base'],
            ['switch', '-q', '-c', 'developer'],
        ):
            subprocess.run(['git', *argv], cwd=folder, check=True, capture_output=True)

    def test_states_from_the_real_script(self):
        self.project('billing-api', '# billing\n')
        self.project('acme/shop-web', MARK.format('0.1.0') + '\n# shop\n')
        self.project('done', MARK.format('0.2.0') + '\n')
        self.project('claude-cli-agents-workspace', '# product\n')
        text = title.project_warning(
            {'prompt': 'billing-api, shop-web, done and claude-cli-agents-workspace'}, self.root
        )
        self.assertIn('`billing-api` (projects/billing-api) has no AI-WORKSPACE-PROJECT marker', text)
        self.assertIn('`shop-web` (projects/acme/shop-web) is on workspace version 0.1.0', text)
        self.assertIn('with the migrations 0.2.0 pending', text)
        self.assertNotIn('`done`', text)
        self.assertNotIn('claude-cli-agents-workspace', text)
        self.assertNotIn('Hotfix pending', text)

    def test_a_hotfix_on_main_from_the_real_script(self):
        self.project('done', MARK.format('0.2.0') + '\n')
        folder = os.path.join(self.root, 'projects', 'done')
        for argv in (
            ['switch', '-q', 'main'],
            ['commit', '-q', '--allow-empty', '-m', 'hotfix'],
            ['switch', '-q', 'developer'],
        ):
            subprocess.run(['git', *argv], cwd=folder, check=True, capture_output=True)
        text = title.project_warning({'prompt': 'change projects/done/app.py'}, self.root)
        self.assertIn('`done` (projects/done) has a hotfix on main that is not merged into developer', text)
        subprocess.run(['git', 'merge', '-q', '--no-edit', 'main'], cwd=folder, check=True, capture_output=True)
        self.assertIsNone(title.project_warning({'prompt': 'change projects/done/app.py'}, self.root))


if __name__ == '__main__':
    unittest.main()
