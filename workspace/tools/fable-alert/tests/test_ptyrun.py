"""Tests of tools/ptyrun.py: AC-12, AC-13 and AC-14. Every `claude` here is a fake in a temp dir."""

import contextlib
import io
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'tools'))

import ptyrun

SCRIPT = Path(__file__).resolve().parent.parent / 'tools' / 'ptyrun.py'
SYSTEM_PATH = '/usr/bin:/bin'
LONG_RECORDING_SECONDS = 30
WATCHDOG_SECONDS = 20
SET_TINT = b'\x1b]11;#420c0c\x07'
RESET_TINT = b'\x1b]111\x07'
LINE_CHARACTER = '\u2500'.encode()


class FakeClaudeCase(unittest.TestCase):
    """Gives each test a temp dir and a PATH that holds only the system tools and, once installed, a fake claude."""

    def setUp(self):
        """Creates the temp dir and points PATH at it, so the real claude can never run."""
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.folder = Path(folder.name)
        patcher = mock.patch.dict(os.environ, {'PATH': f'{self.folder}{os.pathsep}{SYSTEM_PATH}'})
        patcher.start()
        self.addCleanup(patcher.stop)

    def install_fake_claude(self, body):
        """Writes a POSIX shell script named claude, the one shell every test environment has."""
        path = self.folder / 'claude'
        path.write_text(f'#!/bin/sh\n{body}\n', encoding='utf-8')
        path.chmod(0o755)

    def run_main(self, *arguments):
        """Runs main in process and returns what it printed."""
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed):
            ptyrun.main([str(argument) for argument in arguments])
        return printed.getvalue()


class RecordTest(FakeClaudeCase):
    """AC-12: records what the fake claude draws."""

    def test_ac12_records_what_claude_draws(self):
        """AC-12: every byte comes back and the fake ending by itself ends the recording early."""
        self.install_fake_claude("printf 'hello'; sleep 0.2")

        self.assertEqual(ptyrun.record(LONG_RECORDING_SECONDS, []), b'hello')

    def test_ac12_passes_the_arguments_to_claude(self):
        """AC-12: the arguments after SECONDS reach claude untouched."""
        self.install_fake_claude('printf \'%s|\' "$@"; sleep 0.2')

        self.assertEqual(ptyrun.record(LONG_RECORDING_SECONDS, ['--model', 'fa ble']), b'--model|fa ble|')

    def test_ac12_ends_a_claude_still_running_after_the_seconds(self):
        """AC-12: a claude that never ends gets SIGTERM once the time is over."""
        self.install_fake_claude("printf 'drawn'; exec sleep 300")

        self.assertEqual(ptyrun.record(1, []), b'drawn')

    def test_ac12_keeps_what_claude_draws_while_ending(self):
        """AC-12: what comes after SIGTERM is recorded and gets no answer to its queries."""
        self.install_fake_claude(
            "trap 'printf \"\\033[cbye\"; sleep 0.2; exit 0' TERM\nprintf 'up'\nwhile :; do sleep 0.1; done"
        )

        recorded = ptyrun.record(1, [])

        self.assertEqual(recorded, b'up\x1b[cbye')

    def test_ac12_answers_the_device_attributes_query(self):
        """AC-12: the answer is what the query asks for; the terminal echoes it, which shows it was sent."""
        self.install_fake_claude("printf '\\033[c'; sleep 0.5")

        recorded = ptyrun.record(LONG_RECORDING_SECONDS, [])

        self.assertIn(b'[?62;22c', recorded)

    def test_ac12_answers_the_background_color_query(self):
        """AC-12: same for the query of the background color."""
        self.install_fake_claude("printf '\\033]11;?\\007'; sleep 0.5")

        recorded = ptyrun.record(LONG_RECORDING_SECONDS, [])

        self.assertIn(b']11;rgb:1e1e/1e1e/1e1e', recorded)

    def test_ac12_leaves_other_output_unanswered(self):
        """AC-12: output with no query gets nothing back."""
        self.install_fake_claude("printf 'plain'; sleep 0.3")

        self.assertEqual(ptyrun.record(LONG_RECORDING_SECONDS, []), b'plain')


