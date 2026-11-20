"""SessionStart hook of the maintenance session of this repository: the rules index of the session.

It builds the index from the product's own, the section "## Reference" of workspace/AGENTS.md (its tables
"| File | Read before |" and "| File | Loads with |"), with the maintenance file .claude/session-index.md applied:
"## Ignore from the product index" drops files, the arrow bullets of "## Mapping" rewrite the words of each product
trigger, and the tables of "## CAW index" add rows with paths relative to the repository root. Rows naming the same
files merge their triggers. A product rule workspace/rules/<name>.md is named with its layer .claude/rules/<name>.md
when that file exists. The text goes to the session as hookSpecificOutput.additionalContext; after a compaction
(source "compact") it opens with a line saying the rules read before it are gone. In a work clone
(<root>/tmp/work/<yyyy-mm-dd>-<slug>/claude-cli-agents-workspace) it ends with the pilot mode line, read from the main
root's .claude/pilot-mode.local.md (missing, a link or another value: assisted): Claude Code skips the import of
CLAUDE.md "Pilot mode" in a session started there.
A hook must never break a session start: any failure (a missing file or section, a malformed line, an index too long)
still exits 0 with a context that says why and points at both files. Only a usage error of the flags exits 2.
Usage: python3 -I -B tests/caw-session-index.py [--root <dir>]   (hook JSON on stdin)
"""

import argparse
import json
import os
import re
import sys

PRODUCT_INDEX = 'workspace/AGENTS.md'
SESSION_INDEX = '.claude/session-index.md'
PRODUCT_PREFIX = 'workspace/'
REFERENCE = '## Reference'
IGNORE = '## Ignore from the product index'
MAPPING = '## Mapping'
CAW_INDEX = '## CAW index'
# The two table forms of an index, and the words that open a trigger of each.
TABLE_KINDS = {'read before': 'before', 'loads with': 'when touching'}
KIND_ORDER = ('before', 'when touching')
# Claude Code caps the context of a hook at 10,000 characters; the index stays well under it.
MAX_CONTEXT = 9000
MAX_READ = 1_000_000
SOURCES = ('startup', 'resume', 'clear', 'compact')
PRODUCT_RULE = re.compile(r'^workspace/rules/([a-z0-9]+(?:-[a-z0-9]+)*)\.md$')
FILE_CELL = re.compile(r'^`[^`]+`(?:\s*,\s*`[^`]+`)*$')
BACKTICKED = re.compile(r'`([^`]+)`')
IGNORE_BULLET = re.compile(r'^-\s+((?:`[^`]+`\s*,\s*)*`[^`]+`)\s*:')
MAPPING_BULLET = re.compile(r'^-\s+`([^`]+)`\s+→\s+(?:`([^`]*)`|nothing)\s*$')
SEPARATOR_CELL = re.compile(r'^:?-+:?$')
# The pilot mode of a session started in a work clone (CLAUDE.md "Pilot mode"): the main root's file, which
# /caw-pilot writes, holding the line Pilot mode: `<mode>`.
CLONE_NAME = 'claude-cli-agents-workspace'
WORK_NAME = re.compile(r'^\d{4}-\d{2}-\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*$')
PILOT_FILE = '.claude/pilot-mode.local.md'
PILOT_VALUE = re.compile(r'^Pilot mode: `(auto|assisted)`\.?\s*$', re.MULTILINE)
MAX_PILOT_READ = 4096
PILOT_LINE = (
    'Pilot mode: {mode} (this session started in a work clone, where Claude Code skips the import of `CLAUDE.md` '
    '"Pilot mode"; read from `{path}` of the main root, which /caw-pilot writes). This line wins over that section.'
)
PILOT_ASSISTED = ' Read `.claude/assisted.md` in full before your first reply and follow it.'

