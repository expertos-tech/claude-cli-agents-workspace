"""Imports the work of an older workspace into this one: its git repositories into projects/, the branches of its
worktrees and work clones into those repositories, its pending work and its backlog as requests in custom/requests/.
Its rules are listed, never imported.

The older workspace is only read: every git call takes no optional lock and runs none of its fsmonitor, filters or
signature checks; .env files (but .env.example), keys, certificates and credential files are never opened; nothing of
it runs. The script does every step that is a fact and keeps the state in custom/migrations/import-<yyyy-mm-dd>.json
(-2, -3... for another scan the same day). It asks only what needs judgement, as questions with their evidence:
  R-n  a repository outside the projects folder: "project", "data" (of the older workspace) or "backlog" (its
       markdown files become backlog items; not brought); a clone of it follows the answer. Its evidence says when
       it sits in scratch of the older workspace (a dot folder, or a folder its own repository ignores). One whose
       origin is the older workspace itself or one of its worktrees is its own work: listed, never asked
  P-n  the destination in projects/ of a repository whose path is no kebab-case path under the projects folder, or
       is taken: a kebab-case path, or "skip" (not brought)
  C-n  a code folder with no git that no tool of tools/ covers: "project" or "tool" (of the older workspace). None
       is asked inside a repository or a worktree (valid or orphan), nor for scratch of the older workspace (inside a
       dot folder, or a folder its own repository ignores, outside the projects folder): counted only
  B-n  a backlog item: the project it is about, or "workspace" (the older workspace's own process: dropped)
An orphan worktree (a .git file whose gitdir <repository>/.git/worktrees/<name> is gone, and no such entry left)
belongs to that repository: its project's pending-work request names it, to compare its files by hand; nothing of it
is fetched. A worktree moved with the older workspace (copied from another machine or folder: its .git file and the
entry <repository>/.git/worktrees/<name> still name the old place) is paired with that entry and counted once, where it
is now: its branch or detached head from the entry, its changed files read through it (nothing written); its branch
comes with its repository, a detached head is fetched from the entry. The plan says the workspace was moved; the
person may repair the pointers there with git worktree repair, the import never does. The worktrees of the older
workspace itself are one line of the plan: their count and the folders they live under.
Missing objects (a snapshot taken while git wrote, a clone whose objects/info/alternates names a folder that is gone):
scan names each repository's refs that point to a missing object and its gone alternates; counts leave those refs out,
and a count git cannot make is said, never taken for 0. bring brings every complete branch and names the others; a
project with nothing complete, or a branch that cannot be fetched for a missing object, is recorded as not brought and
apply goes on; the pending-work request names each. A project with no remote: its request says once that the whole
repository is unpushed work, every local branch brought as it is.

Commands:
  scan <folder>        the inventory (read only) and the questions; writes a new state
  questions [--json]   the open questions, each with its evidence and its allowed answers
  answer <id> <value> [--title <title>]
                       records an answer, validated against the allowed ones (--title: the title of the request of a
                       backlog item; default its first heading); refused once apply started
  skip <project>, include <project>
                       a project (its destination, or its path in the folder) is brought (import, the default) or
                       not (skip): not brought, none of its branches, worktrees or work clones, no pending-work
                       request, a backlog item about it dropped; a repository inside a skipped one is skipped with
                       it, unless included on its own; refused once apply started
  plan                 writes custom/migrations/import-<date>.md: every project with where it goes, its size (files
                       and .git) and its status (import or skip), the branches of worktrees and work clones, the
                       pending work per project, the backlog, what is not imported; refused while a question is open
  apply --yes          runs the steps of the plan once each, in order, recording each; a failed step stops there and
                       the next apply resumes from it: bring of each repository (scripts/aiwp-cmds.sh bring, outermost
                       first, a nested one at its path inside its parent), bring-branch of each work-clone branch and
                       detached worktree, the secret scan of the backlog items kept (scripts/validate.sh --only
                       secrets), the requests, then one commit of custom/ by path. Never pushes. Refused while a
                       question is open, without --yes, or with no plan for the current answers
  status               where the import is: inventory, questions, plan, steps done and left
Options: --state <file> (default: the latest custom/migrations/import-*.json), --help.
Exit codes: 0 done; 1 refused or a step failed, with the reason; 2 usage.
Usage: python3 -I -B scripts/workspace-import.py <command> [args]
Example: python3 -I -B scripts/workspace-import.py scan ~/old-workspace
"""

import argparse
import datetime
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
STATE_DIR = 'custom/migrations'
REQUESTS = 'custom/requests'
STATE_NAME = re.compile(r'import-(\d{4}-\d{2}-\d{2})(?:-(\d+))?\.json\Z')
SKIP_DIRS = frozenset({'node_modules', '.venv'})
MANIFESTS = frozenset(
    {
        'go.mod', 'package.json', 'pom.xml', 'build.gradle', 'build.gradle.kts', 'pyproject.toml', 'setup.py',
        'Cargo.toml', 'composer.json', 'Gemfile',
    }
)  # fmt: skip
MANIFEST_SUFFIXES = ('.csproj', '.sln')
BACKLOG_DIRS = frozenset({'backlog', 'ideas', 'todo', 'requests'})
# Folders of a backlog that hold no pending item: what was delivered or set aside.
BACKLOG_SKIP = frozenset({'done', 'qa', 'archive', 'archived'})
INSTRUCTION_FILES = frozenset({'claude.md', 'claude.local.md', 'agents.md'})
INSTRUCTION_DIRS = frozenset({'rules', '.claude', 'skills', 'agents', 'hooks'})
KEBAB = re.compile(r'[a-z0-9]+(?:-[a-z0-9]+)*(?:/[a-z0-9]+(?:-[a-z0-9]+)*)*\Z')
# Files never opened: they may hold a secret. .env.example is the one template that is read.
SECRET_NAMES = frozenset(
    {
        'local.settings.json', '.netrc', '.pgpass', '.npmrc', '.pypirc', '.git-credentials', 'credentials',
        '.htpasswd', 'kubeconfig', 'id_rsa', 'id_dsa', 'id_ecdsa', 'id_ed25519',
    }
)  # fmt: skip
SECRET_SUFFIXES = (
    '.env', '.pem', '.key', '.p12', '.pfx', '.jks', '.keystore', '.crt', '.cer', '.der', '.kdbx', '.gpg', '.asc',
    '.tfstate', '.tfvars', '.ppk',
)  # fmt: skip
SECRET_WORDS = ('secret', 'credential', 'password', 'passwd')
MAX_TEXT = 1_000_000
MAX_HASH_FILES = 2000
MAX_HASH_SIZE = 5_000_000
MAX_COMMITS = 20
MAX_FILES = 200
MAX_ENTRIES = 25
COVERED_SHARE = 0.5
TIMEOUT = 600
KINDS = ('R', 'P', 'C', 'B')
SECRET_NOTE = (
    'Its text was not copied: it holds what looks like a secret, or its name marks a file that may hold one. Read it '
    'at its source and write the request here without the secret.'
)
UNREAD_NOTE = 'Its text was not copied: it could not be read. Read it at its source.'
GIT_SAFE = ('-c', 'core.fsmonitor=false', '-c', 'log.showSignature=false')
SHA = re.compile(r'[0-9a-f]{40}(?:[0-9a-f]{24})?\Z')
GLOB_PREFIX = {'branches': 'refs/heads/', 'remotes': 'refs/remotes/'}
MOVED_NOTE = (
    'its worktrees still point there; each is read where it is now. The person may repair those pointers in the '
    'older workspace with `git worktree repair`; the import never does'
)
FILTERS = {}
PATTERNS = []


class Refused(Exception):
    """A command the state does not allow; the message says why."""


class StepFailed(Exception):
    """A step of apply that failed; the message says why."""


