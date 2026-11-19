"""Unit tests of scripts/workspace-import.py (/import-workspace), with git and the workspace scripts faked.

Every command the module runs goes through subprocess.run, replaced here by FakeRun: it answers the read-only git
commands from the facts a test gives per folder, and the workspace scripts (aiwp-cmds.sh, validate.sh) and the
commit of custom/ from the codes a test sets. The end-to-end scenarios with real git are
scripts/tests/workspace-import/test-workspace-import.sh.
"""

import contextlib
import importlib.util
import io
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPTS = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location('workspace_import', SCRIPTS / 'workspace-import.py')
wi = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(wi)

SHA = 'a' * 40
OTHER = 'b' * 40


class Facts:
    """What the fake git answers for one folder."""

    def __init__(self, branch='main', head=SHA, status=None, branches=None, remotes=None, worktrees='', stashes=0):
        """Facts of a clean repository on main with an origin and its branch pushed, unless given."""
        self.status = status if status is not None else []
        self.branch, self.head = branch, head
        self.branches = branches if branches is not None else [('main', SHA, 'refs/remotes/origin/main', '')]
        self.remotes = remotes if remotes is not None else {}
        self.worktrees, self.stashes = worktrees, stashes
        self.count, self.log, self.filters, self.ignored = '1', 'abc1234 change', '', ''


class FakeRun:
    """Stands in for subprocess.run: answers git from Facts per folder, and the scripts from codes per command."""

    def __init__(self):
        """No folder known: git fails in it."""
        self.facts, self.calls, self.scripts, self.refs = {}, [], {}, {}
        self.toplevel, self.commit_rc, self.add_rc = None, 0, 0

    def git(self, args):
        """(code, output) of a git command line."""
        path = args[args.index('-C') + 1] if '-C' in args else None
        rest = args[args.index('-C') + 2 :] if '-C' in args else args[1:]
        sub = rest[0]
        if sub == 'rev-parse' and '--show-toplevel' in rest:
            return (0, self.toplevel + '\n') if self.toplevel else (128, '')
        if sub == 'rev-parse':
            sha = self.refs.get((path, rest[-1]))
            return (0, sha + '\n') if sha else (1, '')
        if sub in ('add', 'commit'):
            return (self.add_rc if sub == 'add' else self.commit_rc), ''
        facts = self.facts.get(path)
        if facts is None:
            return 128, ''
        return self.answer(facts, sub, rest)

    def answer(self, facts, sub, rest):
        """(code, output) of a read command in a known folder."""
        if sub == 'config' and '--name-only' in rest:
            return (0, facts.filters) if facts.filters else (1, '')
        if sub == 'config':
            lines = [f'remote.{name}.url {url}' for name, url in facts.remotes.items()]
            return (0, '\n'.join(lines) + '\n') if lines else (1, '')
        if sub == 'status':
            head = facts.branch or '(detached)'
            fields = [f'# branch.oid {facts.head or "(initial)"}', f'# branch.head {head}'] + facts.status
            return 0, '\0'.join(fields) + '\0'
        if sub == 'for-each-ref':
            return 0, ''.join(f'refs/heads/{n}\0{s}\0{u}\0{t}\n' for n, s, u, t in facts.branches)
        if sub == 'check-ignore':
            return (0, facts.ignored) if facts.ignored else (1, '')
        if sub == 'rev-list':
            return 0, facts.count + '\n'
        if sub == 'log':
            return 0, facts.log + '\n'
        if sub == 'stash':
            return 0, 'x\n' * facts.stashes
        if sub == 'worktree':
            return 0, facts.worktrees
        return 128, ''

    def __call__(self, argv, **kwargs):
        """Records the call and answers it."""
        self.calls.append(argv)
        if argv[0] == 'git':
            code, out = self.git(argv)
        else:
            key = ' '.join(argv[1:3])
            code, out = self.scripts.get(key, (0, f'ran {key}'))
            if callable(code):
                code, out = code(argv)
        return subprocess.CompletedProcess(argv, code, out, '')


