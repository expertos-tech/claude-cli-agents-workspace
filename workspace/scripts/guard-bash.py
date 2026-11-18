"""Decision logic of scripts/guard-bash.sh (PreToolUse hook, matcher Bash).

Reads the hook JSON on stdin and prints a decision JSON, or nothing (the command follows the normal permission flow).
It asks the human before a command that destroys data, rewrites history, moves a branch by force or reaches a remote,
in the spellings scripts/guard-bash.sh --help lists (git -C <dir>, wrappers, shell keywords, bash -c, command
substitution, ssh, heredocs), and it refuses a commit that carries a local secret file or a secret gitleaks finds.
In an installed workspace it refuses chmod, chown, chgrp, git init and git clone that reach the read-only core, and
denies aiwp update, rollback, repair, forget and the opening (aiwp, aiwp -- ...) inside a session. It denies a way
around the person's merge order: changing CLAUDECODE or CLAUDE_CODE_SESSION_ID, writing .history/merge-orders/,
running scripts/session-title.py. It asks before deleting, moving or emptying Grafana's data (tools/observability/
.data) and before aiwp-cmds.sh deploy. What it cannot read, it asks about. A line it would ask about that holds other
top-level commands too is denied instead ("Run it alone:"), so the question shows only the command it asks about; a
leading cd or assignment travels with it.
It allows, with no question, a line it can tell stays in one clone of tmp/work/<yyyy-mm-dd>-<slug>/<clone>/: every
command runs there, every path it names (arguments and redirections, links resolved) stays there out of its .git and
is no local secret file, nothing deletes that .git, and none reaches a remote system (a push, a publish, a deploy, ssh,
curl, a cloud or cluster CLI, a global install). Docker only in the task's own group (agent_<MMDD>-<slug>[--<clone>]:
an allowlist of docker compose subcommands, no up or build, exec only into a container on isolated networks, resources
told by their compose label), where deleting a volume or a database asks nothing. SQL clients on the
host and the workspace scripts are never allowed by it. Every deny and ask comes first; what it cannot tell stays
silent.
A speed bump with the human's confirmation behind it, not a sandbox: text a shell builds at run time is not seen.
Usage: python3 -I -B guard-bash.py <workspace-root>
"""

import fnmatch
import glob
import itertools
import json
import os
import re
import shlex
import signal
import subprocess
import sys
import tempfile

ASSIGNMENT = re.compile(r'[A-Za-z_][A-Za-z0-9_]*=')
VARIABLE = re.compile(r'\$(?:\{([A-Za-z_]\w*)\}|([A-Za-z_]\w*))')
# Shell words that open and close a compound command, whose inner commands make one top-level command.
OPENERS = {'if', 'for', 'while', 'until', 'case', 'select', '{'}
COMPOUND_CLOSERS = {'fi', 'done', 'esac', '}'}
# Shell words that only introduce the command that follows them.
KEYWORDS = {'if', 'then', 'elif', 'else', 'do', 'while', 'until', '!', '{', '}', 'function', 'coproc'}
# Wrappers that run the command that follows them; the value is the number of their own leading words to drop.
WRAPPERS = {
    'sudo': 0, 'doas': 0, 'command': 0, 'builtin': 0, 'exec': 0, 'nohup': 0, 'nice': 0, 'ionice': 0, 'env': 0,
    'stdbuf': 0, 'setsid': 0, 'timeout': 1, 'xargs': 0, 'watch': 0, 'flock': 1, 'time': 0, 'busybox': 0, 'noglob': 0,
    'nocorrect': 0, 'parallel': 0, 'sshpass': 0, 'caffeinate': 0, 'unbuffer': 0, 'gosu': 1,
}  # fmt: skip
# Options of those wrappers that take the next word as their value.
WRAPPER_VALUE_OPTIONS = {
    'xargs': {
        '-I', '-n', '-P', '-L', '-d', '-E', '-s', '-a', '--max-args', '--max-procs', '--max-lines', '--delimiter',
        '--arg-file', '--max-chars', '--eof',
    },
    'timeout': {'-k', '-s', '--kill-after', '--signal'},
    'env': {'-u', '-C', '-S', '--unset', '--chdir', '--split-string'},
    'nice': {'-n', '--adjustment'},
    'ionice': {'-c', '-n', '-p'},
    'sudo': {
        '-u', '-g', '-C', '-h', '-p', '-D', '-R', '-r', '-t', '-T', '-U', '--user', '--group', '--chdir', '--host',
        '--prompt', '--chroot',
    },
    'doas': {'-u', '-C'},
    'exec': {'-a'},
    'watch': {'-n', '-d', '--interval'},
    'flock': {'-w', '-E', '--timeout'},
    'stdbuf': {'-i', '-o', '-e'},
    'parallel': {'-j', '--jobs'},
    'sshpass': {'-p', '-f', '-P'},
    'caffeinate': {'-t', '-w'},
}  # fmt: skip
SHELLS = {'bash', 'sh', 'zsh', 'dash', 'ksh', 'fish', 'ash'}
SQL_CLIENTS = {'psql', 'mysql', 'mariadb', 'sqlite3', 'sqlcmd', 'mongosh', 'duckdb'}
# Programs whose arguments hold a command that runs elsewhere (another host, another user, under a lock).
LAUNCHERS = {'ssh', 'su', 'nsenter', 'chroot', 'heavy-run.sh'}
# Programs that run the command given after their own words, in a prepared environment.
RUNNERS = {'uv', 'poetry', 'pipenv', 'npx', 'bunx', 'op', 'aws-vault', 'doppler', 'direnv', 'mise', 'dotenvx'}
# Programs that take the command lines of docker.
DOCKERS = {'docker', 'podman', 'nerdctl'}
GUARDED = {
    'git', 'rm', 'docker-compose', 'terraform', 'tofu', 'aiwp-cmds.sh', 'aiwp-gate.sh', 'aiwp', 'aiwp.sh',
    'dropdb', 'mysqladmin', 'dotnet', 'prisma', 'rails', 'rake', 'chmod', 'chown', 'chgrp',
} | SQL_CLIENTS | DOCKERS  # fmt: skip
GUARDED_WORD = re.compile(r'(?<![\w.-])(' + '|'.join(re.escape(word) for word in sorted(GUARDED)) + r')(?![\w-])')
HELP_OPTIONS = {'--help', '-help', '--version'}
GIT_VALUE_OPTIONS = {
    '-C', '-c', '--git-dir', '--work-tree', '--namespace', '--exec-path', '--config-env', '--super-prefix',
}  # fmt: skip
# Options of git branch and git tag whose value is not an option, whatever it looks like (--sort -committerdate).
BRANCH_VALUE_OPTIONS = {'--sort', '--format', '--contains', '--no-contains', '--points-at', '--color', '--column'}
TAG_VALUE_OPTIONS = BRANCH_VALUE_OPTIONS | {
    '-m', '--message', '-F', '--file', '-u', '--local-user', '--cleanup', '--trailer',
}  # fmt: skip
COMMIT_VALUE_OPTIONS = {
    '-m', '--message', '-F', '--file', '-C', '--reuse-message', '-c', '--reedit-message', '--fixup', '--squash',
    '--author', '--date', '-t', '--template', '--cleanup', '--pathspec-from-file', '--trailer',
}  # fmt: skip
COMMIT_ATTACHED_OPTIONS = {'-u', '-S'}
DOCKER_VALUE_OPTIONS = {'--context', '-c', '--config', '-H', '--host', '-l', '--log-level'}
COMPOSE_VALUE_OPTIONS = {
    '-f', '--file', '-p', '--project-name', '--profile', '--env-file', '--project-directory', '--ansi', '--progress',
    '--parallel',
}  # fmt: skip
SSH_VALUE_OPTIONS = set('-B -b -c -D -E -e -F -I -i -J -L -l -m -O -o -p -Q -R -S -W -w'.split())
SQL_DESTRUCTIVE = re.compile(r'\b(drop|truncate|dropDatabase|dropIndex(es)?)\b', re.I)
# The two names docker/config/gitleaks.toml leaves out of the file scan, so a tracked one is never judged by it.
LOCAL_SECRET_FILES = {'.env', 'local.settings.json'}
# The filled .env files of the custom layer, custom/env/<name>.env: env/<name>.env in that repo.
CUSTOM_ENV_FILE = re.compile(r'(^|/)env/[^/]+\.env$')
LEAK_MARKER = re.compile(r'leaks found|RuleID|Finding:|tracked by git')
MAX_DEPTH = 4
MAX_NESTING = 40
MAX_CANDIDATES = 3
MAX_TEXTS = 300
MAX_ARITHMETIC = 4096
SCAN_TIMEOUT_SECONDS = 180
# The whole hook gives up after this long and exits 2, which the wrapper turns into a question.
BUDGET_SECONDS = 240
NO_STDIN = (False, [])
UNREADABLE = 'I could not read this command in full, and it names a program that can destroy data or send to the remote'
UNSEEN_STDIN = 'a shell runs commands that arrive on its input, and I cannot see them'
# What stands for a $(...) or <(...) that downloads its text (curl, wget): a shell that runs it runs unseen commands.
FETCHED = '$(fetch)'
FETCHERS = {'curl', 'wget'}
FETCHED_TEXT = 'a shell runs text downloaded from the network on this line, and I cannot see it'
ANSI = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')
# Programs whose launched command runs in another machine, container or user: a git commit there is not scanned here.
ELSEWHERE = {'ssh', 'su', 'nsenter', 'chroot', 'docker-compose', 'kubectl'} | DOCKERS


class OutOfTime(Exception):
    """The hook passed its time budget."""


class Lexer:
    """Reads a shell command line into its simple commands, the way a shell would group them: quotes, escapes, line
    continuations, comments, redirections, heredocs, $(...), backticks, <(...), subshells and arithmetic. Every simple
    command, at any nesting, lands in self.commands with its words (redirections apart), the folder it would run in,
    what reaches its stdin as text (heredoc bodies, here-strings), the command that pipes into it, and its group: the
    index of the top-level command it belongs to (top-level commands are joined by ;, &&, ||, & or a newline; a
    pipeline, a subshell, a substitution and a compound command, if...fi, for/while/until...done, case...esac and
    { ... }, stay in one). A cd, pushd or popd changes the folder of what follows it,
    inside its own subshell only. Raises ValueError on text it cannot read (an open quote, an open parenthesis)."""

    def __init__(self, text, cwd, commands=None):
        self.text, self.size = text, len(text)
        self.cwd, self.oldpwd, self.dirs, self.exports, self.vars = cwd, None, [], {}, {}
        self.commands = [] if commands is None else commands
        # Redirections with no command to carry them ((a) > f, > f): (operator, target, folder, group), which no entry
        # holds.
        self.loose = []
        self.pending, self.depth, self.group, self.compound = [], 0, [0], 0

    def child(self, text):
        """Returns a lexer for a nested text (backticks, a heredoc body) that feeds the same command list."""
        other = Lexer(text, self.cwd, self.commands)
        other.exports, other.vars, other.depth = dict(self.exports), dict(self.vars), self.depth
        other.group, other.loose = self.group, self.loose
        return other

    def run(self):
        """Reads the whole text and returns self."""
        self.parse_list(0, None)
        return self

    def parse_list(self, i, closer):
        """Reads commands from index i until the unquoted closer (")" or None for the end of the text). Returns the
        index after the closer. A list with a closer is a subshell or a substitution: its cd does not leak out."""
        self.depth += 1
        if self.depth > MAX_NESTING:
            raise ValueError('nesting')
        saved = (self.cwd, self.oldpwd, list(self.dirs), dict(self.exports), dict(self.vars))
        text, size = self.text, self.size
        words, word, piped, source, inputs, redirects, awaiting = [], None, False, None, [], [], None

        def push():
            """Ends the current word: a command word, the target of a redirection or the text of a here-string."""
            nonlocal word, awaiting
            if word is None:
                return
            if awaiting == '<<<':
                inputs.append(word)
            elif awaiting:
                redirects.append((awaiting, word))
            else:
                words.append(word)
            word, awaiting = None, None

        def redirect(operator):
            """Starts a redirection; a number glued to its left is the file descriptor, not a word."""
            nonlocal word, awaiting
            if word is not None and word.isdigit():
                word = None
            push()
            awaiting = operator

        def finish(next_piped=False):
            """Ends the current simple command."""
            nonlocal words, piped, source, inputs, redirects, awaiting
            push()
            entry = self.emit(words, piped, source, inputs, redirects) if words else None
            if not words:
                self.loose.extend((operator, target, self.cwd, self.group[0]) for operator, target in redirects)
            words, inputs, redirects, awaiting = [], [], [], None
            piped, source = next_piped, entry if next_piped else None

        def separate():
            """Ends a top-level command: what follows belongs to the next group, unless a compound command is open."""
            if self.depth == 1 and self.compound <= 0:
                self.group[0] += 1

        while i < size:
            char = text[i]
            pair = text[i : i + 2]
            if char == '\\':
                if pair == '\\\n':
                    i += 2
                    continue
                word = (word or '') + text[i + 1 : i + 2]
                i += 2
            elif char == "'":
                end = text.find("'", i + 1)
                if end < 0:
                    raise ValueError('quote')
                word = (word or '') + text[i + 1 : end]
                i = end + 1
            elif char == '"':
                i, piece = self.double_quoted(i + 1)
                word = (word or '') + piece
            elif char == '$':
                i, piece = self.dollar(i, quoted=False)
                word = (word or '') + piece
            elif char == '`':
                i = self.backtick(i)
                word = (word or '') + '$()'
            elif char == '#' and word is None:
                end = text.find('\n', i)
                i = size if end < 0 else end
            elif char in ' \t\r':
                push()
                i += 1
            elif char == '\n':
                finish()
                i += 1
                if self.pending:
                    i = self.read_heredocs(i)
                separate()
            elif pair in ('&&', '||', ';;'):
                finish()
                separate()
                i += 2
            elif char == '&' and text[i + 1 : i + 2] == '>':
                end = i + (3 if text[i + 2 : i + 3] == '>' else 2)
                redirect(text[i:end])
                i = end
            elif char in ';&':
                finish()
                separate()
                i += 1
            elif char == '|':
                finish(next_piped=True)
                i += 2 if pair == '|&' else 1
            elif char == '(':
                if pair == '((' and word is None and all(item in KEYWORDS for item in words):
                    try:
                        i = self.arithmetic(i + 2)
                        continue
                    except ValueError:
                        pass
                finish()
                i = self.parse_list(i + 1, ')')
            elif char == ')':
                finish()
                if closer == ')':
                    self.cwd, self.oldpwd, self.dirs, self.exports, self.vars = saved
                    self.depth -= 1
                    return i + 1
                i += 1
            elif char in '<>':
                if text.startswith('<<<', i):
                    redirect('<<<')
                    i += 3
                elif pair == '<<' and word is not None and '[' in word and ']' not in word:
                    word += pair  # a shift inside an array subscript, a[1<<2]=x
                    i += 2
                elif pair == '<<':
                    push()
                    i = self.heredoc_start(i + 2, inputs)
                elif text[i + 1 : i + 2] == '(':
                    mark = len(self.commands)
                    i = self.parse_list(i + 2, ')')
                    word = (word or '') + self.stands_for(mark)
                else:
                    end = i
                    while end < size and text[end] in '<>':
                        end += 1
                    if text[end : end + 1] in ('&', '|'):
                        end += 1
                    redirect(text[i:end])
                    i = end
            else:
                word = (word or '') + char
                i += 1
        finish()
        if closer is not None:
            raise ValueError('open parenthesis')
        self.depth -= 1
        return size

    def double_quoted(self, i):
        """Reads from index i, right after an opening double quote. Returns (index after the closing quote, text)."""
        text, size, out = self.text, self.size, []
        while i < size:
            char = text[i]
            if char == '"':
                return i + 1, ''.join(out)
            if char == '\\':
                following = text[i + 1 : i + 2]
                if following != '\n':
                    out.append(following if following in '$`"\\' else '\\' + following)
                i += 2
            elif char == '$':
                i, piece = self.dollar(i, quoted=True)
                out.append(piece)
            elif char == '`':
                i = self.backtick(i)
                out.append('$()')
            else:
                out.append(char)
                i += 1
        raise ValueError('quote')

    def dollar(self, i, quoted):
        """Reads what starts with the "$" at index i. Returns (index after it, the text that stands for it). A
        $(cat <<EOF ... EOF) stands for its heredoc body, because that is the text the shell puts there."""
        text = self.text
        if text.startswith('$((', i):
            try:
                return self.arithmetic(i + 3), '$(())'
            except ValueError:
                pass
        if text.startswith('$(', i):
            mark = len(self.commands)
            end = self.parse_list(i + 2, ')')
            return end, self.stands_for(mark)
        if text.startswith('$[', i):
            end = text.find(']', i)
            if end < 0:
                raise ValueError('arithmetic')
            return end + 1, '$(())'
        if text.startswith('${', i):
            end, level = i + 2, 1
            while end < self.size and level:
                char = text[end]
                if char == '\\':
                    end += 2
                elif char == '$' and text.startswith('$(', end):
                    end, _ = self.dollar(end, quoted=True)
                elif char == '`':
                    end = self.backtick(end)
                else:
                    level += {'{': 1, '}': -1}.get(char, 0)
                    end += 1
            if level:
                raise ValueError('brace')
            return end, text[i:end]
        if text.startswith("$'", i) and not quoted:
            end = i + 2
            while end < self.size and text[end] != "'":
                end += 2 if text[end] == '\\' else 1
            if end >= self.size:
                raise ValueError('quote')
            return end + 1, text[i + 2 : end]
        return i + 1, '$'

    def stands_for(self, mark):
        """Returns the text that stands for a substitution whose commands were recorded from index mark on: the body
        of a lone cat <<EOF, FETCHED when one of them downloads its output, "$()" otherwise."""
        added = self.commands[mark:]
        if len(added) == 1 and added[0]['argv'] == ['cat'] and len(added[0]['inputs']) == 1:
            return added[0]['inputs'][0]
        names = [os.path.basename((strip_wrappers(entry['argv'])[0] or [''])[0]) for entry in added]
        return FETCHED if FETCHERS & set(names) else '$()'

    def arithmetic(self, i):
        """Returns the index after the "))" that closes the arithmetic expression starting at index i, reading the
        command substitutions inside it. Raises ValueError when the text is not an arithmetic expression."""
        text, level, limit = self.text, 0, min(self.size, i + MAX_ARITHMETIC)
        while i < limit:
            char = text[i]
            if char == '(':
                level += 1
            elif char == ')':
                if level == 0:
                    if text[i + 1 : i + 2] == ')':
                        return i + 2
                    raise ValueError('arithmetic')
                level -= 1
            elif char == '$' and text.startswith('$(', i) and not text.startswith('$((', i):
                i = self.parse_list(i + 2, ')')
                continue
            elif char == '`':
                i = self.backtick(i)
                continue
            i += 1
        raise ValueError('arithmetic')

    def backtick(self, i):
        """Reads the backtick substitution that opens at index i. Returns the index after its closing backtick."""
        text, end = self.text, i + 1
        while end < self.size and text[end] != '`':
            end += 2 if text[end] == '\\' else 1
        if end >= self.size:
            raise ValueError('backtick')
        self.child(text[i + 1 : end].replace('\\`', '`')).run()
        return end + 1

    def heredoc_start(self, i, inputs):
        """Reads the delimiter of a heredoc from index i, right after "<<". Returns the index after it. inputs: the
        stdin texts of the command that owns the heredoc, where its body lands once read."""
        text, size = self.text, self.size
        strip_tabs = text[i : i + 1] == '-'
        i += 1 if strip_tabs else 0
        while i < size and text[i] in ' \t':
            i += 1
        word, quoted = '', False
        while i < size and text[i] not in ' \t\n;&|<>()':
            char = text[i]
            if char in '\'"':
                end = text.find(char, i + 1)
                if end < 0:
                    raise ValueError('quote')
                word, quoted, i = word + text[i + 1 : end], True, end + 1
            elif char == '\\':
                word, quoted, i = word + text[i + 1 : i + 2], True, i + 2
            else:
                word, i = word + char, i + 1
        if word:
            self.pending.append((word, quoted, strip_tabs, inputs))
        return i

    def read_heredocs(self, i):
        """Reads the bodies of the pending heredocs, which begin at index i. Returns the index after them. A body with
        an unquoted delimiter is expanded by the shell, so the commands inside its $(...) and backticks are read."""
        text, size = self.text, self.size
        for word, quoted, strip_tabs, inputs in self.pending:
            body = []
            while i < size:
                end = text.find('\n', i)
                line = text[i : size if end < 0 else end]
                i = size if end < 0 else end + 1
                if (line.lstrip('\t') if strip_tabs else line) == word:
                    break
                body.append(line)
            content = '\n'.join(body)
            inputs.append(content)
            if not quoted:
                self.child(content).substitutions()
        self.pending = []
        return i

    def substitutions(self):
        """Reads only the $(...) and backtick substitutions of the text, as inside double quotes."""
        i = 0
        while i < self.size:
            char = self.text[i]
            if char == '\\':
                i += 2
            elif char == '$' and self.text.startswith('$(', i):
                i, _ = self.dollar(i, quoted=True)
            elif char == '`':
                i = self.backtick(i)
            else:
                i += 1

    def emit(self, words, piped, source, inputs, redirects):
        """Records one simple command with the folder it runs in, then applies its cd, pushd, popd, export or
        assignment. Returns the record. source: the record of the command that pipes into this one, when known."""
        entry = {
            'argv': words, 'cwd': self.cwd, 'piped': piped, 'source': source, 'inputs': inputs,
            'redirects': redirects, 'exports': dict(self.exports), 'vars': dict(self.vars), 'group': self.group[0],
        }  # fmt: skip
        self.commands.append(entry)
        if self.depth == 1:
            for word in itertools.takewhile(lambda w: w in KEYWORDS | OPENERS | COMPOUND_CLOSERS, words):
                self.compound += (word in OPENERS) - (word in COMPOUND_CLOSERS)
        argv, info = strip_wrappers(words)
        if not argv:
            if not info['wrappers']:
                self.vars.update(info['env'])
            return entry
        name, args = argv[0], argv[1:]
        if name in ('export', 'declare', 'typeset', 'readonly', 'local'):
            exported = name == 'export' or has_short_flag(args, 'x')
            for arg in args:
                key, assigned, value = arg.partition('=')
                if assigned and ASSIGNMENT.match(arg):
                    self.vars[key] = value
                if exported and key in self.vars:
                    self.exports[key] = self.vars[key]
        elif name in ('cd', 'pushd'):
            target = first_operand(args)
            if name == 'pushd':
                self.dirs.append(self.cwd)
            if target == '-':
                self.cwd, self.oldpwd = self.oldpwd, self.cwd
            else:
                self.oldpwd, self.cwd = self.cwd, resolve_folder(self.cwd, target, self.vars)
        elif name == 'popd':
            self.oldpwd, self.cwd = self.cwd, (self.dirs.pop() if self.dirs else None)
        return entry


