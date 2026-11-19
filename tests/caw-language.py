"""SessionStart hook of the maintenance session of this repository: the preferred language of communication.

The preferred language is the native Claude Code setting "language". It counts when it is a non-empty string in
.claude/settings.local.json of the repository ($CLAUDE_PROJECT_DIR) or in the user's settings ($CLAUDE_CONFIG_DIR/
settings.json when that variable is set, else ~/.claude/settings.json). With one set, the hook prints nothing: Claude
Code applies the setting by itself. With none, it prints the SessionStart JSON whose
hookSpecificOutput.additionalContext tells the session to ask, in its first reply and before anything else, the
person's preferred language, write it as "language" in .claude/settings.local.json of the repository root keeping
every other key, and reply in it from then on. It runs on startup, resume, clear and compact, so the question
survives a compaction while it is unanswered.
A hook must never break a session start: a missing, unreadable or malformed settings file counts as "not set", a
missing CLAUDE_PROJECT_DIR skips the local file, and any other failure prints nothing; it always exits 0, with
nothing on stderr. Only a usage error of the flags exits 2.
Usage: python3 -I -B tests/caw-language.py   (hook JSON on stdin, read and ignored)
"""

import argparse
import json
import os
import sys

LOCAL_SETTINGS = os.path.join('.claude', 'settings.local.json')
USER_SETTINGS = 'settings.json'
MAX_READ = 1_000_000

CONTEXT = (
    'Preferred language of communication (tests/caw-language.py): none is set, neither `language` in '
    '`.claude/settings.local.json` of the repository root nor in the user settings (`~/.claude/settings.json`, or '
    '`$CLAUDE_CONFIG_DIR/settings.json`). In your first reply, before anything else, even before the task the person '
    'asked for, ask the person their preferred language of communication: its English name, such as `portuguese` or '
    '`spanish`, at most 40 characters of letters, spaces, hyphens and parentheses; ask again for anything else. Then '
    'write the answer as the key `language` in `.claude/settings.local.json` of the repository root (git ignores it): '
    'create the file when it is missing, and keep every other key it holds. From then on, reply in that language; '
    'files stay in English.'
)


def parse_args(argv):
    """Parses the flags (only --help); argparse exits 2 on a usage error and 0 after --help."""
    parser = argparse.ArgumentParser(
        prog='tests/caw-language.py',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description=(
            'SessionStart hook of the maintenance session: when no preferred language is set (the Claude Code\n'
            'setting "language", a non-empty string, in .claude/settings.local.json of $CLAUDE_PROJECT_DIR or in\n'
            '$CLAUDE_CONFIG_DIR/settings.json, else ~/.claude/settings.json), prints the JSON\n'
            '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "<ask it>"}}\n'
            'telling the session to ask the person for it first and save it. With one set it prints nothing.\n'
            'A missing, unreadable or malformed settings file counts as not set; any other failure prints nothing.'
        ),
        epilog=(
            'Exit codes: 0 always when run as the hook; 2 a usage error of the flags.\n\n'
            'Examples:\n'
            '  python3 -I -B tests/caw-language.py < /dev/null\n'
            '  CLAUDE_PROJECT_DIR="$PWD" python3 -I -B tests/caw-language.py < /dev/null'
        ),
    )
    return parser.parse_args(argv)


def language_in(path):
    """Returns True when the JSON file <path> holds a non-empty string "language"; False when it does not or cannot."""
    try:
        with open(path, encoding='utf-8') as handle:
            data = json.loads(handle.read(MAX_READ))
    except (OSError, ValueError, UnicodeDecodeError):
        return False
    value = data.get('language') if isinstance(data, dict) else None
    return isinstance(value, str) and value.strip() != ''


def settings_files(environ):
    """Returns the settings files that may set the language: the project's local one (when CLAUDE_PROJECT_DIR is set)
    and the user's one ($CLAUDE_CONFIG_DIR/settings.json, else $HOME/.claude/settings.json; neither set: none)."""
    files = []
    project = environ.get('CLAUDE_PROJECT_DIR', '')
    if project:
        files.append(os.path.join(project, LOCAL_SETTINGS))
    config = environ.get('CLAUDE_CONFIG_DIR', '')
    if not config:
        home = environ.get('HOME', '')
        config = os.path.join(home, '.claude') if home else ''
    if config:
        files.append(os.path.join(config, USER_SETTINGS))
    return files


def language_set(environ):
    """Returns True when any settings file of <environ> sets the preferred language."""
    return any(language_in(path) for path in settings_files(environ))


def drain(stream):
    """Reads and drops the hook JSON on <stream>, so the writer never meets a closed pipe; a terminal is left alone."""
    try:
        if stream is not None and not stream.isatty():
            stream.read(MAX_READ)
    except (OSError, ValueError, UnicodeDecodeError):
        pass


def main(argv):
    """Runs the hook: prints the SessionStart JSON that asks for the language when none is set; returns 0."""
    parse_args(argv)
    try:
        drain(sys.stdin)
        if language_set(os.environ):
            return 0
        payload = {'hookSpecificOutput': {'hookEventName': 'SessionStart', 'additionalContext': CONTEXT}}
        sys.stdout.write(json.dumps(payload) + '\n')
    except Exception:  # noqa: BLE001  A hook never breaks a session start.
        return 0
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
