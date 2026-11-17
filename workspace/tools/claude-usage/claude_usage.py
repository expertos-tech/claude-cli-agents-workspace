#!/usr/bin/env python3
"""Claude Code usage read from the local session transcripts.

The transcripts live in ~/.claude/projects, or in the folder given with
--projects-dir. Only sessions that ran on this machine are counted. The model
of each response comes from the API response itself, the same model the plan
limits are counted against.

Commands:
  daily          responses and tokens per day and model
  sessions       every session: when, where, prompts, models of the main
                 conversation and of its subagents
  default-model  the model each new session started with, per day, which
                 shows when the default model changed

Times are shown in this machine's time zone. --since takes a local date or
date and time, such as 2026-11-16 or 2026-11-16T04:59.
"""

import argparse
import collections
import glob
import json
import os
import sys
from datetime import datetime, timedelta

DEFAULT_PROJECTS_DIR = '~/.claude/projects'
SYNTHETIC_MODEL = '<synthetic>'


def parse_instant(text, tz):
    """Read an ISO date or date and time, taking a value with no offset as tz; raise ValueError when invalid."""
    t = datetime.fromisoformat(text.replace('Z', '+00:00'))
    return t if t.tzinfo else t.replace(tzinfo=tz)


def parse_time(stamp, tz):
    """Return a transcript timestamp in tz, or None when it is missing or invalid."""
    try:
        return parse_instant(stamp, tz).astimezone(tz)
    except (AttributeError, ValueError, OverflowError):
        return None


def modified_since(path, since):
    """Tell whether a transcript changed at or after since; a vanished file did not."""
    try:
        return os.path.getmtime(path) >= since.timestamp()
    except OSError:
        return False


def transcripts(root, since):
    """Yield the path of every transcript under root that changed at or after since."""
    for path in glob.glob(os.path.join(glob.escape(root), '**', '*.jsonl'), recursive=True):
        if modified_since(path, since):
            yield path


def parse_record(line):
    """Return the JSON object held in a transcript line, or None for anything else."""
    try:
        record = json.loads(line)
    except (ValueError, RecursionError):
        return None
    return record if isinstance(record, dict) else None


def records(path):
    """Yield the valid records of a transcript, stopping quietly when the file cannot be read."""
    try:
        with open(path, encoding='utf-8', errors='ignore') as f:
            for line in f:
                record = parse_record(line)
                if record is not None:
                    yield record
    except OSError:
        return


def transcript_records(root, since):
    """Yield (path, record) for every record of the transcripts that changed at or after since."""
    for path in transcripts(root, since):
        for record in records(path):
            yield path, record


def project_of(path, root):
    """Return the project folder name of a transcript."""
    return os.path.relpath(path, root).split(os.sep)[0]


def is_subagent(path, record, root):
    """Tell whether a record belongs to a subagent, by its transcript path below root or its sidechain flag."""
    return f'{os.sep}subagents{os.sep}' in os.path.relpath(path, root) or bool(record.get('isSidechain'))


def text_of(value):
    """Return value when it is a string, else None."""
    return value if isinstance(value, str) else None


def message_of(record):
    """Return the message object of a record, or an empty one when it has none."""
    message = record.get('message')
    return message if isinstance(message, dict) else {}


def model_of(record):
    """Return the model that answered a record, or None when absent or synthetic."""
    model = text_of(message_of(record).get('model'))
    return None if not model or model == SYNTHETIC_MODEL else model


def token_count(usage, field):
    """Return a token count of a usage object; anything but a non-negative integer counts as zero."""
    value = usage.get(field, 0)
    valid = isinstance(value, int) and not isinstance(value, bool) and value >= 0
    return value if valid else 0


def response_of(record, seen):
    """Return the model and usage of an API response, once per response, else None."""
    if record.get('type') != 'assistant':
        return None
    model = model_of(record)
    message = message_of(record)
    usage = message.get('usage')
    if not model or not usage or not isinstance(usage, dict):
        return None
    key = (text_of(message.get('id')), text_of(record.get('requestId')))
    if key in seen:
        return None
    seen.add(key)
    return model, usage