def first_operand(args):
    """Returns the first argument that is not an option; None when there is none."""
    return next((arg for arg in args if arg == '-' or not arg.startswith('-')), None)


def resolve_folder(cwd, target, variables=None):
    """Returns the folder a cd to target leads to, or None when it cannot be known (a variable with no value in the
    line or in the environment, a command substitution, an unknown start)."""
    if target is None:
        return os.path.expanduser('~')
    known = {**os.environ, 'PWD': cwd or '', **(variables or {})}
    missing = []

    def value(match):
        name = match.group(1) or match.group(2)
        if not known.get(name):
            missing.append(name)
        return known.get(name, '')

    target = VARIABLE.sub(value, target)
    if missing or '$' in target:
        return None
    target = os.path.expanduser(target)
    if os.path.isabs(target):
        return os.path.normpath(target)
    return os.path.normpath(os.path.join(cwd, target)) if cwd is not None else None


def short_options(word, values):
    """Splits one word of short options (-iu, -n5, -x): returns (the option names in it, the one that takes a value or
    None, the value glued to it or None when the value is the next word)."""
    names = []
    for position, letter in enumerate(word[1:], start=2):
        names.append('-' + letter)
        if names[-1] in values:
            return names, names[-1], word[position:] or None
    return names, None, None


def strip_wrappers(argv):
    """Drops leading shell keywords, variable assignments and wrapper commands (sudo, env, timeout 5, xargs -n 1).
    Returns (the command left, what was dropped: env, wrappers, chdir, the texts given to env -S and flock -c,
    shell: True for sudo -s or -i, which open a shell, unset: the names env -u takes out of the environment, and
    cleared: True for env -i, env - and exec -c, which start from an empty environment)."""
    info = {'env': {}, 'wrappers': set(), 'chdir': '', 'texts': [], 'shell': False, 'unset': [], 'cleared': False}
    i, size = 0, len(argv)
    while i < size:
        if ASSIGNMENT.match(argv[i]):
            name, _, value = argv[i].partition('=')
            info['env'][name] = value
            i += 1
            continue
        name = os.path.basename(argv[i])
        if name in KEYWORDS:
            i += 2 if name == 'function' else 1
            continue
        if name not in WRAPPERS:
            break
        info['wrappers'].add(name)
        i += 1
        values = WRAPPER_VALUE_OPTIONS.get(name, ())
        while i < size and (argv[i].startswith('-') or ASSIGNMENT.match(argv[i])):
            word = argv[i]
            if ASSIGNMENT.match(word):
                key, _, value = word.partition('=')
                info['env'][key] = value
                i += 1
                continue
            if word == '--':
                i += 1
                break
            if word.startswith('--'):
                option, _, value = word.partition('=')
                names, separate = [option], word in values
            else:
                names, option, glued = short_options(word, values)
                separate, value = option is not None and glued is None, glued or ''
            if separate:
                value = argv[i + 1] if i + 1 < size else ''
            if name == 'env' and option in ('-C', '--chdir'):
                info['chdir'] = value
            elif name == 'env' and option in ('-S', '--split-string'):
                info['texts'].append(value)
            elif name == 'env' and option in ('-u', '--unset'):
                info['unset'].append(value)
            if (name == 'env' and (word == '-' or {'-i', '--ignore-environment'} & set(names))) or (
                name == 'exec' and '-c' in names
            ):
                info['cleared'] = True
            if name in ('sudo', 'doas') and {'-s', '-i', '--shell', '--login'} & set(names):
                info['shell'] = True
            i += 2 if separate else 1
        i += WRAPPERS[name]
        if name == 'flock' and i + 1 < size and argv[i] in ('-c', '--command'):
            info['texts'].append(argv[i + 1])
            i += 2
    return argv[i:], info


def has_short_flag(args, letters):
    """True when a short option group of args (-rf, -d) holds one of the letters."""
    return any(a.startswith('-') and not a.startswith('--') and set(a[1:]) & set(letters) for a in args)


def plain_words(args):
    """Returns the arguments that are not options."""
    return [a for a in args if not a.startswith('-')]


# git -c keys whose value is a command, or that bring in other configuration: they can run what the line does not show.
HIDDEN_CONFIG = re.compile(
    r'^(alias\.|core\.(hookspath|fsmonitor|sshcommand|pager|editor|askpass|gitproxy)$|sequence\.editor$'
    r'|diff\.external$|.*\.textconv$|filter\.|merge\..*\.driver$|credential\.|gpg\.|uploadpack\.|protocol\.'
    r'|remote\..*\.(uploadpack|receivepack|vcs|fetch|push|url|pushurl)$|url\.|include\.|includeif\.)'
)
HIDDEN_ENV = {
    'GIT_CONFIG_COUNT', 'GIT_CONFIG_PARAMETERS', 'GIT_SSH_COMMAND', 'GIT_SSH', 'GIT_EXTERNAL_DIFF', 'GIT_PAGER',
    'GIT_EDITOR', 'GIT_ASKPASS', 'GIT_EXEC_PATH', 'GIT_CONFIG_GLOBAL', 'GIT_CONFIG_SYSTEM',
}  # fmt: skip
HIDDEN_OPTIONS = ('--upload-pack', '--receive-pack', '--exec')


def git_parts(argv, env=None):
    """Returns what a git command line says before and after its subcommand: the -C folder, --git-dir and
    --work-tree (or GIT_DIR and GIT_WORK_TREE), whether configuration on the line can run a command the line does not
    show (an alias, a hooks folder, fsmonitor, ssh, a pager, --config-env, GIT_CONFIG_* and the like), the
    subcommand and its arguments."""
    env = env or {}
    parts = {
        'folder': '',
        'git_dir': env.get('GIT_DIR', ''),
        'work_tree': env.get('GIT_WORK_TREE', ''),
        'hidden': bool(HIDDEN_ENV & set(env)) or any(key.startswith('GIT_CONFIG_KEY_') for key in env),
    }
    i = 1
    while i < len(argv):
        word = argv[i]
        name, _, attached = word.partition('=')
        if name in ('--git-dir', '--work-tree') and attached:
            parts['git_dir' if name == '--git-dir' else 'work_tree'] = attached
            i += 1
        elif name in ('--config-env', '--exec-path'):
            parts['hidden'] = True
            i += 1 if attached or name == '--exec-path' else 2
        elif word in GIT_VALUE_OPTIONS:
            value = argv[i + 1] if i + 1 < len(argv) else ''
            if word == '-C':
                parts['folder'] = os.path.join(parts['folder'], value)
            elif word == '--git-dir':
                parts['git_dir'] = value
            elif word == '--work-tree':
                parts['work_tree'] = value
            elif word == '-c' and HIDDEN_CONFIG.match(value.partition('=')[0].lower()):
                parts['hidden'] = True
            i += 2
        elif word.startswith('-c') and len(word) > 2 and HIDDEN_CONFIG.match(word[2:].partition('=')[0].lower()):
            parts['hidden'] = True
            i += 1
        elif word.startswith('-C') and len(word) > 2:
            parts['folder'] = os.path.join(parts['folder'], word[2:])
            i += 1
        elif word.startswith('-'):
            i += 1
        else:
            break
    parts['sub'] = argv[i] if i < len(argv) else ''
    parts['args'] = argv[i + 1 :]
    if any(a.split('=')[0] in HIDDEN_OPTIONS for a in parts['args']):
        parts['hidden'] = True
    return parts


def repo_folder(parts, cwd):
    """Returns the folder git would work in for that command line, or None when the starting folder is unknown."""
    if cwd is None and not os.path.isabs(parts['work_tree'] or parts['git_dir'] or parts['folder']):
        return None
    base = os.path.join(cwd or '', parts['folder'])
    if parts['work_tree']:
        return os.path.join(base, parts['work_tree'])
    if parts['git_dir']:
        git_dir = os.path.join(base, parts['git_dir']).rstrip('/')
        return os.path.dirname(git_dir) if os.path.basename(git_dir) == '.git' else git_dir
    return base


def commit_options(args):
    """Returns (the option names of a git commit, its pathspecs), skipping the values of -m, -F and the like."""
    flags, paths, i = set(), [], 0
    while i < len(args):
        word = args[i]
        if word == '--':
            paths.extend(args[i + 1 :])
            break
        if word.startswith('--'):
            name, _, attached = word.partition('=')
            flags.add(name)
            i += 2 if name in COMMIT_VALUE_OPTIONS and not attached else 1
        elif word.startswith('-') and len(word) > 1:
            i += 1
            for position, letter in enumerate(word[1:], start=2):
                flags.add('-' + letter)
                if '-' + letter in COMMIT_ATTACHED_OPTIONS:
                    break
                if '-' + letter in COMMIT_VALUE_OPTIONS:
                    i += 0 if word[position:] else 1
                    break
        else:
            paths.append(word)
            i += 1
    return flags, paths


def exists_in(folder, name):
    """True when name is a path that exists in the folder; False when the folder is unknown."""
    return folder is not None and os.path.exists(os.path.join(folder, name))


def reset_moves_branch(args, folder):
    """True when a git reset names a commit other than HEAD, which moves the branch."""
    before_paths = args[: args.index('--')] if '--' in args else args
    words = plain_words(before_paths)
    return bool(words) and words[0] != 'HEAD' and not exists_in(folder, words[0])


def drop_values(args, options):
    """Returns args without those options and the word that follows each (its value)."""
    kept, skip = [], False
    for arg in args:
        if skip:
            skip = False
        elif arg in options:
            skip = True
        else:
            kept.append(arg)
    return kept


def docker_words(args):
    """Returns the words of a docker command line without its options: the values of the global options, and of the
    options docker compose takes before its subcommand (-f a.yml, -p name, --profile dev), are dropped too."""
    words, skip = [], False
    for arg in args:
        values = DOCKER_VALUE_OPTIONS if not words else COMPOSE_VALUE_OPTIONS if words == ['compose'] else ()
        if skip:
            skip = False
        elif arg in values:
            skip = True
        elif not arg.startswith('-'):
            words.append(arg)
    return words


# Git subcommands that only read: they run anywhere, projects/ and the core included.
GIT_READS = {
    'status', 'log', 'diff', 'show', 'rev-parse', 'ls-files', 'ls-tree', 'ls-remote', 'cat-file', 'describe', 'blame',
    'annotate', 'grep', 'shortlog', 'for-each-ref', 'merge-base', 'rev-list', 'name-rev', 'show-ref', 'show-branch',
    'whatchanged', 'diff-tree', 'diff-files', 'diff-index', 'count-objects', 'check-ignore', 'check-attr', 'var',
    'help', 'version', 'fsck', 'verify-commit', 'verify-tag', 'cherry', 'range-diff', 'archive', 'fetch',
}  # fmt: skip
# Subcommands that read when given only these first words or options (git branch -a, git stash list, ...).
GIT_READ_FORMS = {
    'branch': {'--list', '-l', '-a', '--all', '-r', '--remotes', '-v', '-vv', '--verbose', '--show-current',
               '--contains', '--no-contains', '--merged', '--no-merged', '--points-at', '--sort', '--format',
               '--color', '--column'},
    'tag': {'-l', '--list', '-n', '--contains', '--no-contains', '--merged', '--no-merged', '--points-at', '--sort',
            '--format', '--color', '--column'},
    'stash': {'list', 'show'},
    'remote': {'-v', '--verbose', 'show', 'get-url'},
    'config': {'--get', '--get-all', '--get-regexp', '-l', '--list', '--show-origin', '--show-scope', '--name-only',
               '--local', '--global', '--system', '--worktree', '--file', '-f', '--type', '--null', '-z'},
    'worktree': {'list'},
    'reflog': {'show'},
    'notes': {'list', 'show'},
    'submodule': {'status', 'summary'},
}  # fmt: skip
GATE_HINT = (
    'projects/ and the workspace core change only through the gate. Work in a clone under tmp/work/ '
    '(bash scripts/aiwp-cmds.sh open) and bring it to the base with /merge (bash scripts/aiwp-cmds.sh gate)'
)
TARGET_SUBS = {'push', 'fetch', 'pull', 'clone', 'init', 'remote', 'worktree', 'submodule', 'config', 'bundle'}
TF_CHANGES = {'apply', 'destroy', 'import', 'taint', 'untaint', 'force-unlock', 'refresh', 'test'}
TF_STATE_CHANGES = {'rm', 'mv', 'push', 'replace-provider'}
AIWP_SCRIPTS = ('aiwp-cmds.sh', 'aiwp-gate.sh')
DATA_FILE = re.compile(r'(^|/)\.data(/|$)|\.(db|sqlite3?|mdf|ldf)$')


# Options of git branch and git tag that take the next word as their value when reading (--color and --column take
# only an attached value: the next word is a name, which creates a ref).
BRANCH_READ_VALUES = BRANCH_VALUE_OPTIONS - {'--color', '--column'}
TAG_READ_VALUES = TAG_VALUE_OPTIONS - {'--color', '--column'}


def git_reads(sub, args):
    """True when a git command line only reads (it may still write FETCH_HEAD or remote-tracking refs)."""
    if sub == 'fetch':
        words = plain_words(args)
        return not (
            has_short_flag(args, 'fu')
            or {'--force', '--update-head-ok'} & set(args)
            or any(w.startswith('+') or ':' in w for w in words)
        )
    if sub in GIT_READS:
        return not any(a.startswith('--output') for a in args)
    forms = GIT_READ_FORMS.get(sub)
    if forms is None:
        return False
    if sub in ('branch', 'tag'):
        values = BRANCH_READ_VALUES if sub == 'branch' else TAG_READ_VALUES
        flags = drop_values(args, values)
        listing = not plain_words(flags) or bool({'--list', '-l'} & set(flags))
        known = all(a in forms or a.startswith(tuple(f + '=' for f in forms)) for a in flags if a.startswith('-'))
        return listing and known
    if sub == 'config':
        return any(a in ('--get', '--get-all', '--get-regexp', '-l', '--list') for a in args)
    if sub == 'remote':
        words = plain_words(args)
        return not words or words[0] in ('show', 'get-url')
    if not args:
        # git stash alone is git stash push; the others list or show with no words.
        return sub != 'stash'
    return args[0] in forms


