"""Unit tests of the usage report; every test name carries the acceptance criterion it proves."""

import contextlib
import io
import json
import os
import runpy
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import claude_usage

SCRIPT = str(Path(__file__).resolve().parent.parent / 'claude_usage.py')
TZ = timezone(timedelta(hours=-3))
NOW = datetime(2026, 10, 30, 12, 0, tzinfo=TZ)
SINCE = datetime(2026, 10, 20, tzinfo=TZ)
USAGE = {'input_tokens': 10, 'output_tokens': 100, 'cache_read_input_tokens': 1000, 'cache_creation_input_tokens': 50}


def assistant(stamp='2026-10-22T12:00:00.000Z', model='model-alpha', msg='m1', req='r1', session='sess-0001', **extra):
    """Build an assistant record of a fictitious session; a usage keyword replaces the default usage."""
    usage = extra.pop('usage', USAGE)
    message = {'id': msg, 'model': model, 'usage': usage}
    return {
        'type': 'assistant',
        'timestamp': stamp,
        'sessionId': session,
        'requestId': req,
        'message': message,
        **extra,
    }


def user(stamp='2026-10-22T11:59:00.000Z', content='fictitious prompt', session='sess-0001', **extra):
    """Build a user record of a fictitious session."""
    return {'type': 'user', 'timestamp': stamp, 'sessionId': session, 'message': {'content': content}, **extra}


GOLDEN_TREE = {
    '-home-demo-alpha/sess-aaaa.jsonl': [
        user('2026-10-20T12:00:00.000Z', session='aaaaaaaa-0001', entrypoint='cli'),
        assistant('2026-10-20T12:00:05.000Z', 'model-alpha', 'm1', 'r1', 'aaaaaaaa-0001'),
        assistant('2026-10-20T12:00:06.000Z', 'model-alpha', 'm1', 'r1', 'aaaaaaaa-0001'),
        assistant('2026-10-20T12:01:00.000Z', '<synthetic>', 'm0', 'r0', 'aaaaaaaa-0001'),
        assistant(
            '2026-10-21T02:30:00.000Z',
            'model-beta',
            'm2',
            'r2',
            'aaaaaaaa-0001',
            usage={'input_tokens': 1, 'output_tokens': 300},
        ),
        user('2026-10-21T02:31:00.000Z', [{'type': 'text', 'text': 'x'}], 'aaaaaaaa-0001', entrypoint='vscode'),
        user('2026-10-21T02:32:00.000Z', [{'type': 'tool_result'}], 'aaaaaaaa-0001'),
        user('2026-10-21T02:33:00.000Z', session='aaaaaaaa-0001', isMeta=True),
        assistant('2026-10-21T02:34:00.000Z', 'model-sub', 'm3', 'r3', 'aaaaaaaa-0001', isSidechain=True),
    ],
    '-home-demo-alpha/aaaaaaaa-0001/subagents/agent-1.jsonl': [
        user('2026-10-20T12:02:00.000Z', session='aaaaaaaa-0001'),
        assistant('2026-10-20T12:02:30.000Z', 'model-sub', 'm4', 'r4', 'aaaaaaaa-0001'),
    ],
    '-home-demo-a-very-long-project-folder-name-beta/sess-bbbb.jsonl': [
        assistant('2026-10-22T15:00:00.000Z', 'model-beta', 'm5', 'r5', 'bbbbbbbb-0002', entrypoint='sdk-cli'),
        assistant('2026-10-22T15:10:00+00:00', 'model-beta', 'm6', 'r6', 'bbbbbbbb-0002', usage={'output_tokens': 7}),
    ],
    '-home-demo-gamma/sess-cccc.jsonl': [user('2026-10-22T16:00:00.000Z', session='cccccccc-0003')],
    '-home-demo-gamma/sess-old.jsonl': [
        assistant('2026-10-01T12:00:00.000Z', 'model-old', 'm7', 'r7', 'dddddddd-0004'),
        assistant('2026-10-22T18:00:00.000Z', 'model-old', 'm8', 'r8', 'dddddddd-0004'),
    ],
}

GOLDEN_DAILY = """\
day            model                  responses     input     output    cache read  cache write
2026-10-20 Tue model-alpha                    1        10        100          1000           50
2026-10-20 Tue model-beta                     1         1        300             0            0
2026-10-20 Tue model-sub                      2        20        200          2000          100
2026-10-22 Thu model-beta                     2        10        107          1000           50
2026-10-22 Thu model-old                      1        10        100          1000           50

Output tokens by model:
  model-beta                    407   50.4%
  model-sub                     200   24.8%
  model-alpha                   100   12.4%
  model-old                     100   12.4%
"""

GOLDEN_SESSIONS = """\
aaaaaaaa  Tue 20 09:00 - Tue 20 23:34  -home-demo-alpha                  cli,vscode        prompts=2    output=600\
        main={'model-alpha': 1, 'model-beta': 1}  subagents={'model-sub': 2}
bbbbbbbb  Thu 22 12:00 - Thu 22 12:10  ry-long-project-folder-name-beta  sdk-cli           prompts=0    output=107\
        main={'model-beta': 2}  subagents={}
dddddddd  Thu 22 15:00 - Thu 22 15:00  -home-demo-gamma                                    prompts=0    output=100\
        main={'model-old': 1}  subagents={}
"""