HEADER = (
    'Rules index of this session (tests/caw-session-index.py, from the section "Reference" of `workspace/AGENTS.md` '
    'with `.claude/session-index.md` applied). Read each file below before the task it names, once per session and '
    'again after a compaction. A product rule `workspace/rules/<name>.md` is followed with its layer '
    '`.claude/rules/<name>.md` over it: the layer wins where they differ.\n'
    'A line that holds only `@<path>`, in the root `CLAUDE.md` or in a rule or a skill of `.claude/`, points at a file '
    'to read in full, its path relative to the root where this session started, when the file '
    'holding the line applies (a rule: before the task this index names for it); the sections of the file holding the '
    'line win where they differ. An `@` anywhere else is not a pointer: a package (`@types/node`), a handle, a '
    'decorator, or any `@` in a file read as code, such as the files of `workspace/`.'
)
COMPACTED = (
    'The context was compacted: the rules read before it are gone. Read again the files below that the next task '
    'needs before acting.'
)
FALLBACK = (
    'The rules index of this session could not be built: {reason}. Read the section "Reference" of '
    '`workspace/AGENTS.md` and `.claude/session-index.md` and follow them: read each file they name before the task '
    'it names, a product rule `workspace/rules/<name>.md` with its layer `.claude/rules/<name>.md` over it, once per '
    'session and again after a compaction.'
)


class IndexBuildError(Exception):
    """A reason the index cannot be built, said to the session in the fallback context."""


def default_root():
    """Returns the repository root that holds this script: the parent of its tests/ folder."""
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def parse_args(argv):
    """Parses the flags; argparse exits 2 on a usage error and 0 after --help."""
    parser = argparse.ArgumentParser(
        prog='tests/caw-session-index.py',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description=(
            'SessionStart hook of the maintenance session: prints the rules index of the session, built from the\n'
            'section "Reference" of workspace/AGENTS.md with .claude/session-index.md applied, as the JSON\n'
            '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "<index>"}}.\n'
            'Reads the hook JSON on stdin (empty or invalid stdin is fine); source "compact" adds a first line\n'
            'saying the rules read before the compaction are gone. Any failure still prints a context that says\n'
            'why and points at both files.'
        ),
        epilog=(
            'Exit codes: 0 always when run as the hook (an index or the fallback context); 2 a usage error of\n'
            'the flags.\n\n'
            'Examples:\n'
            '  python3 -I -B tests/caw-session-index.py < /dev/null\n'
            '  echo \'{"source": "compact"}\' | python3 -I -B tests/caw-session-index.py --root /path/to/clone'
        ),
    )
    parser.add_argument('--root', default=None, help='repository root to read (default: the root holding this script)')
    args = parser.parse_args(argv)
    if args.root is not None and not os.path.isdir(args.root):
        parser.error(f'--root is not a folder: {args.root}')
    return args


def read_source(stream):
    """Returns the "source" of the hook JSON on <stream>, or "" when stdin is a terminal, empty or invalid."""
    try:
        if stream is None or stream.isatty():
            return ''
        data = json.loads(stream.read(MAX_READ) or 'null')
    except (OSError, ValueError, UnicodeDecodeError):
        return ''
    source = data.get('source') if isinstance(data, dict) else None
    return source if source in SOURCES else ''


def read_text(root, rel):
    """Returns the text of the file <rel> under <root>; raises IndexBuildError when it is missing or unreadable."""
    try:
        with open(os.path.join(root, rel), encoding='utf-8') as handle:
            return handle.read(MAX_READ)
    except FileNotFoundError:
        raise IndexBuildError(f'`{rel}` is missing') from None
    except (OSError, UnicodeDecodeError) as error:
        raise IndexBuildError(f'`{rel}` cannot be read ({type(error).__name__})') from None


def section(text, heading, rel):
    """Returns the numbered lines of the section <heading> of <text>, up to the next "## " heading, as a list of
    (line number, line); raises IndexBuildError naming <rel> when the heading is not there."""
    lines = text.splitlines()
    for start, line in enumerate(lines):
        if line.rstrip() == heading:
            body = []
            for number in range(start + 1, len(lines)):
                if lines[number].startswith('## '):
                    break
                body.append((number + 1, lines[number]))
            return body
    raise IndexBuildError(f'`{rel}` has no section "{heading}"')


def split_row(line):
    """Returns the cells of the markdown table row <line>, stripped, without the outer pipes."""
    inner = line.strip()
    inner = inner[1:] if inner.startswith('|') else inner
    inner = inner[:-1] if inner.endswith('|') else inner
    return [cell.strip() for cell in inner.split('|')]