def path_kind(root, path):
    """Returns the kind of repo a path falls in by where it is, without git: 'core' for the workspace root and its .git,
    'projects' under projects/, 'clone' under tmp/work/, 'custom' under custom/, else None."""
    base = os.path.realpath(root)
    path = os.path.realpath(path)
    if path == base or path == os.path.join(base, '.git') or path.startswith(os.path.join(base, '.git') + os.sep):
        return 'core'
    for prefix, kind in (('projects', 'projects'), (os.path.join('tmp', 'work'), 'clone'), ('custom', 'custom')):
        inside = os.path.join(base, prefix)
        if path == inside or path.startswith(inside + os.sep):
            return kind
    return None


def repo_kind(run, root, folder):
    """Returns what kind of repo holds a folder: 'core' (the workspace repo), 'projects' (a repo of projects/),
    'clone' (tmp/work/), 'custom', 'other', None when there is no repo there, or 'unknown' when the folder is. Judged by
    the real git folder (it works inside .git too, and a linked worktree counts as its repo); when git finds none, by
    where the path is."""
    if folder is None:
        return 'unknown'
    found = run_git(run, folder, 'rev-parse', '--absolute-git-dir', '--git-common-dir')
    if not found:
        kind = path_kind(root, folder)
        return kind if kind in ('core', 'projects') else None
    lines = found[0].split('\n') if len(found) == 1 else found
    common = lines[1].strip() if len(lines) > 1 else lines[0].strip()
    git_dir = common if os.path.isabs(common) else os.path.join(lines[0].strip(), common)
    git_dir = os.path.realpath(git_dir)
    top = os.path.dirname(git_dir) if os.path.basename(git_dir) == '.git' else git_dir
    return path_kind(root, git_dir) or path_kind(root, top) or 'other'


def git_dir_kind(parts, start, root):
    """Returns 'core' or 'projects' when --git-dir or GIT_DIR names the git folder of the workspace repo or of a repo
    of projects/, whatever --work-tree says; else None. start: the folder the command runs in (cwd and -C)."""
    if not parts['git_dir'] or (start is None and not os.path.isabs(parts['git_dir'])):
        return None
    git_dir = os.path.realpath(os.path.join(start or '', parts['git_dir']))
    base = os.path.realpath(root)
    if git_dir == os.path.join(base, '.git') or git_dir.startswith(os.path.join(base, '.git') + os.sep):
        return 'core'
    inside = os.path.join(base, 'projects')
    return 'projects' if git_dir.startswith(inside + os.sep) else None


def git_verdict(parts, folder, root, run, start=None):
    """Returns ('deny' | 'ask', reason) for a git command line, or None. A commit of the custom layer or of another
    repo is judged by commit_decision afterwards. start: the folder the command runs in, for a relative --git-dir."""
    sub, args = parts['sub'], parts['args']
    if parts['hidden']:
        return (
            'ask',
            'git -c defines an alias or changes the hooks folder on the line itself, which can hide another command',
        )
    if not sub or HELP_OPTIONS & set(args) or '-h' in args:
        return None
    if sub == 'push' and any(len(a) >= 6 and '--no-verify'.startswith(a) for a in args):
        return (
            'deny',
            'git push --no-verify skips the secret scan the clone runs before each push. Run it without that flag',
        )
    if git_reads(sub, args):
        return None
    # The repo git writes: the one --git-dir or GIT_DIR names, else the one it finds from where it runs; the files it
    # writes: the work tree, wherever --work-tree or GIT_WORK_TREE puts it.
    kinds = set()
    if sub not in ('clone', 'init'):
        if parts['git_dir']:
            git_dir = None if start is None else os.path.join(start, parts['git_dir'])
            kinds.add(git_dir_kind(parts, start, root) or (repo_kind(run, root, git_dir) if git_dir else 'unknown'))
        else:
            kinds.add(repo_kind(run, root, start if start is not None else folder))
        if parts['work_tree']:
            kinds.add('unknown' if start is None else path_kind(root, os.path.join(start, parts['work_tree'])))
    # Paths the command writes to: a local remote of push or fetch, a clone or init target, config --file, a worktree
    # or submodule folder. A pathspec (git add ../x) is not one: git refuses what falls outside its repo.
    if sub in TARGET_SUBS and start is not None:
        for word in plain_words(args) + [a.partition('=')[2] for a in args if a.startswith('--file=')]:
            if ('/' in word or word.startswith('.')) and ':' not in word:
                kinds.add(path_kind(root, os.path.join(start, word)))
    targets = len(plain_words(args))
    if start is not None and ((sub == 'init' and targets == 0) or (sub == 'clone' and targets < 2)):
        kinds.add(path_kind(root, start))
    kind = (
        'core'
        if 'core' in kinds
        else 'projects'
        if 'projects' in kinds
        else ('unknown' if 'unknown' in kinds else None)
    )
    if kind in ('core', 'projects'):
        where = 'to the workspace core' if kind == 'core' else 'to a repository of projects/'
        return 'deny', 'git ' + sub + ' would write ' + where + '. ' + GATE_HINT + '.'
    if kind == 'unknown':
        reason = (
            'I do not know which repository this git ' + sub + ' writes to, '
            'and projects/ and the core change only through the gate'
        )
        return 'ask', reason
    return None


def docker_db_reason(args):
    """Returns why a docker command deletes a database (a volume) and needs the human's confirmation, or None."""
    words = docker_words(args)
    if not words or {'exec', 'run'} & set(words[:2]):
        return None
    if words[0] == 'compose':
        down = words[1:2] == ['down'] and (has_short_flag(args, 'v') or any(a.startswith('--volumes') for a in args))
        removes = words[1:2] == ['rm'] and (has_short_flag(args, 'v') or '--volumes' in args)
        return 'docker compose deletes volumes, where the databases live' if down or removes else None
    if words[0] == 'volume' and words[1:2] in (['rm'], ['prune'], ['remove']):
        return 'docker volume ' + words[1] + ' deletes volumes, where the databases live'
    if words[:2] == ['system', 'prune'] and '--volumes' in args:
        return 'docker system prune --volumes deletes volumes, where the databases live'
    if words[:1] in (['rm'], ['container']) and (has_short_flag(args, 'v') or '--volumes' in args):
        return 'docker rm -v deletes the container volumes, where the databases live'
    return None


def aiwp_verdict(argv):
    """Returns ('ask', reason) for the commands of scripts/aiwp-cmds.sh that the human confirms (release, deploy, the
    hotfix commands, checkpoint, developer --create, gate --untested, apply --apply, close --discard), or None."""
    words = argv[1:]
    sub = words[0] if words else ''
    if sub == 'release':
        return 'ask', (
            'aiwp-cmds.sh release takes developer into main and pushes main to the remote; with --tag it also creates '
            'and pushes a release tag'
        )
    if sub == 'deploy':
        return 'ask', (
            'aiwp-cmds.sh deploy updates the final stack of a project, the one the person uses, from a branch; confirm '
            'only when the person ran /docker-deploy'
        )
    if sub == 'hotfix':
        return 'ask', (
            'aiwp-cmds.sh hotfix moves production: it pushes the checked fix to main of the remote (with '
            '--pr-if-refused it may open a pull request into main instead); confirm only after the review with no '
            "BLOCKER and the human's OK"
        )
    if sub == 'hotfix-tag':
        return (
            'ask',
            'aiwp-cmds.sh hotfix-tag creates and pushes a release tag on main; only when the human says publish',
        )
    if sub == 'hotfix-down':
        return 'ask', (
            'aiwp-cmds.sh hotfix-down writes developer of the project: it merges main into developer and pushes it'
        )
    if sub == 'checkpoint':
        return 'ask', (
            'aiwp-cmds.sh checkpoint creates the checkpoint tags of /normalize-projects on developer and main and '
            'pushes them to the remote'
        )
    if sub == 'gate' and '--untested' in words:
        return 'ask', (
            'aiwp-cmds.sh gate --untested takes a normalization into developer without running its tests; confirm only '
            'if the person chose to go on untested'
        )
    if sub == 'developer' and '--create' in words:
        return 'ask', 'aiwp-cmds.sh developer --create creates developer on the remote of the project'
    if sub == 'apply' and '--apply' in words:
        return 'ask', 'aiwp-cmds.sh apply --apply applies the Terraform plan to the cloud; check the plan shown'
    if sub == 'close' and '--discard' in words:
        return 'ask', 'aiwp-cmds.sh close --discard deletes a work clone along with what was not merged'
    return None


# What swaps or restores the read-only core of an installed workspace: aiwp <command>. Denied inside a session, because
# it changes the rules of the open session; the person runs it in a terminal with the session closed.
AIWP_PROGRAMS = ('aiwp', 'aiwp.sh')
AIWP_CORE_COMMANDS = {
    'update': 'Updating the workspace changes the rules of this open session. Close the session and run `aiwp update` '
    'in a terminal.',
    'rollback': 'Rolling the workspace back changes the rules of this open session. Close the session and run '
    '`aiwp rollback` in a terminal.',
    'repair': 'Repairing the workspace rewrites the rules of this open session. Close the session and run '
    '`aiwp repair` in a terminal.',
    '_sync': 'Syncing the workspace changes the rules of this open session. Close the session and run `aiwp update` '
    'in a terminal.',
    'forget': 'Forgetting a workspace changes the registry of the installed workspaces. Close the session and run '
    '`aiwp forget` in a terminal.',
}
# aiwp with no command, or with -- and the arguments of claude, opens the workspace: it starts claude.
AIWP_OPEN = 'Opening the workspace starts claude inside this session. Close the session and run `aiwp` in a terminal.'
AIWP_OPEN_WORDS = ('', '--')
AIWP_UNSEEN = (
    'I cannot see which aiwp command this runs (its words come from xargs, a variable or a command substitution), and '
    'aiwp update, rollback and repair change the rules of this open session. Write the aiwp command out; to update, '
    'close the session and run `aiwp update` in a terminal.'
)
# Programs that change permissions or owners; their option letters (GNU and BSD), none of which takes a value.
CHANGERS = {'chmod', 'chown', 'chgrp'}
CHANGER_LETTERS = set('cfvRHLPh')
CHANGER_WORD = re.compile(r'(?<![\w.-])ch(mod|own|grp)(?![\w-])')
FIND_ACTIONS = ('-exec', '-execdir', '-ok', '-okdir')
# What a shell expands in a word into several paths; a word holding one is judged by its literal prefix.
GLOB_CHARS = '*?[{'
# What stands for the file find or xargs hands to the command: {}, or a positional parameter of sh -c.
PLACEHOLDER = re.compile(r'\{\}|^\$(\d|@|\*|\{\d+\}|\{@\})$')
INIT_VALUE_OPTIONS = {'--template', '--separate-git-dir', '-b', '--initial-branch', '--object-format', '--ref-format'}
CLONE_VALUE_OPTIONS = {
    '-o', '--origin', '-b', '--branch', '-u', '--upload-pack', '--reference', '--reference-if-able',
    '--separate-git-dir', '--depth', '--shallow-since', '--shallow-exclude', '-c', '--config', '--server-option',
    '-j', '--jobs', '--template', '--filter', '--bundle-uri', '--ref-format', '--revision',
}  # fmt: skip
MANIFEST = os.path.join('.aiwp', 'manifest.json')
HERE = os.path.dirname(os.path.realpath(__file__))
WRITABLE_TIMEOUT_SECONDS = 15
CORE_HINT = (
    'The core of an installed workspace is read-only on purpose (folders 555, files 444) and changes only through '
    'aiwp update, rollback or repair, run in a terminal with the session closed; change custom/, projects/, tmp/ or '
    'another writable folder '
    '(scripts/aiwp.sh _writable) instead'
)
NO_REPO_HINT = (
    'The root of an installed workspace is not a git repository: the repositories are custom/ and each project, and '
    'the core changes only through aiwp'
)


def syntax_check_only(options):
    """True when the words before the script are only short options of the shell, -n among them and no -c: the shell
    then reads the script without running it. With -c, or an operand before the script, the script may run."""
    if not options or not all(o.startswith('-') and not o.startswith('--') and len(o) > 1 for o in options):
        return False
    letters = ''.join(o[1:] for o in options)
    return 'n' in letters and 'c' not in letters


def aiwp_core_verdict(argv, wrappers=frozenset()):
    """Returns ('deny', reason) for aiwp update, rollback, repair (and the internal _sync), which swap or restore the
    read-only core and so the rules of the open session; for aiwp forget, which changes the registry; and for aiwp
    with no command or with --, which starts claude inside the session. Run directly (aiwp, ~/.local/bin/aiwp,
    scripts/aiwp.sh) or by a shell. Also when the command word cannot be seen: it comes from xargs or parallel, or
    from a variable or a command substitution. None otherwise: list, check, version, new and --help (aiwp itself
    refuses new over a registered folder inside a session)."""
    name, args = os.path.basename(argv[0]), argv[1:]
    if name not in AIWP_PROGRAMS:
        index = next((k for k, a in enumerate(args) if os.path.basename(a) in AIWP_PROGRAMS), None)
        if name not in SHELLS | {'source', '.'} or index is None:
            return None
        if name in SHELLS and syntax_check_only(args[:index]):
            return None  # bash -n <script> only reads the script
        args = args[index + 1 :]
    first = args[0] if args else ''
    # A word the shell still expands ($, backticks, a glob or braces, a backslash of $'...') may become update.
    if wrappers & {'xargs', 'parallel'} or any(char in first for char in '$`\\' + GLOB_CHARS):
        return 'deny', AIWP_UNSEEN
    if first in AIWP_OPEN_WORDS:
        return 'deny', AIWP_OPEN  # after --, even --help is an argument of claude
    reason = AIWP_CORE_COMMANDS.get(first)
    if reason and first != '_sync' and HELP_OPTIONS & set(args[1:]):
        return None  # aiwp update, rollback, repair and forget --help print the help and change nothing
    return ('deny', reason) if reason else None


def installed_root(path):
    """Returns the root of the installed workspace that holds a real path (the nearest folder at or above it with
    .aiwp/manifest.json), or None."""
    while True:
        if os.path.exists(os.path.join(path, MANIFEST)):
            return path
        parent = os.path.dirname(path)
        if parent == path:
            return None
        path = parent


def strictly_under(path, folder):
    """True when path lies inside folder and is not the folder itself (both real paths)."""
    return path != folder and path.startswith(folder.rstrip(os.sep) + os.sep)


def canonical(path):
    """Returns an absolute path with its folder's links resolved and its last name kept (a link stays the link)."""
    path = os.path.normpath(path)
    return os.path.join(os.path.realpath(os.path.dirname(path)), os.path.basename(path))


def changer_operands(argv):
    """Returns (the files, recursive, follows links in the tree) of a chmod, chown or chgrp command line. The mode,
    owner or group operand is not a file; with --reference there is none. Options may sit among the files."""
    files, first, recursive, follows, ended, i = [], True, False, False, False, 1
    while i < len(argv):
        word = argv[i]
        i += 1
        if not ended and word == '--':
            ended = True
        elif not ended and word.startswith('--') and len(word) > 2:
            option, attached, _ = word.partition('=')
            recursive = recursive or option.startswith('--rec')
            follows = follows or option == '--dereference'
            if option.startswith(('--ref', '--fr')):
                first = first and not option.startswith('--ref')
                i += 0 if attached else 1
        elif not ended and len(word) > 1 and word[0] == '-' and set(word[1:]) <= CHANGER_LETTERS:
            recursive = recursive or 'R' in word
            follows = follows or bool(set(word) & {'L', 'H'})
        elif first:
            first = False
        else:
            files.append(word)
    return files, recursive, follows and recursive


def find_starts(argv):
    """Returns (the folders find walks, whether it follows links) of a find command line."""
    i, follows = 1, False
    while i < len(argv) and (argv[i] in ('-H', '-L', '-P', '-D') or argv[i].startswith('-O')):
        follows = follows or argv[i] == '-L'
        i += 2 if argv[i] == '-D' else 1
    starts = []
    while i < len(argv) and not argv[i].startswith('-') and argv[i] not in ('(', '!', ')', ','):
        starts.append(argv[i])
        i += 1
    return starts or ['.'], follows or '-follow' in argv


def find_changes(argv):
    """True when a find command line runs chmod, chown or chgrp on what it finds (-exec, -execdir, -ok)."""
    for index, word in enumerate(argv):
        if word in FIND_ACTIONS:
            rest = argv[index + 1 :]
            stop = next((k for k, w in enumerate(rest) if w in (';', '+')), len(rest))
            if any(CHANGER_WORD.search(w) for w in rest[:stop]):
                return True
    return False


def makes_links(argv):
    """True for a command line that makes links: ln, and cp with -l or --link (hard links), -s or --symbolic-link."""
    name = os.path.basename(argv[0])
    if name == 'ln':
        return True
    if name != 'cp':
        return False
    for word in argv[1:]:
        if word == '--':
            break
        if word in ('--link', '--symbolic-link'):
            return True
        if word.startswith('-') and not word.startswith('--'):
            names, _, _ = short_options(word, {'-t', '-S'})
            if {'-l', '-s'} & set(names):
                return True
    return False


def link_paths(argv, folder):
    """Returns [(link, [where it may point])] for an ln (or cp -l, cp -s) command line run in folder: each link it
    makes, as a canonical path, and its target read from the link's folder (a symbolic link) and from folder (a hard
    or -r link)."""
    if folder is None:
        return []
    names, target_dir, i = [], None, 1
    while i < len(argv):
        word = argv[i]
        i += 1
        if word == '--':
            names.extend(argv[i:])
            break
        if word.startswith('--'):
            option, attached, value = word.partition('=')
            if option in ('--target-directory', '--suffix'):
                value = value if attached else (argv[i] if i < len(argv) else '')
                i += 0 if attached else 1
                target_dir = value if option == '--target-directory' else target_dir
        elif word.startswith('-') and len(word) > 1:
            _, option, glued = short_options(word, {'-t', '-S'})
            value = glued if glued is not None else (argv[i] if option and i < len(argv) else '')
            i += 1 if option and glued is None else 0
            target_dir = value if option == '-t' else target_dir
        else:
            names.append(word)
    if target_dir is not None:
        pairs = [(os.path.join(target_dir, os.path.basename(n.rstrip('/'))), n) for n in names]
    elif len(names) == 1:
        pairs = [(os.path.basename(names[0].rstrip('/')), names[0])]
    else:
        pairs = [(names[-1], n) for n in names[:-1]]
        pairs += [(os.path.join(names[-1], os.path.basename(n.rstrip('/'))), n) for n in names[:-1]]
    links = []
    for link, source in pairs:
        where = canonical(os.path.join(folder, os.path.expanduser(link)))
        source = os.path.expanduser(source)
        links.append((where, [os.path.join(os.path.dirname(where), source), os.path.join(folder, source)]))
    return links