GOLDEN_DEFAULT_MODEL = """\
Model of the first response of each new session, per day:
  2026-10-20 Tue  model-alpha: 1
  2026-10-22 Thu  model-beta: 1
"""


class TranscriptCase(unittest.TestCase):
    """Base of the tests: a temporary projects folder and helpers to fill it and run the report."""

    def setUp(self):
        """Create the temporary projects folder."""
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.root = os.path.realpath(folder.name)

    def write(self, relative, lines, mtime=NOW):
        """Write a transcript from dicts or raw bytes and set its modification time."""
        path = os.path.join(self.root, relative)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'wb') as f:
            for line in lines:
                f.write(line if isinstance(line, bytes) else json.dumps(line).encode('utf-8'))
                f.write(b'\n')
        os.utime(path, (mtime.timestamp(), mtime.timestamp()))
        return path

    def run_main(self, *argv, projects_dir=None):
        """Run the command line and return its exit code, stdout and stderr."""
        out, err = io.StringIO(), io.StringIO()
        code = 0
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                claude_usage.main([*argv, '--projects-dir', projects_dir or self.root], now=NOW)
            except SystemExit as stop:
                code = stop.code
        return code, out.getvalue(), err.getvalue()

    def report(self, *argv):
        """Run a command that must succeed and return its stdout."""
        code, out, err = self.run_main(*argv)
        self.assertEqual(code, 0, err)
        return out


class DailyTests(TranscriptCase):
    """AC-1: the daily report."""

    def test_ac1_tokens_per_day_and_model(self):
        """AC-1: responses and the four token kinds add up per day and model."""
        self.write(
            '-demo/s.jsonl',
            [
                assistant('2026-10-22T12:00:00Z', 'model-alpha', 'm1'),
                assistant('2026-10-22T13:00:00Z', 'model-alpha', 'm2'),
                assistant('2026-10-22T13:00:00Z', 'model-beta', 'm3'),
                assistant('2026-10-23T13:00:00Z', 'model-alpha', 'm4'),
            ],
        )
        days = claude_usage.aggregate_daily(self.root, SINCE, TZ)
        self.assertEqual(
            days[('2026-10-22 Thu', 'model-alpha')],
            {'responses': 2, 'input': 20, 'output': 200, 'cache_read': 2000, 'cache_write': 100},
        )
        self.assertEqual(days[('2026-10-22 Thu', 'model-beta')]['responses'], 1)
        self.assertEqual(days[('2026-10-23 Fri', 'model-alpha')]['responses'], 1)
        self.assertEqual(len(days), 3)

    def test_ac1_output_share_per_model(self):
        """AC-1: the share of each model is its part of all output tokens, largest first."""
        days = {
            ('2026-10-22 Thu', 'model-alpha'): {'output': 100},
            ('2026-10-23 Fri', 'model-beta'): {'output': 300},
        }
        self.assertEqual(
            claude_usage.output_share(days),
            [('model-beta', 300, 75.0), ('model-alpha', 100, 25.0)],
        )

    def test_ac1_output_share_with_no_output_does_not_divide_by_zero(self):
        """AC-1: a report with no tokens has a share of zero."""
        days = {('2026-10-22 Thu', 'model-alpha'): {'output': 0}}
        self.assertEqual(claude_usage.output_share(days), [('model-alpha', 0, 0.0)])
        self.assertEqual(claude_usage.output_share({}), [])

    def test_ac1_missing_token_kind_counts_zero(self):
        """AC-1: a token kind absent from the usage adds nothing."""
        self.write('-demo/s.jsonl', [assistant(usage={'output_tokens': 5})])
        totals = claude_usage.aggregate_daily(self.root, SINCE, TZ)[('2026-10-22 Thu', 'model-alpha')]
        self.assertEqual(totals['input'], 0)
        self.assertEqual(totals['output'], 5)

    def test_ac1_day_follows_the_given_time_zone(self):
        """AC-1: the same instant falls on the day of the zone passed in."""
        self.write('-demo/s.jsonl', [assistant('2026-10-22T01:00:00Z')])
        self.assertIn(('2026-10-21 Wed', 'model-alpha'), claude_usage.aggregate_daily(self.root, SINCE, TZ))
        self.assertIn(('2026-10-22 Thu', 'model-alpha'), claude_usage.aggregate_daily(self.root, SINCE, timezone.utc))