class MainTest(FakeClaudeCase):
    """AC-12: writes OUTPUT and reports each background color write."""

    def test_ac12_writes_output_and_reports_each_write(self):
        """AC-12: OUTPUT holds the bytes; each write is reported, with the one that splits a character flagged."""
        self.install_fake_claude(
            "printf 'ab\\033]11;#420c0c\\007cd\\342\\224\\033]111\\007\\200ef'; sleep 0.2",
        )
        output = self.folder / 'opening.bin'

        printed = self.run_main(output, LONG_RECORDING_SECONDS)

        expected = b'ab' + SET_TINT + b'cd\xe2\x94' + RESET_TINT + b'\x80ef'
        self.assertEqual(output.read_bytes(), expected)
        self.assertEqual(
            printed.splitlines(),
            [
                f'{len(expected)} bytes written to {output}',
                'background color writes: 2',
                '  set (OSC 11) at byte 2: clean',
                "    before: b'ab'",
                "    after:  b'cd\\xe2\\x94\\x1b]111\\x07\\x80ef'",
                '  reset (OSC 111) at byte 19: SPLITS A CHARACTER',
                "    before: b']11;#420c0c\\x07cd\\xe2\\x94'",
                "    after:  b'\\x80ef'",
            ],
        )

    def test_ac12_reports_no_write_when_there_is_none(self):
        """AC-12: a run with no background color write says so."""
        self.install_fake_claude("printf 'plain'; sleep 0.2")
        output = self.folder / 'opening.bin'

        printed = self.run_main(output, LONG_RECORDING_SECONDS)

        self.assertEqual(printed.splitlines()[1:], ['background color writes: 0'])

    def test_ac14_unwritable_output_exits_with_a_message(self):
        """AC-14: OUTPUT being a folder is reported after the run, with no traceback."""
        self.install_fake_claude("printf 'plain'; sleep 0.2")

        with self.assertRaises(SystemExit) as caught:
            self.run_main(self.folder, LONG_RECORDING_SECONDS)

        self.assertIn('cannot write', caught.exception.code)

    def test_ac14_output_in_a_missing_folder_exits_before_recording(self):
        """AC-14: a folder that does not exist is refused before Claude Code opens."""
        self.install_fake_claude('exit 0')

        with mock.patch.object(ptyrun, 'record') as record, self.assertRaises(SystemExit) as caught:
            self.run_main(self.folder / 'missing' / 'opening.bin', 1)

        record.assert_not_called()
        self.assertIn('folder not found', caught.exception.code)

    def test_ac14_no_claude_on_path_exits_before_recording(self):
        """AC-14: no claude on PATH ends right away, with a message."""
        with mock.patch.object(ptyrun, 'record') as record, self.assertRaises(SystemExit) as caught:
            self.run_main(self.folder / 'opening.bin', LONG_RECORDING_SECONDS)

        record.assert_not_called()
        self.assertIn('claude not found', caught.exception.code)
        self.assertFalse((self.folder / 'opening.bin').exists())

    def test_ac14_a_claude_that_cannot_exec_does_not_hang(self):
        """AC-14: a claude the system refuses to run ends the child, and the recording with it."""
        self.install_fake_claude('exit 0')
        (self.folder / 'claude').write_bytes(b'\x00\x01 not a program')

        self.assertEqual(ptyrun.record(LONG_RECORDING_SECONDS, []), b'')


class ArgumentsTest(FakeClaudeCase):
    """AC-14: wrong arguments exit non-zero with the usage text."""

    def test_ac14_invalid_arguments_exit_with_the_usage_text(self):
        """AC-14: missing arguments, seconds that are no number, not positive or not finite."""
        self.install_fake_claude('exit 0')
        output = str(self.folder / 'opening.bin')
        cases = (
            [],
            [output],
            ['', '1'],
            [output, 'soon'],
            [output, '0'],
            [output, '-3'],
            [output, 'nan'],
            [output, 'inf'],
        )
        for arguments in cases:
            with self.subTest(arguments=arguments):
                with mock.patch.object(ptyrun, 'record') as record, self.assertRaises(SystemExit) as caught:
                    ptyrun.main(arguments)
                record.assert_not_called()
                self.assertEqual(caught.exception.code, ptyrun.__doc__)

    def test_ac14_valid_arguments_are_returned(self):
        """AC-14: a fractional time and the arguments for claude go through."""
        self.assertEqual(
            ptyrun.parse_args(['out.bin', '0.5', '--model', 'fable']),
            ('out.bin', 0.5, ['--model', 'fable']),
        )

    def run_script(self, *arguments):
        """Runs the script as the user does, under a watchdog so a hang fails the test."""
        return subprocess.run(
            [sys.executable, '-I', str(SCRIPT), *arguments],
            capture_output=True,
            check=False,
            cwd=self.folder,
            env=dict(os.environ),
            text=True,
            timeout=WATCHDOG_SECONDS,
        )

    def test_ac14_the_script_shows_usage_and_no_traceback(self):
        """AC-14: wrong arguments in a real process: non-zero, the usage text, no traceback."""
        for arguments in ([], ['opening.bin', 'soon'], ['opening.bin', '0']):
            with self.subTest(arguments=arguments):
                result = self.run_script(*arguments)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Usage:', result.stderr)
                self.assertNotIn('Traceback', result.stderr)
                self.assertEqual(result.stdout, '')

    def test_ac14_the_script_with_no_claude_does_not_hang(self):
        """AC-14: no claude on PATH in a real process: non-zero, a message, no traceback, no OUTPUT."""
        result = self.run_script('opening.bin', str(LONG_RECORDING_SECONDS))

        self.assertNotEqual(result.returncode, 0)
        self.assertIn('claude not found', result.stderr)
        self.assertNotIn('Traceback', result.stderr)
        self.assertFalse((self.folder / 'opening.bin').exists())