class CoreGuard:
    """Judges what would change the read-only core of an installed workspace: chmod, chown and chgrp (also run by
    find, xargs, sudo or a shell) and git init or clone. The core is every path under the root of an installed
    workspace (the nearest folder above with .aiwp/manifest.json), the root included, that is not under one of the
    writable paths scripts/aiwp.sh _writable prints. Outside an installed workspace nothing is judged."""

    def __init__(self, root, cwd, run, entries):
        self.run, self.listed = run, None
        self.roots = {found for found in (installed_root(os.path.realpath(p)) for p in (root, cwd)) if found}
        self.links = []
        for entry in entries:
            if 'argv' in entry and not entry['remote'] and makes_links(entry['argv']):
                self.links.extend(link_paths(entry['argv'], entry['folder']))

    def writable(self):
        """Returns the writable paths of an installed workspace, relative to its root, from the aiwp.sh next to this
        script (the same release); None when it cannot be read. Read once per command line."""
        if self.listed is None:
            script = os.path.join(HERE, 'aiwp.sh')
            try:
                done = self.run(
                    ['bash', script, '_writable'], capture_output=True, text=True, check=False,
                    timeout=WRITABLE_TIMEOUT_SECONDS,
                )  # fmt: skip
                lines = [line.strip().rstrip('/') for line in done.stdout.splitlines() if line.strip()]
                valid = done.returncode == 0 and all(
                    not os.path.isabs(line) and '..' not in line.split('/') and line != '.' for line in lines
                )
                self.listed = [os.path.normpath(line) for line in lines] if valid and lines else []
            except (OSError, subprocess.SubprocessError):
                self.listed = []
        return self.listed or None

    def place(self, real):
        """Returns where a real path lies: (None, None) outside an installed workspace, else (workspace root, its
        path from the root, or '' for the root itself), or (root, None) when the writable list cannot be read and the
        path is not the root. A writable path gives (root, 'writable')."""
        top = installed_root(real)
        if top is None or real == top:
            return top, '' if top else None
        listed = self.writable()
        if listed is None:
            return top, None
        relative = os.path.relpath(real, top)
        if any(relative == w or relative.startswith(w + os.sep) for w in listed):
            return top, 'writable'
        return top, relative

    def reaches(self, real, recursive):
        """Returns a known workspace root (the session's or the folder's) that lies inside a real folder a recursive
        or glob target walks, or None."""
        return next((known for known in sorted(self.roots) if recursive and strictly_under(known, real)), None)

    def judge_path(self, path, recursive=False, follows=False):
        """Returns ('deny' | 'ask', detail) for one target path, or None when it is outside every installed workspace
        or in a writable path."""
        real = os.path.realpath(path)
        top, where = self.place(real)
        below = self.reaches(real, recursive)
        if top is None:
            return ('deny', 'the installed workspace at ' + below + ', inside ' + real) if below else None
        if where == '':
            return 'deny', 'the root of the installed workspace at ' + top
        if where is None:
            return 'ask', 'the list of writable folders could not be read (scripts/aiwp.sh _writable failed)'
        if where != 'writable':
            return 'deny', where + ' (the core of the installed workspace at ' + top + ')'
        if follows:
            return 'deny', real + ', a tree it walks following links, which may lead into the core of ' + top
        if below:
            return 'deny', 'the installed workspace at ' + below + ', inside ' + real
        try:
            info = os.lstat(real)
        except OSError:
            return None
        if not os.path.isdir(real) and info.st_nlink > 1:
            return 'ask', real + ', a file with other hard links, one of which may be a file of the core'
        return None

    def judge_pattern(self, prefix, folder, decision, allow_writable, what):
        """Judges a word the line cannot spell out (a glob, or a variable it cannot resolve) by its literal prefix:
        the folder that prefix names is where the matches lie. allow_writable: a writable folder there is safe.
        what: how the detail names the paths."""
        if folder is None and not os.path.isabs(prefix):
            return (decision, what + ' in a folder the line does not tell') if self.roots else None
        base = prefix if prefix.endswith('/') or not prefix else os.path.dirname(prefix)
        real = os.path.realpath(os.path.join(folder or '', base))
        top, where = self.place(real)
        below = self.reaches(real, True)
        if top is None:
            held = ', which holds the installed workspace at '
            return (decision, what + ' under ' + real + held + below) if below else None
        if where is None:
            return 'ask', 'the list of writable folders could not be read (scripts/aiwp.sh _writable failed)'
        if allow_writable and where == 'writable' and not below:
            return None
        return decision, what + ' under ' + real + ', in the installed workspace at ' + top

    def judge_word(self, word, folder, recursive=False, follows=False, variables=None):
        """Returns ('deny' | 'ask', detail) for one target word of the line, or None. A variable the line or the
        environment does not set asks; a glob is judged by its literal prefix; a link the same line makes is judged
        by where it points."""
        known = {**os.environ, 'PWD': folder or '', **(variables or {})}
        word = VARIABLE.sub(lambda m: known.get(m.group(1) or m.group(2)) or m.group(0), word)
        word = os.path.expanduser(word)
        if '$' in word:
            return self.judge_pattern(word[: word.index('$')], folder, 'ask', False, 'a path held in a variable')
        glob = next((k for k, char in enumerate(word) if char in GLOB_CHARS), None)
        if glob is not None:
            if '..' in word[glob:].split('/') and self.roots:
                return 'deny', 'a pattern that climbs with .. after a wildcard, which I cannot follow'
            found = self.judge_pattern(word[:glob], folder, 'deny', True, 'what the wildcard matches')
            if found or folder is None and not os.path.isabs(word):
                return found
            # A link the same line makes under the folder the wildcard reads is judged by where it points.
            prefix = word[:glob]
            base = prefix if prefix.endswith('/') or not prefix else os.path.dirname(prefix)
            base = canonical(os.path.join(folder or '', base))
            for link, sources in self.links:
                if strictly_under(link, base):
                    for source in sources:
                        linked = self.judge_path(source, recursive, follows)
                        if linked:
                            return linked[0], 'a link the same line makes, pointing to ' + linked[1]
            return None
        if folder is None and not os.path.isabs(word):
            return ('ask', 'a path in a folder the line does not tell') if self.roots else None
        path = os.path.join(folder or '', word)
        found = self.judge_path(path, recursive, follows)
        if found and found[0] == 'deny':
            return found
        target = canonical(path)
        for link, sources in self.links:
            # The target is the link or under it; or, recursive, the link lies in the tree it walks (a hard link shares
            # the core file itself).
            if target == link or strictly_under(target, link):
                tails = [target[len(link) :]]
            elif recursive and strictly_under(link, target):
                tails = ['']
            else:
                continue
            for source in sources:
                linked = self.judge_path(source + tails[0], recursive, follows)
                if linked:
                    return linked[0], 'a link the same line makes, pointing to ' + linked[1]
        return found

    def judge_fed(self, entry, recursive, follows):
        """Yields the verdicts on the files xargs or parallel hands to the command: what reaches its stdin when the
        line shows it, what the command that pipes into it names (the folders a find walks), and the folder it runs
        in, whose files a listing may name."""
        folder = entry['folder']
        yield self.judge_pattern('', folder, 'deny', True, 'the files xargs reads from its input')
        for text in entry.get('stdin') or []:
            for word in text.split():
                yield self.judge_word(word, folder, recursive, follows, entry.get('vars'))
        source = entry.get('source')
        argv = strip_wrappers(source['argv'])[0] if source and entry.get('stdin') is None else []
        if argv and os.path.basename(argv[0]) == 'find':
            starts, walks_links = find_starts(argv)
            for start in starts:
                yield self.judge_word(start, source['cwd'], True, walks_links, source['vars'])
        elif argv and os.path.basename(argv[0]) not in ('echo', 'printf'):
            for word in plain_words(argv[1:]):
                yield self.judge_word(word, source['cwd'], recursive, follows, source['vars'])

    def verdict(self, entry):
        """Returns ('deny' | 'ask', reason) for a chmod, chown or chgrp that reaches the core of an installed
        workspace, run directly or by find, xargs or parallel; None otherwise."""
        argv, folder, wrappers = entry['argv'], entry['folder'], entry['wrappers']
        name = os.path.basename(argv[0])
        found = []
        if HELP_OPTIONS & set(argv[1:]):
            return None
        if name == 'find' and find_changes(argv):
            starts, follows = find_starts(argv)
            found = [self.judge_word(start, folder, True, follows, entry.get('vars')) for start in starts]
            name = 'find -exec ' + next(CHANGER_WORD.search(w).group(0) for w in argv if CHANGER_WORD.search(w))
        elif name in CHANGERS:
            files, recursive, follows = changer_operands(argv)
            handed = bool(wrappers & {'xargs', 'parallel', 'find'})
            found = [
                self.judge_word(word, folder, recursive, follows, entry.get('vars'))
                for word in files
                if not (handed and PLACEHOLDER.search(word))
            ]
            if wrappers & {'xargs', 'parallel'}:
                found.extend(self.judge_fed(entry, recursive, follows))
        return self.pick(name, [item for item in found if item])

    def git_verdict(self, parts, entry):
        """Returns ('deny' | 'ask', reason) for a git init or clone whose new repository (or separate git folder)
        lands in the core of an installed workspace, the root included; None otherwise."""
        sub, args = parts['sub'], parts['args']
        values = INIT_VALUE_OPTIONS if sub == 'init' else CLONE_VALUE_OPTIONS
        words, targets, i = [], [], 0
        while i < len(args):
            word = args[i]
            option, attached, value = word.partition('=')
            if word == '--':
                words.extend(args[i + 1 :])
                break
            if option == '--separate-git-dir':
                targets.append(value if attached else (args[i + 1] if i + 1 < len(args) else '.'))
            i += 2 if word in values else 1
            if not word.startswith('-'):
                words.append(word)
        if sub == 'init':
            targets.append(words[0] if words else '.')
            targets += [parts[key] for key in ('git_dir', 'work_tree') if parts[key]]
        elif len(words) > 1:
            targets.append(words[1])
        elif words:
            name = re.split(r'[/:]', words[0].rstrip('/'))[-1] or '.'
            name = name[:-4] if name.endswith('.git') and len(name) > 4 else name
            targets += [name, name + '.git']
        found = [
            self.judge_word(os.path.join(parts['folder'], target), entry['folder'], variables=entry.get('vars'))
            for target in targets
        ]
        return self.pick('git ' + sub, [item for item in found if item])

    @staticmethod
    def pick(name, found):
        """Returns the first deny among the verdicts, else the first question, as (decision, reason); None when there
        is none."""
        for decision, detail in sorted(found, key=lambda item: item[0] != 'deny'):
            if decision == 'deny' and name.startswith('git '):
                return 'deny', name + ' would create a repository at ' + detail + '. ' + NO_REPO_HINT + '.'
            if decision == 'deny':
                return 'deny', name + ' would change ' + detail + '. ' + CORE_HINT + '.'
            return 'ask', name + ' may reach the read-only core of an installed workspace: ' + detail
        return None


def command_verdict(argv, wrappers):
    """Returns ('deny' | 'ask', reason) for one simple command that is not git (wrappers already dropped), or None.
    Everything else is left to Claude Code's own permission mode."""
    name, args = os.path.basename(argv[0]), argv[1:]
    words = plain_words(args)
    # Before --help: aiwp _sync reads only its first argument, so "aiwp _sync --help" still syncs.
    core = aiwp_core_verdict(argv, wrappers)
    if core:
        return core
    if HELP_OPTIONS & set(args):
        return None
    if name in AIWP_SCRIPTS:
        return aiwp_verdict(argv)
    if name in SHELLS | {'source', '.'}:
        script = next((k for k, a in enumerate(args) if os.path.basename(a) in AIWP_SCRIPTS), None)
        if script is not None:
            return aiwp_verdict(args[script:])
    if name in ('terraform', 'tofu'):
        changes = TF_CHANGES & set(words) or (words[:1] == ['state'] and TF_STATE_CHANGES & set(words[1:2]))
        if changes or words[:2] == ['workspace', 'delete']:
            return 'deny', (
                name + ' changes cloud resources or state. Only through aiwp-cmds.sh apply, from the main branch of '
                "projects/, at the human's request and with the plan confirmed"
            )
        return None
    if name in DOCKERS | {'docker-compose'}:
        reason = docker_db_reason(['compose'] + args if name == 'docker-compose' else args)
        return ('ask', reason) if reason else None
    if name in SQL_CLIENTS and any(
        SQL_DESTRUCTIVE.search(text) for a in args if ' ' in a or '(' in a for text in (a, a[2:])
    ):
        return 'ask', name + ' runs DROP or TRUNCATE and deletes database data'
    dropping = (
        name == 'dropdb'
        or (name == 'mysqladmin' and 'drop' in words)
        or (name == 'dotnet' and words[:3] == ['ef', 'database', 'drop'])
        or (name == 'prisma' and (words[:2] == ['migrate', 'reset'] or '--force-reset' in args))
        or (name in ('rails', 'rake') and bool({'db:drop', 'db:reset', 'db:purge'} & set(words)))
    )
    if dropping:
        return 'ask', name + ' deletes a database'
    if name == 'rm' and any(DATA_FILE.search(w.rstrip('/')) for w in words):
        return 'ask', 'rm deletes the data folder or file of a database'
    return None


def shell_mode(argv):
    """Returns where a shell command line takes its commands from: ('text', the string given to -c), ('script', the
    file), ('stdin', None), or ('none', None) when it runs nothing (-n, or a -c with no string)."""
    i, size, forced, text = 1, len(argv), False, False
    while i < size:
        arg = argv[i]
        if arg in ('-', '--'):
            i += 1
            break
        if not arg.startswith(('-', '+')):
            break
        if arg.startswith('--'):
            i += 2 if arg in ('--rcfile', '--init-file') else 1
            continue
        letters = arg[1:]
        if 'n' in letters and arg.startswith('-'):
            return 'none', None
        text = text or 'c' in letters
        forced = forced or 's' in letters
        i += 2 if letters.endswith(('o', 'O')) else 1
    if text:
        return ('text', argv[i]) if i < size else ('none', None)
    return ('stdin', None) if forced or i >= size or argv[i] == '/dev/stdin' else ('script', argv[i])


def ssh_command(argv):
    """Returns the words of the remote command of an ssh command line: what follows the host and the options ssh
    still accepts after it (ssh host -p 2222 "command")."""

    def after_options(i):
        while i < len(argv) and len(argv[i]) > 1 and argv[i].startswith('-') and argv[i] != '--':
            _, option, glued = short_options(argv[i], SSH_VALUE_OPTIONS)
            i += 2 if option and glued is None else 1
        return i

    remote = argv[after_options(after_options(1) + 1) :]
    return remote[1:] if remote[:1] == ['--'] else remote


def is_launcher(argv):
    """True when the command runs, somewhere else, a command given in its own arguments."""
    name = os.path.basename(argv[0])
    if name in LAUNCHERS | RUNNERS:
        return True
    if name in SHELLS:
        return len(argv) > 1 and os.path.basename(argv[1]) in LAUNCHERS
    if name in DOCKERS | {'docker-compose'}:
        words = docker_words((['compose'] if name == 'docker-compose' else []) + argv[1:])
        return bool({'exec', 'run'} & set(words[:2]))
    if name == 'kubectl':
        before = argv[1 : argv.index('--')] if '--' in argv else argv[1:]
        return bool({'exec', 'run', 'debug'} & set(plain_words(before)))
    return False


def launched(argv):
    """Yields what a command launches, as (kind, value): ('argv', words) from a guarded program or shell in its
    arguments on, ('bulk', words) for what find runs on every file, ('text', string) for a command line another shell
    will read (ssh joins its words; su -c), ('reader', None) when it opens a shell that reads its stdin."""
    name = os.path.basename(argv[0])
    if name == 'find':
        for index, word in enumerate(argv):
            if word in ('-exec', '-execdir', '-ok', '-okdir'):
                rest = argv[index + 1 :]
                stop = next((k for k, w in enumerate(rest) if w in (';', '+')), len(rest))
                if rest[:stop]:
                    yield 'bulk', rest[:stop]
    if name == 'ssh':
        remote = ssh_command(argv)
        yield ('text', ' '.join(remote)) if remote else ('reader', None)
        return
    starts = []
    if is_launcher(argv):
        first = 2 if name in SHELLS else 1
        starts = [k for k in range(first, len(argv)) if os.path.basename(argv[k]) in GUARDED | SHELLS]
        if name == 'su':
            given = [argv[k + 1] for k in range(1, len(argv) - 1) if argv[k] in ('-c', '--command')]
            if given:
                yield 'text', given[0]
            elif not starts:
                yield 'reader', None
    elif name not in GUARDED | {'echo', 'printf'} and '--' in argv[1:-1] and not aiwp_run(argv, ''):
        index = argv.index('--', 1) + 1
        rest = strip_wrappers(argv[index:])[0]
        starts = [index] if rest and os.path.basename(rest[0]) in GUARDED | SHELLS else []
    for index in starts[:MAX_CANDIDATES]:
        yield 'argv', argv[index:]


def nested_texts(argv):
    """Yields the command lines one simple command carries as text: eval, trap "<text>", git submodule foreach
    "<text>". (A shell's -c text is read by shell_mode.)"""
    name = os.path.basename(argv[0])
    if name == 'eval':
        yield ' '.join(argv[1:])
    elif name == 'trap' and len(argv) > 2 and not argv[1].startswith('-'):
        yield argv[1]
    elif name == 'git' and 'foreach' in argv:
        rest = argv[argv.index('foreach') + 1 :]
        while rest and rest[0].startswith('-'):
            rest = rest[1:]
        yield ' '.join(rest)