def secret_patterns():
    """The secret patterns of scripts/prompt-log.py (the core's list), loaded once."""
    if PATTERNS:
        return PATTERNS
    spec = importlib.util.spec_from_file_location('aiwp_prompt_log', os.path.join(HERE, 'prompt-log.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    PATTERNS.extend(module.SECRET_PATTERNS)
    return PATTERNS


def has_secret(text):
    """True when a text matches one of the core's secret patterns."""
    return any(pattern.search(text) for pattern, _ in secret_patterns())


def scrub(text):
    """A text of the older workspace (a commit subject, a file name) with what the core's patterns take for a secret
    replaced: it goes into the state, the plan and the requests."""
    for pattern, replacement in secret_patterns():
        text = pattern.sub(replacement, text)
    return text


def today():
    """Today's date, yyyy-mm-dd."""
    return datetime.date.today().isoformat()


def run(argv, cwd=None, stdin=None):
    """Runs a command with its output captured as text; a command that cannot start or passes TIMEOUT is code 127."""
    env = dict(os.environ, GIT_TERMINAL_PROMPT='0', LC_ALL='C')
    try:
        return subprocess.run(
            argv, cwd=cwd, env=env, input=stdin, capture_output=True, text=True, encoding='utf-8',
            errors='replace', timeout=TIMEOUT, check=False,
        )  # fmt: skip
    except (OSError, subprocess.TimeoutExpired) as error:
        return subprocess.CompletedProcess(argv, 127, '', str(error))


def filter_options(path):
    """The -c options that empty every clean, smudge and process filter a repository's configuration names, so a
    status never runs one of its programs."""
    if path not in FILTERS:
        found = run(['git', *GIT_SAFE, '-C', path, 'config', '--name-only', '--get-regexp', r'^filter\..*\.']).stdout
        drivers = sorted({key[len('filter.') :].rsplit('.', 1)[0] for key in found.split()})
        FILTERS[path] = [o for d in drivers for k in ('clean', 'smudge', 'process') for o in ('-c', f'filter.{d}.{k}=')]
    return FILTERS[path]


def git(path, *args, stdin=None):
    """The output of a read-only git command in a folder of the older workspace, or None when git fails. Nothing of
    the folder runs: no optional lock, fsmonitor off, its filters emptied, no signature check."""
    result = run(['git', '--no-optional-locks', *GIT_SAFE, *filter_options(path), '-C', path, *args], stdin=stdin)
    return result.stdout if result.returncode == 0 else None


def missing_objects(path, shas):
    """The shas, of the ones given, whose object a repository does not have; empty when git cannot tell."""
    shas = [s for s in shas if SHA.fullmatch(s or '')]
    found = git(path, 'cat-file', '--batch-check', stdin=''.join(s + '\n' for s in shas)) if shas else None
    return {line.split(' ')[0] for line in (found or '').splitlines() if line.endswith(' missing')}


def broken_refs(path):
    """The refs of a repository that point to a missing object (one written while the folder was copied, or whose
    object was in a gone alternates), and HEAD when it is detached at one."""
    refs = []
    for line in (git(path, 'for-each-ref', '--format=%(objectname) %(refname)') or '').splitlines():
        sha, _, ref = line.partition(' ')
        if SHA.fullmatch(sha) and ref:
            refs.append((sha, ref))
    if git(path, 'symbolic-ref', '-q', 'HEAD') is None:
        head = (git(path, 'rev-parse', '-q', '--verify', 'HEAD') or '').strip()
        refs += [(head, 'HEAD')] if head else []
    missing = missing_objects(path, [sha for sha, _ in refs])
    return [ref for sha, ref in refs if sha in missing]


def gone_alternates(path):
    """The folders a repository's objects/info/alternates names that are gone (a clone made with --shared or
    --reference where the older workspace was before): the objects it borrowed from them are missing."""
    objects = os.path.join(path, '.git', 'objects')
    gone = []
    for line in (read_text(os.path.join(objects, 'info', 'alternates')) or '').splitlines():
        line = line.strip()
        if line and not line.startswith('#') and not os.path.isdir(os.path.join(objects, line)):
            gone.append(scrub(line))
    return gone


def excluding(broken, *globs):
    """The rev-list arguments --branches or --remotes, each after an --exclude of the broken refs it would take, so a
    ref that points to a missing object never fails a count."""
    args = []
    for glob in globs:
        prefix = GLOB_PREFIX[glob]
        args += [f'--exclude={ref[len(prefix) :]}' for ref in broken if ref.startswith(prefix)]
        args.append(f'--{glob}')
    return args


def secret_name(name):
    """True for a file the script never opens: .env and .env.* (but .env.example), keys, certificates, credentials."""
    lower = name.lower()
    if lower == '.env.example':
        return False
    return (
        lower.startswith('.env')
        or lower in SECRET_NAMES
        or lower.endswith(SECRET_SUFFIXES)
        or any(word in lower for word in SECRET_WORDS)
    )


def read_text(path):
    """The text of a file the script may open (a regular file, no link, no secret name, at most MAX_TEXT bytes), or
    None."""
    if os.path.islink(path) or secret_name(os.path.basename(path)) or not os.path.isfile(path):
        return None
    try:
        with open(path, 'rb') as handle:
            data = handle.read(MAX_TEXT + 1)
    except OSError:
        return None
    return None if len(data) > MAX_TEXT else data.decode('utf-8', 'replace')


def first_heading(text):
    """The first markdown heading of a text, else its first line that is not empty, at most 120 characters; a line
    with a secret is never returned."""
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    heading = next((line.lstrip('#').strip() for line in lines if line.startswith('#')), lines[0] if lines else '')
    return '[secret removed]' if has_secret(heading) else heading[:120]


def kebab(text):
    """A kebab-case name of a text: accents dropped, lower case, every run of other characters one hyphen."""
    plain = unicodedata.normalize('NFKD', text).encode('ascii', 'ignore').decode()
    return re.sub(r'[^a-z0-9]+', '-', plain.lower()).strip('-') or 'item'


def code(text):
    """A markdown code span of a text."""
    return '`' + str(text).replace('`', "'") + '`'


def inside(path, folder):
    """True when a real path is the folder or below it."""
    return os.path.commonpath([path, folder]) == folder


def parents(rel):
    """The folders above a path relative to the scanned folder, nearest first, '.' last."""
    while rel not in ('.', ''):
        rel = os.path.dirname(rel) or '.'
        yield rel


def nearest(rel, folders):
    """The nearest folder of a set above a relative path, or None."""
    return next((p for p in parents(rel) if p in folders), None)


def depth(rel):
    """Sort key: outermost first, then by path."""
    return (rel.count('/'), rel)


def entries(path):
    """Up to MAX_ENTRIES names of a folder, .git left out: evidence for a question (names only, nothing opened)."""
    try:
        names = sorted(name for name in os.listdir(path) if name != '.git')
    except OSError:
        return []
    return names[:MAX_ENTRIES]


# The inventory: names first, then git, read only.


def walk(folder, tool_names=()):
    """Everything the scan needs that names tell, nothing opened: repositories (.git folders), .git files, manifests,
    markdown files under a backlog folder, instruction files and folders, folders named like a tool of this
    workspace (tool_names). Paths relative to the folder."""
    found = {'repos': [], 'git_files': [], 'manifests': {}, 'markdown': [], 'all_markdown': [], 'instructions': []}
    found['named'] = []
    for top, dirs, files in os.walk(folder):
        rel = os.path.relpath(top, folder)
        if '.git' in dirs and not os.path.islink(os.path.join(top, '.git')):
            found['repos'].append(rel)
        if '.git' in files:
            found['git_files'].append(rel)
        dirs[:] = sorted(
            d for d in dirs if d != '.git' and d not in SKIP_DIRS and not os.path.islink(os.path.join(top, d))
        )
        manifests = sorted(f for f in files if f in MANIFESTS or f.endswith(MANIFEST_SUFFIXES))
        if manifests and rel != '.':
            found['manifests'][rel] = manifests
        here = '' if rel == '.' else rel + '/'
        found['named'] += [here + d for d in dirs if d in tool_names]
        found['instructions'] += [here + d + '/' for d in dirs if d.lower() in INSTRUCTION_DIRS]
        for name in sorted(files):
            if name.lower() in INSTRUCTION_FILES:
                found['instructions'].append(here + name)
            elif name.lower().endswith('.md'):
                found['all_markdown'].append(here + name)
                if backlog_file(rel, name):
                    found['markdown'].append(here + name)
    return found


def backlog_file(rel, name):
    """True for a markdown file in a folder named like a backlog, not in a folder of done or set-aside items."""
    parts = [] if rel == '.' else [part.lower() for part in rel.split('/')]
    start = next((i for i, part in enumerate(parts) if part in BACKLOG_DIRS), None)
    if start is None or name.lower() == 'readme.md':
        return False
    return not any(part in BACKLOG_SKIP for part in parts[start + 1 :])


def parse_status(out):
    """(branch or None when detached, head sha or None, changed paths) of git status --porcelain=v2 --branch -z."""
    branch, head, changes = None, None, []
    fields = iter(out.split('\0'))
    for entry in fields:
        if entry.startswith('# branch.oid '):
            head = entry[len('# branch.oid ') :]
            head = None if head == '(initial)' else head
        elif entry.startswith('# branch.head '):
            name = entry[len('# branch.head ') :]
            branch = None if name == '(detached)' else name
        elif entry[:2] in ('1 ', '2 ', 'u ', '? '):
            spaces = {'1': 8, '2': 9, 'u': 10, '?': 1}[entry[0]]
            changes.append(scrub(entry.split(' ', spaces)[-1]))
            if entry[0] == '2':
                next(fields, None)
    return branch, head, changes


def unpushed(path, refs):
    """(count, ['<sha> <subject>'...]) of the commits of a range, at most MAX_COMMITS listed; count None when git
    cannot walk it (a missing object in its history)."""
    count = git(path, 'rev-list', '--count', *refs)
    if count is None or not count.strip().isdigit():
        return None, []
    listed = git(path, 'log', f'-n{MAX_COMMITS}', '--format=%h %s', *refs) or ''
    return int(count.strip()), [scrub(line) for line in listed.splitlines()]


def local_branches(path, broken=()):
    """The local branches of a repository but those that point to a missing object (broken): name, sha, upstream,
    and for one that is not pushed (no upstream, its upstream gone or broken, or ahead of it) its commits not pushed;
    'unread' when a missing object in its history keeps them from being counted."""
    fmt = '%(refname)%00%(objectname)%00%(upstream)%00%(upstream:track,nobracket)'
    result = []
    for line in (git(path, 'for-each-ref', f'--format={fmt}', 'refs/heads/') or '').splitlines():
        ref, sha, upstream, track = (line.split('\0') + ['', '', ''])[:4]
        if ref in broken:
            continue
        name = ref[len('refs/heads/') :]
        ahead = re.search(r'ahead (\d+)', track)
        gone = track == 'gone' or upstream in broken
        branch = {'name': name, 'sha': sha, 'upstream': upstream, 'gone': gone, 'ahead': 0, 'commits': []}
        if upstream in broken:
            branch['upstream_broken'] = True
        if upstream and not gone:
            branch['ahead'] = int(ahead.group(1)) if ahead else 0
            refs = [f'{upstream}..{ref}'] if branch['ahead'] else None
        else:
            refs = [ref, '--not', *excluding(broken, 'remotes')]
        branch['pending'] = refs is not None
        if refs:
            branch['count'], branch['commits'] = unpushed(path, refs)
            # A branch with no upstream whose commits a remote-tracking ref already holds is no pending work.
            branch['pending'] = bool(branch['count']) or bool(upstream and not gone) or branch['count'] is None
            if branch['count'] is None:
                branch['unread'] = True
        result.append(branch)
    return result


def remote_urls(path):
    """{remote name: URL} of a repository's configuration."""
    urls = {}
    for line in (git(path, 'config', '--get-regexp', r'^remote\..*\.url$') or '').splitlines():
        key, _, url = line.partition(' ')
        urls[key[len('remote.') : -len('.url')]] = url
    return urls


def redact(url):
    """A remote URL without its user and password."""
    return re.sub(r'^([A-Za-z][A-Za-z0-9+.-]*://)[^/@]*@', r'\1', url)


def url_key(url, base):
    """What the URLs of one repository share whatever the protocol: host/path, lower case, no user, no .git; a local
    path is its real path."""
    found = re.match(r'[A-Za-z][A-Za-z0-9+.-]*://(?:[^/@]*@)?([^/:]+)(?::\d+)?/(.*)\Z', url)
    found = found or re.match(r'(?:[^@/:]+@)?([^/:]{2,}):(?!//)(.*)\Z', url)
    if not found or url.startswith('file:'):
        local = url[len('file://') :] if url.startswith('file://') else url
        return 'local:' + os.path.realpath(os.path.join(base, local))
    rest = found.group(2).strip('/')
    rest = rest[: -len('.git')] if rest.endswith('.git') else rest
    return f'{found.group(1).lower()}/{rest.lower()}'


def worktree_list(path):
    """The linked worktrees of a repository (its main one left out): path, branch (None when detached), head."""
    blocks = [block for block in (git(path, 'worktree', 'list', '--porcelain') or '').split('\n\n') if block.strip()]
    result = []
    for block in blocks[1:]:
        entry = dict(line.partition(' ')[::2] for line in block.splitlines())
        branch = entry.get('branch', '')
        result.append(
            {
                'path': entry.get('worktree', ''),
                'branch': branch[len('refs/heads/') :] if branch else None,
                'head': entry.get('HEAD', ''),
            }
        )
    return result


def read_repo(folder, rel, repo_rels, projects):
    """The facts of one repository: where it is, its branch and head, changed files, branches, remotes, stashes,
    worktrees. An unreadable one carries 'error'."""
    path = os.path.join(folder, rel)
    repo = {
        'path': rel,
        'nested_in': nearest(rel, repo_rels - {'.'}),
        'in_projects': bool(projects) and rel.startswith(projects + '/'),
    }
    status = git(path, 'status', '--porcelain=v2', '--branch', '-z', '--ignore-submodules=all')
    broken, alternates = broken_refs(path), gone_alternates(path)
    if status is None and not broken and not alternates:
        repo['error'] = 'git could not read it'
        return repo
    if broken:
        repo['broken'] = broken
    if alternates:
        repo['alternates'] = alternates
    if status is None:
        # A HEAD on a missing object: the rest is read, its changed files are not.
        head_ref = (git(path, 'symbolic-ref', '-q', 'HEAD') or '').strip()
        repo['branch'] = head_ref[len('refs/heads/') :] if head_ref.startswith('refs/heads/') else None
        repo['head'], repo['changes'] = None, []
        missing = 'HEAD' in broken or head_ref in broken
        repo['unread'] = 'its HEAD points to a missing object' if missing else 'git status failed on a missing object'
    else:
        repo['branch'], repo['head'], repo['changes'] = parse_status(status)
    urls = remote_urls(path)
    repo['remotes'] = {name: redact(url) for name, url in sorted(urls.items())}
    repo['origin_key'] = url_key(urls['origin'], path) if 'origin' in urls else None
    repo['branches'] = local_branches(path, broken)
    repo['stashes'] = len((git(path, 'stash', 'list', '--format=%h') or '').splitlines())
    repo['detached'] = None
    if not repo['branch'] and repo['head'] and 'HEAD' not in broken:
        repo['detached'] = detached_commits(path, repo['head'], broken)
    repo['worktrees'] = worktree_list(path)
    return repo


def detached_commits(path, head, broken=(), rev='HEAD'):
    """{sha, count, commits} of a detached HEAD (or of a commit, rev): its commits on no branch and no remote; count
    None ('unread') when a missing object in its history keeps them from being counted."""
    count, commits = unpushed(path, [rev, '--not', *excluding(broken, 'branches', 'remotes')])
    found = {'sha': head or '', 'count': count, 'commits': commits}
    if count is None:
        found['unread'] = True
    return found


def read_worktree(folder, main, entry, broken=()):
    """The facts of one linked worktree: its path, branch or detached head, changed files; 'missing' when its folder
    is gone, 'unread' when git cannot read it there (a HEAD on a missing object)."""
    worktree = {'path': entry['path'], 'main': main, 'branch': entry['branch'], 'head': entry['head']}
    worktree['name'] = kebab(os.path.basename(entry['path'].rstrip('/')))
    if not os.path.isdir(entry['path']):
        worktree['missing'] = True
        return worktree
    status = git(entry['path'], 'status', '--porcelain=v2', '--branch', '-z', '--ignore-submodules=all')
    worktree['changes'] = parse_status(status)[2] if status is not None else []
    if status is None:
        worktree['unread'] = True
    worktree['detached'] = None if entry['branch'] else worktree_detached(folder, main, worktree, broken)
    return worktree


def worktree_detached(folder, main, worktree, broken):
    """The commits of a detached worktree on no branch and no remote, counted in its repository; with its head on a
    missing object, 'head_missing' is set on the worktree and nothing is counted."""
    path = os.path.join(folder, main)
    if worktree['head'] in missing_objects(path, [worktree['head']]):
        worktree['head_missing'] = True
        return {'sha': worktree['head'], 'count': None, 'commits': [], 'unread': True}
    if not SHA.fullmatch(worktree['head'] or ''):
        return {'sha': worktree['head'] or '', 'count': 0, 'commits': []}
    return detached_commits(path, worktree['head'], broken, rev=worktree['head'])


def moved_worktree(folder, rel, mains):
    """{main, admin, old, old_root} of a worktree moved with the older workspace (copied from another machine or
    folder): its .git file names <old root>/<main>/.git/worktrees/<name>, which is gone, and the admin entry
    <main>/.git/worktrees/<name> of the folder names <old root>/<rel>/.git back. None for any other .git file. mains:
    the repositories of the folder, longest path first, '.' (the older workspace itself) last."""
    text = read_text(os.path.join(folder, rel, '.git')) or ''
    if rel == '.' or not text.startswith('gitdir:'):
        return None
    gitdir = os.path.normpath(os.path.join(folder, rel, text[len('gitdir:') :].strip()))
    if os.path.exists(gitdir) or '/.git/worktrees/' not in gitdir:
        return None
    old_main, name = gitdir.rsplit('/.git/worktrees/', 1)
    for main in mains:
        if main == '.':
            old_root = old_main
        elif old_main.endswith('/' + main):
            old_root = old_main[: -len(main) - 1]
        else:
            continue
        admin = os.path.normpath(os.path.join(folder, main, '.git', 'worktrees', name))
        recorded = read_text(os.path.join(admin, 'gitdir')) or ''
        old = os.path.join(old_root, rel)
        if recorded.strip() and os.path.normpath(recorded.strip()) == os.path.join(old, '.git'):
            return {'main': main, 'admin': admin, 'old': old, 'old_root': old_root}
    return None


def read_moved(folder, rel, moved, broken):
    """The facts of a worktree moved with the older workspace, read where it is now through its own git folder
    (<main>/.git/worktrees/<name>) with git's safe options, nothing written to either: its branch or detached head
    (from that folder's HEAD), its changed files ('unread' when git cannot read them)."""
    path = os.path.join(folder, rel)
    main_path = os.path.normpath(os.path.join(folder, moved['main']))
    head = (read_text(os.path.join(moved['admin'], 'HEAD')) or '').strip()
    branch = head[len('ref: refs/heads/') :] if head.startswith('ref: refs/heads/') else None
    sha = (git(main_path, 'rev-parse', '-q', '--verify', f'refs/heads/{branch}') or '').strip() if branch else head
    worktree = {'path': path, 'main': moved['main'], 'branch': branch, 'head': sha, 'moved': True}
    worktree.update(name=kebab(os.path.basename(rel)), admin=moved['admin'])
    status = run(
        [
            'git', '--no-optional-locks', *GIT_SAFE, *filter_options(main_path), f'--git-dir={moved["admin"]}',
            f'--work-tree={path}', 'status', '--porcelain=v2', '--branch', '-z', '--ignore-submodules=all',
        ],
        cwd=path,
    )  # fmt: skip
    worktree['changes'] = parse_status(status.stdout)[2] if status.returncode == 0 else []
    if status.returncode != 0:
        worktree['unread'] = True
    worktree['detached'] = None if branch else worktree_detached(folder, moved['main'], worktree, broken)
    return worktree


def own_keys(folder, paths):
    """The url_key of each path that is the older workspace itself: the folder, where it was before it was copied,
    and its own worktrees, there and here; a repository with one of them as its origin is its own clone."""
    return {'local:' + os.path.realpath(p) for p in [folder, *paths]}


def classify(repos, own=frozenset()):
    """Sets the kind of each repository: 'project' (the first of its remote in the projects folder), 'clone' (another
    repository of the same remote: a work clone, clone_of its project), 'candidate' (outside the projects folder,
    alone with its remote: an R question), 'self' (outside the projects folder, its origin the older workspace itself
    or one of its worktrees, own: its own work) or 'unreadable'."""
    groups = {}
    for repo in repos:
        key = repo.get('origin_key') or ''
        key = key[: -len('/.git')] if key.endswith('/.git') else key
        if 'error' not in repo and not repo['in_projects'] and key in own:
            repo['kind'] = 'self'
            continue
        if repo.get('origin_key'):
            groups.setdefault(repo['origin_key'], []).append(repo)
    for repo in repos:
        if repo.get('kind') == 'self':
            continue
        if 'error' in repo:
            repo['kind'] = 'unreadable'
            continue
        group = groups.get(repo['origin_key']) or [repo]
        primary = next((r for r in group if r['in_projects']), group[0])
        if primary is repo:
            repo['kind'] = 'project' if repo['in_projects'] else 'candidate'
        else:
            repo['kind'], repo['clone_of'] = 'clone', primary['path']


class Tools:
    """The tools of this workspace's tools/, to tell a code folder of the older workspace they already cover."""

    def __init__(self, root):
        """Lists the tool folders; their hashes are read only when a name does not match."""
        base = os.path.join(root, 'tools')
        names = sorted(os.listdir(base)) if os.path.isdir(base) else []
        self.folders = {n: os.path.join(base, n) for n in names if os.path.isdir(os.path.join(base, n))}
        self.hashes = {}

    def covering(self, path):
        """(tool, 'name' | 'files') of the tool that covers a code folder, or (None, None)."""
        name = os.path.basename(path)
        if name in self.folders:
            return name, 'name'
        own = file_hashes(path)
        for tool, folder in self.folders.items():
            if tool not in self.hashes:
                self.hashes[tool] = file_hashes(folder)
            if own and len(own & self.hashes[tool]) > COVERED_SHARE * len(own):
                return tool, 'files'
        return None, None


def file_hashes(folder):
    """The sha256 of the files of a folder the script may open (no link, no secret name, no skipped folder, at most
    MAX_HASH_SIZE bytes), at most MAX_HASH_FILES of them."""
    found = set()
    for top, dirs, files in os.walk(folder):
        dirs[:] = sorted(d for d in dirs if d != '.git' and d not in SKIP_DIRS)
        for name in sorted(files):
            path = os.path.join(top, name)
            if os.path.islink(path) or secret_name(name) or not os.path.isfile(path):
                continue
            if os.path.getsize(path) > MAX_HASH_SIZE:
                continue
            try:
                with open(path, 'rb') as handle:
                    found.add(hashlib.sha256(handle.read()).hexdigest())
            except OSError:
                continue
            if len(found) >= MAX_HASH_FILES:
                return found
    return found


def folder_size(path, roots):
    """The bytes of the files of a folder, by their names only (nothing opened): .git, node_modules, .venv and the
    repositories and worktrees inside it (roots: real paths) left out; links not followed."""
    total = 0
    for top, dirs, files in os.walk(path):
        dirs[:] = [
            d for d in dirs
            if d != '.git' and d not in SKIP_DIRS and os.path.realpath(os.path.join(top, d)) not in roots
        ]  # fmt: skip
        for name in files:
            try:
                total += os.lstat(os.path.join(top, name)).st_size
            except OSError:
                continue
    return total


def orphan_main(folder, rel, repos):
    """The repository an orphan worktree belongs to (path in the folder), by its gitdir
    (<repository>/.git/worktrees/<name>), or None: a .git file whose gitdir exists, or names no repository of the
    folder, is no orphan worktree."""
    text = read_text(os.path.join(folder, rel, '.git')) or ''
    if not text.startswith('gitdir:'):
        return None
    gitdir = os.path.normpath(os.path.join(folder, rel, text[len('gitdir:') :].strip()))
    if os.path.exists(gitdir) or '/.git/worktrees/' not in gitdir:
        return None
    main = gitdir.split('/.git/worktrees/')[0]
    for repo in sorted(repos, key=lambda r: -len(r['path'])):
        if main == os.path.join(folder, repo['path']) or main.endswith('/' + repo['path']):
            return repo['path']
    return None


def code_folders(root, folder, found, trees, instruction_dirs, projects):
    """(code folders, scratch) of the folder: the outermost folders with a manifest, or named like a tool of this
    workspace (a tool of the older workspace with no manifest), that no repository or worktree holds, out of the
    instruction folders. One inside a dot folder, or one the older workspace's own repository ignores, outside the
    projects folder, is scratch of the older workspace: counted, never asked."""
    found_paths = []
    for rel in sorted(set(found['manifests']) | set(found.get('named', [])), key=depth):
        if rel in trees or nearest(rel, trees - {'.'}) or nearest(rel, set(found_paths)):
            continue
        if not nearest(rel, instruction_dirs):
            found_paths.append(rel)
    scratched = scratch_of(folder, found, projects, found_paths)
    code, scratch, tools = [], [], Tools(root)
    for rel in found_paths:
        if rel in scratched:
            # A folder named like a tool, with no manifest, in scratch is no code folder: not counted.
            if rel in found['manifests']:
                scratch.append(rel)
            continue
        tool, how = tools.covering(os.path.join(folder, rel))
        code.append({'path': rel, 'manifests': found['manifests'].get(rel, []), 'covered': tool, 'how': how})
    tops = sorted({rel.split('/')[0] + '/' for rel in scratch})
    return code, {'count': len(scratch), 'tops': tops}


def scratch_of(folder, found, projects, paths):
    """The paths, of the ones given, that are scratch of the older workspace: outside the projects folder, and in a
    dot folder (a part of the path starts with a dot) or ignored by the older workspace's own repository."""
    outside = [p for p in paths if p != '.' and not (projects and (p + '/').startswith(projects + '/'))]
    ignored = set()
    if '.' in found['repos'] and outside:
        ignored = set((git(folder, 'check-ignore', '--', *outside) or '').splitlines())
    return {p for p in outside if p in ignored or any(part.startswith('.') for part in p.split('/'))}


def heading_of(path):
    """The first heading of a markdown file, '' when it is not read."""
    text = read_text(path)
    return first_heading(text) if text is not None else ''


def repo_markdown(folder, repo, found, trees):
    """The markdown files of a repository that may be backlog items, should it be answered "backlog": in it and in
    no repository or worktree inside it, not in a backlog folder already (those are items anyway), not in done/, qa/,
    archive/ nor in a dot or instruction folder, no README nor instruction file."""
    items = []
    for rel in found['all_markdown']:
        if not rel.startswith(repo + '/') or rel in found['markdown'] or nearest(rel, trees - {'.'}) != repo:
            continue
        parts = rel[len(repo) + 1 :].lower().split('/')
        folders, name = parts[:-1], parts[-1]
        if name == 'readme.md' or name in INSTRUCTION_FILES:
            continue
        if any(p in BACKLOG_SKIP or p in INSTRUCTION_DIRS or p.startswith('.') for p in folders):
            continue
        items.append({'path': rel, 'heading': heading_of(os.path.join(folder, rel))})
    return items


def inventory(root, folder):
    """The state of a new import: every fact of the folder, read only. Questions come from refresh()."""
    found = walk(folder, set(Tools(root).folders))
    repo_rels = set(found['repos'])
    projects = 'projects' if os.path.isdir(os.path.join(folder, 'projects')) else None
    repos = [read_repo(folder, rel, repo_rels, projects) for rel in sorted(repo_rels - {'.'}, key=depth)]
    # A workspace copied from elsewhere: each worktree once, where it is now, paired with its admin entry.
    mains = sorted(repo_rels - {'.'}, key=lambda r: (-len(r), r)) + (['.'] if '.' in repo_rels else [])
    moved = {rel: m for rel in found['git_files'] for m in [moved_worktree(folder, rel, mains)] if m}
    replaced = {(m['main'], m['old']) for m in moved.values()}
    root_listed = [w['path'] for w in worktree_list(folder)] if '.' in repo_rels else []
    root_worktrees = [p for p in root_listed if ('.', os.path.normpath(p)) not in replaced]
    root_worktrees += [os.path.join(folder, rel) for rel, m in sorted(moved.items()) if m['main'] == '.']
    old_roots = sorted({m['old_root'] for m in moved.values()})
    classify(repos, own_keys(folder, [*old_roots, *root_listed, *root_worktrees]))
    broken = {r['path']: r.get('broken', []) for r in repos}
    worktrees, seen = [], set()
    for repo in repos:
        for entry in repo.pop('worktrees', []):
            if (repo['path'], os.path.normpath(entry['path'])) in replaced:
                continue
            worktrees.append(read_worktree(folder, repo['path'], entry, broken[repo['path']]))
            seen.add(os.path.realpath(entry['path']))
    for rel, m in sorted(moved.items()):
        seen.add(os.path.realpath(os.path.join(folder, rel)))
        if m['main'] != '.':
            worktrees.append(read_moved(folder, rel, m, broken.get(m['main'], [])))
    seen |= {os.path.realpath(p) for p in root_worktrees}
    outside = [r['path'] for r in repos if r['kind'] == 'candidate']
    for rel in scratch_of(folder, found, projects, outside):
        dot = any(part.startswith('.') for part in rel.split('/'))
        next(r for r in repos if r['path'] == rel)['scratch'] = 'dot' if dot else 'ignored'
    roots = {os.path.realpath(os.path.join(folder, rel)) for rel in repo_rels} | seen
    for repo in repos:
        if 'changes' in repo:
            repo['changes'] = [
                c for c in repo['changes'] if os.path.realpath(os.path.join(folder, repo['path'], c)) not in roots
            ]
    for repo in repos:
        path = os.path.join(folder, repo['path'])
        repo['size'] = {'files': folder_size(path, roots), 'git': folder_size(os.path.join(path, '.git'), set())}
    others = []
    for rel in found['git_files']:
        if rel in moved or os.path.realpath(os.path.join(folder, rel)) in seen:
            continue
        main = orphan_main(folder, rel, repos)
        if main is None:
            others.append(rel)
            continue
        worktrees.append(
            {
                'path': os.path.join(folder, rel), 'main': main, 'name': kebab(os.path.basename(rel)), 'branch': None,
                'head': '', 'orphan': True,
            }
        )  # fmt: skip
    kinds = {r['path']: r['kind'] for r in repos}
    # The tree of a worktree, valid or orphan, is a repository's: no code folder, backlog or instruction file in it.
    trees = set(found['git_files'])
    # A clone of the older workspace itself holds its own files: no backlog item or instruction file of it is asked.
    owned = {rel for rel, kind in kinds.items() if kind in ('project', 'clone', 'self')} | trees
    instruction_dirs = {i.rstrip('/') for i in found['instructions'] if i.endswith('/')}
    code, scratch = code_folders(root, folder, found, repo_rels | trees, instruction_dirs, projects)
    backlog = []
    for rel in found['markdown']:
        if nearest(rel, owned) is None:
            backlog.append({'path': rel, 'heading': heading_of(os.path.join(folder, rel))})
    for repo in repos:
        if repo['kind'] == 'candidate':
            repo['markdown'] = repo_markdown(folder, repo['path'], found, repo_rels | trees)
    instructions = [i for i in found['instructions'] if nearest(i.rstrip('/'), owned) is None]
    instructions = [i for i in instructions if not nearest(i.rstrip('/'), instruction_dirs)]
    # Scratch is no rule: an instruction file in a dot folder or a folder the older workspace ignores is left out.
    holders = {i: os.path.dirname(i.rstrip('/')) or '.' for i in instructions}
    scratched = scratch_of(folder, found, projects, sorted(set(holders.values())))
    instructions = [i for i in instructions if holders[i] not in scratched]
    # Those of a code folder of the older workspace (a tool's hooks) are listed with it, not as its rules.
    code_paths = {c['path'] for c in code}
    for folder_ in code:
        folder_['instructions'] = [i for i in instructions if nearest(i.rstrip('/'), code_paths) == folder_['path']]
    instructions = [i for i in instructions if nearest(i.rstrip('/'), code_paths) is None]
    return {
        'version': 1,
        'source': folder,
        'scanned': today(),
        'projects_folder': projects,
        'root_repo': '.' in repo_rels,
        'root_worktrees': root_worktrees,
        'moved_from': old_roots,
        'repos': repos,
        'worktrees': worktrees,
        'other_git_files': others,
        'code_folders': code,
        'scratch': scratch,
        'backlog': backlog,
        'instructions': instructions,
        'questions': [],
        'steps': [],
        'plan_key': None,
    }


# Roles, destinations and questions.


def answer_of(state, kind, subject):
    """The recorded answer of the question of a kind about a subject, or None."""
    for question in state['questions']:
        if question['kind'] == kind and question['subject'] == subject and question['status'] == 'answered':
            return question['answer']
    return None


def workspace_projects(root):
    """The repositories already in this workspace's projects/, relative to it, at most four folders deep."""
    base = os.path.join(root, 'projects')
    found = []
    for top, dirs, _ in os.walk(base):
        rel = os.path.relpath(top, base)
        if '.git' in dirs and rel != '.':
            found.append(rel)
        dirs[:] = [] if rel.count('/') >= 3 else sorted(d for d in dirs if d != '.git' and d not in SKIP_DIRS)
    return found


def resolve(state, root):
    """The role of each repository (project, clone, data, skip, off, unreadable; None while a question is open), the
    destination of each project, the questions needed now [(kind, subject, evidence, allowed)], and the name of
    each project the person skipped (its destination had it been brought)."""
    repos = {r['path']: r for r in state['repos']}
    role, dest, needs, names = {}, {}, [], {}
    for repo in state['repos']:
        role[repo['path']] = repo['kind']
        if repo['kind'] == 'candidate':
            role[repo['path']] = answer_of(state, 'R', repo['path'])
            needs.append(('R', repo['path'], r_evidence(state, repo), ['project', 'data', 'backlog']))
    clone_roles(state, role)
    for repo in sorted(state['repos'], key=lambda r: depth(r['path'])):
        if role[repo['path']] != 'project':
            continue
        parent, waiting = imported_parent(repo, repos, role, dest)
        if waiting:
            continue
        auto = None
        if parent and KEBAB.match(os.path.relpath(repo['path'], parent)):
            auto = f'{dest[parent]}/{os.path.relpath(repo["path"], parent)}'
        elif not parent and repo['in_projects'] and KEBAB.match(repo['path'][len(state['projects_folder']) + 1 :]):
            auto = repo['path'][len(state['projects_folder']) + 1 :]
        if skipped_by_person(state, repos, repo):
            role[repo['path']] = 'skip'
            names[repo['path']] = auto or p_evidence(state, repo, parent, parent and dest[parent], None)['proposal']
            continue
        if auto and not os.path.lexists(os.path.join(root, 'projects', auto)):
            dest[repo['path']] = auto
            continue
        evidence = p_evidence(state, repo, parent, parent and dest[parent], auto)
        needs.append(('P', repo['path'], evidence, ['<kebab-case path>', 'skip']))
        answered = answer_of(state, 'P', repo['path'])
        if answered == 'skip':
            role[repo['path']] = 'skip'
        elif answered:
            dest[repo['path']] = answered
    clone_roles(state, role)
    for folder in state['code_folders']:
        if not folder['covered']:
            where = os.path.join(state['source'], folder['path'])
            evidence = {'folder': where, 'manifests': folder['manifests'], 'entries': entries(where)}
            needs.append(('C', folder['path'], evidence, ['project', 'tool']))
    if all(r is not None for r in role.values()) and all(k != 'P' or answer_of(state, k, s) for k, s, _, _ in needs):
        projects = sorted(set(dest.values()) | set(names.values()) | set(workspace_projects(root)))
        items = list(state['backlog'])
        for repo in state['repos']:
            if role[repo['path']] == 'backlog':
                items += repo.get('markdown', [])
        for item in items:
            evidence = {'file': os.path.join(state['source'], item['path']), 'heading': item['heading']}
            evidence['projects'] = projects
            needs.append(('B', item['path'], evidence, projects + ['workspace']))
    return role, dest, needs, names


def skipped_by_person(state, repos, repo):
    """True when the person skipped a repository (skip), or one that holds it, and did not include it on its own
    (include)."""
    path = repo['path']
    while path:
        if path in state.get('included', []):
            return False
        if path in state.get('skipped', []):
            return True
        path = repos[path]['nested_in']
    return False


def clone_roles(state, role):
    """The role of each work clone from its project's: clone while the project is brought, None while its question
    is open, off otherwise."""
    for repo in state['repos']:
        if repo['kind'] == 'clone':
            primary = role[repo['clone_of']]
            role[repo['path']] = 'clone' if primary == 'project' else (None if primary is None else 'off')


def imported_parent(repo, repos, role, dest):
    """(the nearest repository above that is brought, waiting): waiting while one above has an open question."""
    above = repo['nested_in']
    while above:
        if role[above] is None or (role[above] == 'project' and above not in dest):
            return None, True
        if role[above] == 'project':
            return above, False
        above = repos[above]['nested_in']
    return None, False


def r_evidence(state, repo):
    """The evidence of an R question: where the repository is, its remotes, branches, changes, clones, README."""
    path = os.path.join(state['source'], repo['path'])
    readme = read_text(os.path.join(path, 'README.md'))
    evidence = {
        'repository': path,
        'remotes': repo['remotes'],
        'branch': repo['branch'],
        'branches': [b['name'] for b in repo['branches']],
        'changed_files': len(repo['changes']),
        'clones': [r['path'] for r in state['repos'] if r.get('clone_of') == repo['path']],
        'readme_heading': first_heading(readme) if readme else '',
        'entries': entries(path),
    }
    if repo.get('scratch'):
        where = 'inside a dot folder' if repo['scratch'] == 'dot' else 'in a folder its own repository ignores'
        evidence['scratch'] = f'it sits {where}: scratch of the older workspace, so most likely its data'
    return evidence


def p_evidence(state, repo, parent, parent_dest, taken):
    """The evidence of a P question: the repository, a proposal, the destination of the repository that holds it,
    the destination that is taken."""
    if parent_dest:
        proposal = f'{parent_dest}/{kebab_path(os.path.relpath(repo["path"], parent))}'
    elif repo['in_projects']:
        proposal = kebab_path(repo['path'][len(state['projects_folder']) + 1 :])
    else:
        proposal = kebab(os.path.basename(repo['path']))
    evidence = {'repository': os.path.join(state['source'], repo['path']), 'proposal': proposal}
    evidence['remotes'] = repo['remotes']
    if parent_dest:
        evidence['inside'] = parent_dest
    if taken:
        evidence['taken'] = f'projects/{taken} exists in this workspace'
    return evidence


def kebab_path(rel):
    """A kebab-case path of a relative path, folder by folder."""
    return '/'.join(kebab(part) for part in rel.split('/') if part)


ASK = {
    'R': 'Is this repository a project, data of the older workspace (its prompts, its notes), or its backlog (its '
    'markdown files become backlog items)? "project", "data" or "backlog". None but a project is brought.',
    'P': 'Where in projects/ does it go? A kebab-case path (the proposal, or another), or "skip" (not brought).',
    'C': 'Is this code folder a project (listed with the command to make it a repository) or a tool of the older '
    'workspace? "project" or "tool". Nothing of either is brought.',
    'B': 'Which project is this item about? One of projects, or "workspace" (the older workspace\'s own process: '
    'dropped). A title for its request with --title (default: its heading).',
}


def refresh(state, root):
    """Brings the questions up to date with the answers: creates the ones needed now (ids R-n, P-n, C-n, B-n in
    order), updates their evidence, sets aside (moot) the ones no longer needed, until nothing changes. Returns
    (role, dest, names)."""
    before = None
    while True:
        role, dest, needs, names = resolve(state, root)
        if (role, dest, needs, names) == before:
            return role, dest, names
        before = (role, dest, needs, names)
        wanted = {(kind, subject): (evidence, allowed) for kind, subject, evidence, allowed in needs}
        for question in state['questions']:
            found = wanted.pop((question['kind'], question['subject']), None)
            if found is None:
                question['status'] = 'moot'
                continue
            question['evidence'], question['allowed'] = found
            question['status'] = 'answered' if question.get('answer') else 'open'
        for kind, subject, _, _ in needs:
            if (kind, subject) in wanted:
                evidence, allowed = wanted.pop((kind, subject))
                number = 1 + max([int(q['id'][2:]) for q in state['questions'] if q['kind'] == kind] or [0])
                state['questions'].append(
                    {
                        'id': f'{kind}-{number}', 'kind': kind, 'subject': subject, 'evidence': evidence,
                        'allowed': allowed, 'ask': ASK[kind], 'status': 'open', 'answer': None,
                    }
                )  # fmt: skip


def open_questions(state):
    """The questions still open, in the order they were asked."""
    return [q for q in state['questions'] if q['status'] == 'open']


def answers_key(state):
    """A digest of every answer and project status that counts: a plan holds only for the ones it was written from."""
    data = sorted((q['id'], q['answer'], q.get('title')) for q in state['questions'] if q['status'] == 'answered')
    data += [sorted(state.get('skipped', [])), sorted(state.get('included', []))]
    return hashlib.sha256(json.dumps(data).encode()).hexdigest()


# The state file.


def state_files(root):
    """The import states of custom/migrations/, oldest first."""
    base = os.path.join(root, STATE_DIR)
    names = os.listdir(base) if os.path.isdir(base) else []
    found = [(m.group(1), int(m.group(2) or 1), n) for n in names for m in [STATE_NAME.match(n)] if m]
    return [os.path.join(base, name) for _, _, name in sorted(found)]


def new_state_path(root):
    """custom/migrations/import-<today>.json, or -2, -3... when it exists."""
    day, number = today(), 1
    while True:
        name = f'import-{day}.json' if number == 1 else f'import-{day}-{number}.json'
        path = os.path.join(root, STATE_DIR, name)
        if not os.path.exists(path):
            return path
        number += 1


def load(root, given):
    """(path, state) of the state named by --state, else the latest one; Refused when there is none."""
    path = os.path.abspath(given) if given else (state_files(root) or [None])[-1]
    if not path or not os.path.isfile(path):
        raise Refused('no import state: run scan <folder> first' if not given else f'no state file: {given}')
    try:
        with open(path, encoding='utf-8') as handle:
            state = json.load(handle)
    except (OSError, ValueError) as error:
        raise Refused(f'the state {path} cannot be read: {error}') from error
    return path, state


def save(path, state):
    """Writes the state, replacing the file in one move."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path + '.tmp', 'w', encoding='utf-8') as handle:
        json.dump(state, handle, indent=1, sort_keys=True)
        handle.write('\n')
    os.replace(path + '.tmp', path)


def rel_to(root, path):
    """A path relative to the workspace root."""
    return os.path.relpath(path, root)


# The commands.


def cmd_scan(root, folder):
    """Scans a folder of an older workspace, read only, and writes a new state with its questions."""
    real = os.path.realpath(folder)
    base = os.path.realpath(root)
    if not os.path.isdir(real):
        raise Refused(f'not a folder: {folder}')
    if inside(real, base) or inside(base, real):
        raise Refused(f'{folder} is this workspace, inside it, or holds it: give the folder of the older workspace')
    FILTERS.clear()
    state = inventory(base, real)
    refresh(state, root)
    path = new_state_path(root)
    save(path, state)
    print(f'state: {rel_to(root, path)} (source: {real})')
    print(summary(state))
    if state['moved_from']:
        print(f'attention: copied here from {", ".join(state["moved_from"])}: {MOVED_NOTE}')
    for repo in state['repos']:
        for note in damage_notes(repo):
            print(f'attention: {repo["path"]}: {note}')
    count = len(open_questions(state))
    print(f'questions: {count} open' + (' (questions --json)' if count else '; next: plan'))


def damage_notes(repo):
    """What a repository misses, one note each: refs that point to a missing object, a gone alternates, a status git
    could not read."""
    notes = []
    if repo.get('broken'):
        notes.append(f'{len(repo["broken"])} ref(s) point to a missing object: {", ".join(repo["broken"])}')
    if repo.get('alternates'):
        notes.append(f'its objects/info/alternates names {", ".join(repo["alternates"])}, which is gone')
    if repo.get('unread'):
        notes.append(f'its changed files were not read: {repo["unread"]}')
    return notes


def summary(state):
    """One line with the counts of the inventory."""
    kinds = [r['kind'] for r in state['repos']]
    own = f', {kinds.count("self")} clone(s) of the older workspace itself' if 'self' in kinds else ''
    parts = [
        f'{len(kinds)} repositories ({kinds.count("project")} in the projects folder, {kinds.count("clone")} work '
        f'clone(s), {kinds.count("candidate")} outside it{own})',
        f'{len(state["worktrees"])} worktree(s)',
        f'{len(state["code_folders"])} code folder(s) with no git',
        f'{(state.get("scratch") or {"count": 0})["count"]} scratch folder(s)',
        f'{len(state["backlog"])} backlog item(s)',
        f'{len(state["instructions"])} instruction file(s) or folder(s)',
    ]
    root = '; the older workspace itself is a repository, not brought' if state['root_repo'] else ''
    return 'inventory: ' + ', '.join(parts) + root


def cmd_questions(state, as_json):
    """Prints the open questions."""
    questions = [{key: q[key] for key in ('id', 'kind', 'evidence', 'ask', 'allowed')} for q in open_questions(state)]
    if as_json:
        print(json.dumps(questions, indent=1))
        return
    if not questions:
        print('no open question; next: plan')
    for question in questions:
        print(f'{question["id"]}  {question["ask"]}')
        for key, value in question['evidence'].items():
            print(f'      {key}: {value if isinstance(value, str) else json.dumps(value)}')
        print(f'      allowed: {", ".join(question["allowed"])}')


def cmd_answer(root, state, qid, value, title):
    """Records an answer, validated; clears the plan, which then has to be written again."""
    if any(step['done'] for step in state['steps']):
        raise Refused('apply has started: the plan is fixed; scan again for another import')
    question = next((q for q in state['questions'] if q['id'] == qid and q['status'] != 'moot'), None)
    if question is None:
        raise Refused(f'no question {qid} (questions lists the open ones)')
    if title is not None and question['kind'] != 'B':
        raise Refused('--title is only for a backlog item (B-n)')
    if title is not None and (not title.strip() or len(title) > 120 or '\n' in title):
        raise Refused('the title is one line of 1 to 120 characters')
    if question['kind'] == 'P':
        check_destination(root, state, question, value)
    elif value not in question['allowed']:
        raise Refused(f'{value} is not an answer of {qid}: one of {", ".join(question["allowed"])}')
    question.update(answer=value, status='answered')
    if title is not None:
        question['title'] = title.strip()
    state['steps'], state['plan_key'] = [], None
    refresh(state, root)
    print(f'{qid}: {value}' + (f' ({title.strip()})' if title else ''))
    count = len(open_questions(state))
    print(f'questions: {count} open' if count else 'no open question; next: plan')


def cmd_mark(root, state, target, skip):
    """skip or include a project: recorded in the state; the plan has to be written again."""
    if any(step['done'] for step in state['steps']):
        raise Refused('apply has started: the plan is fixed; scan again for another import')
    role, dest, names = refresh(state, root)
    projects = [r for r in state['repos'] if role[r['path']] in ('project', 'skip')]
    found = next((r for r in projects if target in (r['path'], dest.get(r['path']), names.get(r['path']))), None)
    if found is None:
        listed = ', '.join(dest.get(r['path']) or names.get(r['path']) or r['path'] for r in projects)
        raise Refused(f'{target} is no project of this import: one of {listed}')
    path = found['path']
    skipped, included = state.setdefault('skipped', []), state.setdefault('included', [])
    for listing in (skipped, included):
        if path in listing:
            listing.remove(path)
    if skip:
        skipped.append(path)
    elif skipped_by_person(state, {r['path']: r for r in state['repos']}, found):
        included.append(path)
    state['steps'], state['plan_key'] = [], None
    role, dest, names = refresh(state, root)
    where = dest.get(path) or names.get(path) or path
    print(f'{where}: ' + ('import' if path in dest else 'skip'))
    count = len(open_questions(state))
    print(f'questions: {count} open' if count else 'no open question; next: plan')


def check_destination(root, state, question, value):
    """Refuses a destination that is no kebab-case path, is taken in projects/, or is not inside its parent's."""
    if value == 'skip':
        return
    if not KEBAB.match(value):
        raise Refused(f'{value} is no kebab-case path (lower case words joined by -, folders by /), nor skip')
    if os.path.lexists(os.path.join(root, 'projects', value)):
        raise Refused(f'projects/{value} exists in this workspace: choose another path, or skip')
    inside_of = question['evidence'].get('inside')
    if inside_of and not value.startswith(inside_of + '/'):
        raise Refused(f'{value} is not inside {inside_of}, the destination of the repository that holds it')


def plan_model(root, state):
    """Everything the plan shows and apply runs, from a state with every question answered; Refused when the
    answers do not fit together (two projects in one destination, a backlog item about no project)."""
    role, dest, names = refresh(state, root)
    if open_questions(state):
        raise Refused('questions are open: ' + ', '.join(q['id'] for q in open_questions(state)))
    repos = {r['path']: r for r in state['repos']}
    seen = {}
    for path, where in dest.items():
        if where in seen:
            raise Refused(f'{seen[where]} and {path} both go to projects/{where}: answer their P question again')
        seen[where] = path
    projects = sorted(dest, key=lambda p: depth(dest[p]))
    model = {'projects': [(p, dest[p]) for p in projects], 'branches': [], 'skipped': [], 'pending': {}}
    for path in projects:
        model['branches'] += branch_steps(state, repos, role, path, dest[path], model['skipped'])
        sources = pending_sources(state, repos, role, path)
        if sources:
            model['pending'][dest[path]] = sources
    allowed = set(dest.values()) | set(workspace_projects(root))
    model['backlog'], model['dropped'] = [], []
    for question in [q for q in state['questions'] if q['kind'] == 'B' and q['status'] == 'answered']:
        if question['answer'] == 'workspace':
            model['dropped'].append((question, "the older workspace's own process"))
        elif question['answer'] in set(names.values()) - allowed:
            model['dropped'].append((question, f'its project {question["answer"]} is not imported'))
        elif question['answer'] in allowed:
            model['backlog'].append(question)
        else:
            raise Refused(f'{question["id"]}: {question["answer"]} is no project of this import: answer it again')
    model['role'], model['dest'], model['names'] = role, dest, names
    return model


def taken_names(repo):
    """The local branches a project has once brought: every local branch of its source."""
    return {b['name'] for b in repo.get('branches', [])}


def clashes(taken, name):
    """True when a branch name is taken, or a taken one is a folder of it or it is a folder of a taken one."""
    return any(t == name or t.startswith(name + '/') or name.startswith(t + '/') for t in taken)


def unique_branch(taken, prefix, rest):
    """The first branch name of import/<prefix>[-n][/<rest>] that clashes with no taken one; it is then taken."""
    number = 1
    while True:
        name = f'import/{prefix}' + (f'-{number}' if number > 1 else '') + (f'/{rest}' if rest else '')
        if not clashes(taken, name):
            taken.add(name)
            return name
        number += 1


def branch_steps(state, repos, role, path, where, skipped):
    """The bring-branch steps of a project: a branch per detached worktree of it or of its work clones, and the
    branches of its work clones (a name taken gets import/<clone>/); skipped lists the clone branches it already has
    or that are on the remote."""
    project = repos[path]
    taken = taken_names(project)
    shas = {b['name']: b['sha'] for b in project.get('branches', [])}
    steps = []
    clones = [r for r in state['repos'] if r.get('clone_of') == path and role[r['path']] == 'clone']
    for worktree in [w for w in state['worktrees'] if w['main'] in [path] + [c['path'] for c in clones]]:
        if worktree.get('missing') or worktree.get('orphan') or worktree['branch'] or worktree.get('head_missing'):
            continue
        if worktree.get('moved'):
            # Its .git file names the old path: its HEAD is read through its own git folder.
            if worktree['head']:
                name = unique_branch(taken, worktree['name'], '')
                steps.append(step('branch', worktree['admin'], where, 'HEAD', name, worktree['head'], worktree['path']))
            continue
        name = unique_branch(taken, worktree['name'], '')
        steps.append(step('branch', worktree['path'], where, 'HEAD', name, worktree['head']))
    for clone in clones:
        source = os.path.join(state['source'], clone['path'])
        label = kebab(os.path.basename(clone['path']))
        for branch in clone['branches']:
            if shas.get(branch['name']) == branch['sha'] or not branch['pending']:
                why = 'already in the project' if shas.get(branch['name']) == branch['sha'] else 'on the remote'
                skipped.append((source, branch['name'], why))
                continue
            if clashes(taken, branch['name']):
                name = unique_branch(taken, label, branch['name'])
            else:
                name = branch['name']
                taken.add(name)
            steps.append(step('branch', source, where, f'refs/heads/{branch["name"]}', name, branch['sha']))
        if clone['detached'] and clone['detached']['count']:
            name = unique_branch(taken, label, '')
            steps.append(step('branch', source, where, 'HEAD', name, clone['detached']['sha']))
    return steps


def step(kind, source, where, ref, branch, sha, shown=None):
    """A bring-branch step; shown: the path the person knows the source by, when git reads it elsewhere."""
    found = {'kind': kind, 'source': source, 'dest': where, 'ref': ref, 'branch': branch, 'sha': sha}
    if shown:
        found['shown'] = shown
    return found


def counted(detached):
    """A detached HEAD that is pending work: commits on no branch, or commits git could not count."""
    return detached if detached and (detached['count'] or detached.get('unread')) else None


def pending_sources(state, repos, role, path):
    """The sources of a project with pending work: the repository, its worktrees, its work clones and theirs. A
    repository with no remote at all is pending work as a whole; one with missing objects names them."""
    sources = []
    clones = [r['path'] for r in state['repos'] if r.get('clone_of') == path and role[r['path']] == 'clone']
    for rel in [path] + clones:
        repo = repos[rel]
        what = 'repository' if rel == path else 'work clone'
        no_remote = not repo.get('remotes')
        worktrees = [w for w in state['worktrees'] if w['main'] == rel and not w.get('missing') and not w.get('orphan')]
        # The branch of a worktree is shown with the worktree; with no remote, the whole repository is unpushed.
        branches = [b for b in repo['branches'] if b['pending'] and b['name'] not in {w['branch'] for w in worktrees}]
        branches = [] if no_remote else branches
        detached = counted(repo['detached'])
        damage = {key: repo[key] for key in ('broken', 'alternates', 'unread') if repo.get(key)}
        if repo['changes'] or branches or repo['stashes'] or detached or damage or no_remote:
            source = {
                'path': os.path.join(state['source'], rel), 'what': what, 'branch': repo['branch'],
                'head': repo['head'], 'changes': repo['changes'], 'branches': branches, 'stashes': repo['stashes'],
                'detached': detached, **damage,
            }  # fmt: skip
            if no_remote:
                source['no_remote'] = [b['name'] for b in repo['branches']]
            sources.append(source)
        main_branches = {b['name']: b for b in repo['branches']}
        for worktree in worktrees:
            mine = main_branches.get(worktree['branch'])
            branches = [mine] if mine and mine['pending'] and not no_remote else []
            detached = counted(worktree['detached'])
            moved = ', moved with the older workspace' if worktree.get('moved') else ''
            if worktree['changes'] or branches or detached or worktree.get('unread'):
                sources.append(
                    {
                        'path': worktree['path'], 'what': f'worktree of {os.path.join(state["source"], rel)}{moved}',
                        'branch': worktree['branch'], 'head': worktree['head'], 'changes': worktree['changes'],
                        'branches': branches, 'stashes': 0, 'detached': detached,
                        'unread': worktree.get('unread') and 'git could not read its files',
                        'head_missing': worktree.get('head_missing'),
                    }
                )  # fmt: skip
        for worktree in [w for w in state['worktrees'] if w['main'] == rel and w.get('orphan')]:
            sources.append({'path': worktree['path'], 'what': 'orphan worktree', 'orphan': True})
    return sources


def source_lines(source, brought):
    """The markdown lines of one source with pending work."""
    if source.get('orphan'):
        return [
            f'- {code(source["path"])} (orphan worktree): its repository no longer tracks it; only its files are '
            'left, compare them by hand'
        ]
    if source['branch']:
        head = f'branch {code(source["branch"])}'
    else:
        head = f'detached at {code(source["head"][:12])}' if source['head'] else 'HEAD unknown'
    lines = [f'- {code(source["path"])} ({source["what"]}), {head}']
    if source.get('no_remote') is not None:
        names = ', '.join(code(n) for n in source['no_remote'][:MAX_ENTRIES])
        more = len(source['no_remote']) - MAX_ENTRIES
        lines.append(
            '  - No remote: the whole repository is unpushed work; every local branch is brought as it is'
            + (f': {names}' if names else '')
            + (f' and {more} more' if more > 0 else '')
        )
    if source.get('unread'):
        lines.append(f'  - Changed files: not read ({source["unread"]})')
    if source['changes']:
        names = ', '.join(code(c) for c in source['changes'][:MAX_FILES])
        more = len(source['changes']) - MAX_FILES
        lines.append(f'  - Changed files: {names}' + (f' and {more} more' if more > 0 else ''))
    if source.get('broken'):
        refs = ', '.join(code(r) for r in source['broken'])
        lines.append(f'  - Refs that point to a missing object, not brought: {refs}')
    if source.get('alternates'):
        lines.append(
            f'  - Its objects/info/alternates names {", ".join(code(a) for a in source["alternates"])}, which is gone: '
            'the objects it borrowed from there are missing (a clone made with --shared or --reference); only the '
            'branches whose objects are complete can be brought'
        )
    for branch in source['branches']:
        upstream = branch['upstream'].replace('refs/remotes/', '')
        how = 'no upstream' if not upstream else ('its upstream is gone' if branch['gone'] else f'ahead of {upstream}')
        if branch.get('upstream_broken'):
            how = f'its upstream {upstream} points to a missing object'
        count = branch.get('count', 0)
        pushed = f'{count} commit(s) not pushed' if count else 'every commit of it is on a remote'
        if count is None:
            pushed = 'a missing object in its history: its commits could not be counted'
        lines.append(f'  - Branch {code(branch["name"])}: {how}, {pushed}')
        lines += [f'    - {code(c)}' for c in branch['commits']]
    if source.get('head_missing'):
        lines.append('  - Detached HEAD: it points to a missing object; it cannot be brought')
    elif source['detached'] and source['detached']['count'] is None:
        lines.append('  - Detached HEAD: a missing object in its history: its commits could not be counted')
    elif source['detached']:
        lines.append(f'  - Detached HEAD: {source["detached"]["count"]} commit(s) on no branch and no remote')
        lines += [f'    - {code(c)}' for c in source['detached']['commits']]
    if source['stashes']:
        lines.append(f'  - Stashes: {source["stashes"]} (not brought: they stay in the source)')
    for name in brought.get(source['path'], []):
        lines.append(f'  - Brought into the project as the branch {code(name)}')
    return lines


def brought_by_source(model):
    """{source path: [branch names]} of the bring-branch steps."""
    return brought_of(model['branches'])


def brought_of(steps):
    """{source path as the person knows it: [branch names]} of bring-branch steps, but those not brought."""
    found = {}
    for item in steps:
        if not item.get('missing'):
            found.setdefault(item.get('shown', item['source']), []).append(item['branch'])
    return found


def render_plan(root, state, path, model):
    """The markdown of the plan."""
    source = state['source']
    out = [
        f'# Import of {os.path.basename(source)}',
        '',
        f'**Source:** {code(source)}',
        '',
        f'**State:** {code(rel_to(root, path))}',
        '',
    ]
    if state.get('moved_from'):
        out += [f'**Moved:** copied here from {", ".join(code(p) for p in state["moved_from"])}: {MOVED_NOTE}.', '']
    out += [
        'Nothing is written until `python3 -I -B scripts/workspace-import.py apply --yes`. To change a row, answer its '
        'question again (`answer <id> <value>`), then `plan`. Nothing is pushed: the projects keep the remotes of '
        'their sources, and `custom/` is committed by path.',
        '',
        '## Projects',
        '',
        'Each project is brought (`import`) unless the person skips it: `skip <project>`, `include <project>` (a '
        'repository inside a skipped one is skipped with it, unless included on its own), then `plan` again.',
        '',
    ]
    out += project_rows(state, model)
    out += ['', '## Branches of worktrees and work clones', '']
    if model['branches']:
        out += ['| Source | Ref | Into | As |', '| --- | --- | --- | --- |']
        for item in model['branches']:
            out.append(
                f'| {code(item["source"])} | {code(item["ref"])} | {code("projects/" + item["dest"])} '
                f'| {code(item["branch"])} |'
            )
    else:
        out.append('None.')
    out += ['', 'The branch of a worktree comes with its repository.']
    if model['skipped']:
        out += ['', 'Branches of work clones not brought:', '']
        out += [f'- {code(s)}: {code(b)}, {why}' for s, b, why in model['skipped']]
    out += ['', '## Pending work', '']
    brought = brought_by_source(model)
    for where, sources in sorted(model['pending'].items()):
        out += [f'### {where}: {code(pending_name(where))}', '']
        for source_ in sources:
            out += source_lines(source_, brought)
        out.append('')
    if not model['pending']:
        out += ['None.', '']
    out += ['## Backlog', '']
    if model['backlog']:
        out += ['| Item | Project | Title |', '| --- | --- | --- |']
        for question in model['backlog']:
            title = question.get('title') or question['evidence']['heading'] or 'untitled'
            out.append(f'| {code(question["evidence"]["file"])} | {question["answer"]} | {title} |')
    else:
        out.append('None.')
    if model['dropped']:
        out += ['', 'Dropped:', '']
        for question, why in model['dropped']:
            heading = question['evidence']['heading'] or 'untitled'
            out.append(f'- {code(question["evidence"]["file"])}: {heading} ({why})')
    out += ['', '## Not imported, for reference', '']
    out += not_imported(state, model)
    return '\n'.join(out).rstrip('\n') + '\n'


def human_size(count):
    """A size in bytes, readable: B, KB, MB, GB, TB."""
    size, unit = float(count), 'B'
    for unit in ('B', 'KB', 'MB', 'GB', 'TB'):
        if size < 1024 or unit == 'TB':
            break
        size /= 1024
    return f'{int(size)} B' if unit == 'B' else f'{size:.1f} {unit}'


def project_rows(state, model):
    """The table of every project with its destination, remote, size and status (import or skip)."""
    role, dest, names = model['role'], model['dest'], model['names']
    repos = sorted(state['repos'], key=lambda r: depth(r['path']))
    repos = [r for r in repos if role[r['path']] in ('project', 'skip')]
    if not repos:
        return ['None.']
    rows = ['| Source | Destination | Remote | Files | .git | Status |', '| --- | --- | --- | --- | --- | --- |']
    by_path = {r['path']: r for r in state['repos']}
    for repo in repos:
        path = repo['path']
        where = dest.get(path) or names.get(path)
        status = 'import' if path in dest else 'skip'
        above = repo['nested_in']
        while above and status == 'import':
            if role[above] == 'skip':
                status = f'import (its parent {os.path.join(state["source"], above)} is not imported)'
                break
            above = by_path[above]['nested_in']
        size = repo.get('size', {})
        rows.append(
            f'| {code(os.path.join(state["source"], path))} | {code("projects/" + where) if where else "—"} '
            f'| {code(repo["remotes"].get("origin", "none"))} | {human_size(size.get("files", 0))} '
            f'| {human_size(size.get("git", 0))} | {status} |'
        )
    return rows


def not_imported(state, model):
    """The lines of what is not imported: the older workspace itself, data repositories, instruction files, code
    folders with no git, other .git files."""
    source, role = state['source'], model['role']
    lines = []
    if state['root_repo']:
        lines.append(f'- {code(source)}: the older workspace itself, a repository; not a project')
    lines += root_worktree_lines(state)
    for repo in state['repos']:
        origin = repo.get('remotes', {}).get('origin', '')
        why = {
            'self': f'a clone of the older workspace itself (origin {code(origin)}): its own work, not a project',
            'data': 'data of the older workspace',
            'backlog': 'the backlog of the older workspace: its markdown files are the backlog items above',
            'skip': 'a project not imported (skip)',
            'off': f'a work clone of {code(os.path.join(source, repo.get("clone_of", "")))}, which is not imported',
            'unreadable': 'git could not read it',
        }.get(role[repo['path']])
        if why:
            lines.append(f'- {code(os.path.join(source, repo["path"]))}: {why}')
    for worktree in state['worktrees']:
        if role.get(worktree['main']) not in ('project', 'clone'):
            main = os.path.join(source, worktree['main'])
            kind = 'an orphan worktree' if worktree.get('orphan') else 'a worktree'
            lines.append(f'- {code(worktree["path"])}: {kind} of {code(main)}, which is not imported')
    scratch = state.get('scratch') or {'count': 0}
    if scratch['count']:
        tops = ', '.join(code(top) for top in scratch['tops'])
        lines.append(f'- Scratch of the older workspace: {scratch["count"]} code folder(s) with no git under {tops}')
    answers = {q['subject']: q['answer'] for q in state['questions'] if q['kind'] == 'C' and q['status'] == 'answered'}
    for folder in state['code_folders']:
        where = os.path.join(source, folder['path'])
        if folder['covered']:
            how = 'its name' if folder['how'] == 'name' else 'most of its files'
            lines.append(f'- {code(where)}: covered by `tools/{folder["covered"]}` of this workspace ({how})')
        elif answers.get(folder['path']) == 'tool':
            lines.append(f'- {code(where)}: a tool of the older workspace')
        else:
            lines.append(
                f'- {code(where)}: a project with no git. To bring it, make it a repository with its remote: '
                f'`git -C {where} init -b main && git -C {where} remote add origin <remote-url>`, commit what belongs '
                f'(never a .env or a key) and push, then `bash scripts/aiwp-cmds.sh bring {where} <path>`'
            )
        if folder.get('instructions'):
            names = ', '.join(code(i[len(folder['path']) + 1 :]) for i in folder['instructions'])
            lines.append(f'  - its own instruction files, part of it: {names}')
    lines += [
        f'- {code(os.path.join(source, i))}: an instruction file of the older workspace' for i in state['instructions']
    ]
    lines += [
        f'- {code(os.path.join(source, g))}: a .git file of no repository of the folder (a submodule, or a worktree '
        'of a repository outside it)'
        for g in state['other_git_files']
    ]
    return lines or ['Nothing.']


def root_worktree_lines(state):
    """One line for the worktrees of the older workspace itself: their count and the folders they live under."""
    paths = state['root_worktrees']
    if not paths:
        return []
    source = state['source']
    here = [os.path.relpath(p, source) for p in paths if inside(os.path.normpath(p), source)]
    folders = sorted({(os.path.dirname(rel) or '.') + '/' for rel in here})
    shown = ', '.join(code(f) for f in folders[:MAX_ENTRIES]) + (' and others' if len(folders) > MAX_ENTRIES else '')
    gone = len(paths) - len(here)
    line = f'- {len(paths)} worktree(s) of the older workspace itself'
    line += f', under {shown}' if here else ''
    line += ': its own work, not projects'
    return [line + (f'; {gone} of them no longer there' if gone else '')]


def pending_name(where):
    """The file name of the pending-work request of a project, before the date and the suffix."""
    return f'custom/requests/<date>-{where.replace("/", "-")}-pending-work.md'


def plan_steps(model):
    """The steps of apply, in order."""
    steps = [{'kind': 'bring', 'repo': rel, 'dest': where} for rel, where in model['projects']]
    steps += model['branches']
    if model['backlog']:
        steps.append({'kind': 'secrets'})
    steps += [{'kind': 'pending', 'dest': where} for where in sorted(model['pending'])]
    steps += [{'kind': 'backlog', 'question': q['id']} for q in model['backlog']]
    steps.append({'kind': 'commit'})
    for item in steps:
        item.update(done=False, result='')
    return steps


def cmd_plan(root, path, state):
    """Writes the plan and records its steps."""
    model = plan_model(root, state)
    state['steps'] = plan_steps(model)
    state['pending_sources'] = model['pending']
    state['plan_key'] = answers_key(state)
    plan = path[: -len('.json')] + '.md'
    with open(plan, 'w', encoding='utf-8') as handle:
        handle.write(render_plan(root, state, path, model))
    state['plan'] = rel_to(root, plan)
    save(path, state)
    print(f'plan: {rel_to(root, plan)}')
    print(
        f'{len(model["projects"])} project(s) to bring, {len(model["branches"])} branch(es) of worktrees and work '
        f'clones, {len(model["pending"])} pending-work request(s), {len(model["backlog"])} backlog request(s), '
        f'{len(model["dropped"])} item(s) dropped'
    )
    print('next: show the plan to the person; once confirmed, apply --yes')


def cmd_status(root, path, state):
    """Prints where the import is."""
    print(f'state: {rel_to(root, path)} (source: {state["source"]})')
    print(summary(state))
    questions = state['questions']
    open_ = [q['id'] for q in questions if q['status'] == 'open']
    answered = sum(q['status'] == 'answered' for q in questions)
    print(f'questions: {len(open_)} open' + (f' ({", ".join(open_)})' if open_ else '') + f', {answered} answered')
    role = resolve(state, root)[0]
    print(f'projects: {list(role.values()).count("project")} import, {list(role.values()).count("skip")} skip')
    if not state['steps']:
        print('plan: not written' + ('' if open_ else '; next: plan'))
        return
    stale = state['plan_key'] != answers_key(state)
    print(f'plan: {state.get("plan")}' + (' (stale: the answers changed; run plan)' if stale else ''))
    done = sum(s['done'] for s in state['steps'])
    print(f'apply: {done} of {len(state["steps"])} steps done')
    left = next((s for s in state['steps'] if not s['done']), None)
    if left:
        print(f'next step: {describe(left)}' + (f' (failed: {left["error"]})' if left.get('error') else ''))


def describe(item):
    """One line naming a step."""
    kind = item['kind']
    if kind == 'bring':
        return f'bring {item["repo"]} into projects/{item["dest"]}'
    if kind == 'branch':
        return f'bring-branch {item["ref"]} of {item["source"]} into projects/{item["dest"]} as {item["branch"]}'
    if kind == 'pending':
        return f'the pending-work request of {item["dest"]}'
    if kind == 'backlog':
        return f'the request of the backlog item {item["question"]}'
    return {'secrets': 'the secret scan of the backlog items kept', 'commit': 'the commit of custom/'}[kind]


# apply


def cmd_apply(root, path, state, yes):
    """Runs the steps not done yet, in order, recording each; stops at the first failure."""
    if not yes:
        raise Refused('apply runs only with --yes, once the person confirmed the plan')
    if open_questions(state):
        raise Refused('questions are open: ' + ', '.join(q['id'] for q in open_questions(state)))
    if not state['steps'] or state['plan_key'] != answers_key(state):
        raise Refused('no plan for the current answers: run plan, show it to the person, then apply --yes')
    if not os.path.isdir(state['source']):
        raise Refused(f'the source is gone: {state["source"]}')
    runner = Apply(root, path, state)
    for item in state['steps']:
        if item['done']:
            continue
        try:
            item['result'] = runner.run(item)
        except StepFailed as error:
            item['error'] = str(error)
            save(path, state)
            done = sum(s['done'] for s in state['steps'])
            print(f'failed: {describe(item)}: {error}', file=sys.stderr)
            print(f'{done} of {len(state["steps"])} steps done; apply --yes again resumes from this step')
            return 1
        item.update(done=True, error=None)
        save(path, state)
        print(f'done: {describe(item)}' + (f': {item["result"]}' if item['result'] else ''))
    print(f'import applied: {len(state["steps"])} steps; nothing was pushed')
    return 0


class Apply:
    """Runs the steps of apply in a workspace."""

    def __init__(self, root, path, state):
        """Keeps the workspace root, the state and its path."""
        self.root, self.path, self.state = root, path, state
        self.repos = {r['path']: r for r in state['repos']}

    def run(self, item):
        """Runs one step; returns its result line, or raises StepFailed."""
        return getattr(self, 'step_' + item['kind'])(item)

    def script(self, *args):
        """Runs a workspace script from the root; its output is printed; StepFailed when it fails."""
        result = run(['bash', *args], cwd=self.root)
        text = (result.stdout + result.stderr).strip()
        if text:
            print(text)
        if result.returncode != 0:
            raise StepFailed((text.splitlines() or [f'exit {result.returncode}'])[-1])
        return text

    def ref_sha(self, where, ref):
        """The sha of a ref of a repository of this workspace's projects/, or None."""
        found = run(['git', '-C', os.path.join(self.root, 'projects', where), 'rev-parse', '-q', '--verify', ref])
        return found.stdout.strip() if found.returncode == 0 else None

    def step_bring(self, item):
        """bring of one repository; one already there with every branch of its source is taken as done."""
        repo = self.repos[item['repo']]
        dest = os.path.join(self.root, 'projects', item['dest'])
        if os.path.isdir(os.path.join(dest, '.git')):
            if all(self.ref_sha(item['dest'], f'refs/heads/{b["name"]}') == b['sha'] for b in repo['branches']):
                return f'projects/{item["dest"]} was already brought'
            raise StepFailed(f'projects/{item["dest"]} exists without the branches of its source: tell the person')
        try:
            self.script('scripts/aiwp-cmds.sh', 'bring', os.path.join(self.state['source'], item['repo']), item['dest'])
        except StepFailed as error:
            # Nothing of it complete (bring left nothing): the rest of the import goes on; its request says so.
            if 'missing object' not in str(error):
                raise
            reason = re.sub(r'^error: ', '', str(error))
            self.state.setdefault('not_brought', {})[item['dest']] = reason
            return f'not brought: {reason}'
        return f'projects/{item["dest"]}'

    def step_branch(self, item):
        """bring-branch of one branch; one already there at its sha is taken as done; one with a missing object, or
        of a project not brought, is recorded as not brought and the import goes on."""
        if item['dest'] in self.state.get('not_brought', {}):
            item['missing'] = f'its project projects/{item["dest"]} was not brought'
            return f'not brought: {item["missing"]}'
        have = self.ref_sha(item['dest'], f'refs/heads/{item["branch"]}')
        if have == item['sha']:
            return f'{item["branch"]} was already in projects/{item["dest"]}'
        try:
            self.script(
                'scripts/aiwp-cmds.sh', 'bring-branch', item['source'], item['dest'], item['ref'], item['branch']
            )
        except StepFailed as error:
            if 'missing object' not in str(error):
                raise
            item['missing'] = re.sub(r'^error: ', '', str(error))
            return f'not brought: {item["missing"]}'
        return f'{item["branch"]} in projects/{item["dest"]}'

    def kept_items(self):
        """The backlog questions whose item becomes a request."""
        ids = {s['question'] for s in self.state['steps'] if s['kind'] == 'backlog'}
        return [q for q in self.state['questions'] if q['id'] in ids]

    def step_secrets(self, item):
        """The secret scan of each backlog item kept: its name, the core's patterns, then scripts/validate.sh
        --only secrets (gitleaks and trivy) on a copy under tmp/; a hit, or an item not read, keeps only its path."""
        found, clean = {}, []
        for question in self.kept_items():
            text = read_text(question['evidence']['file'])
            if secret_name(os.path.basename(question['evidence']['file'])):
                found[question['id']] = 'secret'
            elif text is None:
                found[question['id']] = 'unread'
            elif has_secret(text):
                found[question['id']] = 'secret'
            else:
                clean.append((question['id'], text))
        work = os.path.join(self.root, 'tmp', 'import-' + os.path.basename(self.path)[: -len('.json')])
        shutil.rmtree(work, ignore_errors=True)
        try:
            for qid in self.scan_copies(work, clean):
                found[qid] = 'secret'
        finally:
            shutil.rmtree(work, ignore_errors=True)
        self.state['secrets'] = found
        return f'{len(found)} item(s) keep only their source path' if found else 'no secret found'

    def scan_copies(self, work, items):
        """The ids of the items scripts/validate.sh finds a secret in: all at once, then one by one when it fails."""
        if not items:
            return []
        os.makedirs(work, exist_ok=True)
        names = []
        for qid, text in items:
            with open(os.path.join(work, qid + '.md'), 'w', encoding='utf-8') as handle:
                handle.write(text)
            names.append((qid, rel_to(self.root, os.path.join(work, qid + '.md'))))
        if self.validate(work, [n for _, n in names]):
            return []
        return [qid for qid, name in names if not self.validate(work, [name])]

    def validate(self, work, names):
        """True when scripts/validate.sh --only secrets passes on the files; StepFailed when it cannot run."""
        listing = os.path.join(work, 'files.txt')
        with open(listing, 'w', encoding='utf-8') as handle:
            handle.write('\n'.join(names) + '\n')
        result = run(
            ['bash', 'scripts/validate.sh', '--path', rel_to(self.root, work), '--only', 'secrets', '--files', listing],
            cwd=self.root,
        )
        output = result.stdout + result.stderr
        if result.returncode == 0:
            return True
        if result.returncode == 1 and 'FAIL secrets' in output:
            return False
        last = (output.strip().splitlines() or [f'exit {result.returncode}'])[-1]
        raise StepFailed(f'the secret scan could not run (scripts/validate.sh: {last}); is Docker up?')

    def write_request(self, name, text):
        """Writes a request in custom/requests/, never over another one (-2, -3...); returns its path."""
        base = os.path.join(self.root, REQUESTS)
        os.makedirs(base, exist_ok=True)
        number = 1
        while True:
            path = os.path.join(base, f'{name}.md' if number == 1 else f'{name}-{number}.md')
            if not os.path.exists(path):
                break
            number += 1
        with open(path, 'w', encoding='utf-8') as handle:
            handle.write(text)
        self.state.setdefault('written', []).append(rel_to(self.root, path))
        return rel_to(self.root, path)

    def step_pending(self, item):
        """The pending-work request of a project."""
        where = item['dest']
        steps = [other for other in self.state['steps'] if other['kind'] == 'branch' and other['dest'] == where]
        brought = brought_of(steps)
        lines = [
            f'# Pending work of {where} from an older workspace',
            '',
            f'**Project:** {where}',
            '',
            '**State:** ready',
            '',
            'Adjustment.',
            '',
            '**What:** the work in progress an older workspace left for this project: finish it, move it to a request '
            'of its own, or drop it. Compare each with the base when you work on it.',
            '',
            '**Where:**',
            '',
        ]
        for source in self.state['pending_sources'][where]:
            lines += source_lines(source, brought)
        for other in [s for s in steps if s.get('missing')]:
            lines.append(
                f'- Not brought: {code(other["ref"])} of {code(other.get("shown", other["source"]))} as '
                f'{code(other["branch"])}: {other["missing"]}'
            )
        not_brought = self.state.get('not_brought', {}).get(where)
        if not_brought:
            held = f'`projects/{where}` was not brought: {not_brought}. Everything above is only in the source.'
        else:
            held = (
                f'`projects/{where}` holds every local branch of its source whose objects are complete, and the '
                'branches named above. Changed files and stashes were not copied: they are only in the source.'
            )
        lines += [
            '',
            held,
            '',
            '**Done when:** each item above is merged, in a request of its own, or dropped by the person.',
            '',
            '**Effort:** medium; it depends on each item.',
            '',
        ]
        return self.write_request(f'{today()}-{where.replace("/", "-")}-pending-work', '\n'.join(lines))

    def step_backlog(self, item):
        """The request of a backlog item kept: state idea, its project, the original text under Requested."""
        question = next(q for q in self.state['questions'] if q['id'] == item['question'])
        file = question['evidence']['file']
        title = question.get('title') or question['evidence']['heading'] or os.path.splitext(os.path.basename(file))[0]
        hit = self.state.get('secrets', {}).get(question['id'])
        text = None if hit else read_text(file)
        if hit == 'secret':
            body = SECRET_NOTE
        elif text is None:
            body = UNREAD_NOTE
        else:
            body = text.rstrip('\n')
        lines = [f'# {title}', '', f'**Project:** {question["answer"]}', '', '**State:** idea', '', '## Requested', '']
        lines += [f'Imported from {code(file)} of an older workspace.', '', body]
        slug = kebab(title)[:60].strip('-') or 'item'
        return self.write_request(f'{today()}-{slug}', '\n'.join(lines).rstrip('\n') + '\n')

    def step_commit(self, item):
        """One commit of custom/ by path: the requests, the plan and the state; never pushed."""
        custom = os.path.join(self.root, 'custom')
        top = run(['git', '-C', custom, 'rev-parse', '--show-toplevel'])
        if top.returncode != 0 or os.path.realpath(top.stdout.strip()) != os.path.realpath(custom):
            return 'custom/ is no git repository: nothing committed'
        paths = [os.path.relpath(os.path.join(self.root, p), custom) for p in self.state.get('written', [])]
        paths += [os.path.relpath(self.path, custom)]
        if self.state.get('plan'):
            paths.append(os.path.relpath(os.path.join(self.root, self.state['plan']), custom))
        result = f'custom/ committed ({len(paths)} file(s)), not pushed'
        item.update(done=True, result=result, error=None)
        save(self.path, self.state)
        message = (
            'docs(requests): import the work of an older workspace\n\n'
            f'- {len(self.state.get("written", []))} request(s) of its pending work and backlog, and the import plan '
            f'of {os.path.basename(self.state["source"])} (scripts/workspace-import.py)\n\n'
            '[#automatic-agent-commit]\n'
        )
        committed = run(['git', '-C', custom, 'add', '--', *paths])
        if committed.returncode == 0:
            committed = run(['git', '-C', custom, 'commit', '-q', '-F', '-', '--', *paths], stdin=message)
        if committed.returncode != 0:
            item.update(done=False, result='')
            save(self.path, self.state)
            last = ((committed.stdout + committed.stderr).strip().splitlines() or ['git failed'])[-1]
            raise StepFailed(f'the commit of custom/ failed: {last}')
        return result


def parse_args(argv):
    """The parsed command line."""
    parser = argparse.ArgumentParser(
        prog='workspace-import.py',
        description=__doc__.split('\n\n', 1)[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__.split('\n\n', 1)[1],
    )
    parser.add_argument('--state', help='the state file (default: the latest custom/migrations/import-*.json)')
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('scan').add_argument('folder')
    commands.add_parser('questions').add_argument('--json', action='store_true')
    answer = commands.add_parser('answer')
    answer.add_argument('id')
    answer.add_argument('value')
    answer.add_argument('--title')
    for name in ('skip', 'include'):
        commands.add_parser(name).add_argument('project')
    commands.add_parser('plan')
    commands.add_parser('apply').add_argument('--yes', action='store_true')
    commands.add_parser('status')
    return parser.parse_args(argv)


def main(argv=None, root=ROOT):
    """Runs one command; returns the exit code."""
    args = parse_args(argv)
    try:
        if args.command == 'scan':
            cmd_scan(root, args.folder)
            return 0
        path, state = load(root, args.state)
        if args.command == 'questions':
            cmd_questions(state, args.json)
        elif args.command == 'answer':
            cmd_answer(root, state, args.id, args.value, args.title)
            save(path, state)
        elif args.command in ('skip', 'include'):
            cmd_mark(root, state, args.project, args.command == 'skip')
            save(path, state)
        elif args.command == 'plan':
            cmd_plan(root, path, state)
        elif args.command == 'apply':
            return cmd_apply(root, path, state, args.yes)
        else:
            cmd_status(root, path, state)
        return 0
    except Refused as error:
        print(f'refused: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