class SplitsUtf8Test(unittest.TestCase):
    """AC-13: what counts as a write landing inside one UTF-8 character."""

    def test_ac13_splits_after_the_lead_byte(self):
        """AC-13: lead byte, write, then the rest of the character."""
        data = LINE_CHARACTER[:1] + RESET_TINT + LINE_CHARACTER[1:]
        self.assertTrue(ptyrun.splits_utf8(data, 1, 1 + len(RESET_TINT)))

    def test_ac13_splits_between_continuation_bytes(self):
        """AC-13: lead and continuation byte, write, then the last continuation byte."""
        data = LINE_CHARACTER[:2] + RESET_TINT + LINE_CHARACTER[2:]
        self.assertTrue(ptyrun.splits_utf8(data, 2, 2 + len(RESET_TINT)))

    def test_ac13_a_write_at_the_end_after_a_lead_byte_splits(self):
        """AC-13: a lead byte right before the write is a split, even with nothing recorded after."""
        data = LINE_CHARACTER[:1] + RESET_TINT
        self.assertTrue(ptyrun.splits_utf8(data, 1, len(data)))

    def test_ac13_clean_writes(self):
        """AC-13: writes that fall between characters, at either end of the data, or with ASCII around them."""
        cases = {
            'between ASCII': (b'ab' + RESET_TINT + b'cd', 2),
            'at the start': (RESET_TINT + b'cd', 0),
            'at the end': (b'ab' + RESET_TINT, 2),
            'alone': (RESET_TINT, 0),
            'after a whole character': (LINE_CHARACTER + RESET_TINT + b'cd', len(LINE_CHARACTER)),
            'between whole characters': (LINE_CHARACTER + RESET_TINT + LINE_CHARACTER, len(LINE_CHARACTER)),
            'before a whole character': (b'ab' + RESET_TINT + LINE_CHARACTER, 2),
        }
        for name, (data, start) in cases.items():
            with self.subTest(name):
                self.assertFalse(ptyrun.splits_utf8(data, start, start + len(RESET_TINT)))


class ReportTest(unittest.TestCase):
    """AC-12: the report text of the background color writes."""

    def test_ac12_recognizes_both_terminators(self):
        """AC-12: BEL and ST end an OSC 11 or OSC 111 write alike."""
        data = b'\x1b]11;#420c0c\x1b\\' + b'\x1b]111\x1b\\'

        lines = ptyrun.background_write_report(data)

        self.assertEqual(lines[0], 'background color writes: 2')
        self.assertTrue(lines[1].startswith('  set (OSC 11) at byte 0: clean'))
        self.assertTrue(lines[4].startswith('  reset (OSC 111) at byte 14: clean'))

    def test_ac12_ignores_other_sequences(self):
        """AC-12: a query of the background color and other OSC numbers are not writes."""
        self.assertEqual(
            ptyrun.background_write_report(b'\x1b]11;?\x1b]10;#000000\x07\x1b]1110\x07'),
            ['background color writes: 0'],
        )

    def test_ac12_context_is_limited_to_16_bytes(self):
        """AC-12: the bytes shown around a write stop at 16 on each side."""
        data = b'x' * 20 + RESET_TINT + b'y' * 20

        lines = ptyrun.background_write_report(data)

        self.assertEqual(lines[2], f'    before: {b"x" * 16!r}')
        self.assertEqual(lines[3], f'    after:  {b"y" * 16!r}')


if __name__ == '__main__':
    unittest.main()