def stdin_text(argv):
    """Returns, as a list with one text, what an echo or printf command line prints."""
    args = argv[1:]
    while args and args[0].startswith('-'):
        args = args[1:]
    if os.path.basename(argv[0]) == 'printf' and len(args) > 1:
        return ['\n'.join(args[1:]).replace('\\n', '\n')]
    return [' '.join(args).replace('\\n', '\n')]


def output_files(argv):
    """Returns the files a command line names as its output (-o file, --output file, --output=file)."""
    named = [argv[k + 1] for k in range(1, len(argv) - 1) if argv[k] in ('-o', '-O', '--output', '--output-document')]
    return named + [a.partition('=')[2] for a in argv[1:] if a.startswith(('--output=', '--output-document='))]


def file_key(folder, path):
    """Returns the name under which a file the line writes is remembered: its path from the folder of the command."""
    return os.path.normpath(os.path.join(folder, path) if folder is not None else path)


def stdin_of(entry, inherited, folder, written):
    """Returns what reaches the stdin of a command, as (fed, texts): texts is the list of texts when they are
    written in the line (a heredoc, a here-string, an echo or printf piped in, a file the line wrote), None when
    what comes in cannot be seen (another pipe, a download). inherited: the stdin of the command line this one is
    nested in. written: the files the line wrote, by file_key."""
    if entry['inputs']:
        return True, list(entry['inputs'])
    for operator, target in entry['redirects']:
        if operator == '<' and FETCHED in target:
            return True, None
        if operator == '<' and file_key(folder, target) in written:
            return True, list(written[file_key(folder, target)])
    if not entry['piped']:
        return inherited
    source = entry['source']
    argv = strip_wrappers(source['argv'])[0] if source else []
    name = os.path.basename(argv[0]) if argv else ''
    if name in ('echo', 'printf'):
        return True, stdin_text(argv)
    if name == 'cat' and source['inputs'] and not plain_words(argv[1:]):
        return True, list(source['inputs'])
    return True, None


def aiwp_run(argv, folder):
    """Returns (command words, clone folder) for scripts/aiwp-cmds.sh run <work>/<clone> -- <command>, called directly,
    by a shell or by source; None otherwise. The folder is None when the script's place cannot be told."""
    name, args = os.path.basename(argv[0]), argv[1:]
    if name == 'aiwp-cmds.sh':
        script, rest = argv[0], args
    else:
        if name not in SHELLS | {'source', '.'}:
            return None
        index = next((k for k, a in enumerate(args) if os.path.basename(a) == 'aiwp-cmds.sh'), None)
        if index is None:
            return None
        script, rest = args[index], args[index + 1 :]
    if len(rest) < 3 or rest[0] != 'run' or '--' not in rest:
        return None
    command = rest[rest.index('--') + 1 :]
    if folder is None and not os.path.isabs(script):
        return command, None
    root = os.path.dirname(os.path.dirname(os.path.abspath(os.path.join(folder or '', script))))
    target = rest[1]
    if os.path.isabs(target):
        clone = target
    elif target.startswith(os.path.join('tmp', 'work') + os.sep):
        clone = os.path.join(root, target)
    else:
        clone = os.path.join(root, 'tmp', 'work', target)
    return command, clone


def walk(command, cwd, depth=0, wrappers=frozenset(), stdin=NO_STDIN, remote=False, shared=None, group=None):
    """Yields one entry per simple command of a command line, nested command lines included: a dict with argv, env,
    wrappers, folder, redirects, remote, group, unset and cleared (what env -u, env -i or exec -c take out of the
    environment), or {'reason': text, 'group': group} for something that asks on its own. A part with no command
    (X=1, > f, exec 3> f, env -u X) is an entry too, marked bare, with the argv [':'], so its assignments and its
    redirections are judged. wrappers and stdin: what wraps and what feeds the command line this text was found in.
    remote: False, or the entry of the command that runs it in another machine, container or user (ssh, docker exec).
    shared: what the whole walk shares (the files the line wrote, the nested texts left to read; 'unread' once a
    nested text could not be read, 'fed' once a command runs or reads a file the line wrote, 'loose' once a
    redirection carries no command). group: the top-level command of the line this text was found in; None for the
    line itself, whose groups the lexer counts."""
    lexer = Lexer(command, cwd).run()
    shared = {'written': {}, 'texts': MAX_TEXTS} if shared is None else shared
    if lexer.loose:
        shared['loose'] = True
    for operator, target, folder, owner in lexer.loose:
        yield {
            'argv': [':'], 'env': {}, 'wrappers': wrappers, 'folder': folder, 'redirects': [(operator, target)],
            'remote': remote, 'vars': {}, 'stdin': None, 'source': None, 'group': owner if group is None else group,
            'unset': [], 'cleared': False, 'bare': True,
        }  # fmt: skip
    written, texts, owners = shared['written'], [], []
    for entry in lexer.commands:
        mine = entry['group'] if group is None else group
        argv, info = strip_wrappers(entry['argv'])
        if not argv and entry['redirects']:
            shared['loose'] = True  # X=1 > f, exec 3> f: a redirection no entry carries
        folder = entry['cwd']
        if info['chdir']:
            folder = resolve_folder(folder, info['chdir'], entry['vars'])
        outer = info['wrappers'] | wrappers
        fed = stdin_of(entry, stdin, folder, written)
        if any(operator == '<' and file_key(folder, target) in written for operator, target in entry['redirects']):
            shared['fed'] = True
        env = {**entry['exports'], **info['env']}
        texts.extend((text, folder, outer, fed, remote) for text in info['texts'])
        targets = []
        reader = info['shell'] and not argv
        if not argv and (entry['redirects'] or info['env'] or info['unset'] or info['cleared']):
            yield {
                'argv': [':'], 'env': env, 'wrappers': outer, 'folder': folder, 'redirects': entry['redirects'],
                'remote': remote, 'vars': entry['vars'], 'stdin': None, 'source': None, 'group': mine,
                'unset': info['unset'], 'cleared': info['cleared'], 'bare': True,
            }  # fmt: skip
        if argv:
            name = os.path.basename(argv[0])
            record = {
                'argv': argv, 'env': env, 'wrappers': outer, 'folder': folder, 'redirects': entry['redirects'],
                'remote': remote, 'vars': entry['vars'], 'stdin': fed[1], 'source': entry['source'], 'group': mine,
                'unset': info['unset'], 'cleared': info['cleared'],
            }  # fmt: skip
            away = remote or (record if name in ELSEWHERE else False)
            yield record
            targets.append((argv, outer, remote))
            if len(argv) == 1 and ' ' in argv[0].strip():
                texts.append((argv[0], folder, outer, fed, remote))
            files = [target for operator, target in entry['redirects'] if operator.startswith('>')]
            if name in ('cat', 'tee') and fed[1] and (name == 'tee' or not plain_words(argv[1:])):
                for target in files + (plain_words(argv[1:]) if name == 'tee' else []):
                    written[file_key(folder, target)] = fed[1]
            elif name in ('echo', 'printf'):
                for target in files:
                    written[file_key(folder, target)] = stdin_text(argv)
            elif name in FETCHERS:
                for target in files + output_files(argv):
                    written[file_key(folder, target)] = [FETCHED]
            run = aiwp_run(argv, folder)
            if run:
                texts.append((shlex.join(run[0]), run[1], outer, fed, remote))
            for kind, value in launched(argv):
                if kind == 'text':
                    texts.append((value, folder, outer, fed, away))
                elif kind == 'reader':
                    reader = True
                else:
                    inner, more = strip_wrappers(value)
                    if inner:
                        around = outer | more['wrappers'] | ({'find'} if kind == 'bulk' else set())
                        yield {
                            'argv': inner, 'env': env, 'wrappers': around, 'folder': folder, 'redirects': [],
                            'remote': away, 'vars': entry['vars'], 'stdin': None, 'source': None, 'group': mine,
                            'unset': more['unset'], 'cleared': more['cleared'],
                        }  # fmt: skip
                        targets.append((inner, around, away))
        for target, around, away in targets:
            base = os.path.basename(target[0])
            script = target[0]
            if base in SHELLS:
                mode, script = shell_mode(target)
                if mode == 'text':
                    texts.append((script, folder, around, fed, away))
                reader = reader or mode == 'stdin'
                script = script if mode == 'script' else None
            elif base in ('source', '.'):
                script = target[1] if len(target) > 1 else None
            else:
                texts.extend((text, folder, around, fed, away) for text in nested_texts(target))
            if script and FETCHED in script and (base in SHELLS or base in ('source', '.')):
                yield {'reason': FETCHED_TEXT, 'group': mine}
            if script and file_key(folder, script) in written:
                shared['fed'] = True
                texts.extend((body, folder, around, NO_STDIN, away) for body in written[file_key(folder, script)])
            if base in SQL_CLIENTS:
                files = [target[k + 1] for k in range(1, len(target) - 1) if target[k] in ('-f', '--file', '-i')]
                given = (fed[1] or []) + [body for f in files for body in written.get(file_key(folder, f), [])]
                shared['fed'] = shared.get('fed') or any(file_key(folder, f) in written for f in files)
                if any(SQL_DESTRUCTIVE.search(text) for text in given):
                    reason = base + ' gets DROP or TRUNCATE on its input or from a file written on the line'
                    yield {'reason': reason, 'group': mine}
        if reader and fed[0]:
            if fed[1] is None:
                yield {'reason': UNSEEN_STDIN, 'group': mine}
            else:
                texts.extend((text, folder, outer, NO_STDIN, remote) for text in fed[1])
        owners.extend([mine] * (len(texts) - len(owners)))
    for (text, folder, around, fed, away), owner in zip(texts, owners):
        shared['texts'] -= 1
        if depth >= MAX_DEPTH or shared['texts'] < 0:
            yield {'reason': 'there are too many nested commands for me to evaluate', 'group': owner}
            continue
        if FETCHED in text:
            yield {'reason': FETCHED_TEXT, 'group': owner}
            continue
        try:
            yield from walk(text, folder, depth + 1, around, fed, away, shared, owner)
        except ValueError:
            shared['unread'] = True
            if GUARDED_WORD.search(text):
                yield {'reason': UNREADABLE, 'group': owner}


def run_git(run, folder, *args):
    """Runs git in a folder and returns its stdout split on NUL, or None when git fails."""
    done = run(
        ['git', '-C', folder, *args], capture_output=True, encoding='utf-8', errors='surrogateescape', check=False
    )
    if done.returncode != 0:
        return None
    return [part for part in done.stdout.split('\0') if part]


def staging_of(parts, folder, batch=False):
    """Returns what a git command may add to the commit that follows it in the same line: None (nothing),
    {'scope': 'unknown'} when it stages content that cannot be listed beforehand, or {'scope': 'all' | 'tracked' |
    'paths', 'paths': [...], 'force': bool}, or {'scope': 'unstage', 'paths': [...]} when it takes paths out of the
    index. batch: xargs or find runs the command, with paths the line does not show."""
    sub, args = parts['sub'], parts['args']
    words = plain_words(args)
    unknown = {'scope': 'unknown', 'paths': [], 'force': False}
    unstages = (
        (sub == 'restore' and '--staged' in args and '--worktree' not in args and not has_short_flag(args, 'sW'))
        or (sub == 'rm' and '--cached' in args)
        or (sub == 'reset' and not {'--hard', '--soft', '--keep', '--merge'} & set(args))
    )
    if sub == 'reset' and unstages:
        words = [w for w in words if w != 'HEAD' and ('--' in args or exists_in(folder, w))]
    if (sub in ('add', 'stage', 'mv', 'checkout') or unstages) and words and folder is None:
        return unknown
    if unstages and words and not any(a.startswith('--source') for a in args):
        return {'scope': 'unstage', 'paths': [os.path.join(folder, word) for word in words], 'force': False}
    if sub in ('add', 'stage') and (
        batch or any('$' in w or w.startswith(':') for w in words) or any(a.startswith('--pathspec-from') for a in args)
    ):
        return unknown
    paths = [os.path.join(folder or '', word) for word in words]
    if sub in ('add', 'stage'):
        force = has_short_flag(args, 'f') or '--force' in args
        if paths:
            return {'scope': 'paths', 'paths': paths, 'force': force}
        if has_short_flag(args, 'A') or {'--all', '--no-ignore-removal'} & set(args):
            return {'scope': 'all', 'paths': [], 'force': force}
        updates = has_short_flag(args, 'u') or '--update' in args
        return {'scope': 'tracked', 'paths': [], 'force': force} if updates else None
    if sub == 'mv':
        return {'scope': 'paths', 'paths': paths[-1:], 'force': False}
    if sub == 'checkout':
        named = args[args.index('--') + 1 :] if '--' in args else [w for w in words if exists_in(folder, w)]
        taken = [os.path.join(folder or '', word) for word in named]
        return {'scope': 'paths', 'paths': taken, 'force': False} if taken else None
    stages_blind = (
        (sub in ('cherry-pick', 'revert', 'merge') and ({'--no-commit', '--squash'} & set(args) or '-n' in args))
        or (sub == 'apply' and {'--index', '--cached'} & set(args))
        or (sub == 'stash' and words[:1] in (['pop'], ['apply']) and '--index' in args)
        or (sub == 'reset' and reset_moves_branch(args, folder))
        or (sub == 'restore' and any(a.startswith(('--source', '-s')) for a in args))
        or sub in ('read-tree', 'update-index')
    )
    return unknown if stages_blind else None


def is_under(path, folder):
    """True when path is the folder or lies inside it (links resolved)."""
    path, folder = os.path.realpath(path), os.path.realpath(folder)
    return path == folder or path.startswith(folder.rstrip(os.sep) + os.sep)


def commit_files(run, top, wide, staging, created):
    """Returns (the files a commit in repo top may carry, the staged files whose content on disk differs), or None
    when git cannot list them. wide: the commit also takes tracked changes (-a, -i, -o, a pathspec). staging: what the
    same command line does to the index before the commit (staging_of), in order. created: the local secret files
    the line creates."""
    staged = run_git(run, top, 'diff', '--cached', '--name-only', '--diff-filter=ACMRT', '-z')
    unstaged = run_git(run, top, 'diff', '--name-only', '--diff-filter=ACMRT', '-z')
    if staged is None or unstaged is None:
        return None
    names, restaged = set(staged), set()
    takes_tracked = wide or any(item['scope'] in ('all', 'tracked') for item in staging)
    for item in staging:
        specs = [path for path in item['paths'] if is_under(path, top)]
        if item['scope'] == 'unstage':
            names -= {name for name in names if any(is_under(os.path.join(top, name), spec) for spec in specs)}
            continue
        if item['scope'] in ('all', 'tracked'):
            names |= set(unstaged)
        if item['scope'] == 'all':
            names |= set(run_git(run, top, 'ls-files', '--others', '--exclude-standard', '-z') or [])
        if item['force'] and (item['scope'] == 'all' or specs):
            ignored = run_git(run, top, 'ls-files', '--others', '-z', '--', *specs) or []
            names |= {name for name in ignored if local_secret(name)}
        if not specs:
            continue
        untracked = run_git(run, top, 'ls-files', '--others', '--exclude-standard', '-z', '--', *specs)
        changed = run_git(run, top, 'diff', '--name-only', '--diff-filter=ACMRT', '-z', '--', *specs)
        if untracked is None or changed is None:
            return None
        names |= set(untracked) | set(changed)
        restaged |= set(changed)
        # A file the same line creates and names does not exist yet: it is judged by its name.
        names |= {
            os.path.relpath(os.path.realpath(path), top)
            for path in specs
            if local_secret(os.path.relpath(os.path.realpath(path), top))
        }
    if wide:
        names |= set(unstaged)
    for path in created:
        relative = os.path.relpath(os.path.realpath(path), top)
        taking = [
            item
            for item in staging
            if item['scope'] == 'all' or (item['scope'] == 'paths' and any(is_under(path, p) for p in item['paths']))
        ]
        if relative.startswith('..') or not taking:
            continue
        ignore = run(['git', '-C', top, 'check-ignore', '-q', '--', relative], capture_output=True, check=False)
        if any(item['force'] for item in taking) or ignore.returncode != 0:
            names.add(relative)
    differs = [] if takes_tracked else sorted((set(staged) & set(unstaged) & names) - restaged)
    return sorted(names), differs


def scan_secrets(run, root, top, names):
    """Runs the gitleaks check on the files of a commit. Returns ('ok' | 'found' | 'unavailable', detail)."""
    rel_top = os.path.relpath(top, os.path.realpath(root))
    if rel_top.startswith('..'):
        return 'unavailable', 'the repository is outside the workspace'
    if any('\n' in name for name in names):
        return 'unavailable', 'a file name holds a line break'
    listed = [
        os.path.normpath(os.path.join(rel_top, name))
        for name in names
        if os.path.isfile(os.path.join(top, name)) and not os.path.islink(os.path.join(top, name))
    ]
    if not listed:
        return 'ok', ''
    docker = os.environ.get('GUARD_BASH_DOCKER', 'docker')
    validate = os.environ.get('GUARD_BASH_VALIDATE', os.path.join(root, 'scripts', 'validate.sh'))
    handle, list_path = tempfile.mkstemp(prefix='guard-bash-', suffix='.list')
    try:
        with os.fdopen(handle, 'w', encoding='utf-8', errors='surrogateescape') as out:
            out.write('\n'.join(listed) + '\n')
        if run([docker, 'info'], capture_output=True, text=True, check=False, timeout=15).returncode != 0:
            return 'unavailable', 'Docker did not respond'
        done = run(
            ['bash', validate, '--only', 'secrets', '--path', rel_top, '--files', list_path],
            capture_output=True, text=True, check=False, timeout=SCAN_TIMEOUT_SECONDS,
        )  # fmt: skip
    except (OSError, subprocess.SubprocessError) as error:
        return 'unavailable', type(error).__name__
    finally:
        os.unlink(list_path)
    if done.returncode == 0:
        return 'ok', ''
    output = ANSI.sub('', done.stdout + done.stderr).strip()
    tail = '\n'.join(output.splitlines()[-12:])
    return ('found', tail) if done.returncode == 1 and LEAK_MARKER.search(output) else ('unavailable', tail)


