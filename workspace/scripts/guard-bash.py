"""Decision logic of scripts/guard-bash.sh (PreToolUse hook, matcher Bash).

Reads the hook JSON on stdin and prints a decision JSON, or nothing (the command follows the normal permission flow).
It asks the human before a command that destroys data, rewrites history, moves a branch by force or reaches a remote,
in the spellings scripts/guard-bash.sh --help lists (git -C <dir>, wrappers, shell keywords, bash -c, command
substitution, ssh, heredocs), and it refuses a commit that carries a local secret file or a secret gitleaks finds.
In an installed workspace it refuses chmod, chown, chgrp, git init and git clone that reach the read-only core, and
denies aiwp update, rollback, repair, forget and the opening (aiwp, aiwp -- ...) inside a session. What it cannot
read, it asks about.
A speed bump with the human's confirmation behind it, not a sandbox: text a shell builds at run time is not seen.
Usage: python3 -I -B guard-bash.py <workspace-root>
"""

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
    what reaches its stdin as text (heredoc bodies, here-strings) and the command that pipes into it. A cd, pushd or
    popd changes the folder of what follows it, inside its own subshell only. Raises ValueError on text it cannot
    read (an open quote, an open parenthesis)."""

    def __init__(self, text, cwd, commands=None):
        self.text, self.size = text, len(text)
        self.cwd, self.oldpwd, self.dirs, self.exports, self.vars = cwd, None, [], {}, {}
        self.commands = [] if commands is None else commands
        self.pending, self.depth = [], 0

    def child(self, text):
        """Returns a lexer for a nested text (backticks, a heredoc body) that feeds the same command list."""
        other = Lexer(text, self.cwd, self.commands)
        other.exports, other.vars, other.depth = dict(self.exports), dict(self.vars), self.depth
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
            words, inputs, redirects, awaiting = [], [], [], None
            piped, source = next_piped, entry if next_piped else None

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
            elif pair in ('&&', '||', ';;'):
                finish()
                i += 2
            elif char == '&' and text[i + 1 : i + 2] == '>':
                end = i + (3 if text[i + 2 : i + 3] == '>' else 2)
                redirect(text[i:end])
                i = end
            elif char in ';&':
                finish()
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
            'redirects': redirects, 'exports': dict(self.exports), 'vars': dict(self.vars),
        }  # fmt: skip
        self.commands.append(entry)
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
    Returns (the command left, what was dropped: env, wrappers, chdir, the texts given to env -S and flock -c, and
    shell: True for sudo -s or -i, which open a shell)."""
    info = {'env': {}, 'wrappers': set(), 'chdir': '', 'texts': [], 'shell': False}
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
    """Returns ('ask', reason) for the commands of scripts/aiwp-cmds.sh that the human confirms, or None."""
    words = argv[1:]
    sub = words[0] if words else ''
    if sub == 'release':
        return 'ask', (
            'aiwp-cmds.sh release takes developer into main and pushes main to the remote; with --tag it also creates '
            'and pushes a release tag'
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


def walk(command, cwd, depth=0, wrappers=frozenset(), stdin=NO_STDIN, remote=False, shared=None):
    """Yields one entry per simple command of a command line, nested command lines included: a dict with argv, env,
    wrappers, folder, redirects and remote, or {'reason': text} for something that asks on its own. wrappers and
    stdin: what wraps and what feeds the command line this text was found in. remote: it runs in another machine,
    container or user. shared: what the whole walk shares (the files the line wrote, the nested texts left to read)."""
    lexer = Lexer(command, cwd).run()
    shared = {'written': {}, 'texts': MAX_TEXTS} if shared is None else shared
    written, texts = shared['written'], []
    for entry in lexer.commands:
        argv, info = strip_wrappers(entry['argv'])
        folder = entry['cwd']
        if info['chdir']:
            folder = resolve_folder(folder, info['chdir'], entry['vars'])
        outer = info['wrappers'] | wrappers
        fed = stdin_of(entry, stdin, folder, written)
        env = {**entry['exports'], **info['env']}
        texts.extend((text, folder, outer, fed, remote) for text in info['texts'])
        targets = []
        reader = info['shell'] and not argv
        if argv:
            name = os.path.basename(argv[0])
            away = remote or name in ELSEWHERE
            yield {
                'argv': argv, 'env': env, 'wrappers': outer, 'folder': folder, 'redirects': entry['redirects'],
                'remote': remote, 'vars': entry['vars'], 'stdin': fed[1], 'source': entry['source'],
            }  # fmt: skip
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
                            'remote': away, 'vars': entry['vars'], 'stdin': None, 'source': None,
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
                yield {'reason': FETCHED_TEXT}
            if script and file_key(folder, script) in written:
                texts.extend((body, folder, around, NO_STDIN, away) for body in written[file_key(folder, script)])
            if base in SQL_CLIENTS:
                files = [target[k + 1] for k in range(1, len(target) - 1) if target[k] in ('-f', '--file', '-i')]
                given = (fed[1] or []) + [body for f in files for body in written.get(file_key(folder, f), [])]
                if any(SQL_DESTRUCTIVE.search(text) for text in given):
                    yield {'reason': base + ' gets DROP or TRUNCATE on its input or from a file written on the line'}
        if reader and fed[0]:
            if fed[1] is None:
                yield {'reason': UNSEEN_STDIN}
            else:
                texts.extend((text, folder, outer, NO_STDIN, remote) for text in fed[1])
    for text, folder, around, fed, away in texts:
        shared['texts'] -= 1
        if depth >= MAX_DEPTH or shared['texts'] < 0:
            yield {'reason': 'there are too many nested commands for me to evaluate'}
            continue
        if FETCHED in text:
            yield {'reason': FETCHED_TEXT}
            continue
        try:
            yield from walk(text, folder, depth + 1, around, fed, away, shared)
        except ValueError:
            if GUARDED_WORD.search(text):
                yield {'reason': UNREADABLE}


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


def emit(decision, reason):
    """Prints the hook decision."""
    output = {'hookEventName': 'PreToolUse', 'permissionDecision': decision, 'permissionDecisionReason': reason}
    print(json.dumps({'hookSpecificOutput': output}))


def decide(data, root, run=subprocess.run):
    """Judges one Bash tool call: deny or ask with the reason, or stay silent. Denies: a git write in projects/ or in
    the core, Terraform that changes the cloud, git push --no-verify, a commit with a local secret file or a secret,
    chmod, chown, chgrp, git init or git clone in the read-only core of an installed workspace, aiwp update, rollback
    and repair. Asks: deleting a database, aiwp-cmds.sh release, checkpoint, developer --create, gate --untested,
    apply --apply and close --discard. The rest is left to Claude Code's own permission mode."""
    command = data['tool_input']['command']
    if not isinstance(command, str):
        raise TypeError('command is not a string')
    cwd = data.get('cwd') or os.getcwd()
    try:
        entries = list(walk(command, cwd))
    except ValueError:
        if GUARDED_WORD.search(command):
            emit('ask', UNREADABLE + '. Confirm.')
        return
    asks, staging, created = [], [], []
    core = CoreGuard(root, cwd, run, entries)
    for entry in entries:
        verdict = None
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
        if verdict and verdict[0] == 'deny':
            emit(*verdict)
            return
        if verdict and verdict[1] not in asks:
            asks.append(verdict[1])
    if asks:
        emit('ask', 'Confirm before running: ' + '; '.join(reason.rstrip('.') for reason in asks[:3]) + '.')


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
