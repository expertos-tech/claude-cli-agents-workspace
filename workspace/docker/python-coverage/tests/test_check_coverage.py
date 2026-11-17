"""Unit tests of the per-module coverage gate."""

import contextlib
import io
import json
import runpy
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import check_coverage


def module(lines=(100, 100), branches=(10, 10)):
    """Returns a report entry from (covered, total) pairs of lines and branches."""
    return {
        'summary': {
            'covered_lines': lines[0],
            'num_statements': lines[1],
            'covered_branches': branches[0],
            'num_branches': branches[1],
        }
    }


def report(**modules):
    """Returns a branch-measured report holding the given modules."""
    return {'meta': {'branch_coverage': True}, 'files': modules}


def run_gate(content):
    """Runs main on a report file holding content, a string written as is or a value dumped as JSON.

    Returns (exit code, stdout, stderr).
    """
    text = content if isinstance(content, str) else json.dumps(content)
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / 'coverage.json'
        path.write_text(text, encoding='utf-8')
        return run_main([str(path)])


def run_main(arguments):
    """Runs main with the arguments and returns (exit code, stdout, stderr)."""
    out, err = io.StringIO(), io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = check_coverage.main(arguments)
    return code, out.getvalue(), err.getvalue()


class GateTest(unittest.TestCase):
    """The gate passes or fails per module, on lines and on branches."""

    def test_passes_at_exactly_85_percent(self):
        """A module exactly at the gate passes and its line shows both numbers."""
        code, out, _ = run_gate(report(**{'a.py': module((85, 100), (17, 20))}))
        self.assertEqual(code, check_coverage.EXIT_PASSED)
        self.assertEqual(out, 'PASS a.py: lines 85.0% (85/100), branches 85.0% (17/20)\n')

    def test_fails_below_85_lines(self):
        """Lines below the gate fail even with full branches."""
        code, out, _ = run_gate(report(**{'a.py': module((84, 100), (10, 10))}))
        self.assertEqual(code, check_coverage.EXIT_BELOW_GATE)
        self.assertEqual(out, 'FAIL a.py: lines 84.0% (84/100), branches 100.0% (10/10)\n')

    def test_fails_below_85_branches(self):
        """Branches below the gate fail even with full lines."""
        code, out, _ = run_gate(report(**{'a.py': module((100, 100), (8, 10))}))
        self.assertEqual(code, check_coverage.EXIT_BELOW_GATE)
        self.assertEqual(out, 'FAIL a.py: lines 100.0% (100/100), branches 80.0% (8/10)\n')

    def test_fails_just_below_85_without_rounding_up(self):
        """84.96% fails and does not print as 85.0%."""
        code, out, _ = run_gate(report(**{'a.py': module((2124, 2500))}))
        self.assertEqual(code, check_coverage.EXIT_BELOW_GATE)
        self.assertIn('lines 84.9%', out)

    def test_module_without_branches_passes_the_branch_part(self):
        """Zero branches never fails the branch part."""
        code, out, _ = run_gate(report(**{'a.py': module((90, 100), (0, 0))}))
        self.assertEqual(code, check_coverage.EXIT_PASSED)
        self.assertIn('branches 100.0% (0/0)', out)

    def test_module_without_branches_still_fails_on_lines(self):
        """Zero branches does not excuse low lines."""
        code, _, _ = run_gate(report(**{'a.py': module((10, 100), (0, 0))}))
        self.assertEqual(code, check_coverage.EXIT_BELOW_GATE)

    def test_empty_module_passes(self):
        """A module with no statements, such as an empty __init__.py, passes."""
        code, _, _ = run_gate(report(**{'__init__.py': module((0, 0), (0, 0))}))
        self.assertEqual(code, check_coverage.EXIT_PASSED)

    def test_one_bad_module_among_good_ones_fails(self):
        """The gate is per module: a high total does not hide one low module."""
        code, out, _ = run_gate(
            report(**{'a.py': module((1000, 1000)), 'b.py': module((1, 10)), 'c.py': module((1000, 1000))})
        )
        self.assertEqual(code, check_coverage.EXIT_BELOW_GATE)
        self.assertEqual(
            [line.split()[:2] for line in out.splitlines()],
            [['PASS', 'a.py:'], ['FAIL', 'b.py:'], ['PASS', 'c.py:']],
        )