def commit_decision(parts, folder, root, run, staging, created):
    """Returns (decision, reason) for a git commit, or None when nothing stops it. staging: what the same command
    line stages before the commit (a list of staging_of results). created: the local secret files the line creates."""
    flags, paths = commit_options(parts['args'])
    if '--dry-run' in flags or HELP_OPTIONS & flags or '-h' in flags:
        return None
    asks = []
    tops = run_git(run, folder, 'rev-parse', '--show-toplevel') if folder is not None else None
    if not tops:
        return 'ask', 'I could not identify the repository of this commit to scan for secrets'
    top = os.path.realpath(tops[0].strip())
    wide = bool(paths) or bool({'-a', '--all', '-i', '--include', '-o', '--only'} & flags)
    files = commit_files(run, top, wide, staging, created)
    if files is None:
        return 'ask', 'git did not list the files of this commit, and I cannot scan for secrets'
    names, differs = files
    local = [name for name in names if local_secret(name)]
    if local:
        return 'deny', (
            'Commit refused: ' + ', '.join(local) + ' is a local secret file and does not go into git. '
            'Leave it out of the commit (git restore --staged <file>, or name in git add only what goes in) and put it '
            'in .gitignore. If the fix is on this same line (the .gitignore, for example), run the commit in a '
            'separate command. If it is intentional, the human makes this commit.'
        )  # fmt: skip
    state, detail = scan_secrets(run, root, top, names)
    if state == 'found':
        return 'deny', 'Commit refused: the secret scan (gitleaks) failed on the files of the commit.\n' + detail
    if state == 'unavailable':
        asks.append('the secret scan did not run (' + detail + '); confirm only if the commit carries no secret')
    if differs:
        asks.append('the staged content of ' + ', '.join(differs) + ' differs from disk, and the scan reads the disk')
    if any(item['scope'] == 'unknown' for item in staging):
        asks.append('the same line changes the stage before the commit, and I cannot see what will go into it')
    return ('ask', '; '.join(asks)) if asks else None


def local_secret(path):
    """True when a path names a local secret file: .env, local.settings.json, or a filled env/<name>.env of the
    custom layer."""
    return os.path.basename(path) in LOCAL_SECRET_FILES or bool(CUSTOM_ENV_FILE.search(path))


def created_secrets(entry):
    """Returns the local secret files one command creates, as paths: the target of a redirection, what cp, mv,
    touch and tee write, or the file a command names as its output (curl -o .env)."""
    argv, folder = entry['argv'], entry['folder']
    name, words = os.path.basename(argv[0]), plain_words(argv[1:])
    targets = [target for operator, target in entry['redirects'] if '>' in operator]
    if name in ('cp', 'mv', 'install', 'ln') and len(words) > 1:
        sources = [w for w in words[:-1] if local_secret(w)]
        targets += [words[-1]] + [os.path.join(words[-1], os.path.basename(source)) for source in sources]
    elif name in ('touch', 'tee'):
        targets += words
    targets += output_files(argv)
    if folder is None:
        return []
    return [path for path in (os.path.join(folder, t) for t in targets) if local_secret(path)]


# Approval of a line that stays in one clone of tmp/work/ (the trail): every command runs in the clone, every path it
# names stays there, and none reaches a remote system. What it cannot tell is left to the normal permission flow.
WORK_NAME = re.compile(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z0-9]+(-[a-z0-9]+)*$')
# Programs never approved: they reach a remote system, a cloud or a cluster (downloading dependencies is not that:
# npm, pip, uv, go, mvn, gradle and dotnet are judged like any command), run as another user or elsewhere, change the
# machine outside the clone, or keep their own rules (Docker and SQL clients; the workspace scripts, allowed by rule).
NOT_APPROVED = {
    'ssh', 'scp', 'sftp', 'rsync', 'ftp', 'telnet', 'nc', 'ncat', 'netcat', 'socat', 'mosh', 'rclone', 's3cmd',
    'aws', 'az', 'gcloud', 'gsutil', 'bq', 'kubectl', 'helm', 'terraform', 'tofu', 'pulumi', 'gh', 'glab', 'eksctl',
    'oc', 'doctl', 'flyctl', 'fly', 'heroku', 'vercel', 'netlify', 'firebase', 'wrangler', 'serverless', 'sls', 'cdk',
    'sam', 'ansible', 'ansible-playbook', 'vagrant', 'packer', 'skaffold', 'twine', 'pipx', 'docker-compose', 'kill',
    'pkill', 'killall', 'systemctl', 'launchctl', 'service', 'crontab', 'mount', 'umount', 'shutdown', 'reboot',
    'osascript', 'open', 'xdg-open', 'brew', 'apt', 'apt-get', 'dnf', 'yum', 'pacman', 'snap', 'defaults',
    'security', 'gpg', 'ssh-add', 'ssh-keygen', 'ssh-copy-id', 'conda', 'mamba', 'micromamba',
} | FETCHERS | DOCKERS | SQL_CLIENTS | LAUNCHERS | set(AIWP_SCRIPTS) | set(AIWP_PROGRAMS)  # fmt: skip
# Subcommand words that act on a remote system: npm publish, mvn deploy, gem push, twine upload, cargo yank...
REMOTE_WORDS = {'push', 'publish', 'unpublish', 'deploy', 'release', 'upload', 'login', 'logout', 'adduser', 'yank'}
# Package tools whose config subcommand writes the user's configuration (~/.npmrc, pip.conf, go env -w).
PACKAGE_TOOLS = {
    'npm', 'pnpm', 'yarn', 'bun', 'pip', 'pip3', 'uv', 'poetry', 'cargo', 'go', 'gem', 'bundle', 'composer',
}  # fmt: skip
# Wrappers whose command runs as another user, under a lock, or on arguments the line does not show.
UNCLEAR_WRAPPERS = {'sudo', 'doas', 'gosu', 'sshpass', 'xargs', 'parallel', 'flock'}
# Programs whose target, when it is the clone itself, takes its .git folder along (the hooks that scan and push).
WHOLE_CLONE = {'rm', 'mv', 'chmod', 'chown', 'chgrp'}
URL = re.compile(r'^[A-Za-z][A-Za-z0-9+.-]*://')
# What separates the tokens of a word that holds code or a message.
TOKEN_SEPARATORS = re.compile(r'[\s\'"`();,|&<>]+')
GLOB_ONLY = '*?['
MAX_MATCHES = 1000
SAFE_TARGETS = {'/dev/null', '/dev/stdout', '/dev/stderr', '/dev/stdin'}
# What entry_clone returns for a command that runs nowhere in particular: a cd, pushd or popd with no target.
ANYWHERE = ''


def clone_of(root, folder):
    """Returns the clone that holds a folder, as a real path: <root>/tmp/work/<yyyy-mm-dd>-<slug>/<clone>, links
    resolved; None when the folder is unknown or lies in no clone."""
    if folder is None or '$' in folder:
        return None
    work = os.path.realpath(os.path.join(root, 'tmp', 'work'))
    real = os.path.realpath(folder)
    if not strictly_under(real, work):
        return None
    parts = os.path.relpath(real, work).split(os.sep)
    if len(parts) < 2 or not WORK_NAME.match(parts[0]):
        return None
    return os.path.join(work, parts[0], parts[1])


def stays_in(path, clone):
    """True when a path, links resolved, is the clone or lies inside it, out of its .git folder (which holds the hooks
    that scan and push the branch)."""
    real = os.path.realpath(path)
    return is_under(real, clone) and os.path.relpath(real, clone).split(os.sep)[0] != '.git'


def glob_stays(piece, folder, clone):
    """True when what a wildcard word matches stays in the clone: the folder of its literal part is in the clone, no
    .. and no segment that starts with a dot follows the wildcard (.* may match ..), and what it matches now, links
    resolved, is in the clone too and is no local secret file."""
    segments = piece.split('/')
    first = next(k for k, segment in enumerate(segments) if any(char in segment for char in GLOB_ONLY))
    rest = segments[first:]
    if '..' in rest or any(segment.startswith('.') for segment in rest):
        return False
    prefix = '/'.join(segments[:first]) or ('/' if piece.startswith('/') else '.')
    if not stays_in(os.path.join(folder, prefix), clone):
        return False
    pattern = os.path.join(glob.escape(folder), piece)
    matches = list(itertools.islice(glob.iglob(pattern), MAX_MATCHES + 1))
    return len(matches) <= MAX_MATCHES and all(stays_in(match, clone) and not local_secret(match) for match in matches)


def piece_stays(piece, folder, clone):
    """True when one piece of a word, read as a path from the folder, stays in the clone. Every piece is read as a
    path: a plain name stays unless it is a link that leaves, or .git. A local secret file (.env, local.settings.json,
    env/<name>.env) never counts as staying: reading or copying it is left to the permission mode."""
    if piece in ('', '-', '{}'):
        return True
    if piece.startswith('~') or re.search(r'\{[^}]*(,|\.\.)', piece) or local_secret(piece):
        return False  # the home folder, a brace expansion ({a,../x}, {1..3}) that may name anything, a .env
    if any(char in piece for char in GLOB_ONLY):
        return glob_stays(piece, folder, clone)
    return stays_in(os.path.join(folder, piece), clone)


def word_stays(word, folder, clone):
    """True when every path a word may name stays in the clone, read from the folder: the word itself and each token
    of it (code or a message given as one word: python3 -c "open('/x')"), and of each, the value after its first =
    (--out=x, of=x, DESTDIR=x), the value glued to a short option (-o/x) and each piece between colons (a:/x). A URL is
    not a path, except file:. False when it cannot tell: a $ (a variable, a substitution), a ~, a brace expansion or a
    wildcard that could leave."""
    if '$' in word:
        return False
    candidates = []
    for token in dict.fromkeys([word, *TOKEN_SEPARATORS.split(word)]):
        candidates.append(token)
        if token.startswith('-') and not token.startswith('--'):
            candidates.append(token[2:])
        if '=' in token:
            candidates.append(token.partition('=')[2])
    pieces = []
    for item in candidates:
        if URL.match(item):
            if item.lower().startswith('file:'):
                return False
            continue
        pieces.append(item)
        if ':' in item and '://' not in item:
            pieces.extend(item.split(':'))
    return all(piece_stays(piece, folder, clone) for piece in pieces)


def redirects_stay(redirects, folder, clone):
    """True when every redirection target stays in the clone: /dev/null and the standard streams, a file descriptor
    duplication (2>&1, >&-), or a file read from the folder. With no clone, only the first two."""
    for operator, target in redirects:
        if target in SAFE_TARGETS or (operator.endswith('&') and (target.isdigit() or target == '-')):
            continue
        if clone is None or folder is None or not word_stays(target, folder, clone):
            return False
    return True


def reaches_out(argv):
    """True when a command acts on a remote system or outside the clone by what it is, whatever its paths say: a
    program of NOT_APPROVED (also run by a shell, a runner or after --), a remote subcommand word (push, publish,
    deploy...), git remote add or set-url, a git config write (it can turn off the clone's hooks), a link, a global
    install (npm -g, npm link, pip --user, python3 -m pip --user, go install, cargo install, uv tool, gem install,
    dotnet tool -g, composer global) and a package tool's configuration (npm config, go env -w)."""
    name, args = os.path.basename(argv[0]), argv[1:]
    words = plain_words(args)
    if name in NOT_APPROVED or makes_links(argv):
        return True
    if any(w.partition(':')[0] in REMOTE_WORDS or w.startswith('publish') for w in words):
        return True
    if (name in SHELLS | RUNNERS | {'source', '.'} or '--' in args) and any(
        os.path.basename(a) in NOT_APPROVED for a in args
    ):
        return True
    if name == 'git':
        parts = git_parts(argv)
        return parts['sub'] in ('remote', 'config', 'credential', 'send-email', 'request-pull') and not git_reads(
            parts['sub'], parts['args']
        )
    if name in ('npm', 'pnpm', 'yarn', 'bun') and (
        {'-g', '--global'} & set(args) or words[:1] in (['global'], ['link'], ['unlink'])
    ):
        return True
    if (name == 'uv' and words[:1] == ['tool'] and words[1:2] != ['run']) or (name == 'composer' and 'global' in words):
        return True  # uv tool install, composer global require: the user's tools, outside the clone
    if name == 'gem' and words[:1] in (['install'], ['i'], ['update'], ['uninstall']):
        return True  # gems land in the user's or the system's gem folder
    if name in ('npm', 'pnpm', 'yarn', 'bun') and any(
        a in ('--location=global', '--location=user') or (a == '--location' and b in ('global', 'user'))
        for a, b in zip(args, args[1:] + [''])
    ):
        return True
    if (name == 'bundle' and '--system' in args) or (name == 'uv' and '--system' in args):
        return True  # bundle install --system, uv pip install --system: the system's gems or packages
    if name == 'dotnet' and words[:1] == ['tool'] and {'-g', '--global'} & set(args):
        return True
    if name.startswith('python') and '--user' in args and {'pip', 'pip3', '-mpip', '-mpip3'} & set(args):
        return True  # python3 -m pip install --user
    if name in PACKAGE_TOOLS and (words[:1] == ['config'] or words[:1] == ['env'] and '-w' in args):
        return True  # npm config set, pip config set, go env -w: the user's configuration, outside the clone
    return (name in ('go', 'cargo') and words[:1] == ['install']) or (name in ('pip', 'pip3') and '--user' in args)


def entry_clone(entry, root):
    """Returns the clone one command of the line stays in (a real path); ANYWHERE for a cd, pushd or popd with no
    target, which only moves the folder of what follows; None when it cannot tell. The outer scripts/aiwp-cmds.sh run
    <work>/<clone> -- <command> of this workspace stays in the clone it names wherever it runs: its command is judged
    on its own, in the clone. A command that deletes or moves the clone's .git, or a folder that holds it, never
    stays."""
    argv, folder = entry['argv'], entry['folder']
    if entry['remote'] or entry['wrappers'] & UNCLEAR_WRAPPERS:
        return None
    values = list(entry['env'].values())
    name, args = os.path.basename(argv[0]), argv[1:]
    if name in ('cd', 'pushd', 'popd'):
        target = None if name == 'popd' else first_operand(args)
        if target in (None, '-'):
            return ANYWHERE if redirects_stay(entry['redirects'], folder, None) else None
        clone = None if '$' in target or '~' in target[:1] else clone_of(root, resolve_folder(folder, target))
    elif aiwp_run(argv, folder):
        run = aiwp_run(argv, folder)
        script = next(a for a in argv if os.path.basename(a) == 'aiwp-cmds.sh')
        own = os.path.realpath(os.path.join(root, 'scripts', 'aiwp-cmds.sh'))
        mine = folder is not None and os.path.realpath(os.path.join(folder, script)) == own
        clone = clone_of(root, run[1]) if mine and run[1] else None
    else:
        clone = clone_of(root, folder)
        if clone is None or reaches_out(argv):
            return None
        values += argv
        if name in WHOLE_CLONE and any(os.path.realpath(os.path.join(folder, w)) == clone for w in plain_words(args)):
            return None
        if removes_git(entry, clone):
            return None
    if clone is None or folder is None or not redirects_stay(entry['redirects'], folder, clone):
        return None
    return clone if all(word_stays(word, folder, clone) for word in values) else None


def approval(entries, root, shared, groups=None):
    """Returns the clone, relative to the root, that every command of the line stays in, or None when it cannot tell
    (a nested text it could not read, a redirection with no command, a command that asks on its own, two clones, one
    command outside a clone). A docker command on the task's own group, and what a container of that group runs,
    stay in the clone of that group (groups: the DockerGroups of the line). An assignment alone is no command."""
    if shared.get('unread') or shared.get('loose'):
        return None
    clones = set()
    for entry in entries:
        if entry.get('bare') and not entry['redirects']:
            continue
        try:
            found = None if 'reason' in entry else (groups and groups.clone(entry)) or entry_clone(entry, root)
        except (OSError, ValueError):
            found = None  # a path the system cannot resolve (a NUL byte, a name too long): it cannot tell
        if found is None:
            return None
        clones.add(found)
    clones.discard(ANYWHERE)
    return os.path.relpath(clones.pop(), os.path.realpath(root)) if len(clones) == 1 else None


# What the line does to the paths it names, for the protected folders below and for the .git of a clone.
DELETERS = {'rmdir', 'unlink', 'shred', 'truncate', 'srm', 'wipe'}
PLACERS = {'mv', 'cp', 'install', 'ln', 'rsync'}
FILE_WRITERS = {'tee', 'touch', 'mkdir'}
# Programs that run code given on their own line (python3 -c, node -e, awk '...'): their code is read as tokens.
INTERPRETERS = {
    'node', 'nodejs', 'deno', 'bun', 'perl', 'ruby', 'php', 'awk', 'gawk', 'mawk', 'nawk', 'sed', 'lua', 'Rscript',
    'pwsh', 'tclsh', 'osascript',
}  # fmt: skip
# Programs that only read the paths they name.
READERS = {
    'cat', 'less', 'more', 'head', 'tail', 'ls', 'grep', 'egrep', 'fgrep', 'rg', 'wc', 'stat', 'file', 'diff', 'cmp',
    'md5sum', 'sha1sum', 'sha256sum', 'sha512sum', 'shasum', 'test', '[', '[[', 'realpath', 'readlink', 'basename',
    'dirname', 'echo', 'printf', 'du', 'tree', 'od', 'xxd', 'hexdump', 'strings', 'nl', 'jq', 'cd', 'pushd', 'popd',
    'pwd', 'true', ':', 'column', 'cut', 'tr',
}  # fmt: skip
FIND_WRITES = ('-delete', '-fprint', '-fprint0', '-fprintf', '-fls') + FIND_ACTIONS
# BR-9: Grafana's data, at the root of the workspace. BR-13: the person's merge orders, written only by the
# UserPromptSubmit hook (scripts/session-title.py), read by scripts/aiwp-gate.sh with the session's variables.
GRAFANA_DATA = os.path.join('tools', 'observability', '.data')
GRAFANA_MARK = re.compile(r'(^|[/=,])observability/\.data(/|:|,|$)')
GRAFANA_REASON = (
    'it deletes, moves or empties tools/observability/.data, the data of Grafana (dashboards, users, settings)'
)
MERGE_ORDERS = os.path.join('.history', 'merge-orders')
ORDERS_MARK = re.compile(r'(^|[/=,])merge-orders(/|:|,|$)')
ORDER_SCRIPT = 'session-title.py'
SESSION_VARIABLES = {'CLAUDECODE', 'CLAUDE_CODE_SESSION_ID'}
SESSION_WORD = re.compile(r'(?<![\w${])(CLAUDECODE|CLAUDE_CODE_SESSION_ID)(?!\w)')
SESSION_DEFAULT = re.compile(r'\$\{(CLAUDECODE|CLAUDE_CODE_SESSION_ID):?=')
# Shell builtins that set, export or unset the variable they name.
NAMING_BUILTINS = {
    'export', 'declare', 'typeset', 'readonly', 'local', 'unset', 'read', 'printf', 'mapfile', 'readarray', 'getopts',
    'let',
}  # fmt: skip
ORDER_HINT = (
    "The merge order is the person's: only the person's /merge, typed in this session, records it. Never run around "
    'it; offer /merge'
)
SESSION_REASON = (
    'Refused: this line sets, unsets or clears CLAUDECODE or CLAUDE_CODE_SESSION_ID, which tell scripts/aiwp-gate.sh '
    'whose session runs the merge. ' + ORDER_HINT + '.'
)
ORDERS_REASON = (
    'Refused: this line writes, moves, deletes or links .history/merge-orders/, where the UserPromptSubmit hook '
    'records the /merge the person typed, or runs scripts/session-title.py, which writes it. ' + ORDER_HINT + '.'
)