class Base(unittest.TestCase):
    """A throwaway workspace and older workspace, with git faked."""

    def setUp(self):
        """Creates both roots and the fake."""
        self.tmp = tempfile.TemporaryDirectory()
        base = os.path.realpath(self.tmp.name)
        self.root, self.old = os.path.join(base, 'ws'), os.path.join(base, 'old')
        for folder in ('projects', 'custom', 'tmp', 'tools/observability'):
            os.makedirs(os.path.join(self.root, folder))
        self.write(self.root, 'tools/observability/panel.js', 'panel')
        self.write(self.root, 'tools/observability/package.json', '{}')
        os.makedirs(self.old)
        self.fake = FakeRun()
        patcher = mock.patch.object(wi.subprocess, 'run', self.fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        wi.FILTERS.clear()

    def tearDown(self):
        """Removes the roots."""
        self.tmp.cleanup()

    def write(self, base, rel, text):
        """Writes a file, creating its folders."""
        path = os.path.join(base, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8') as handle:
            handle.write(text)
        return path

    def repo(self, rel, **facts):
        """A repository of the older workspace: a .git folder and its facts."""
        path = os.path.join(self.old, rel) if rel != '.' else self.old
        os.makedirs(os.path.join(path, '.git'), exist_ok=True)
        self.fake.facts[path] = Facts(**facts)
        return path

    def main(self, *argv):
        """(code, output) of a command of the script on the workspace."""
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            code = wi.main(list(argv), root=self.root)
        return code, out.getvalue()

    def state(self):
        """The latest state."""
        with open(wi.state_files(self.root)[-1], encoding='utf-8') as handle:
            return json.load(handle)

    def questions(self):
        """The open questions, as JSON."""
        code, out = self.main('questions', '--json')
        self.assertEqual(code, 0, out)
        return {q['id']: q for q in json.loads(out)}

    def answer(self, *args):
        """Answers, asserting success."""
        code, out = self.main('answer', *args)
        self.assertEqual(code, 0, out)


def origin(name):
    """An invented remote URL."""
    return f'https://user:token@git.example.com/acme/{name}.git'


class HelpersTest(unittest.TestCase):
    """The helpers that need no git."""

    def test_secret_names(self):
        """.env and its variants, keys and credentials are never opened; .env.example is."""
        for name in ('.env', '.env.local', 'prod.env', 'id_rsa', 'server.pem', 'my-secrets.md', 'local.settings.json'):
            self.assertTrue(wi.secret_name(name), name)
        for name in ('.env.example', 'notes.md', 'package.json'):
            self.assertFalse(wi.secret_name(name), name)

    def test_read_text(self):
        """A regular file under the size limit; never a link, a secret, a big file or one that cannot be opened."""
        with tempfile.TemporaryDirectory() as base:
            plain = os.path.join(base, 'a.md')
            Path(plain).write_text('hello')
            self.assertEqual(wi.read_text(plain), 'hello')
            os.symlink(plain, os.path.join(base, 'link.md'))
            self.assertIsNone(wi.read_text(os.path.join(base, 'link.md')))
            Path(base, '.env').write_text('X=1')
            self.assertIsNone(wi.read_text(os.path.join(base, '.env')))
            self.assertIsNone(wi.read_text(os.path.join(base, 'missing.md')))
            with mock.patch.object(wi, 'MAX_TEXT', 2):
                self.assertIsNone(wi.read_text(plain))
            with mock.patch('builtins.open', side_effect=OSError('denied')):
                self.assertIsNone(wi.read_text(plain))

    def test_first_heading(self):
        """The first heading, else the first line; a secret never."""
        self.assertEqual(wi.first_heading('intro\n## Title\n'), 'Title')
        self.assertEqual(wi.first_heading('\nfirst line\n'), 'first line')
        self.assertEqual(wi.first_heading(''), '')
        self.assertEqual(wi.first_heading('# key AKIA' + 'ABCDEFGHIJKLMNOP'), '[secret removed]')

    def test_kebab_and_paths(self):
        """kebab-case names and paths, relatives, nearest folders."""
        self.assertEqual(wi.kebab('Relatório Mensal_v2'), 'relatorio-mensal-v2')
        self.assertEqual(wi.kebab('***'), 'item')
        self.assertEqual(wi.kebab_path('Acme/Billing API'), 'acme/billing-api')
        self.assertEqual(list(wi.parents('a/b/c')), ['a/b', 'a', '.'])
        self.assertEqual(wi.nearest('a/b/c', {'a', '.'}), 'a')
        self.assertIsNone(wi.nearest('a', set()))
        self.assertEqual(wi.code('a`b'), "`a'b`")
        self.assertEqual(wi.entries('/no/such/folder'), [])

    def test_parse_status(self):
        """Branch, head and changed paths of every kind of entry; a rename's original path is skipped."""
        out = '\0'.join(
            [
                '# branch.oid (initial)', '# branch.head (detached)', '# branch.upstream origin/main',
                '1 .M N... 100644 100644 100644 a a a.txt', '2 R. N... 100644 100644 100644 a a R100 new name.txt',
                'old.txt', 'u UU N... 1 1 1 1 a a a c.txt', '? new dir/',
            ]
        )  # fmt: skip
        self.assertEqual(wi.parse_status(out), (None, None, ['a.txt', 'new name.txt', 'c.txt', 'new dir/']))
        self.assertEqual(wi.parse_status('# branch.oid ' + SHA + '\0# branch.head main\0'), ('main', SHA, []))

    def test_urls(self):
        """A remote URL loses its credentials; the URLs of one repository share a key, whatever the protocol."""
        self.assertEqual(wi.redact(origin('x')), 'https://git.example.com/acme/x.git')
        keys = {
            wi.url_key(u, '/w')
            for u in (origin('x'), 'git@git.example.com:acme/x.git', 'ssh://git@git.example.com:22/acme/x/')
        }
        self.assertEqual(keys, {'git.example.com/acme/x'})
        self.assertEqual(wi.url_key('../remote.git', '/w/repo'), 'local:/w/remote.git')
        self.assertEqual(wi.url_key('file:///srv/remote.git', '/w'), 'local:/srv/remote.git')

    def test_backlog_file(self):
        """Markdown under a backlog folder, not in done/, qa/ or archive/, never a README."""
        self.assertTrue(wi.backlog_file('custom/requests', 'a.md'))
        self.assertTrue(wi.backlog_file('Backlog/2026', 'a.md'))
        self.assertFalse(wi.backlog_file('custom/requests/done/x', 'a.md'))
        self.assertFalse(wi.backlog_file('backlog', 'README.md'))
        self.assertFalse(wi.backlog_file('.', 'a.md'))

    def test_unique_branch_names(self):
        """A branch name never clashes with a taken one, nor with a folder of one."""
        taken = {'import/spike', 'main'}
        self.assertEqual(wi.unique_branch(taken, 'spike', ''), 'import/spike-2')
        self.assertEqual(wi.unique_branch(taken, 'spike', 'main'), 'import/spike-3/main')
        self.assertTrue(wi.clashes({'a/b'}, 'a'))

    def test_state_files_and_load_errors(self):
        """The latest state by date and number; a missing or broken one is refused."""
        with tempfile.TemporaryDirectory() as root:
            self.assertEqual(wi.state_files(root), [])
            base = os.path.join(root, wi.STATE_DIR)
            os.makedirs(base)
            for name in ('import-2026-01-02.json', 'import-2026-01-02-10.json', 'import-2026-01-02-2.json', 'x.json'):
                Path(base, name).write_text('{')
            self.assertEqual([os.path.basename(p) for p in wi.state_files(root)][-1], 'import-2026-01-02-10.json')
            with self.assertRaisesRegex(wi.Refused, 'cannot be read'):
                wi.load(root, None)
            with self.assertRaisesRegex(wi.Refused, 'no state file'):
                wi.load(root, os.path.join(root, 'none.json'))

    def test_run_reports_a_command_that_cannot_start(self):
        """A missing program is code 127, never an exception."""
        self.assertEqual(wi.run(['/no/such/program']).returncode, 127)


class SizeTest(unittest.TestCase):
    """The sizes the plan shows."""

    def test_human_size(self):
        """Bytes to B, KB, MB, GB, TB."""
        self.assertEqual(wi.human_size(10), '10 B')
        self.assertEqual(wi.human_size(1536), '1.5 KB')
        self.assertEqual(wi.human_size(5 * 1024**5), '5120.0 TB')

    def test_folder_size_leaves_out_git_skipped_folders_and_inner_repositories(self):
        """Only the files of the folder itself count, by name, links not followed."""
        with tempfile.TemporaryDirectory() as base:
            for rel, size in (('a.txt', 10), ('.git/objects/x', 100), ('node_modules/m.js', 1000), ('inner/b.txt', 7)):
                os.makedirs(os.path.dirname(os.path.join(base, rel)) or base, exist_ok=True)
                Path(base, rel).write_bytes(b'x' * size)
            os.symlink(os.path.join(base, 'a.txt'), os.path.join(base, 'link'))
            inner = os.path.realpath(os.path.join(base, 'inner'))
            self.assertEqual(wi.folder_size(base, {inner}), 10 + len(os.path.join(base, 'a.txt')))
            self.assertEqual(wi.folder_size(os.path.join(base, '.git'), set()), 100)
            with mock.patch.object(wi.os, 'lstat', side_effect=OSError('gone')):
                self.assertEqual(wi.folder_size(base, set()), 0)


class GitReadTest(Base):
    """The read-only git calls."""

    def test_filters_of_the_source_are_emptied(self):
        """Every filter its configuration names is emptied on every call, and git runs with no optional lock."""
        path = self.repo('r')
        self.fake.facts[path].filters = 'filter.lfs.clean\nfilter.lfs.smudge\nfilter.a.b.process\n'
        wi.git(path, 'status')
        call = self.fake.calls[-1]
        self.assertIn('--no-optional-locks', call)
        self.assertIn('filter.lfs.clean=', call)
        self.assertIn('filter.a.b.process=', call)
        self.assertIn('core.fsmonitor=false', call)
        self.assertIsNone(wi.git(os.path.join(self.old, 'unknown'), 'status'))

    def test_branches_pending_or_pushed(self):
        """Ahead is pending; no upstream or gone only with commits no remote holds; even with upstream is not."""
        path = self.repo(
            'r',
            branches=[
                ('main', SHA, 'refs/remotes/origin/main', ''),
                ('ahead', SHA, 'refs/remotes/origin/ahead', 'ahead 2, behind 1'),
                ('gone', SHA, 'refs/remotes/origin/gone', 'gone'),
                ('local', SHA, '', ''),
            ],
        )
        self.fake.facts[path].count = '0'
        self.fake.facts[path].log = 'abc1234 change\ndef5678 use token=' + 'abcdefgh12345678'
        found = {b['name']: b for b in wi.local_branches(path)}
        self.assertFalse(found['main']['pending'])
        self.assertEqual(found['ahead']['ahead'], 2)
        self.assertTrue(found['ahead']['pending'])
        # With no upstream (or a gone one), only commits no remote-tracking ref holds are pending.
        self.assertFalse(found['gone']['pending'] or found['local']['pending'])
        self.assertEqual(found['local']['count'], 0)
        # A count git cannot make (a missing object in the history) is never taken for 0: pending, unread.
        self.fake.facts[path].count = 'x'
        found = {b['name']: b for b in wi.local_branches(path)}
        self.assertTrue(found['local']['pending'] and found['local']['unread'])
        self.assertIsNone(found['local']['count'])
        found = {b['name']: b for b in wi.local_branches(path, ['refs/heads/local', 'refs/remotes/origin/gone'])}
        self.assertNotIn('local', found)
        self.assertTrue(found['gone']['gone'])
        self.fake.facts[path].count = '2'
        found = {b['name']: b for b in wi.local_branches(path)}
        self.assertTrue(found['gone']['pending'] and found['local']['pending'])
        self.assertEqual(found['local']['count'], 2)
        self.assertEqual(found['local']['commits'][0], 'abc1234 change')
        self.assertNotIn('abcdefgh12345678', found['local']['commits'][1])

    def test_worktree_list_skips_the_main_one(self):
        """The linked worktrees with their branch or detached head."""
        path = self.repo(
            'r', worktrees=f'worktree /m\nHEAD {SHA}\nbranch refs/heads/main\n\nworktree /w\nHEAD {SHA}\ndetached\n\n'
        )
        self.assertEqual(wi.worktree_list(path), [{'path': '/w', 'branch': None, 'head': SHA}])


class EmptyTest(Base):
    """An older workspace with nothing to bring."""

    def test_no_project_at_all(self):
        """Only a data repository: the plan has no project, no branch, no pending work and no backlog."""
        self.repo('notes', remotes={'origin': origin('notes')})
        code, out = self.main('scan', self.old)
        self.assertEqual(code, 0, out)
        self.answer('R-1', 'data')
        code, out = self.main('plan')
        self.assertEqual(code, 0, out)
        plan = Path(self.root, self.state()['plan']).read_text()
        self.assertIn('## Projects\n\nEach project', plan)
        self.assertEqual(plan.count('None.'), 4)


class Fixture(Base):
    """An older workspace: itself a repository, projects/billing-api with a worktree and a detached one, a nested
    repository, a work clone, a data repository, a code folder with no git, a covered tool, a backlog and rules."""

    def setUp(self):
        """Builds the folders and the facts."""
        super().setUp()
        self.repo('.', worktrees=f'worktree {self.old}\nHEAD {SHA}\nbranch refs/heads/main\n\n')
        wt, spike = os.path.join(self.old, 'worktrees/wt'), os.path.join(self.old, 'worktrees/spike')
        listing = (
            f'worktree {self.old}/projects/billing-api\nHEAD {SHA}\nbranch refs/heads/main\n\n'
            f'worktree {wt}\nHEAD {SHA}\nbranch refs/heads/feat/wt\n\nworktree {spike}\nHEAD {OTHER}\ndetached\n\n'
            f'worktree {self.old}/gone\nHEAD {SHA}\ndetached\nprunable\n\n'
        )
        self.repo(
            'projects/billing-api',
            remotes={'origin': origin('billing-api')},
            branches=[('main', SHA, 'refs/remotes/origin/main', ''), ('feat/wt', SHA, '', '')],
            worktrees=listing,
            stashes=1,
            status=['? nested/', '? notes.txt'],
        )
        self.repo('projects/billing-api/nested', remotes={'origin': origin('nested')})
        for path, facts in ((wt, Facts(branch='feat/wt', status=['? draft.txt'])), (spike, Facts(branch=None))):
            self.write(path, '.git', 'gitdir: x')
            self.fake.facts[path] = facts
        self.write(self.old, 'submodule/.git', 'gitdir: ../.git/modules/x')
        self.repo(
            'tmp/work/fix/billing-api',
            remotes={'origin': 'git@git.example.com:acme/billing-api.git'},
            branches=[
                ('main', SHA, 'refs/remotes/origin/main', ''),
                ('feat/wt', OTHER, '', ''),
                ('fix/totals', OTHER, '', ''),
                ('pushed', OTHER, 'refs/remotes/origin/pushed', ''),
            ],
            branch=None,
            head=OTHER,
        )
        self.repo('Notes Repo', remotes={'origin': origin('notes')})
        self.write(self.old, 'Notes Repo/README.md', '# Prompts and notes\n')
        self.write(self.old, 'tools/acme-cli/package.json', '{}')
        self.write(self.old, 'tools/acme-cli/.env', 'TOKEN=value')
        self.write(self.old, 'tools/acme-cli/sub/go.mod', 'module x')
        self.write(self.old, 'tools/observability/package.json', '{}')
        self.write(self.old, 'extras/dash/package.json', '{}')
        self.write(self.old, 'extras/dash/panel.js', 'panel')
        self.write(self.old, '.claude/hooks/package.json', '{}')
        self.write(self.old, 'CLAUDE.md', '# old')
        self.write(self.old, 'rules/review.md', '# review')
        self.write(self.old, 'backlog/export.md', '# Export invoices\n\nAs CSV.\n')
        self.write(self.old, 'backlog/queue.md', '# Session queue\n')
        self.write(self.old, 'backlog/secrets-rotation.md', '# Rotate\n')
        self.write(self.old, 'backlog/leak.md', '# Leak\n\nLEAKED\n')
        self.write(self.old, 'backlog/done/old.md', '# Done\n')
        self.write(self.old, 'projects/billing-api/requests/own.md', '# The project own request\n')

    def scan(self):
        """Scans the older workspace, asserting success."""
        code, out = self.main('scan', self.old)
        self.assertEqual(code, 0, out)
        return out

    def to_plan(self, keep_all=False):
        """Scans, answers every question, writes the plan."""
        self.scan()
        self.answer('R-1', 'data')
        self.answer('C-1', 'project')
        for qid, question in self.questions().items():
            name = os.path.basename(question['evidence']['file'])
            value = 'workspace' if name == 'queue.md' and not keep_all else 'billing-api'
            self.answer(qid, value, *(['--title', 'Export as CSV'] if name == 'export.md' else []))
        code, out = self.main('plan')
        self.assertEqual(code, 0, out)


class ScanTest(Fixture):
    """scan and the questions."""

    def test_inventory(self):
        """Each kind found, nothing opened that may hold a secret, the questions asked in order."""
        out = self.scan()
        self.assertIn('the older workspace itself is a repository', out)
        state = self.state()
        kinds = {r['path']: r['kind'] for r in state['repos']}
        self.assertEqual(kinds['projects/billing-api'], 'project')
        self.assertEqual(kinds['tmp/work/fix/billing-api'], 'clone')
        self.assertEqual(kinds['Notes Repo'], 'candidate')
        billing = next(r for r in state['repos'] if r['path'] == 'projects/billing-api')
        self.assertEqual(billing['changes'], ['notes.txt'])
        self.assertEqual(billing['remotes'], {'origin': 'https://git.example.com/acme/billing-api.git'})
        self.assertEqual(sorted(w['name'] for w in state['worktrees']), ['gone', 'spike', 'wt'])
        self.assertEqual(state['other_git_files'], ['submodule'])
        code = {c['path']: c for c in state['code_folders']}
        self.assertEqual(sorted(code), ['extras/dash', 'tools/acme-cli', 'tools/observability'])
        self.assertEqual(code['tools/observability']['how'], 'name')
        self.assertEqual(code['extras/dash']['how'], 'files')
        self.assertIsNone(code['tools/acme-cli']['covered'])
        backlog = {b['path'] for b in state['backlog']}
        self.assertEqual(
            backlog, {'backlog/export.md', 'backlog/queue.md', 'backlog/secrets-rotation.md', 'backlog/leak.md'}
        )
        self.assertIn('rules/', state['instructions'])
        self.assertIn('.claude/', state['instructions'])
        self.assertNotIn('TOKEN', json.dumps(state))
        self.assertEqual(sorted(self.questions()), ['C-1', 'R-1'])
        self.assertEqual(self.questions()['R-1']['evidence']['readme_heading'], 'Prompts and notes')

    def test_questions_in_text_and_the_backlog_after_the_repositories(self):
        """The backlog is asked once every repository is settled; the text form lists evidence and answers."""
        self.scan()
        code, out = self.main('questions')
        self.assertIn('R-1  Is this repository a project', out)
        self.assertIn('allowed: project, data', out)
        self.answer('R-1', 'data')
        questions = self.questions()
        self.assertEqual(sorted(questions), ['B-1', 'B-2', 'B-3', 'B-4', 'C-1'])
        self.assertEqual(questions['B-1']['allowed'], ['billing-api', 'billing-api/nested', 'workspace'])
        for qid in sorted(questions):
            self.answer(qid, 'tool' if qid == 'C-1' else 'workspace')
        code, out = self.main('questions')
        self.assertIn('no open question', out)

    def test_refusals_of_scan(self):
        """The workspace itself, a folder inside it or holding it, and a missing folder are refused."""
        for folder in (self.root, os.path.join(self.root, 'projects'), os.path.dirname(self.root), '/no/such'):
            code, out = self.main('scan', folder)
            self.assertEqual(code, 1, folder)
        code, out = self.main('status')
        self.assertIn('no import state', out)

    def test_an_unreadable_repository_is_listed(self):
        """A .git folder git cannot read is not brought and is listed."""
        os.makedirs(os.path.join(self.old, 'projects/broken/.git'))
        self.to_plan()
        plan = Path(self.root, self.state()['plan']).read_text()
        self.assertIn('projects/broken`: git could not read it', plan)


class AnswerTest(Fixture):
    """answer and the destinations."""

    def test_answers_are_validated(self):
        """An unknown id, a value not allowed, a title on another question or too long, are refused."""
        self.scan()
        for args, why in (
            (('X-1', 'data'), 'no question X-1'),
            (('R-1', 'maybe'), 'not an answer of R-1'),
            (('R-1', 'data', '--title', 'T'), 'only for a backlog item'),
        ):
            code, out = self.main('answer', *args)
            self.assertEqual(code, 1, out)
            self.assertIn(why, out)
        self.answer('R-1', 'data')
        code, out = self.main('answer', 'B-1', 'billing-api', '--title', 'x' * 121)
        self.assertIn('one line of 1 to 120', out)

    def test_a_repository_outside_the_projects_folder_becomes_a_project_where_answered(self):
        """R project opens P with a proposal; the repositories inside it wait for it; skip leaves it out."""
        self.repo('Notes Repo/inner', remotes={'origin': origin('inner')})
        self.repo('Notes Repo/Odd Name', remotes={'origin': origin('odd')})
        self.scan()
        for qid in ('R-1', 'R-2', 'R-3'):
            self.answer(qid, 'project')
        questions = self.questions()
        self.assertEqual(questions['P-1']['evidence']['proposal'], 'notes-repo')
        self.assertNotIn('P-2', questions)
        code, out = self.main('answer', 'P-1', 'Bad')
        self.assertIn('no kebab-case', out)
        os.makedirs(os.path.join(self.root, 'projects/taken'))
        code, out = self.main('answer', 'P-1', 'taken')
        self.assertIn('exists in this workspace', out)
        self.answer('P-1', 'knowledge/notes')
        questions = self.questions()
        self.assertEqual(questions['P-2']['evidence']['inside'], 'knowledge/notes')
        self.assertEqual(questions['P-2']['evidence']['proposal'], 'knowledge/notes/odd-name')
        code, out = self.main('answer', 'P-2', 'elsewhere/odd')
        self.assertIn('not inside knowledge/notes', out)
        self.answer('P-2', 'knowledge/notes/odd')
        self.assertIn('knowledge/notes/inner', self.questions()['B-1']['allowed'])
        self.answer('P-1', 'skip')
        questions = self.questions()
        self.assertEqual(questions['P-3']['evidence']['proposal'], 'inner')
        self.assertNotIn('B-1', questions)

    def test_a_destination_taken_in_the_workspace_is_asked(self):
        """A project whose path exists in projects/ gets a P question; skip leaves it out with its clones."""
        os.makedirs(os.path.join(self.root, 'projects/billing-api'))
        self.scan()
        questions = self.questions()
        self.assertIn('taken', questions['P-1']['evidence'])
        self.answer('P-1', 'skip')
        self.answer('R-1', 'data')
        self.answer('C-1', 'tool')
        for qid in [q for q in self.questions() if q.startswith('B-')]:
            self.answer(qid, 'workspace')
        code, out = self.main('plan')
        self.assertEqual(code, 0, out)
        plan = Path(self.root, self.state()['plan']).read_text()
        self.assertIn('billing-api`: a project not imported (skip)', plan)
        self.assertIn('which is not imported', plan)
        self.assertIn('a tool of the older workspace', plan)

    def test_two_projects_in_one_destination_and_a_backlog_item_about_no_project(self):
        """plan refuses both, naming the question to answer again."""
        self.scan()
        self.answer('R-1', 'project')
        self.answer('P-1', 'billing-api/nested')
        self.answer('C-1', 'tool')
        for qid in [q for q in self.questions() if q.startswith('B-')]:
            self.answer(qid, 'workspace')
        code, out = self.main('plan')
        self.assertEqual(code, 1)
        self.assertIn('both go to projects/billing-api/nested', out)
        state = self.state()
        question = next(q for q in state['questions'] if q['kind'] == 'B')
        question['answer'] = 'nowhere'
        with open(wi.state_files(self.root)[-1], 'w', encoding='utf-8') as handle:
            json.dump(state, handle)
        self.answer('P-1', 'notes')
        code, out = self.main('plan')
        self.assertIn('nowhere is no project of this import', out)


class OlderLayoutTest(Fixture):
    """Worktree trees, scratch, orphan worktrees and a repository answered backlog."""

    def setUp(self):
        """Adds them to the fixture."""
        super().setUp()
        self.write(self.old, 'worktrees/wt/audio-src/package.json', '{}')
        self.write(self.old, '.history/backups/package.json', '{}')
        self.write(self.old, 'scratch/probes/package.json', '{}')
        self.write(self.old, 'projects/no-repo/package.json', '{"name": "no-repo"}')
        self.fake.facts[self.old].ignored = 'scratch/probes\n'
        gitdir = os.path.join(self.old, 'projects/billing-api/.git/worktrees/old')
        self.write(self.old, 'worktrees/old/.git', f'gitdir: {gitdir}\n')
        self.write(self.old, 'worktrees/old/game/package.json', '{}')
        self.write(self.old, 'worktrees/moved/.git', 'gitdir: /elsewhere/projects/billing-api/.git/worktrees/moved\n')
        self.write(self.old, 'worktrees/stray/.git', 'gitdir: /elsewhere/unknown/.git/worktrees/stray\n')
        self.write(self.old, 'worktrees/plain/.git', 'not a gitdir line\n')
        self.write(self.old, 'Notes Repo/drafts/pdf.md', '# Monthly PDF\n')
        self.write(self.old, 'Notes Repo/done/old.md', '# Old\n')
        self.write(self.old, 'Notes Repo/.github/pr.md', '# PR\n')
        self.write(self.old, 'Notes Repo/CLAUDE.md', '# rules\n')
        self.write(self.old, 'Notes Repo/backlog/x.md', '# Already an item\n')
        self.write(self.old, '.history/backups/CLAUDE.md', '# old copy\n')
        self.write(self.old, 'scratch/probes/CLAUDE.md', '# probe\n')
        self.write(self.old, 'projects/no-repo/hooks/run.sh', 'true\n')
        self.write(self.old, 'pocs/observability/plugin/hooks/hooks.json', '{}')
        self.write(self.old, '.history/observability/notes.txt', 'a backup')

    def test_inventory_of_the_layout(self):
        """No code folder in a worktree tree; scratch counted; orphans attributed; a stray .git file listed."""
        self.scan()
        state = self.state()
        paths = {c['path'] for c in state['code_folders']}
        self.assertNotIn('worktrees/wt/audio-src', paths)
        self.assertNotIn('worktrees/old/game', paths)
        self.assertIn('projects/no-repo', paths)
        self.assertEqual(next(c for c in state['code_folders'] if c['path'] == 'projects/no-repo')['instructions'],
                         ['projects/no-repo/hooks/'])  # fmt: skip
        self.assertEqual(sorted(state['instructions']), ['.claude/', 'CLAUDE.md', 'Notes Repo/CLAUDE.md', 'rules/'])
        tool = next(c for c in state['code_folders'] if c['path'] == 'pocs/observability')
        self.assertEqual((tool['covered'], tool['manifests'], tool['instructions']), (
            'observability', [], ['pocs/observability/plugin/hooks/']))  # fmt: skip
        self.assertEqual(state['scratch'], {'count': 2, 'tops': ['.history/', 'scratch/']})
        orphans = {os.path.basename(w['path']): w['main'] for w in state['worktrees'] if w.get('orphan')}
        self.assertEqual(orphans, {'old': 'projects/billing-api', 'moved': 'projects/billing-api'})
        self.assertEqual(sorted(state['other_git_files']), ['submodule', 'worktrees/plain', 'worktrees/stray'])
        notes = next(r for r in state['repos'] if r['path'] == 'Notes Repo')
        # Its own backlog folder is its markdown, asked only once it is answered backlog; never a backlog item now.
        markdown = [m['path'] for m in notes['markdown']]
        self.assertEqual(markdown, ['Notes Repo/backlog/x.md', 'Notes Repo/drafts/pdf.md'])
        self.assertNotIn('Notes Repo/backlog/x.md', {b['path'] for b in state['backlog']})

    def test_a_backlog_repository_and_orphans_in_the_plan(self):
        """R backlog: its markdown files are B questions; the orphans go to the pending work, never fetched."""
        self.scan()
        self.answer('R-1', 'backlog')
        self.answer('C-1', 'tool')
        self.answer('C-2', 'project')
        files = {q['evidence']['file']: qid for qid, q in self.questions().items() if q['kind'] == 'B'}
        self.assertIn(os.path.join(self.old, 'Notes Repo/drafts/pdf.md'), files)
        self.assertIn(os.path.join(self.old, 'Notes Repo/backlog/x.md'), files)
        for qid in files.values():
            self.answer(qid, 'billing-api')
        code, out = self.main('plan')
        self.assertEqual(code, 0, out)
        plan = Path(self.root, self.state()['plan']).read_text()
        self.assertIn('(orphan worktree): its repository no longer tracks it', plan)
        scratch = 'Scratch of the older workspace: 2 code folder(s) with no git under `.history/`, `scratch/`'
        self.assertIn(scratch, plan)
        self.assertIn('Notes Repo`: the backlog of the older workspace', plan)
        self.assertIn('  - its own instruction files, part of it: `hooks/`', plan)
        self.assertFalse(any(s.get('source', '').endswith(('/old', '/moved')) for s in self.state()['steps']))
        self.main('skip', 'billing-api')
        self.main('plan')
        plan = Path(self.root, self.state()['plan']).read_text()
        self.assertIn('worktrees/old`: an orphan worktree of', plan)

    def test_no_root_repository_asks_git_for_nothing_ignored(self):
        """Without the older workspace's own repository, nothing is scratch but dot folders."""
        os.rename(os.path.join(self.old, '.git'), os.path.join(self.old, 'not-git'))
        self.scan()
        self.assertEqual(self.state()['scratch']['count'], 1)


class PlanApplyTest(Fixture):
    """plan, apply and status."""

    def test_plan_lists_everything(self):
        """Projects, branches, pending work, backlog and what is not imported."""
        self.to_plan()
        plan = Path(self.root, self.state()['plan']).read_text()
        self.assertIn('| `projects/billing-api` |', plan)
        self.assertIn('`projects/billing-api/nested`', plan)
        self.assertIn('`import/spike`', plan)
        self.assertIn('`fix/totals`', plan)
        self.assertIn('`import/billing-api/feat/wt`', plan)
        self.assertIn('`import/billing-api-2`', plan)
        self.assertIn('`main`, already in the project', plan)
        self.assertIn('`pushed`, on the remote', plan)
        self.assertIn('Stashes: 1', plan)
        self.assertIn('Changed files: `draft.txt`', plan)
        self.assertIn('Dropped', plan)
        self.assertIn('init -b main', plan)
        self.assertIn('covered by `tools/observability` of this workspace (its name)', plan)
        self.assertIn('(most of its files)', plan)
        self.assertIn('a .git file of no repository', plan)
        self.assertIn('an instruction file', plan)
        code, out = self.main('status')
        self.assertIn('apply: 0 of', out)
        self.assertIn('next step: bring projects/billing-api', out)

    def test_apply_runs_every_step_once_and_resumes(self):
        """Every step through the scripts; a failure stops it; the next apply resumes; the commit of custom/."""
        self.to_plan(keep_all=True)
        self.fake.toplevel = os.path.join(self.root, 'custom')
        calls = []

        def validate(argv):
            """Fails secrets when a listed file holds LEAKED."""
            listing = argv[argv.index('--files') + 1]
            names = Path(listing).read_text().split()
            calls.append(names)
            leaked = any('LEAKED' in Path(self.root, n).read_text() for n in names)
            return (1, 'FAIL secrets') if leaked else (0, 'PASS secrets')

        self.fake.scripts['scripts/aiwp-cmds.sh bring-branch'] = (1, 'error: refused')
        code, out = self.main('apply', '--yes')
        self.assertEqual(code, 1, out)
        self.assertIn('failed: bring-branch', out)
        code, out = self.main('status')
        self.assertIn('(failed: error: refused)', out)
        self.fake.scripts['scripts/aiwp-cmds.sh bring-branch'] = (0, '')
        self.fake.scripts['scripts/validate.sh --path'] = (validate, None)
        code, out = self.main('apply', '--yes')
        self.assertEqual(code, 0, out)
        self.assertNotIn('done: bring projects', out)
        self.assertEqual(len(calls), 4)
        requests = Path(self.root, wi.REQUESTS)
        names = sorted(p.name for p in requests.iterdir())
        day = wi.today()
        self.assertIn(f'{day}-billing-api-pending-work.md', names)
        export = (requests / f'{day}-export-as-csv.md').read_text()
        self.assertIn('**Project:** billing-api', export)
        self.assertIn('# Export invoices\n\nAs CSV.', export)
        self.assertIn('looks like a secret', (requests / f'{day}-leak.md').read_text())
        self.assertIn('looks like a secret', (requests / f'{day}-secrets-rotation.md').read_text())
        self.assertIn('**State:** idea', (requests / f'{day}-session-queue.md').read_text())
        commit = [c for c in self.fake.calls if c[:1] == ['git'] and 'commit' in c]
        self.assertTrue(commit and commit[-1][-1].endswith('.md'))
        code, out = self.main('apply', '--yes')
        self.assertIn('import applied', out)
        code, out = self.main('answer', 'C-1', 'tool')
        self.assertIn('apply has started', out)
        code, out = self.main('status')
        self.assertNotIn('next step', out)

    def test_skip_and_include(self):
        """A skipped project is not brought, nor its branches, worktrees, clones or pending work; one inside it goes
        with it unless included; a backlog item about it is dropped."""
        self.scan()
        self.answer('R-1', 'data')
        self.answer('C-1', 'tool')
        code, out = self.main('skip', 'nowhere')
        self.assertEqual(code, 1)
        self.assertIn('one of billing-api, billing-api/nested', out)
        code, out = self.main('skip', 'billing-api')
        self.assertEqual(code, 0, out)
        self.assertIn('billing-api: skip', out)
        code, out = self.main('status')
        self.assertIn('projects: 0 import, 2 skip', out)
        code, out = self.main('include', 'projects/billing-api/nested')
        self.assertIn('billing-api/nested: import', out)
        self.assertEqual(self.state()['included'], ['projects/billing-api/nested'])
        for qid in [q for q in self.questions() if q.startswith('B-')]:
            self.answer(qid, 'billing-api')
        code, out = self.main('plan')
        self.assertEqual(code, 0, out)
        plan = Path(self.root, self.state()['plan']).read_text()
        self.assertIn('| skip |', plan)
        self.assertIn('import (its parent', plan)
        self.assertIn('(its project billing-api is not imported)', plan)
        self.assertIn('a work clone of', plan)
        self.assertIn('worktrees/wt`: a worktree of', plan)
        steps = self.state()['steps']
        self.assertEqual([s['kind'] for s in steps], ['bring', 'commit'])
        self.assertEqual(steps[0]['dest'], 'billing-api/nested')
        code, out = self.main('include', 'billing-api')
        self.assertEqual(code, 0, out)
        self.assertEqual(self.state()['skipped'], [])
        code, out = self.main('apply', '--yes')
        self.assertIn('no plan for the current answers', out)
        self.main('skip', 'billing-api/nested')
        self.main('plan')
        self.fake.scripts['scripts/validate.sh --path'] = (0, 'PASS')
        code, out = self.main('apply', '--yes')
        self.assertEqual(code, 0, out)
        code, out = self.main('include', 'billing-api/nested')
        self.assertIn('apply has started', out)

    def test_apply_refusals(self):
        """Without --yes, with open questions, with no plan, or with the source gone."""
        self.scan()
        code, out = self.main('apply', '--yes')
        self.assertIn('questions are open', out)
        code, out = self.main('plan')
        self.assertIn('questions are open', out)
        code, out = self.main('status')
        self.assertIn('plan: not written', out)
        self.to_plan()
        code, out = self.main('apply')
        self.assertIn('only with --yes', out)
        self.answer('C-1', 'tool')
        code, out = self.main('apply', '--yes')
        self.assertIn('no plan for the current answers', out)
        self.main('plan')
        os.rename(self.old, self.old + '-moved')
        code, out = self.main('apply', '--yes')
        self.assertIn('the source is gone', out)

    def test_steps_already_done_and_failures(self):
        """A project or branch already there is done; one there without its branches, a scan that cannot run, a
        commit that fails and a custom/ that is no repository are reported."""
        self.to_plan()
        dest = os.path.join(self.root, 'projects', 'billing-api')
        os.makedirs(os.path.join(dest, '.git'))
        code, out = self.main('apply', '--yes')
        self.assertIn('exists without the branches of its source', out)
        self.fake.refs[(dest, 'refs/heads/main')] = SHA
        self.fake.refs[(dest, 'refs/heads/feat/wt')] = SHA
        self.fake.refs[(dest, 'refs/heads/import/spike')] = OTHER
        self.fake.scripts['scripts/validate.sh --path'] = (2, 'error: docker')
        code, out = self.main('apply', '--yes')
        self.assertIn('was already brought', out)
        self.assertIn('import/spike was already in', out)
        self.assertIn('the secret scan could not run', out)
        self.fake.scripts['scripts/validate.sh --path'] = (0, 'PASS secrets')
        self.fake.toplevel = os.path.join(self.root, 'custom')
        self.fake.commit_rc = 1
        code, out = self.main('apply', '--yes')
        self.assertIn('the commit of custom/ failed', out)
        self.fake.toplevel = None
        code, out = self.main('apply', '--yes')
        self.assertEqual(code, 0, out)
        self.assertIn('custom/ is no git repository', out)

    def test_an_unread_backlog_item_keeps_its_path(self):
        """An item that cannot be read at apply keeps only its path and a note."""
        self.to_plan()
        os.remove(os.path.join(self.old, 'backlog/export.md'))
        self.fake.scripts['scripts/validate.sh --path'] = (0, 'PASS')
        code, out = self.main('apply', '--yes')
        self.assertEqual(code, 0, out)
        text = Path(self.root, wi.REQUESTS, f'{wi.today()}-export-as-csv.md').read_text()
        self.assertIn('could not be read', text)

    def test_a_second_scan_the_same_day_and_a_request_name_taken(self):
        """A new state -2; a request never overwrites another."""
        self.scan()
        self.scan()
        self.assertTrue(wi.state_files(self.root)[-1].endswith(f'import-{wi.today()}-2.json'))
        self.write(self.root, f'{wi.REQUESTS}/{wi.today()}-billing-api-pending-work.md', 'other')
        self.to_plan()
        self.fake.scripts['scripts/validate.sh --path'] = (0, 'PASS')
        code, out = self.main('--state', wi.state_files(self.root)[-1], 'apply', '--yes')
        self.assertEqual(code, 0, out)
        self.assertTrue(Path(self.root, wi.REQUESTS, f'{wi.today()}-billing-api-pending-work-2.md').is_file())


if __name__ == '__main__':
    unittest.main()