class InvalidReportTest(unittest.TestCase):
    """A report the gate cannot trust fails instead of passing silently."""

    def assert_invalid(self, content, message):
        """Asserts the content is rejected with the message on stderr and no module line on stdout."""
        code, out, err = run_gate(content)
        self.assertEqual(code, check_coverage.EXIT_INVALID_REPORT)
        self.assertEqual(out, '')
        self.assertIn(message, err)

    def test_not_json(self):
        """Text that is not JSON is rejected."""
        self.assert_invalid('not json', 'cannot read')

    def test_not_an_object(self):
        """A JSON value that is not an object is rejected."""
        self.assert_invalid([], 'no files object')

    def test_files_not_an_object(self):
        """A files value that is not an object is rejected."""
        self.assert_invalid({'files': []}, 'no files object')

    def test_no_measured_module(self):
        """A report with no module is rejected, so a wrong source setting cannot pass."""
        self.assert_invalid(report(), 'measured no module')

    def test_no_meta(self):
        """A report without meta is rejected."""
        self.assert_invalid({'files': {'a.py': module()}}, 'branch = True')

    def test_not_branch_measured(self):
        """A report measured without branch = True is rejected."""
        self.assert_invalid({'meta': {'branch_coverage': False}, 'files': {'a.py': module()}}, 'branch = True')

    def test_module_not_an_object(self):
        """A module entry that is not an object is rejected."""
        self.assert_invalid(report(**{'a.py': 'x'}), 'a.py: summary lacks')

    def test_summary_missing_count(self):
        """A summary without a count is rejected."""
        self.assert_invalid(report(**{'a.py': {'summary': {'covered_lines': 1}}}), 'a.py: summary lacks')

    def test_count_of_wrong_type(self):
        """A count that is not an integer is rejected."""
        self.assert_invalid(report(**{'a.py': module(('1', 1))}), 'a.py: summary lacks')

    def test_boolean_count(self):
        """A JSON boolean is not a count."""
        self.assert_invalid(report(**{'a.py': module((True, 1))}), 'a.py: summary lacks')

    def test_negative_count(self):
        """A negative count is rejected."""
        self.assert_invalid(report(**{'a.py': module((-1, 1))}), 'a.py: summary lacks')

    def test_covered_lines_above_total(self):
        """More covered lines than statements is rejected."""
        self.assert_invalid(report(**{'a.py': module((2, 1))}), 'a.py: covered count above')

    def test_covered_branches_above_total(self):
        """More covered branches than branches is rejected."""
        self.assert_invalid(report(**{'a.py': module((1, 1), (2, 1))}), 'a.py: covered count above')

    def test_later_invalid_module_prints_no_partial_result(self):
        """One invalid module rejects the whole report, with no module line printed."""
        self.assert_invalid(report(**{'a.py': module(), 'b.py': 'x'}), 'b.py: summary lacks')


class CommandLineTest(unittest.TestCase):
    """The script validates its arguments and exits with the code of main."""

    def test_missing_file(self):
        """A report path that does not exist is rejected."""
        code, _, err = run_main(['/nonexistent/coverage.json'])
        self.assertEqual(code, check_coverage.EXIT_INVALID_REPORT)
        self.assertIn('cannot read', err)

    def test_wrong_argument_count(self):
        """Anything but one argument prints the usage."""
        for arguments in ([], ['a', 'b']):
            with self.subTest(arguments=arguments):
                code, _, err = run_main(arguments)
                self.assertEqual(code, check_coverage.EXIT_INVALID_REPORT)
                self.assertIn('usage:', err)

    def test_script_exits_with_the_code_of_main(self):
        """Run as a script, a failing gate becomes a non-zero process exit."""
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'coverage.json'
            path.write_text(json.dumps(report(**{'a.py': module((1, 100))})), encoding='utf-8')
            argv = ['check_coverage.py', str(path)]
            with mock.patch.object(sys, 'argv', argv), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    runpy.run_path(check_coverage.__file__, run_name='__main__')
        self.assertEqual(raised.exception.code, check_coverage.EXIT_BELOW_GATE)


if __name__ == '__main__':
    unittest.main()