class SessionsTests(TranscriptCase):
    """AC-2: the sessions report."""

    def test_ac2_session_totals(self):
        """AC-2: when, where, entrypoints, prompts, output and models of main and subagents."""
        self.write(
            '-demo-project/s.jsonl',
            [
                user('2026-10-22T11:00:00Z', entrypoint='cli'),
                assistant('2026-10-22T11:01:00Z', 'model-alpha', 'm1'),
                user('2026-10-22T11:02:00Z', [{'type': 'text', 'text': 'x'}], entrypoint='vscode'),
                assistant('2026-10-22T11:03:00Z', 'model-side', 'm2', isSidechain=True),
            ],
        )
        self.write('-demo-project/s/subagents/a.jsonl', [assistant('2026-10-22T11:04:00Z', 'model-sub', 'm3')])
        session = claude_usage.aggregate_sessions(self.root, SINCE, TZ)['sess-0001']
        self.assertEqual(session['first'], datetime(2026, 10, 22, 8, 0, tzinfo=TZ))
        self.assertEqual(session['last'], datetime(2026, 10, 22, 8, 4, tzinfo=TZ))
        self.assertEqual(session['project'], '-demo-project')
        self.assertEqual(session['entrypoints'], {'cli', 'vscode'})
        self.assertEqual(session['prompts'], 2)
        self.assertEqual(session['output'], 300)
        self.assertEqual(session['main'], {'model-alpha': 1})
        self.assertEqual(session['subagents'], {'model-side': 1, 'model-sub': 1})

    def test_ac2_sort_by_start_and_by_tokens(self):
        """AC-2: --sort start orders by first activity and --sort tokens by output, largest first."""
        self.write(
            '-demo/s.jsonl',
            [
                assistant('2026-10-22T11:00:00Z', msg='m1', session='small-early', usage={'output_tokens': 1}),
                assistant('2026-10-22T12:00:00Z', msg='m2', session='large-late', usage={'output_tokens': 9}),
            ],
        )
        self.assertEqual(self.report('sessions', '--since', '2026-10-20', '--sort', 'start')[:8], 'small-ea')
        self.assertEqual(self.report('sessions', '--since', '2026-10-20', '--sort', 'tokens')[:8], 'large-la')
        self.assertEqual(self.report('sessions', '--since', '2026-10-20')[:8], 'small-ea')

    def test_ac2_invalid_sort_exits_2(self):
        """AC-2: an unknown --sort value is rejected."""
        code, _, err = self.run_main('sessions', '--sort', 'size')
        self.assertEqual(code, 2)
        self.assertIn('--sort', err)

    def test_ac2_session_with_no_response_is_not_listed(self):
        """AC-2: a session that only has prompts stays out of the list."""
        self.write('-demo/s.jsonl', [user()])
        self.assertEqual(self.report('sessions', '--since', '2026-10-20'), '')

    def test_ac2_activity_before_since_is_left_out(self):
        """AC-2: records before --since change neither the times nor the counts of a session."""
        self.write(
            '-demo/s.jsonl',
            [
                user('2026-10-01T12:00:00Z'),
                assistant('2026-10-01T12:00:00Z', 'model-old', 'm1'),
                assistant('2026-10-22T12:00:00Z', 'model-alpha', 'm2'),
                {'type': 'assistant', 'sessionId': 'sess-0001'},
            ],
        )
        session = claude_usage.aggregate_sessions(self.root, SINCE, TZ)['sess-0001']
        self.assertEqual(session['first'], datetime(2026, 10, 22, 9, 0, tzinfo=TZ))
        self.assertEqual(session['prompts'], 0)
        self.assertEqual(session['main'], {'model-alpha': 1})

    def test_ac2_session_without_id_is_keyed_by_path(self):
        """AC-2: records with no session id group by their transcript."""
        path = self.write('-demo/s.jsonl', [assistant(session=None)])
        self.assertEqual(list(claude_usage.aggregate_sessions(self.root, SINCE, TZ)), [path])

    def test_ac2_prompts_are_only_what_the_person_typed(self):
        """AC-2: text and text parts count; tool results, meta records and subagents do not."""
        main, sub = os.path.join(self.root, 'p', 's.jsonl'), os.path.join(self.root, 'p', 's', 'subagents', 'a.jsonl')
        cases = [
            (main, user(), True),
            (main, user(content=[{'type': 'text', 'text': 'x'}]), True),
            (main, user(content=[{'type': 'tool_result'}]), False),
            (main, user(content=['not a part']), False),
            (main, user(content=3), False),
            (main, user(isMeta=True), False),
            (main, user(isSidechain=True), False),
            (main, assistant(), False),
            (sub, user(), False),
        ]
        for path, record, expected in cases:
            with self.subTest(record=record):
                self.assertEqual(claude_usage.is_prompt(path, record, self.root), expected)


