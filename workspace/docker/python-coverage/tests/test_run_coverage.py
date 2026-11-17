"""Unit tests of the coverage check entry point. Coverage itself is doubled: the host Python does not have it."""

import contextlib
import io
import os
import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import run_coverage


def completed(code):
    """Returns a stand-in for a finished process with the given exit code."""
    return mock.Mock(returncode=code)


def run_main(arguments, folder=run_coverage.TARGET, environ=None):
    """Runs main with an empty environment unless given one and returns (exit code, stdout, stderr)."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = run_coverage.main(arguments, folder, {} if environ is None else environ)
    return code, out.getvalue(), err.getvalue()


class TargetTestCase(unittest.TestCase):
    """Gives each test a temporary coverage target."""

    def setUp(self):
        """Creates a folder with the layout of a valid target."""
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.target = Path(folder.name)
        (self.target / '.coveragerc').write_text('[run]\nbranch = True\n', encoding='utf-8')
        (self.target / 'tests').mkdir()


class StepsTest(TargetTestCase):
    """The steps run in order and the first failure decides the exit code."""

    @mock.patch.object(run_coverage.check_coverage, 'main', return_value=0)
    @mock.patch.object(run_coverage.subprocess, 'run', return_value=completed(0))
    def test_passes_when_tests_and_gate_pass(self, run, gate):
        """Passing tests and gate exit 0, running the tests, then the report, then the gate on that report."""
        code, _, _ = run_main([], self.target)
        self.assertEqual(code, 0)
        self.assertEqual(
            [call.args[0] for call in run.call_args_list],
            [
                ('coverage', 'run', '-m', 'unittest', 'discover', '-s', 'tests'),
                ('coverage', 'json', '-q', '-o', run_coverage.REPORT),
            ],
        )
        gate.assert_called_once_with([run_coverage.REPORT])

    @mock.patch.object(run_coverage.check_coverage, 'main')
    @mock.patch.object(run_coverage.subprocess, 'run', return_value=completed(1))
    def test_failing_tests_fail_and_skip_the_rest(self, run, gate):
        """A failing test fails the check, with no report and no gate."""
        code, _, _ = run_main([], self.target)
        self.assertEqual(code, 1)
        self.assertEqual(run.call_count, 1)
        gate.assert_not_called()

    @mock.patch.object(run_coverage.check_coverage, 'main')
    @mock.patch.object(run_coverage.subprocess, 'run', side_effect=[completed(0), completed(3)])
    def test_failing_report_fails_and_skips_the_gate(self, _, gate):
        """A report that cannot be written fails the check, with no gate."""
        code, _, _ = run_main([], self.target)
        self.assertEqual(code, 3)
        gate.assert_not_called()

    @mock.patch.object(run_coverage.check_coverage, 'main', return_value=1)
    @mock.patch.object(run_coverage.subprocess, 'run', return_value=completed(0))
    def test_gate_failure_fails(self, _, __):
        """Passing tests with a module below the gate fail the check."""
        code, _, _ = run_main([], self.target)
        self.assertEqual(code, 1)


class ValidationTest(TargetTestCase):
    """Arguments and the target layout are validated before anything runs."""

    def assert_rejected(self, arguments, message):
        """Asserts a usage error with the message on stderr and no step run."""
        with mock.patch.object(run_coverage.subprocess, 'run') as run:
            code, _, err = run_main(arguments, self.target)
        self.assertEqual(code, run_coverage.EXIT_USAGE)
        self.assertIn(message, err)
        run.assert_not_called()

    def test_unknown_option(self):
        """An unknown argument is rejected."""
        self.assert_rejected(['--nope'], 'unknown option: --nope')

    def test_missing_coveragerc(self):
        """A folder without .coveragerc is rejected."""
        (self.target / '.coveragerc').unlink()
        self.assert_rejected([], 'no .coveragerc')

    def test_missing_tests_folder(self):
        """A folder without tests/ is rejected."""
        (self.target / 'tests').rmdir()
        self.assert_rejected([], 'no tests folder')

    def test_default_target_is_the_current_folder(self):
        """Without a folder, main checks the current one."""
        self.assertEqual(run_coverage.TARGET, Path('.'))
        with mock.patch.object(run_coverage, 'layout_error', return_value='stop') as layout:
            with mock.patch.dict(os.environ), contextlib.redirect_stderr(io.StringIO()):
                os.environ.pop(run_coverage.TIMEOUT_VARIABLE, None)
                code = run_coverage.main([])
        self.assertEqual(code, run_coverage.EXIT_USAGE)
        self.assertEqual(layout.call_args.args, (run_coverage.TARGET,))


class DeadlineTest(TargetTestCase):
    """Each step has a deadline from COVERAGE_TIMEOUT_SECONDS, and a hung step fails the check."""

    @mock.patch.object(run_coverage.check_coverage, 'main', return_value=0)
    @mock.patch.object(run_coverage.subprocess, 'run', return_value=completed(0))
    def assert_deadline(self, environ, expected, run, _):
        """Asserts the check passes with the expected deadline on every step."""
        code, _, _ = run_main([], self.target, environ)
        self.assertEqual(code, run_coverage.EXIT_PASSED)
        self.assertEqual([call.kwargs['timeout'] for call in run.call_args_list], [expected, expected])

    def test_default_deadline(self):
        """Without the variable the deadline is 600 seconds."""
        self.assert_deadline({}, 600)

    def test_deadline_from_the_environment(self):
        """The variable sets the deadline."""
        self.assert_deadline({run_coverage.TIMEOUT_VARIABLE: '5'}, 5)

    def test_largest_deadline(self):
        """The largest accepted value is 999999999."""
        self.assert_deadline({run_coverage.TIMEOUT_VARIABLE: '999999999'}, 999999999)

    @mock.patch.object(run_coverage.check_coverage, 'main', return_value=0)
    @mock.patch.object(run_coverage.subprocess, 'run', return_value=completed(0))
    def test_process_environment_is_the_default(self, run, _):
        """Without an explicit environment, main reads the one of the process."""
        with mock.patch.dict(os.environ, {run_coverage.TIMEOUT_VARIABLE: '7'}):
            code = run_coverage.main([], self.target)
        self.assertEqual(code, run_coverage.EXIT_PASSED)
        self.assertEqual(run.call_args.kwargs['timeout'], 7)

    def test_invalid_deadline_fails_fast(self):
        """An empty, non-numeric, non-positive, fractional or oversized value is rejected and nothing runs."""
        for value in ('', 'abc', '0', '-5', '1.5', ' 5', '5\n', '05', '٣', '1000000000'):
            with self.subTest(value=value), mock.patch.object(run_coverage.subprocess, 'run') as run:
                code, _, err = run_main([], self.target, {run_coverage.TIMEOUT_VARIABLE: value})
                self.assertEqual(code, run_coverage.EXIT_USAGE)
                self.assertIn('COVERAGE_TIMEOUT_SECONDS must be a whole number of seconds', err)
                self.assertIn(repr(value), err)
                run.assert_not_called()

    @mock.patch.object(run_coverage.check_coverage, 'main')
    @mock.patch.object(run_coverage.subprocess, 'run')
    def test_timeout_fails_naming_the_deadline(self, run, gate):
        """A hung step fails the check, names the command and the deadline, and skips the rest."""
        step = run_coverage.STEPS[0]
        run.side_effect = subprocess.TimeoutExpired(step, 5)
        code, _, err = run_main([], self.target, {run_coverage.TIMEOUT_VARIABLE: '5'})
        self.assertEqual(code, run_coverage.EXIT_TIMEOUT)
        self.assertIn('coverage run -m unittest discover -s tests exceeded the deadline of 5s', err)
        self.assertIn('COVERAGE_TIMEOUT_SECONDS', err)
        self.assertEqual(run.call_count, 1)
        gate.assert_not_called()

    def test_real_hung_process_is_killed_at_the_deadline(self):
        """A real process that outlives the deadline is stopped and fails the check."""
        hung = (sys.executable, '-c', 'import time; time.sleep(60)')
        with mock.patch.object(run_coverage, 'STEPS', (hung,)), contextlib.redirect_stderr(io.StringIO()) as err:
            code = run_coverage.run_steps(1)
        self.assertEqual(code, run_coverage.EXIT_TIMEOUT)
        self.assertIn('exceeded the deadline of 1s', err.getvalue())


class CommandLineTest(unittest.TestCase):
    """The script prints its help and exits with the code of main."""

    def test_help(self):
        """--help and -h print the docstring and exit 0, running nothing."""
        for option in ('--help', '-h'):
            with self.subTest(option=option), mock.patch.object(run_coverage.subprocess, 'run') as run:
                code, out, _ = run_main([option])
                self.assertEqual(code, run_coverage.EXIT_PASSED)
                self.assertIn('Container entry point', out)
                run.assert_not_called()

    def test_script_exits_with_the_code_of_main(self):
        """Run as a script, a usage error becomes a non-zero process exit."""
        argv = ['run_coverage.py', '--nope']
        with mock.patch.object(sys, 'argv', argv), contextlib.redirect_stderr(io.StringIO()):
            with self.assertRaises(SystemExit) as raised:
                runpy.run_path(run_coverage.__file__, run_name='__main__')
        self.assertEqual(raised.exception.code, run_coverage.EXIT_USAGE)


if __name__ == '__main__':
    unittest.main()