def table_rows(lines, rel):
    """Returns the rows of the index tables in <lines> as (files, kind, trigger): a table with the header
    "| File | Read before |" gives kind "before", "| File | Loads with |" gives "when touching"; separator rows are
    skipped. Raises IndexBuildError naming <rel> and the line for a row outside such a table or a malformed row."""
    rows = []
    kind = None
    for number, line in lines:
        if not line.lstrip().startswith('|'):
            kind = None
            continue
        cells = split_row(line)
        if len(cells) == 2 and cells[0] == 'File' and cells[1].lower() in TABLE_KINDS:
            kind = TABLE_KINDS[cells[1].lower()]
            continue
        if all(SEPARATOR_CELL.match(cell) for cell in cells):
            continue
        if kind is None:
            raise IndexBuildError(
                f'`{rel}` line {number}: a table row outside a "File | Read before" or "File | Loads with" table'
            )
        if len(cells) != 2 or not FILE_CELL.match(cells[0]) or not cells[1]:
            raise IndexBuildError(f'`{rel}` line {number}: a row must be "| `<path>`[, `<path>`...] | <trigger> |"')
        rows.append((BACKTICKED.findall(cells[0]), kind, cells[1]))
    return rows


def ignored_files(lines, rel):
    """Returns the set of product paths listed by the bullets of the Ignore section; raises IndexBuildError for a bullet
    that does not start with backticked paths before a colon."""
    ignored = set()
    for number, line in lines:
        if not line.startswith('- '):
            continue
        match = IGNORE_BULLET.match(line)
        if not match:
            raise IndexBuildError(f'`{rel}` line {number}: an ignore bullet must start with "`<path>`[, `<path>`...]:"')
        ignored.update(BACKTICKED.findall(match.group(1)))
    return ignored


def substitutions(lines, rel):
    """Returns the (old, new) text substitutions of the Mapping section, in file order: the bullets
    "- `A` -> `B`" and "- `A` -> nothing" (with the arrow U+2192). Raises IndexBuildError for an arrow bullet of another
    form; prose bullets with no arrow are skipped."""
    pairs = []
    for number, line in lines:
        if not line.startswith('- ') or '→' not in line:
            continue
        match = MAPPING_BULLET.match(line)
        if not match:
            raise IndexBuildError(f'`{rel}` line {number}: a mapping bullet must be "- `A` → `B`" or "- `A` → nothing"')
        pairs.append((match.group(1), match.group(2) or ''))
    return pairs


def build_groups(root):
    """Returns the index as an ordered list of (files, triggers): the product rows, less the ignored files and with
    the substitutions applied, then the CAW rows, merged by their set of files. Raises IndexBuildError on a failure."""
    product = read_text(root, PRODUCT_INDEX)
    reference = section(product, REFERENCE, PRODUCT_INDEX)
    product_rows = table_rows(reference, PRODUCT_INDEX)
    if not product_rows:
        raise IndexBuildError(f'the section "{REFERENCE}" of `{PRODUCT_INDEX}` has no table row')
    layer = read_text(root, SESSION_INDEX)
    # Every section is found first, so a missing heading is named as such, never as a malformed line of the section
    # above it.
    ignore_lines, mapping_lines, caw_lines = (
        section(layer, name, SESSION_INDEX) for name in (IGNORE, MAPPING, CAW_INDEX)
    )
    ignored = ignored_files(ignore_lines, SESSION_INDEX)
    pairs = substitutions(mapping_lines, SESSION_INDEX)
    caw_rows = table_rows(caw_lines, SESSION_INDEX)

    rows = []
    for files, kind, trigger in product_rows:
        kept = [PRODUCT_PREFIX + path for path in files if path not in ignored]
        if not kept:
            continue
        for old, new in pairs:
            trigger = trigger.replace(old, new)
        rows.append((kept, kind, trigger.strip()))
    rows.extend(caw_rows)

    groups = {}
    for files, kind, trigger in rows:
        key = tuple(sorted(set(files)))
        entry = groups.setdefault(key, (list(dict.fromkeys(files)), []))
        if (kind, trigger) not in entry[1]:
            entry[1].append((kind, trigger))
    return list(groups.values())