class DefaultModelTests(TranscriptCase):
    """AC-3: the default-model report."""

    def counts(self, since=SINCE):
        """Return the sessions per day and model as plain dicts."""
        days = claude_usage.aggregate_default_model(self.root, since, TZ)
        return {day: dict(models) for day, models in days.items()}

    def test_ac3_first_response_of_each_session_per_day(self):
        """AC-3: only the first response of each transcript counts, on the day it happened."""
        self.write(
            '-demo/a.jsonl',
            [
                user('2026-10-22T11:59:00Z'),
                assistant('2026-10-22T12:00:00Z', 'model-alpha', 'm1'),
                assistant('2026-10-23T12:00:00Z', 'model-beta', 'm2'),
            ],
        )
        self.write('-demo/b.jsonl', [assistant('2026-10-22T13:00:00Z', 'model-alpha', 'm3')])
        self.write('-demo/c.jsonl', [assistant('2026-10-23T13:00:00Z', 'model-beta', 'm4')])
        self.assertEqual(self.counts(), {'2026-10-22 Thu': {'model-alpha': 2}, '2026-10-23 Fri': {'model-beta': 1}})

    def test_ac3_subagent_transcripts_are_ignored(self):
        """AC-3: a transcript in a subagents folder never counts."""
        self.write('-demo/a/subagents/x.jsonl', [assistant(model='model-sub')])
        self.assertEqual(self.counts(), {})

    def test_ac3_sidechains_are_ignored(self):
        """AC-3: a sidechain response is not the first response of the session."""
        self.write(
            '-demo/a.jsonl',
            [assistant(model='model-side', msg='m1', isSidechain=True), assistant(model='model-alpha', msg='m2')],
        )
        self.assertEqual(self.counts(), {'2026-10-22 Thu': {'model-alpha': 1}})

    def test_ac3_records_with_no_usable_model_or_time_are_passed_over(self):
        """AC-3: the first response is the first one with a real model and a valid time."""
        self.write(
            '-demo/a.jsonl',
            [
                assistant(model='<synthetic>', msg='m1'),
                assistant(model=None, msg='m2'),
                assistant(stamp='not a time', model='model-beta', msg='m3'),
                assistant(model='model-alpha', msg='m4'),
            ],
        )
        self.assertEqual(self.counts(), {'2026-10-22 Thu': {'model-alpha': 1}})

    def test_ac3_session_started_before_since_is_not_new(self):
        """AC-3: a session that started before --since does not count, even with later responses."""
        self.write(
            '-demo/a.jsonl',
            [
                assistant('2026-10-01T12:00:00Z', 'model-old', 'm1'),
                assistant('2026-10-22T12:00:00Z', 'model-alpha', 'm2'),
            ],
        )
        self.assertEqual(self.counts(), {})

    def test_ac3_transcript_with_no_response_does_not_count(self):
        """AC-3: a transcript with only prompts has no first response."""
        self.write('-demo/a.jsonl', [user()])
        self.assertEqual(self.counts(), {})


class DeduplicationTests(TranscriptCase):
    """AC-4: what counts as a response."""

    def daily_responses(self):
        """Return how many responses the daily report counted."""
        return sum(c['responses'] for c in claude_usage.aggregate_daily(self.root, SINCE, TZ).values())

    def test_ac4_same_message_and_request_counts_once(self):
        """AC-4: a response repeated in a transcript counts once."""
        self.write('-demo/s.jsonl', [assistant(), assistant()])
        self.assertEqual(self.daily_responses(), 1)
        session = claude_usage.aggregate_sessions(self.root, SINCE, TZ)['sess-0001']
        self.assertEqual(session['main'], {'model-alpha': 1})
        self.assertEqual(session['output'], 100)

    def test_ac4_same_response_in_two_transcripts_counts_once(self):
        """AC-4: the deduplication spans every transcript of the run."""
        self.write('-demo/a.jsonl', [assistant()])
        self.write('-demo/b.jsonl', [assistant()])
        self.assertEqual(self.daily_responses(), 1)

    def test_ac4_different_message_or_request_counts_again(self):
        """AC-4: only the pair of message id and request id identifies a response."""
        self.write(
            '-demo/s.jsonl',
            [assistant(msg='m1', req='r1'), assistant(msg='m1', req='r2'), assistant(msg='m2', req='r1')],
        )
        self.assertEqual(self.daily_responses(), 3)

    def test_ac4_response_seen_before_since_stays_deduplicated(self):
        """AC-4: in the daily report a copy dated in the period does not count one seen before it."""
        self.write('-demo/s.jsonl', [assistant('2026-10-01T12:00:00Z'), assistant('2026-10-22T12:00:00Z')])
        self.assertEqual(self.daily_responses(), 0)

    def test_ac4_synthetic_or_incomplete_messages_do_not_count(self):
        """AC-4: synthetic, no model, no usage and empty usage never count."""
        cases = {
            'synthetic': assistant(model='<synthetic>'),
            'no model': assistant(model=None),
            'empty model': assistant(model=''),
            'no usage': assistant(usage=None),
            'empty usage': assistant(usage={}),
            'no message': {'type': 'assistant', 'timestamp': '2026-10-22T12:00:00Z', 'sessionId': 'sess-0001'},
            'not assistant': user(),
        }
        for name, record in cases.items():
            with self.subTest(name):
                self.assertIsNone(claude_usage.response_of(record, set()))


