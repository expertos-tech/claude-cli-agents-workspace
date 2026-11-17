"""Tests of the WRITE_TO_SESSION_TTY script of plugin/hooks/register.tsx: AC-10.

The script is taken from the mod's source, so these tests run exactly what the mod runs. `ps` is a fake
that answers from a table of fictitious processes; the walk starts at this test process, the script's parent.
"""

import os
import re
import shlex
import subprocess
import tempfile
import unittest
from pathlib import Path

REGISTER = Path(__file__).resolve().parent.parent / 'plugin' / 'hooks' / 'register.tsx'
CONSTANT = re.compile(r'const WRITE_TO_SESSION_TTY = `(?P<script>[^`]*)`')
SYSTEM_PATH = '/usr/bin:/bin'
FIRST_FICTITIOUS_PID = 40001
WALK_LIMIT = 8
WATCHDOG_SECONDS = 10
SEQUENCE = '\\033]11;#420c0c\\007'
NO_TTY = '??'


def read_script(source=REGISTER):
    """Returns the script text, raising when the constant is gone or holds what only JavaScript would expand."""
    found = CONSTANT.search(source.read_text(encoding='utf-8'))
    if found is None:
        raise AssertionError(f'WRITE_TO_SESSION_TTY not found in {source}')
    script = found.group('script')
    if '${' in script or '\\' in script:
        raise AssertionError('WRITE_TO_SESSION_TTY needs JavaScript evaluation; this test can no longer run it as is')
    return script


def fake_ps_script(processes, log):
    """Builds a fake `ps` answering `-o tty=` and `-o ppid=` from {pid: (tty, ppid)}, padded as the real one pads."""
    cases = []
    for pid, (tty, ppid) in processes.items():
        cases.append(f"  'tty=:{pid}') printf '%s\\n' {shlex.quote(f'  {tty}')} ;;")
        cases.append(f"  'ppid=:{pid}') printf '%s\\n' {shlex.quote(f' {ppid}')} ;;")
    body = '\n'.join(cases)
    return f'#!/bin/sh\nprintf \'%s\\n\' "$2:$4" >> {shlex.quote(str(log))}\ncase "$2:$4" in\n{body}\nesac\n'


def ancestor_chain(ttys):
    """Builds {pid: (tty, ppid)} from the test process upwards, one ancestor per given tty."""
    pids = [os.getpid(), *range(FIRST_FICTITIOUS_PID, FIRST_FICTITIOUS_PID + len(ttys))]
    return {pid: (tty, parent) for pid, parent, tty in zip(pids, pids[1:], ttys)}


class SessionTtyScriptTest(unittest.TestCase):
    """AC-10: the walk up the process tree, under a fake `ps` first on PATH."""

    def setUp(self):
        """Creates the temp dir of the fake `ps` and of its call log."""
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.folder = Path(folder.name)
        self.log = self.folder / 'ps-calls.log'

    def run_script(self, processes):
        """Runs the script under sh as the mod runs it, with the fake `ps` first on PATH."""
        fake_ps = self.folder / 'ps'
        fake_ps.write_text(fake_ps_script(processes, self.log), encoding='utf-8')
        fake_ps.chmod(0o755)
        return subprocess.run(
            ['sh', '-c', read_script(), 'fable-alert', SEQUENCE],
            capture_output=True,
            check=False,
            env={'PATH': f'{self.folder}{os.pathsep}{SYSTEM_PATH}'},
            text=True,
            timeout=WATCHDOG_SECONDS,
        )

    def visited(self):
        """Returns the pids the fake `ps` was asked the tty of, in order."""
        if not self.log.exists():
            return []
        calls = self.log.read_text(encoding='utf-8').splitlines()
        return [int(call.split(':')[1]) for call in calls if call.startswith('tty=')]

    def test_ac10_renamed_constant_fails_loudly(self):
        """AC-10: a renamed constant is an assertion failure, which every test here goes through; no skip."""
        renamed = self.folder / 'register.tsx'
        renamed.write_text('const OTHER_NAME = `exit 0`\n', encoding='utf-8')

        with self.assertRaisesRegex(AssertionError, 'WRITE_TO_SESSION_TTY not found'):
            read_script(renamed)

    def test_ac10_script_expanded_by_javascript_fails_loudly(self):
        """AC-10: a script holding a template expansion or an escape cannot be run as written; no skip."""
        for text in ('exit ${code}', 'printf "\\\\033"'):
            with self.subTest(text=text):
                changed = self.folder / 'register.tsx'
                changed.write_text(f'const WRITE_TO_SESSION_TTY = `{text}`\n', encoding='utf-8')

                with self.assertRaisesRegex(AssertionError, 'JavaScript'):
                    read_script(changed)

    def test_ac10_script_is_read_from_the_mod(self):
        """AC-10: the real source holds the constant with the walk in it."""
        self.assertIn('ps -o tty=', read_script())

    def test_ac10_first_ancestor_with_a_tty_writes_and_exits_0(self):
        """AC-10: `null` makes the script write to /dev/null; nothing above that ancestor is asked."""
        result = self.run_script(ancestor_chain(['null', NO_TTY]))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.visited(), [os.getpid()])

    def test_ac10_writes_the_sequence_to_the_device_of_the_ancestor(self):
        """AC-10: the bytes that arrive are the escape sequence, with printf having expanded it."""
        target = self.folder / 'fake-tty'
        tty = os.path.relpath(target, '/dev')

        result = self.run_script(ancestor_chain([tty]))

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(target.read_bytes(), b'\x1b]11;#420c0c\x07')

    def test_ac10_unknown_and_empty_ttys_keep_walking(self):
        """AC-10: `??` and an empty tty are skipped until an ancestor with a tty."""
        processes = ancestor_chain([NO_TTY, '', 'null'])

        result = self.run_script(processes)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.visited(), list(processes))

    def test_ac10_no_tty_within_the_limit_exits_1(self):
        """AC-10: the walk gives up after eight ancestors, even with a tty right above them."""
        processes = ancestor_chain([NO_TTY] * WALK_LIMIT + ['null'])

        result = self.run_script(processes)

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.visited(), list(processes)[:WALK_LIMIT])

    def test_ac10_tty_on_the_last_ancestor_within_the_limit_writes(self):
        """AC-10: the eighth ancestor still counts."""
        result = self.run_script(ancestor_chain([NO_TTY] * (WALK_LIMIT - 1) + ['null']))

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_ac10_process_with_no_parent_exits_1(self):
        """AC-10: an empty ppid ends the walk."""
        result = self.run_script({os.getpid(): (NO_TTY, '')})

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.visited(), [os.getpid()])

    def test_ac10_init_is_never_asked(self):
        """AC-10: reaching pid 1 ends the walk."""
        result = self.run_script({os.getpid(): (NO_TTY, 1), 1: ('null', 0)})

        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.visited(), [os.getpid()])

    def test_ac10_a_device_that_cannot_be_written_keeps_walking(self):
        """AC-10: a failed write does not count as written; the next ancestor is tried."""
        processes = ancestor_chain(['missing-folder-of-the-test/tty', 'null'])

        result = self.run_script(processes)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.visited(), list(processes))


if __name__ == '__main__':
    unittest.main()