def target_folder(args):
    """Returns the value of -t or --target-directory of a cp, mv, install or ln command line, or None."""
    for index, word in enumerate(args):
        option, attached, value = word.partition('=')
        if option == '--target-directory':
            return value if attached else (args[index + 1] if index + 1 < len(args) else '')
        if word.startswith('-') and not word.startswith('--'):
            _, found, glued = short_options(word, {'-t', '-S'})
            if found == '-t':
                return glued if glued is not None else (args[index + 1] if index + 1 < len(args) else '')
    return None


def find_removes(argv):
    """True when a find command line deletes or moves what it finds: -delete, or -exec, -execdir, -ok or -okdir
    running rm, mv or another deleting program (also through a shell)."""
    if '-delete' in argv:
        return True
    for index, word in enumerate(argv):
        if word in FIND_ACTIONS:
            rest = argv[index + 1 :]
            stop = next((k for k, w in enumerate(rest) if w in (';', '+')), len(rest))
            names = {os.path.basename(token) for w in rest[:stop] for token in w.split()}
            if names & (DELETERS | {'rm', 'mv'}):
                return True
    return False


def touches(argv, redirects):
    """Returns what one command does to the paths it names, as (mode, word, sources): 'write' (it writes, empties or
    deletes that path), 'remove' (it deletes or moves the path with all it holds) or 'into' (it puts the sources in
    that folder). Redirection targets are writes."""
    found = [
        ('write', target, ())
        for operator, target in redirects
        if '>' in operator
        and target not in SAFE_TARGETS
        and not (operator.endswith('&') and (target.isdigit() or target == '-'))
    ]
    name, args = os.path.basename(argv[0]), argv[1:]
    words = plain_words(args)
    if name == 'rm':
        mode = 'remove' if has_short_flag(args, 'rR') or '--recursive' in args else 'write'
        found += [(mode, word, ()) for word in words]
    elif name in DELETERS | FILE_WRITERS:
        found += [('write', word, ()) for word in words]
    elif name in PLACERS:
        folder = target_folder(args)
        words = plain_words(drop_values(args, {'-t', '--target-directory', '-S', '--suffix'}))
        sources = words if folder is not None else words[:-1]
        if name == 'mv' or (name == 'rsync' and any(a.startswith('--remove-source') for a in args)):
            found += [('remove', word, ()) for word in sources]
        if name == 'rsync' and any(a.startswith('--del') for a in args):
            found += [('remove', word, ()) for word in words]
        if makes_links(argv):
            found += [('write', word, ()) for word in words]
        if folder is not None or len(words) > 1:
            found.append(('into', words[-1] if folder is None else folder, tuple(sources)))
    elif name == 'find' and find_removes(argv):
        found += [('remove', start, ()) for start in find_starts(argv)[0]]
    elif name == 'dd':
        found += [('write', a[3:], ()) for a in args if a.startswith('of=')]
    elif name in ('sed', 'perl') and (has_short_flag(args, 'i') or any(a.startswith('--in-place') for a in args)):
        found += [('write', word, ()) for word in words]
    return found


def word_place(word, folder, root, variables=None):
    """Returns (the real path a word names, its first wildcard segment or None), read from the folder the command
    runs in, else from the root; None when the word cannot be read as a path (a variable with no value)."""
    known = {**os.environ, 'PWD': folder or '', **(variables or {})}
    word = os.path.expanduser(VARIABLE.sub(lambda m: known.get(m.group(1) or m.group(2)) or m.group(0), word))
    if not word or '$' in word or word.startswith('~'):
        return None
    base = folder if folder is not None else root
    segments = word.split('/')
    wild = next((k for k, segment in enumerate(segments) if any(char in segment for char in GLOB_CHARS)), None)
    if wild is None:
        return os.path.realpath(os.path.join(base, word)), None
    prefix = '/'.join(segments[:wild]) or ('/' if word.startswith('/') else '.')
    return os.path.realpath(os.path.join(base, prefix)), segments[wild]


def reaches_path(place, path, mode, sources=()):
    """True when a (real path, wildcard segment) place reaches a protected real path in that mode: it is the path or
    lies inside it; or it holds the path and the command removes it whole ('remove'), or puts there a source named
    like the next folder down to the path ('into'). A wildcard holds the path when it may match that next folder."""
    real, pattern = place
    if real == path or strictly_under(real, path):
        return True
    if not strictly_under(path, real):
        return False
    first = os.path.relpath(path, real).split(os.sep)[0]
    if pattern is not None:
        # As in a shell, a wildcard matches a name that starts with a dot only when it starts with a dot too.
        hidden = first.startswith('.') and not pattern.startswith('.')
        matches = not hidden and ('{' in pattern or fnmatch.fnmatchcase(first, pattern))
        return matches and (mode == 'remove' or os.path.join(real, first) == path)
    if mode == 'remove':
        return True
    return mode == 'into' and first in {os.path.basename(source.rstrip('/')) for source in sources}


def fed_words(entry):
    """Returns the words xargs or parallel hands to the command: what reaches its stdin when the line shows it, else
    the folders the find piped into it walks, or the words of the command piped into it."""
    if entry.get('stdin'):
        return [word for text in entry['stdin'] for word in text.split()]
    source = entry.get('source')
    argv = strip_wrappers(source['argv'])[0] if source else []
    if argv and os.path.basename(argv[0]) == 'find':
        return find_starts(argv)[0]
    return plain_words(argv[1:]) if argv else []


def code_tokens(argv):
    """Returns the tokens of the code an interpreter gets on its own line (python3 -c, node -e, awk '...'): the
    words that hold a space, a parenthesis or a semicolon, split; [] for other programs."""
    name = os.path.basename(argv[0])
    if name not in INTERPRETERS and not name.startswith(('python', 'pypy')):
        return []
    return [token for word in argv[1:] if re.search(r'[\s(;]', word) for token in TOKEN_SEPARATORS.split(word)]


def protected_hit(entry, root, relative, mark, every_word=False):
    """True when one command reaches a protected folder of the root (relative): it deletes, moves, empties or writes
    it, anything in it or a folder that holds it, by its paths (read from its folder, links resolved), by a
    redirection, by the files xargs hands it, or by interpreter code or a Docker mount that names it (mark, which
    ends at /, :, a comma or the end of the word: -v <it>:/d, --mount source=<it>,target=/d). every_word: any
    path a command other than a reader names inside the folder counts too. A command that runs elsewhere (ssh, a
    container) is judged by the mark only."""
    argv, folder = entry['argv'], entry['folder']
    found = touches(argv, entry['redirects'])
    name = os.path.basename(argv[0])
    if entry['wrappers'] & {'xargs', 'parallel'} and (found or name in DELETERS | PLACERS | {'rm'}):
        found += [('remove', word, ()) for word in fed_words(entry)]
    if every_word and name not in READERS and not (name == 'find' and not any(a in FIND_WRITES for a in argv)):
        for word in argv[1:]:
            found += [('write', piece, ()) for piece in (word, word.partition('=')[2], word[2:]) if piece]
    if any(mark.search(token) for token in code_tokens(argv)):
        return True
    if name in DOCKERS | {'docker-compose'} and any(mark.search(word) for word in argv[1:]):
        return True  # a mount (-v <it>:/d, --mount source=<it>) hands it to a container
    path = os.path.realpath(os.path.join(root, relative))
    for mode, word, sources in found:
        if mark.search(word.rstrip('/')):
            return True
        place = None if entry['remote'] else word_place(word, folder, root, entry.get('vars'))
        if place and reaches_path(place, path, mode, sources):
            return True
    return False


def session_change(entry):
    """True when one command sets, exports, unsets or clears CLAUDECODE or CLAUDE_CODE_SESSION_ID: an assignment
    (VAR=x cmd, VAR=x alone, env VAR=x), export, declare, unset, read, printf -v, ${VAR:=x}, env -u, env -i, env -
    and exec -c."""
    if SESSION_VARIABLES & set(entry['env']) or SESSION_VARIABLES & set(entry.get('unset') or ()):
        return True
    if entry.get('cleared'):
        return True
    argv = entry['argv']
    if os.path.basename(argv[0]) in NAMING_BUILTINS and any(SESSION_WORD.search(a) for a in argv[1:]):
        return True
    return any(SESSION_DEFAULT.search(a) for a in argv)


def brace_forms(word, limit=MAX_CANDIDATES * 8):
    """Returns the words a brace expansion of a word gives ({a,b} and nested ones), at most limit of them."""
    found = re.search(r'\{([^{}]*,[^{}]*)\}', word)
    if not found:
        return [word]
    forms = []
    for choice in found.group(1).split(','):
        forms.extend(brace_forms(word[: found.start()] + choice + word[found.end() :], limit))
    return forms[:limit]


def names_order_script(word, folder):
    """True when a word may name scripts/session-title.py: its last name is that name, or, holding a wildcard or
    braces, it matches a file of that name read from the folder, or its last name matches that name as a pattern
    and keeps a piece of it (session-t*.py, session-title?py, session-title.p[y])."""
    word = os.path.expanduser(word.rstrip('/'))
    if os.path.basename(word) == ORDER_SCRIPT:
        return True
    if not any(char in word for char in GLOB_CHARS):
        return False
    for form in brace_forms(word):
        last = os.path.basename(form)
        literal = re.sub(r'\[[^]]*\]|[*?]', ' ', last)
        if fnmatch.fnmatchcase(ORDER_SCRIPT, last) and re.search(r'session|title|ion-t', literal):
            return True
        pattern = form if os.path.isabs(form) else os.path.join(glob.escape(folder), form)
        if any(os.path.basename(m) == ORDER_SCRIPT for m in itertools.islice(glob.iglob(pattern), MAX_MATCHES)):
            return True
    return False


def runs_order_script(entry, root, alone=False):
    """True when a command names scripts/session-title.py, the hook that records the person's /merge, in a word, a
    redirection or interpreter code (also a wildcard or braces that match it) and may run, copy, move, link or write
    it: any command but a reader (python3 it, python3 < it, cp it, ln, vim). A reader (cat, less, ls, grep, wc) is let
    through only when it is the one command of the line (alone: no pipe, no other command) and has no redirection,
    so nothing can run or keep what it prints. git commands that read are left alone."""
    argv = entry['argv']
    name = os.path.basename(argv[0])
    parts = git_parts(argv) if name == 'git' else None
    if parts and git_reads(parts['sub'], parts['args']):
        return False
    folder = entry['folder'] if entry['folder'] is not None else root
    words = argv + code_tokens(argv) + [target for _, target in entry['redirects']]
    pieces = [piece for word in words for piece in (word, word.partition('=')[2]) if piece]
    if not any(names_order_script(piece, folder) for piece in pieces):
        return False
    return name not in READERS or not alone or bool(entry['redirects'])


def protection_verdict(entry, root, alone=False):
    """Returns ('deny', reason) for a command that gets around the person's merge order (BR-13): it changes the
    session's variables, writes .history/merge-orders/ or runs the hook that writes it; ('ask', reason) for one that
    deletes, moves or empties Grafana's data (BR-9), wherever it runs and whatever the rest of the line is; else
    None. alone: the command is the only one of the line."""
    if session_change(entry):
        return 'deny', SESSION_REASON
    if runs_order_script(entry, root, alone):
        return 'deny', ORDERS_REASON
    if protected_hit(entry, root, MERGE_ORDERS, ORDERS_MARK, every_word=True):
        return 'deny', ORDERS_REASON
    if protected_hit(entry, root, GRAFANA_DATA, GRAFANA_MARK):
        return 'ask', GRAFANA_REASON
    return None


def removes_git(entry, clone):
    """True when a command deletes or moves the .git of the clone, or a folder that holds it (find . -delete, find .
    -exec rm, rm -rf ., mv . x): the hooks that scan and push go, and every commit not pushed yet."""
    path = os.path.join(clone, '.git')
    for mode, word, sources in touches(entry['argv'], []):
        place = word_place(word, entry['folder'], clone, entry.get('vars'))
        if mode != 'write' and place and reaches_path(place, path, mode, sources):
            return True
    return False


# BR-8: the task's own Docker group, a compose project agent_<MMDD>-<slug> or agent_<MMDD>-<slug>--<clone> of the work
# tmp/work/<yyyy-mm-dd>-<slug>/, is free (a work slug never holds --, so a clone's group never takes the name of another
# work's group). Its resources carry the compose label with that name.
GROUP_NAME = re.compile(r'^agent_[0-9]{4}-[a-z0-9][a-z0-9-]*$')
GROUP_LABEL = 'com.docker.compose.project'
OVERRIDE_FILE = re.compile(r'^agent-(.+)\.compose\.yaml$')
INSPECT_TIMEOUT_SECONDS = 5
COMPOSE_FLAGS = {'--dry-run', '--compatibility', '--all-resources', '--verbose'}
# The docker compose subcommands allowed on the own group: they act on the containers the copy already has. up, build,
# start, create, run, cp, attach, watch and the rest are left to the permission mode: a container starts only through
# scripts/aiwp-cmds.sh up <work>/<clone>, which writes the copy's override and refuses a service that is not safe.
# config is left out too: it prints the values of the env files, secrets among them.
COMPOSE_SUBCOMMANDS = {
    'down', 'ps', 'logs', 'stop', 'restart', 'top', 'images', 'port', 'pause', 'unpause', 'exec',
}  # fmt: skip
# The options of docker compose down and exec it knows, without and with a value; any other is not approved.
DOWN_OPTIONS = ({'-v', '--volumes', '--remove-orphans'}, {'-t', '--timeout'})
EXEC_OPTIONS = (
    {'-T', '-i', '-t', '-d', '--no-TTY', '--interactive', '--tty', '--detach'},
    {'-e', '--env', '-w', '--workdir', '-u', '--user', '--index'},
)
# docker <words> that remove or read a resource, its kind, and the options they may carry.
RESOURCE_COMMANDS = {
    ('rm',): 'container', ('container', 'rm'): 'container', ('container', 'remove'): 'container',
    ('rmi',): 'image', ('image', 'rm'): 'image', ('image', 'remove'): 'image',
    ('volume', 'rm'): 'volume', ('volume', 'remove'): 'volume', ('volume', 'inspect'): 'volume',
    ('network', 'rm'): 'network', ('network', 'remove'): 'network',
}  # fmt: skip
RESOURCE_OPTIONS = {
    'container': {'-f', '--force', '-v', '--volumes'}, 'image': {'-f', '--force', '--no-prune'},
    'volume': {'-f', '--force'}, 'network': {'-f', '--force'},
}  # fmt: skip
LABELS_FORMAT = {
    'container': '{{json .Config.Labels}}', 'image': '{{json .Config.Labels}}', 'volume': '{{json .Labels}}',
    'network': '{{json .Labels}}',
}  # fmt: skip
RESOURCE_NAME = re.compile(r'^[A-Za-z0-9][A-Za-z0-9_.:/@-]*$')


def own_groups(clone):
    """Returns the names of the Docker groups of the work a clone belongs to: agent_<MMDD>-<slug> and
    agent_<MMDD>-<slug>--<clone> for each clone folder of the work, those that are valid group names."""
    work = os.path.dirname(clone)
    name = os.path.basename(work)
    base = 'agent_' + name[5:7] + name[8:10] + '-' + name[11:]
    try:
        clones = [c for c in os.listdir(work) if not c.startswith('.') and os.path.isdir(os.path.join(work, c))]
    except OSError:
        clones = []
    return {group for group in [base] + [base + '--' + c for c in clones] if GROUP_NAME.match(group)}


def option_value(args, index, glued_ok=True):
    """Returns (option, value, words used) for the option at args[index]: --name=value, --name value, -xvalue or
    -x value."""
    word = args[index]
    option, attached, value = word.partition('=')
    if attached:
        return option, value, 1
    if glued_ok and not word.startswith('--') and len(word) > 2:
        return word[:2], word[2:], 1
    return word, args[index + 1] if index + 1 < len(args) else '', 2


def pflag_operands(words, flags, values, interspersed=True):
    """Returns the operands of a command line read the way docker's option parser (pflag) reads it: --name, --name=
    value, --name value, and grouped short options (-it, -eA=1, -e A=1) where a letter that takes a value takes the
    rest of the group or the next word. interspersed False: the first operand ends the options (exec <service>
    <command>). Returns None when an option is not in flags or values."""
    operands, i = [], 0
    while i < len(words):
        word = words[i]
        i += 1
        if word == '--' or (operands and not interspersed):
            operands.extend(words[i - (word != '--') :])
            break
        if word.startswith('--'):
            name, attached, _ = word.partition('=')
            if name in values:
                i += 0 if attached else 1
            elif name not in flags or attached:
                return None
        elif word.startswith('-') and len(word) > 1:
            for k in range(1, len(word)):
                letter = '-' + word[k]
                if letter in values:
                    i += 1 if k + 1 == len(word) else 0
                    break
                if letter not in flags:
                    return None
        else:
            operands.append(word)
    return operands