def is_prompt(path, record, root):
    """Tell whether a record is a message the person typed in the main conversation."""
    if record.get('type') != 'user' or record.get('isMeta') or is_subagent(path, record, root):
        return False
    content = message_of(record).get('content')
    if isinstance(content, str):
        return True
    return isinstance(content, list) and any(isinstance(part, dict) and part.get('type') == 'text' for part in content)


def day_label(t):
    """Return the day a report groups a time under."""
    return t.strftime('%Y-%m-%d %a')


def add_usage(counter, usage):
    """Add one response and its token counts to the totals of a day and model."""
    counter['responses'] += 1
    counter['input'] += token_count(usage, 'input_tokens')
    counter['output'] += token_count(usage, 'output_tokens')
    counter['cache_read'] += token_count(usage, 'cache_read_input_tokens')
    counter['cache_write'] += token_count(usage, 'cache_creation_input_tokens')


def aggregate_daily(root, since, tz):
    """Return the response and token totals per (day, model)."""
    days = collections.defaultdict(collections.Counter)
    seen = set()
    for _, record in transcript_records(root, since):
        response = response_of(record, seen)
        t = parse_time(record.get('timestamp'), tz)
        if response and t is not None and t >= since:
            model, usage = response
            add_usage(days[(day_label(t), model)], usage)
    return days


def output_share(days):
    """Return (model, output tokens, percent of all output) per model, largest first."""
    totals = collections.Counter()
    for (_, model), c in sorted(days.items()):
        totals[model] += c['output']
    all_output = sum(totals.values()) or 1
    return [(model, n, 100 * n / all_output) for model, n in totals.most_common()]


def print_daily(days):
    """Print the daily table and the output share per model."""
    print(f'{"day":15}{"model":22}{"responses":>10}{"input":>10}{"output":>11}{"cache read":>14}{"cache write":>13}')
    for (day, model), c in sorted(days.items()):
        print(
            f'{day:15}{model:22}{c["responses"]:>10}{c["input"]:>10}{c["output"]:>11}'
            f'{c["cache_read"]:>14}{c["cache_write"]:>13}'
        )
    print('\nOutput tokens by model:')
    for model, n, share in output_share(days):
        print(f'  {model:22}{n:>11}  {share:5.1f}%')


def new_session(path, root, t):
    """Return the empty totals of a session first seen at time t."""
    return {
        'first': t,
        'last': t,
        'project': project_of(path, root),
        'entrypoints': set(),
        'prompts': 0,
        'main': collections.Counter(),
        'subagents': collections.Counter(),
        'output': 0,
    }


def add_record(session, path, record, t, seen, root):
    """Add one record at time t to the totals of its session."""
    session['first'], session['last'] = min(session['first'], t), max(session['last'], t)
    entrypoint = text_of(record.get('entrypoint'))
    if entrypoint:
        session['entrypoints'].add(entrypoint)
    if is_prompt(path, record, root):
        session['prompts'] += 1
    response = response_of(record, seen)
    if response:
        model, usage = response
        session['subagents' if is_subagent(path, record, root) else 'main'][model] += 1
        session['output'] += token_count(usage, 'output_tokens')


def aggregate_sessions(root, since, tz):
    """Return the totals of every session with activity at or after since, by session id."""
    sessions = {}
    seen = set()
    for path, record in transcript_records(root, since):
        t = parse_time(record.get('timestamp'), tz)
        if t is None or t < since:
            continue
        sid = text_of(record.get('sessionId')) or path
        session = sessions.setdefault(sid, new_session(path, root, t))
        add_record(session, path, record, t, seen, root)
    return sessions


def session_rows(sessions, sort):
    """Return (id, totals) of the sessions that got a response, by start time or by output tokens."""
    rows = [(sid, s) for sid, s in sessions.items() if s['main'] or s['subagents']]
    key = (lambda row: -row[1]['output']) if sort == 'tokens' else (lambda row: row[1]['first'])
    return sorted(rows, key=key)