class SinceTests(TranscriptCase):
    """AC-5: the --since limit."""

    def test_ac5_date_is_midnight_in_the_given_zone(self):
        """AC-5: a date alone starts at midnight of the zone."""
        self.assertEqual(claude_usage.parse_instant('2026-10-21', TZ), datetime(2026, 10, 21, tzinfo=TZ))

    def test_ac5_date_and_time_keep_the_given_zone_or_their_offset(self):
        """AC-5: a date and time is local unless it carries an offset."""
        self.assertEqual(claude_usage.parse_instant('2026-10-21T04:59', TZ), datetime(2026, 10, 21, 4, 59, tzinfo=TZ))
        self.assertEqual(
            claude_usage.parse_instant('2026-10-21T04:59:00+00:00', TZ),
            datetime(2026, 10, 21, 1, 59, tzinfo=TZ),
        )
        self.assertEqual(
            claude_usage.parse_instant('2026-10-21T04:59:00Z', TZ),
            datetime(2026, 10, 21, 1, 59, tzinfo=TZ),
        )

    def test_ac5_timestamp_is_converted_to_the_given_zone(self):
        """AC-5: a transcript time is shown in the zone passed in, also when it has no offset."""
        self.assertEqual(
            claude_usage.parse_time('2026-10-21T12:00:00.000Z', TZ).strftime('%d %H:%M %z'), '21 09:00 -0300'
        )
        self.assertEqual(claude_usage.parse_time('2026-10-21T12:00:00', TZ).strftime('%d %H:%M %z'), '21 12:00 -0300')

    def test_ac5_time_limit_includes_its_exact_instant(self):
        """AC-5: a date and time cuts inside a day, and a record at that instant stays in."""
        self.write(
            '-demo/s.jsonl',
            [
                assistant('2026-10-22T11:59:59Z', 'model-before', 'm1'),
                assistant('2026-10-22T12:00:00Z', 'model-at', 'm2'),
                assistant('2026-10-22T12:00:01Z', 'model-after', 'm3'),
            ],
        )
        out = self.report('daily', '--since', '2026-10-22T09:00')
        self.assertNotIn('model-before', out)
        self.assertIn('model-at', out)
        self.assertIn('model-after', out)

    def test_ac5_limit_applies_to_sessions_and_default_model(self):
        """AC-5: every command honors a date and time."""
        self.write('-demo/s.jsonl', [assistant('2026-10-22T12:00:00Z')])
        self.assertIn('model-alpha', self.report('sessions', '--since', '2026-10-22T09:00'))
        self.assertEqual(self.report('sessions', '--since', '2026-10-22T09:01'), '')
        self.assertIn('model-alpha', self.report('default-model', '--since', '2026-10-22T09:00'))
        self.assertNotIn('model-alpha', self.report('default-model', '--since', '2026-10-22T09:01'))

    def test_ac5_file_not_modified_since_the_limit_is_not_read(self):
        """AC-5: the modification time filters transcripts, with the exact instant still in."""
        since = datetime(2026, 10, 22, 9, 0, tzinfo=TZ)
        at_limit = self.write('-demo/at.jsonl', [assistant(msg='m1')], mtime=since)
        self.write('-demo/older.jsonl', [assistant(msg='m2')], mtime=since - timedelta(seconds=1))
        self.assertEqual(list(claude_usage.transcripts(self.root, since)), [at_limit])

    def test_ac5_default_limits_count_back_from_now(self):
        """AC-5: with no --since, daily and sessions go back 7 days and default-model 35."""
        self.write(
            '-demo/s.jsonl',
            [
                assistant('2026-10-22T12:00:00Z', 'model-recent', 'm1', 'r1', 'recent-1'),
                assistant('2026-10-23T12:00:00Z', 'model-inside', 'm2', 'r2', 'inside-1'),
            ],
        )
        self.write('-demo/t.jsonl', [assistant('2026-09-25T12:00:00Z', 'model-month', 'm3', 'r3', 'month-1')])
        self.write('-demo/u.jsonl', [assistant('2026-09-24T12:00:00Z', 'model-oldest', 'm4', 'r4', 'oldest-1')])
        daily = self.report('daily')
        self.assertIn('model-inside', daily)
        self.assertNotIn('model-recent', daily)
        self.assertNotIn('inside-1', self.report('sessions', '--since', '2026-10-24'))
        self.assertIn('inside-1', self.report('sessions'))
        default_model = self.report('default-model')
        self.assertIn('model-month', default_model)
        self.assertNotIn('model-oldest', default_model)

    def test_ac5_invalid_since_exits_2_with_a_clear_message(self):
        """AC-5: an invalid --since on any command exits 2 and names the problem."""
        for command in ('daily', 'sessions', 'default-model'):
            for value in ('not-a-date', '2026-13-40', ''):
                with self.subTest(command=command, value=value):
                    code, out, err = self.run_main(command, '--since', value)
                    self.assertEqual(code, 2)
                    self.assertEqual(out, '')
                    self.assertIn('invalid --since', err)
                    self.assertNotIn('Traceback', err)

    def test_ac5_invalid_since_as_a_real_process_shows_no_traceback(self):
        """AC-5: the same failure from the script itself, with the host command line."""
        done = subprocess.run(
            [sys.executable, '-I', '-B', SCRIPT, 'daily', '--since', 'not-a-date', '--projects-dir', self.root],
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual(done.returncode, 2)
        self.assertIn('invalid --since', done.stderr)
        self.assertNotIn('Traceback', done.stderr)


WRONG_TYPED = {
    'timestamp number': {**assistant(model='model-bad', msg='b'), 'timestamp': 12345},
    'timestamp list': {**assistant(model='model-bad', msg='b'), 'timestamp': ['x']},
    'timestamp out of range': assistant('0001-01-01T00:00:00+14:00', 'model-bad', 'b'),
    'message text': {**assistant(), 'message': 'text'},
    'message number': {**assistant(), 'message': 3},
    'message list': {**assistant(), 'message': [1]},
    'model list': assistant(model=['model-bad'], msg='b'),
    'model object': assistant(model={'name': 'model-bad'}, msg='b'),
    'model number': assistant(model=3, msg='b'),
    'usage text': assistant(model='model-bad', msg='b', usage='many'),
    'usage list': assistant(model='model-bad', msg='b', usage=[1]),
    'usage number': assistant(model='model-bad', msg='b', usage=3),
    'user message text': {**user(), 'message': 'text'},
    'user content number': user(content=3),
    'entrypoint list': {**user(), 'entrypoint': ['cli']},
    'entrypoint number': {**user(), 'entrypoint': 3},
    'session id list': assistant(model='model-bad', msg='b', session=['x']),
    'session id number': assistant(model='model-bad', msg='b', session=3),
}


class RobustnessTests(TranscriptCase):
    """AC-6: bad data is skipped, never fatal."""

    def assert_good_record_survives(self):
        """Run every command and require the valid record in each report."""
        for argv in (
            ['daily', '--since', '2026-10-20'],
            ['sessions', '--since', '2026-10-20'],
            ['default-model', '--since', '2026-10-20'],
        ):
            self.assertIn('model-good', self.report(*argv))

    def write_with_good_record(self, lines):
        """Write the bad lines followed by a valid response."""
        good = assistant('2026-10-22T12:00:00Z', 'model-good', 'good', 'good')
        return self.write('-demo/s.jsonl', [*lines, good])

    def test_ac6_corrupt_lines_are_skipped(self):
        """AC-6: lines that are not JSON do not stop the run."""
        self.write_with_good_record([b'{corrupt', b'', b'{"type": "assistant", "message":'])
        self.assert_good_record_survives()

    def test_ac6_json_that_is_not_an_object_is_skipped(self):
        """AC-6: a JSON line such as 3 is skipped instead of raising AttributeError."""
        self.write_with_good_record([b'3', b'[1, 2]', b'"text"', b'null', b'true', b'1.5'])
        self.assert_good_record_survives()
        path = os.path.join(self.root, '-demo', 's.jsonl')
        self.assertEqual(len(list(claude_usage.records(path))), 1)

    def test_ac6_too_deeply_nested_json_is_skipped(self):
        """AC-6: a line that exhausts the JSON parser is a corrupt line."""
        self.write_with_good_record([b'[' * 200000])
        self.assert_good_record_survives()

    def test_ac6_wrong_typed_fields_are_skipped(self):
        """AC-6: every field with the wrong type leaves the valid record counted."""
        self.write('-demo/other.jsonl', [assistant('2026-10-22T12:00:00Z', 'model-good', 'good', 'good')])
        for name, record in WRONG_TYPED.items():
            with self.subTest(name):
                self.write_with_good_record([record])
                self.assert_good_record_survives()

    def test_ac6_wrong_typed_model_time_or_usage_does_not_count_in_daily(self):
        """AC-6: a response with one of these fields wrong stays out of the daily report."""
        for name, record in WRONG_TYPED.items():
            if not name.startswith('session id'):
                with self.subTest(name):
                    self.write_with_good_record([record])
                    self.assertNotIn('model-bad', self.report('daily', '--since', '2026-10-20'))

    def test_ac6_wrong_typed_message_or_model_is_not_a_first_response(self):
        """AC-6: default-model passes over these records and takes the next valid response."""
        for name, record in WRONG_TYPED.items():
            if name.startswith(('message', 'model', 'timestamp')):
                with self.subTest(name):
                    self.write_with_good_record([record])
                    days = claude_usage.aggregate_default_model(self.root, SINCE, TZ)
                    self.assertEqual(dict(days['2026-10-22 Thu']), {'model-good': 1})

    def test_ac6_wrong_typed_ids_count_as_missing(self):
        """AC-6: an id that is not a string is treated as absent instead of breaking the deduplication."""
        for value in (['x'], {'a': 1}, 3):
            with self.subTest(value=value):
                record = assistant(msg=value, req=value)
                self.assertEqual(claude_usage.response_of(record, set()), ('model-alpha', USAGE))
                self.assertIsNone(claude_usage.response_of(record, {(None, None)}))

    def test_ac6_session_id_of_wrong_type_falls_back_to_the_path(self):
        """AC-6: a session id that is not a string groups by transcript."""
        path = self.write('-demo/s.jsonl', [assistant(session=['x'])])
        self.assertEqual(list(claude_usage.aggregate_sessions(self.root, SINCE, TZ)), [path])

    def test_ac6_wrong_typed_token_counts_add_nothing(self):
        """AC-6: a token count that is not a non-negative integer adds zero, the rest still counts."""
        for value in ('10', None, 1.5, True, [1], {'a': 1}, -5):
            with self.subTest(value=value):
                usage = {'input_tokens': value, 'output_tokens': 7}
                self.write('-demo/s.jsonl', [assistant(usage=usage)])
                totals = claude_usage.aggregate_daily(self.root, SINCE, TZ)[('2026-10-22 Thu', 'model-alpha')]
                self.assertEqual((totals['responses'], totals['input'], totals['output']), (1, 0, 7))

    def test_ac6_non_utf8_bytes_are_ignored(self):
        """AC-6: bytes that are not UTF-8 are dropped and the rest of the file is read."""
        path = self.write_with_good_record([b'\xff\xfe{broken \x80', b'{"type": "user", "note": "\xffok"}'])
        self.assert_good_record_survives()
        self.assertEqual(next(claude_usage.records(path)), {'type': 'user', 'note': 'ok'})

    def test_ac6_records_are_read_as_utf8(self):
        """AC-6: the encoding is explicit, not the machine's default."""
        path = self.write('-demo/s.jsonl', ['{"note": "ação"}'.encode()])
        self.assertEqual(list(claude_usage.records(path)), [{'note': 'ação'}])

    def test_ac6_transcript_listed_but_gone_is_skipped(self):
        """AC-6: a transcript that vanishes after the listing does not stop the run."""
        self.write_with_good_record([])
        real = claude_usage.glob.glob(os.path.join(self.root, '**', '*.jsonl'), recursive=True)
        gone = os.path.join(self.root, '-demo', 'gone.jsonl')
        with mock.patch.object(claude_usage.glob, 'glob', return_value=[gone, *real]):
            self.assert_good_record_survives()

    def test_ac6_transcript_gone_before_it_is_opened_is_skipped(self):
        """AC-6: a transcript that vanishes after its time check does not stop the run."""
        self.assertEqual(list(claude_usage.records(os.path.join(self.root, 'gone.jsonl'))), [])

    def test_ac6_dangling_link_and_folder_named_as_transcript_are_skipped(self):
        """AC-6: paths that cannot be read as files do not stop the run."""
        self.write_with_good_record([])
        os.symlink(os.path.join(self.root, 'nowhere'), os.path.join(self.root, '-demo', 'link.jsonl'))
        os.mkdir(os.path.join(self.root, '-demo', 'folder.jsonl'))
        self.assert_good_record_survives()

    def test_ac6_read_failure_midway_keeps_what_was_read(self):
        """AC-6: an error while reading ends that transcript only."""

        def lines():
            """Yield one line and then fail like a file that went away."""
            yield '{"type": "user"}\n'
            raise OSError('gone')

        opened = mock.mock_open()
        opened.return_value.__iter__.side_effect = lines
        with mock.patch('builtins.open', opened):
            self.assertEqual(list(claude_usage.records('any.jsonl')), [{'type': 'user'}])

    def test_ac6_text_stdout_cannot_encode_is_escaped(self):
        """AC-6: a lone surrogate in a transcript is escaped in the report instead of failing the print."""
        self.write('-demo/s.jsonl', [assistant(model='model-\ud800')])
        raw = io.BytesIO()
        stream = io.TextIOWrapper(raw, encoding='utf-8')
        with contextlib.redirect_stdout(stream):
            claude_usage.main(['daily', '--since', '2026-10-20', '--projects-dir', self.root], now=NOW)
        stream.flush()
        self.assertIn(b'model-\\ud800', raw.getvalue())


class ProjectsDirTests(TranscriptCase):
    """AC-7: the --projects-dir option."""

    def test_ac7_every_command_reads_the_given_folder(self):
        """AC-7: all commands accept the option and read only that folder."""
        self.write('-demo/s.jsonl', [assistant()])
        for command in ('daily', 'sessions', 'default-model'):
            with self.subTest(command):
                self.assertIn('model-alpha', self.report(command, '--since', '2026-10-20'))

    def test_ac7_default_is_the_folder_under_home(self):
        """AC-7: with no option the folder is .claude/projects under the home folder."""
        self.write('.claude/projects/-demo/s.jsonl', [assistant()])
        out = io.StringIO()
        with mock.patch.dict(os.environ, {'HOME': self.root}), contextlib.redirect_stdout(out):
            claude_usage.main(['daily', '--since', '2026-10-20'], now=NOW)
        self.assertIn('model-alpha', out.getvalue())

    def test_ac7_home_shortcut_in_the_option_is_expanded(self):
        """AC-7: a quoted ~ in the option resolves to the home folder."""
        self.write('other/-demo/s.jsonl', [assistant()])
        with mock.patch.dict(os.environ, {'HOME': self.root}):
            code, out, _ = self.run_main('daily', '--since', '2026-10-20', projects_dir='~/other')
        self.assertEqual(code, 0)
        self.assertIn('model-alpha', out)

    def test_ac7_missing_folder_exits_2_with_a_clear_message(self):
        """AC-7: a folder that does not exist, on any command, exits 2 and names the folder."""
        missing = os.path.join(self.root, 'missing')
        for command in ('daily', 'sessions', 'default-model'):
            with self.subTest(command):
                code, out, err = self.run_main(command, projects_dir=missing)
                self.assertEqual(code, 2)
                self.assertEqual(out, '')
                self.assertIn(f'projects folder not found: {missing}', err)
                self.assertNotIn('Traceback', err)

    def test_ac7_missing_default_folder_exits_2(self):
        """AC-7: the default folder missing is the same clear failure."""
        err = io.StringIO()
        with mock.patch.dict(os.environ, {'HOME': self.root}), contextlib.redirect_stderr(err):
            with self.assertRaises(SystemExit) as stop:
                claude_usage.main(['daily'], now=NOW)
        self.assertEqual(stop.exception.code, 2)
        self.assertIn('projects folder not found', err.getvalue())

    def test_ac7_file_in_place_of_the_folder_exits_2(self):
        """AC-7: a path that is not a folder is rejected."""
        path = self.write('plain-file', [])
        self.assertEqual(self.run_main('daily', projects_dir=path)[0], 2)

    def test_ac7_folder_name_with_glob_characters_is_literal(self):
        """AC-7: glob characters in the folder name match only themselves."""
        self.write('with[1]/-demo/s.jsonl', [assistant()])
        out = self.run_main('daily', '--since', '2026-10-20', projects_dir=os.path.join(self.root, 'with[1]'))[1]
        self.assertIn('model-alpha', out)

    def test_ac7_folder_below_one_named_subagents_is_still_main(self):
        """AC-7: only the path below the projects folder tells a subagent transcript."""
        root = os.path.join(self.root, 'subagents', 'projects')
        self.write('subagents/projects/-demo/s.jsonl', [assistant()])
        session = claude_usage.aggregate_sessions(root, SINCE, TZ)['sess-0001']
        self.assertEqual(session['main'], {'model-alpha': 1})
        self.assertEqual(session['subagents'], {})
        self.assertEqual(session['project'], '-demo')


class OutputFormatTests(TranscriptCase):
    """AC-8: the output format; the expected texts are the golden reports of this same tree."""

    def setUp(self):
        """Write the fictitious reference tree."""
        super().setUp()
        for relative, lines in GOLDEN_TREE.items():
            self.write(relative, [*lines, b'{corrupt'])

    def test_ac8_daily_format(self):
        """AC-8: the daily report matches the golden text."""
        self.assertEqual(self.report('daily', '--since', '2026-10-20'), GOLDEN_DAILY)

    def test_ac8_sessions_format(self):
        """AC-8: the sessions report matches the golden text for both orders."""
        self.assertEqual(self.report('sessions', '--since', '2026-10-20', '--sort', 'start'), GOLDEN_SESSIONS)
        self.assertEqual(self.report('sessions', '--since', '2026-10-20', '--sort', 'tokens'), GOLDEN_SESSIONS)

    def test_ac8_default_model_format(self):
        """AC-8: the default-model report matches the golden text."""
        self.assertEqual(self.report('default-model', '--since', '2026-10-20'), GOLDEN_DEFAULT_MODEL)

    def test_ac8_empty_reports_format(self):
        """AC-8: with nothing in the period the reports keep their headers."""
        self.assertEqual(
            self.report('daily', '--since', '2030-01-01'),
            GOLDEN_DAILY.split('\n', 1)[0] + '\n\nOutput tokens by model:\n',
        )
        self.assertEqual(self.report('sessions', '--since', '2030-01-01'), '')
        self.assertEqual(
            self.report('default-model', '--since', '2030-01-01'),
            'Model of the first response of each new session, per day:\n',
        )


class EntryPointTests(TranscriptCase):
    """The script entry point, with the real clock and machine zone."""

    def test_ac7_script_entry_point_uses_the_real_clock_and_validates_options(self):
        """AC-7: running the file as a script reaches the same checks, with no zone or clock passed in."""
        argv = ['claude_usage.py', 'daily', '--projects-dir', os.path.join(self.root, 'missing')]
        err = io.StringIO()
        with mock.patch.object(sys, 'argv', argv), contextlib.redirect_stderr(err):
            with self.assertRaises(SystemExit) as stop:
                runpy.run_path(SCRIPT, run_name='__main__')
        self.assertEqual(stop.exception.code, 2)
        self.assertIn('projects folder not found', err.getvalue())

    def test_ac8_no_command_exits_2(self):
        """AC-8: a command is mandatory."""
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as stop:
            claude_usage.main([], now=NOW)
        self.assertEqual(stop.exception.code, 2)


if __name__ == '__main__':
    unittest.main()