# The compose label that names the service of a container, and what docker network inspect prints of a network.
SERVICE_LABEL = 'com.docker.compose.service'
NETWORK_FORMAT = '{"internal":{{json .Internal}},"labels":{{json .Labels}},"options":{{json .Options}}}'
# The bridge options that keep the host's gateway out of an internal network (Docker 28 and later).
ISOLATED_GATEWAY = ('com.docker.network.bridge.gateway_mode_ipv4', 'com.docker.network.bridge.gateway_mode_ipv6')
# What docker container inspect prints of a container: its networks and what may reach the host past them.
CONTAINER_FORMAT = (
    '{"networks":{{json .NetworkSettings.Networks}},"privileged":{{json .HostConfig.Privileged}},'
    '"capadd":{{json .HostConfig.CapAdd}},"pid":{{json .HostConfig.PidMode}},"ipc":{{json .HostConfig.IpcMode}},'
    '"uts":{{json .HostConfig.UTSMode}},"cgroupns":{{json .HostConfig.CgroupnsMode}},'
    '"devices":{{json .HostConfig.Devices}},"securityopt":{{json .HostConfig.SecurityOpt}},"mounts":{{json .Mounts}}}'
)
# The namespace modes of a container that keep it to itself; container:<x> is judged by the group of <x>.
PRIVATE_MODES = {
    'pid': {'', 'private'}, 'ipc': {'', 'private', 'shareable', 'none'}, 'uts': {''}, 'cgroupns': {'', 'private'},
}  # fmt: skip
# The security options a container may carry: they only take privileges away.
SAFE_SECURITY_OPTIONS = {'no-new-privileges', 'no-new-privileges:true', 'no-new-privileges=true'}


def reaches_host(container, clone):
    """Returns None when a container (what CONTAINER_FORMAT prints) may reach the host past its networks, read as an
    allowlist; else (the volumes it mounts, the containers whose namespaces it shares), both to be checked against
    the group. It must not be privileged or add capabilities, its pid, ipc, uts and cgroup namespaces must be its
    own (PRIVATE_MODES) or container:<x>, it must have no devices and only no-new-privileges as security options, and
    every mount must be a named volume or a bind of a folder inside the clone, out of its .git (stays_in) and not the
    clone itself. Anything else, or what cannot be read, may reach the host."""
    if container.get('privileged') is not False or container.get('capadd') or container.get('devices'):
        return None
    if not set(container.get('securityopt') or []) <= SAFE_SECURITY_OPTIONS:
        return None
    volumes, peers = [], []
    for key, private in PRIVATE_MODES.items():
        mode = container.get(key)
        if isinstance(mode, str) and mode.startswith('container:') and RESOURCE_NAME.match(mode[10:]):
            peers.append(mode[10:])
        elif mode not in private:
            return None
    mounts = container.get('mounts')
    if not isinstance(mounts, list) or not all(isinstance(mount, dict) for mount in mounts):
        return None
    for mount in mounts:
        kind, source, name = mount.get('Type'), str(mount.get('Source') or ''), str(mount.get('Name') or '')
        if kind == 'volume' and RESOURCE_NAME.match(name):
            volumes.append(name)
            continue
        inside = os.path.isabs(source) and stays_in(source, clone) and os.path.realpath(source) != clone
        if kind != 'bind' or not inside:
            return None
    return volumes, peers


class DockerGroups:
    """Tells which Docker commands of a line act only on the task's own group (BR-8): docker compose -p <group> with
    down and its known options, ps, logs, stop, restart, config, top, images, port, pause, unpause, or exec with its
    known options (never up, build, start, create or run: the copy starts only through aiwp-cmds.sh up); and docker
    rm, rmi, image rm, volume rm or inspect, network rm of resources that all carry the compose label of that group.
    The command runs in a clone of tmp/work/, and the group is one of the work of that clone. exec counts only when
    the service's containers are isolated (isolated, reaches_host): then whatever it runs there (a shell, an
    interpreter, a database tool) cannot reach another machine. The labels and networks come from docker inspect
    under a short timeout; what it cannot tell is not its own."""

    def __init__(self, root, run):
        self.root, self.run, self.known = root, run, {}

    def clone(self, entry):
        """Returns the clone (a real path) of a docker command that acts only on its own group, or of a command an
        isolated container of that group runs through exec (docker compose -p <group> exec db psql); None otherwise.
        Cached per entry."""
        key = id(entry)
        if key not in self.known:
            launcher = entry['remote']
            if isinstance(launcher, dict):
                self.known[key] = self.clone(launcher)  # its exec reaches only an isolated container of the group
            else:
                self.known[key] = self.judge(entry)
        return self.known[key]

    def judge(self, entry):
        """Returns the clone of a docker command run on the line itself that acts only on its own group, or None."""
        argv, folder = entry['argv'], entry['folder']
        if os.path.basename(argv[0]) != 'docker' or len(argv) < 2 or entry['wrappers'] & UNCLEAR_WRAPPERS:
            return None
        if any(key.startswith(('DOCKER_', 'COMPOSE_')) for key in entry['env']):
            return None  # another daemon, another context or another project name
        clone = clone_of(self.root, folder)
        if clone is None or not redirects_stay(entry['redirects'], folder, clone):
            return None
        if not all(word_stays(value, folder, clone) for value in entry['env'].values()):
            return None
        groups = own_groups(clone)
        if argv[1] == 'compose':
            return clone if self.compose(argv[2:], folder, clone, groups) else None
        return clone if self.resources(argv[1:], groups) else None

    def compose(self, args, folder, clone, groups):
        """True when a docker compose command line names only own groups with -p, only files of the clone or the
        copy's override with -f, and runs a subcommand of the allowlist with known options and no push."""
        projects, i = [], 0
        while i < len(args) and args[i].startswith('-'):
            option, value, used = option_value(args, i)
            if option in ('-p', '--project-name'):
                projects.append(value)
            elif option in ('-f', '--file'):
                if not (word_stays(value, folder, clone) or self.override(value, folder, clone)):
                    return False
            elif option in COMPOSE_VALUE_OPTIONS:
                if option in ('--env-file', '--project-directory') and not word_stays(value, folder, clone):
                    return False
            elif args[i] in COMPOSE_FLAGS:
                used = 1
            else:
                return False
            i += used
        if not projects or not set(projects) <= groups or i >= len(args) or args[i] not in COMPOSE_SUBCOMMANDS:
            return False
        sub, rest = args[i], args[i + 1 :]
        if sub == 'exec':
            operands = pflag_operands(rest, *EXEC_OPTIONS, interspersed=False)
            single = len(set(projects)) == 1
            return bool(operands) and single and self.isolated(projects[0], operands[0], clone)
        if sub == 'down':
            operands = pflag_operands(rest, *DOWN_OPTIONS)
            return operands is not None and all(RESOURCE_NAME.match(word) for word in operands)
        return all(word_stays(word, folder, clone) for word in rest)

    def override(self, word, folder, clone):
        """True when a compose file is the override of a clone of the same work: tmp/work/<work>/agent-<clone>.compose
        .yaml, next to an existing clone folder."""
        if '$' in word:
            return False
        real = os.path.realpath(os.path.join(folder, word))
        work = os.path.dirname(clone)
        name = OVERRIDE_FILE.match(os.path.basename(real))
        return bool(name) and os.path.dirname(real) == work and os.path.isdir(os.path.join(work, name.group(1)))

    def resources(self, args, groups):
        """True when docker rm, rmi, image rm, volume rm or inspect, or network rm names only resources that carry
        the label of an own group (docker inspect says so)."""
        kind = RESOURCE_COMMANDS.get(tuple(args[:1])) or RESOURCE_COMMANDS.get(tuple(args[:2]))
        if kind is None:
            return False
        rest = args[1:] if tuple(args[:1]) in RESOURCE_COMMANDS else args[2:]
        allowed = RESOURCE_OPTIONS[kind]
        names, i = [], 0
        while i < len(rest):
            word = rest[i]
            i += 1
            if word in ('--format', '-f') and args[1:2] == ['inspect']:
                i += 1
            elif word.startswith('--format=') and args[1:2] == ['inspect']:
                continue
            elif word.startswith('-'):
                letters = {'-' + letter for letter in word[1:]} if not word.startswith('--') else {word}
                if not letters <= allowed:
                    return False
            elif RESOURCE_NAME.match(word):
                names.append(word)
            else:
                return False
        labels = self.labels(kind, names) if names else None
        return labels is not None and all(found.get(GROUP_LABEL) in groups for found in labels)

    def isolated(self, group, service, clone):
        """True when every running container of a service of the group is attached only to networks that are
        internal (no route out of the machine), carry the label of the group and keep the host's gateway out
        (gateway_mode_ipv4 and _ipv6 isolated), as docker inspect says. A service that publishes ports is also on a
        non-internal network (<group>_edge): not isolated. No container, Docker that does not answer, a container
        with no network, host or none networking, or one that may reach the host past its networks (reaches_host,
        against the clone; the volumes it mounts and the containers whose namespaces it shares must carry the label
        of the group): not isolated."""
        if not RESOURCE_NAME.match(service):
            return False
        labels = ('label=' + GROUP_LABEL + '=' + group, 'label=' + SERVICE_LABEL + '=' + service)
        ids = self.docker(['ps', '--filter', labels[0], '--filter', labels[1], '--format', '{{.ID}}'])
        if not ids or not all(RESOURCE_NAME.match(found) for found in ids):
            return False
        containers = self.inspect(['container', 'inspect', '--format', CONTAINER_FORMAT], ids)
        if containers is None or not all(isinstance(found, dict) for found in containers):
            return False
        attached = [found.get('networks') for found in containers]
        shared = [reaches_host(found, clone) for found in containers]
        if any(found is None for found in shared):
            return False
        volumes = {volume for found, _ in shared for volume in found}
        peers = {peer for _, found in shared for peer in found}
        for kind, names in (('volume', volumes), ('container', peers)):
            found = self.labels(kind, sorted(names)) if names else []
            if found is None or any(item.get(GROUP_LABEL) != group for item in found):
                return False
        if not all(isinstance(nets, dict) and nets for nets in attached):
            return False
        names = sorted({name for nets in attached for name in nets})
        if not all(RESOURCE_NAME.match(name) for name in names):
            return False
        networks = self.inspect(['network', 'inspect', '--format', NETWORK_FORMAT], names)
        if networks is None or not all(isinstance(net, dict) for net in networks):
            return False
        return all(
            net.get('internal') is True
            and (net.get('labels') or {}).get(GROUP_LABEL) == group
            and all((net.get('options') or {}).get(option) == 'isolated' for option in ISOLATED_GATEWAY)
            for net in networks
        )

    def labels(self, kind, names):
        """Returns the labels of each named resource, from docker inspect; None when Docker does not answer, a
        resource is missing or has no labels."""
        found = self.inspect([kind, 'inspect', '--format', LABELS_FORMAT[kind]], names)
        return found if found is not None and all(isinstance(item, dict) for item in found) else None

    def inspect(self, args, names):
        """Returns one JSON value per name from a docker inspect command line, or None when Docker does not answer, a
        name is missing or a line is no JSON."""
        lines = self.docker(args + list(names))
        if lines is None or len(lines) != len(names):
            return None
        try:
            return [json.loads(line) for line in lines]
        except ValueError:
            return None

    def docker(self, args):
        """Runs docker with the arguments under a short timeout; returns its lines that are not blank, or None when it
        fails or does not answer."""
        docker = os.environ.get('GUARD_BASH_DOCKER', 'docker')
        try:
            done = self.run(
                [docker, *args], capture_output=True, text=True, check=False, timeout=INSPECT_TIMEOUT_SECONDS
            )
        except (OSError, subprocess.SubprocessError):
            return None
        if done.returncode != 0:
            return None
        return [line.strip() for line in (done.stdout or '').splitlines() if line.strip()]


OWN_GROUP = "; Docker only in the task's own group"
# What docker compose exec runs in a container of the task's own group with no question: the database tools that ask
# on the host.
GROUP_DATABASE_TOOLS = SQL_CLIENTS | {'dropdb', 'mysqladmin', 'dotnet', 'prisma', 'rails', 'rake', 'rm'}


def in_own_group(entry, docker):
    """True when a question about one command does not apply because it acts only on the task's own Docker group:
    the docker command itself, or a database tool a container of that group runs."""
    if not entry['remote']:
        return os.path.basename(entry['argv'][0]) == 'docker' and bool(docker.clone(entry))
    return os.path.basename(entry['argv'][0]) in GROUP_DATABASE_TOOLS and bool(docker.clone(entry))


def travels(entry):
    """True for a part of the line that travels with the asked command instead of counting as another command: a cd,
    pushd or popd, or an assignment alone, with no redirection."""
    if 'argv' not in entry or entry['redirects']:
        return False
    return bool(entry.get('bare')) or os.path.basename(entry['argv'][0]) in ('cd', 'pushd', 'popd')


def alone_reason(asks):
    """Returns the reason of the refusal of a line that would ask and holds other commands too."""
    what = '; '.join(reason.rstrip('.') for reason in asks[:3])
    return (
        'Run it alone: ' + what + '. Run the other commands of this line first, then this one alone in its own call, '
        'so the question shows only what it asks about.'
    )


def emit(decision, reason):
    """Prints the hook decision."""
    output = {'hookEventName': 'PreToolUse', 'permissionDecision': decision, 'permissionDecisionReason': reason}
    print(json.dumps({'hookSpecificOutput': output}))


def decide(data, root, run=subprocess.run):
    """Judges one Bash tool call: deny, ask or allow with the reason, or stay silent. Denies: a git write in projects/
    or in the core, Terraform that changes the cloud, git push --no-verify, a commit with a local secret file or a
    secret, chmod, chown, chgrp, git init or git clone in the read-only core of an installed workspace, aiwp update,
    rollback and repair; a line that gets around the person's merge order (CLAUDECODE or CLAUDE_CODE_SESSION_ID
    changed, .history/merge-orders/ written, scripts/session-title.py run). Asks: deleting a database (but in the
    task's own Docker group), deleting, moving or emptying Grafana's data, aiwp-cmds.sh release, deploy, hotfix,
    hotfix-tag, hotfix-down, checkpoint, developer --create, gate --untested, apply --apply and close --discard; a line
    that would ask and holds other top-level commands too is denied instead, with "Run it alone:", so the question
    shows only what it asks about (a cd, pushd, popd or an assignment travels with the asked command). Allows, with no
    question, a line it can tell stays in one clone of tmp/work/ and reaches no remote system, Docker only in the
    task's own group (approval); never over a deny or an ask. The rest is left to Claude Code's own permission mode."""
    command = data['tool_input']['command']
    if not isinstance(command, str):
        raise TypeError('command is not a string')
    cwd = data.get('cwd') or os.getcwd()
    shared = {'written': {}, 'texts': MAX_TEXTS}
    try:
        entries = list(walk(command, cwd, shared=shared))
    except ValueError:
        if GUARDED_WORD.search(command):
            emit('ask', UNREADABLE + '. Confirm.')
        return
    asks, asked, staging, created = [], set(), [], []
    core = CoreGuard(root, cwd, run, entries)
    docker = DockerGroups(root, run)
    for entry in entries:
        verdict = None
        guarded = None if 'reason' in entry else protection_verdict(entry, root, len(entries) == 1)
        if 'reason' in entry:
            verdict = ('ask', entry['reason']) if GUARDED_WORD.search(command) else None
        elif os.path.basename(entry['argv'][0]) == 'git':
            parts = git_parts(entry['argv'], entry['env'])
            folder = repo_folder(parts, entry['folder'])
            folder = None if folder and '$' in folder else folder
            helps = HELP_OPTIONS & set(parts['args']) or '-h' in parts['args']
            mine = None
            if parts['sub'] in ('init', 'clone') and not (entry['remote'] or helps):
                mine = core.git_verdict(parts, entry)
            if entry['remote'] and not parts['hidden']:
                verdict = None
            elif mine and mine[0] == 'deny':
                verdict = mine
            else:
                unknown = entry['folder'] is None or '$' in parts['folder'] + parts['git_dir'] + parts['work_tree']
                start = None if unknown else os.path.join(entry['folder'], parts['folder'])
                verdict = git_verdict(parts, folder, root, run, start) or mine
                if verdict is None and parts['sub'] == 'commit' and not parts['hidden']:
                    if repo_kind(run, root, folder) == 'custom':
                        verdict = commit_decision(parts, folder, root, run, staging, created)
                    staging, created = [], []
                elif verdict is None:
                    staged = staging_of(parts, folder, bool(entry['wrappers'] & {'xargs', 'find', 'parallel'}))
                    if staged:
                        staging.append(staged)
        else:
            created.extend(created_secrets(entry))
            verdict = (None if entry['remote'] else core.verdict(entry)) or command_verdict(
                entry['argv'], entry['wrappers']
            )
            if verdict and verdict[0] == 'ask' and in_own_group(entry, docker):
                verdict = None  # BR-8: the task's own group is free, volumes and data included
        found = [item for item in (guarded, verdict) if item]
        refusal = next((item for item in found if item[0] == 'deny'), None)
        if refusal:
            emit(*refusal)
            return
        for _, reason in found:
            asked.add(entry['group'])
            if reason not in asks:
                asks.append(reason)
    if asks:
        groups = {entry['group'] for entry in entries if not travels(entry)}
        # A command that runs a file the line wrote keeps the question: alone, in a later call, the file is not seen.
        if groups - asked and not shared.get('fed'):
            emit('deny', alone_reason(asks))
        else:
            emit('ask', 'Confirm before running: ' + '; '.join(reason.rstrip('.') for reason in asks[:3]) + '.')
        return
    clone = approval(entries, root, shared, docker)
    if clone:
        own = any(not entry['remote'] and docker.known.get(id(entry)) for entry in entries if 'argv' in entry)
        emit('allow', 'Stays in the clone ' + clone + ' and reaches no remote system' + (OWN_GROUP if own else ''))


def out_of_time(signum, frame):
    """Signal handler: the hook passed its time budget. The exception is not an OSError, so nothing on the way (the
    scan, a git call) takes it for a failure of its own."""
    raise OutOfTime


def main():
    """Entry point: any failure, a run past the time budget included, exits 2 with the exception type, and the shell
    wrapper turns it into a question."""
    signal.signal(signal.SIGALRM, out_of_time)
    signal.alarm(BUDGET_SECONDS)
    try:
        decide(json.loads(sys.stdin.buffer.read().decode('utf-8')), sys.argv[1])
    except Exception as exc:  # noqa: BLE001 - every failure must reach the human, whatever its type
        print(type(exc).__name__, file=sys.stderr)
        sys.exit(2)
    finally:
        signal.alarm(0)


if __name__ == '__main__':
    main()