def print_sessions(rows):
    """Print one line per session."""
    for sid, s in rows:
        print(
            f'{sid[:8]}  {s["first"]:%a %d %H:%M} - {s["last"]:%a %d %H:%M}  {s["project"][-32:]:32}'
            f'  {",".join(sorted(s["entrypoints"]))[:16]:16}  prompts={s["prompts"]:<4} output={s["output"]:<9}'
            f'  main={dict(s["main"])}  subagents={dict(s["subagents"])}'
        )


def first_response(path, root, tz):
    """Return the model and time of the first main-conversation response of a transcript, else None."""
    for record in records(path):
        if record.get('type') != 'assistant' or is_subagent(path, record, root):
            continue
        model = model_of(record)
        t = parse_time(record.get('timestamp'), tz)
        if model and t is not None:
            return model, t
    return None


def aggregate_default_model(root, since, tz):
    """Return how many sessions started at or after since with each model, per day."""
    days = collections.defaultdict(collections.Counter)
    for path in transcripts(root, since):
        first = first_response(path, root, tz)
        if first and first[1] >= since:
            model, t = first
            days[day_label(t)][model] += 1
    return days


def print_default_model(days):
    """Print the models new sessions started with, per day."""
    print('Model of the first response of each new session, per day:')
    for day in sorted(days):
        print(f'  {day}  ' + '  '.join(f'{m}: {n}' for m, n in days[day].most_common()))


def cmd_daily(args, root, since, tz):
    """Run the daily report."""
    print_daily(aggregate_daily(root, since, tz))


def cmd_sessions(args, root, since, tz):
    """Run the sessions report."""
    print_sessions(session_rows(aggregate_sessions(root, since, tz), args.sort))


def cmd_default_model(args, root, since, tz):
    """Run the default-model report."""
    print_default_model(aggregate_default_model(root, since, tz))


def build_parser(now):
    """Return the command line parser, with the default periods counted back from now."""
    week_ago = (now - timedelta(days=7)).strftime('%Y-%m-%d')
    five_weeks_ago = (now - timedelta(days=35)).strftime('%Y-%m-%d')
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest='command', required=True)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument(
        '--projects-dir', default=DEFAULT_PROJECTS_DIR, help='transcripts folder (default: %(default)s)'
    )

    daily = commands.add_parser('daily', parents=[common], help='responses and tokens per day and model')
    daily.add_argument('--since', default=week_ago, help='local date or date and time (default: 7 days ago)')
    daily.set_defaults(run=cmd_daily)

    sessions = commands.add_parser('sessions', parents=[common], help='every session with its models and prompts')
    sessions.add_argument('--since', default=week_ago, help='local date or date and time (default: 7 days ago)')
    sessions.add_argument('--sort', choices=['start', 'tokens'], default='start', help='order of the list')
    sessions.set_defaults(run=cmd_sessions)

    default_model = commands.add_parser(
        'default-model', parents=[common], help='the model new sessions started with, per day'
    )
    default_model.add_argument('--since', default=five_weeks_ago, help='local date (default: 35 days ago)')
    default_model.set_defaults(run=cmd_default_model)
    return parser


def checked_options(parser, args, tz):
    """Return the projects folder and start time, ending the run with exit code 2 when either is invalid."""
    try:
        since = parse_instant(args.since, tz)
    except ValueError:
        parser.error(f'invalid --since {args.since!r}: use a date or date and time, such as 2026-11-16T04:59')
    root = os.path.expanduser(args.projects_dir)
    if not os.path.isdir(root):
        parser.error(f'projects folder not found: {root}')
    return root, since


def keep_output_printable():
    """Escape text stdout cannot encode, such as a lone surrogate in a transcript, instead of failing."""
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(errors='backslashreplace')


def main(argv=None, now=None):
    """Run the command line; now is an aware datetime that also sets the time zone of the report."""
    now = now or datetime.now().astimezone()
    parser = build_parser(now)
    args = parser.parse_args(argv)
    root, since = checked_options(parser, args, now.tzinfo)
    keep_output_printable()
    args.run(args, root, since, now.tzinfo)


if __name__ == '__main__':
    main()