def name_file(root, path):
    """Returns the backticked <path>, followed by its layer when it is a product rule whose
    .claude/rules/<name>.md exists under <root>."""
    match = PRODUCT_RULE.match(path)
    if match:
        layer = f'.claude/rules/{match.group(1)}.md'
        if os.path.isfile(os.path.join(root, layer)):
            return f'`{path}` (then `{layer}` over it)'
    return f'`{path}`'


def render(root, groups):
    """Returns the index lines: one per group, its files with their layers, then its triggers, the "before" ones
    first, each opened by its kind."""
    lines = []
    for files, triggers in groups:
        ordered = sorted(triggers, key=lambda item: KIND_ORDER.index(item[0]))
        named = ', '.join(name_file(root, path) for path in files)
        lines.append(f'- {named}: ' + '; '.join(f'{kind} {trigger}' for kind, trigger in ordered))
    return lines


def main_root_of_clone(root):
    """Returns the repository root that holds <root> when <root> is a work clone,
    <main>/tmp/work/<yyyy-mm-dd>-<slug>/claude-cli-agents-workspace (tests/caw-work.sh), else None."""
    work = os.path.dirname(root)
    work_dir = os.path.dirname(work)
    tmp = os.path.dirname(work_dir)
    shaped = (
        os.path.basename(root) == CLONE_NAME
        and WORK_NAME.match(os.path.basename(work))
        and os.path.basename(work_dir) == 'work'
        and os.path.basename(tmp) == 'tmp'
    )
    main = os.path.dirname(tmp)
    return main if shaped and os.path.isfile(os.path.join(main, 'CLAUDE.md')) else None


def pilot_line(root):
    """Returns the pilot mode line of a session started in a work clone, read from the main root's
    .claude/pilot-mode.local.md (missing, a link, unreadable or another value: assisted), or None outside a clone.
    At the root the mode comes from the import of CLAUDE.md "Pilot mode", which Claude Code skips in a clone."""
    main = main_root_of_clone(root)
    if main is None:
        return None
    path = os.path.join(main, PILOT_FILE)
    mode = 'assisted'
    try:
        if os.path.isfile(path) and not os.path.islink(path):
            with open(path, encoding='utf-8') as handle:
                found = PILOT_VALUE.search(handle.read(MAX_PILOT_READ))
            if found:
                mode = found.group(1)
    except (OSError, UnicodeDecodeError):
        mode = 'assisted'
    line = PILOT_LINE.format(mode=mode, path=PILOT_FILE)
    return line + (PILOT_ASSISTED if mode == 'assisted' else '')


def context(root, source):
    """Returns the additionalContext for <source>: the index, or the fallback that says why it could not be built;
    in a work clone, followed by the pilot mode line."""
    first = [COMPACTED] if source == 'compact' else []
    try:
        text = '\n'.join(first + [HEADER, ''] + render(root, build_groups(root)))
        if len(text) > MAX_CONTEXT:
            raise IndexBuildError(f'the index is {len(text)} characters, over the limit of {MAX_CONTEXT}')
    except IndexBuildError as error:
        text = '\n'.join(first + [FALLBACK.format(reason=error)])
    except Exception as error:  # A hook never breaks a session start.
        text = '\n'.join(first + [FALLBACK.format(reason=f'unexpected error ({type(error).__name__})')])
    try:
        line = pilot_line(root)
    except Exception:  # A hook never breaks a session start; the CLAUDE.md default (assisted) still holds.
        line = None
    return text if line is None else f'{text}\n\n{line}'


def main(argv):
    """Runs the hook: prints the SessionStart JSON with the index and returns 0."""
    args = parse_args(argv)
    root = os.path.abspath(args.root) if args.root else default_root()
    payload = {
        'hookSpecificOutput': {
            'hookEventName': 'SessionStart',
            'additionalContext': context(root, read_source(sys.stdin)),
        }
    }
    sys.stdout.write(json.dumps(payload) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
