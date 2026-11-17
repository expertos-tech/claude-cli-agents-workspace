#!/usr/bin/env python3
"""Container entry point of the coverage check: runs the tests of one target and applies the per-module gate.

The target is the current folder, holding .coveragerc and tests/. Nothing is written to it: the data and the
report stay under /tmp. Exits 0 when the tests pass and every module meets the gate, non-zero otherwise.
Each step must finish within COVERAGE_TIMEOUT_SECONDS, a whole number of seconds, default 600.
"""

import os
import re
import subprocess
import sys
from pathlib import Path

import check_coverage

DEFAULT_TIMEOUT_SECONDS = '600'
EXIT_PASSED = 0
EXIT_USAGE = 2
EXIT_TIMEOUT = 124
REPORT = '/tmp/coverage.json'
STEPS = (
    ('coverage', 'run', '-m', 'unittest', 'discover', '-s', 'tests'),
    ('coverage', 'json', '-q', '-o', REPORT),
)
TARGET = Path('.')
TIMEOUT_VARIABLE = 'COVERAGE_TIMEOUT_SECONDS'
VALID_TIMEOUT = re.compile(r'[1-9][0-9]{0,8}')


def step_timeout(environ):
    """Returns the deadline of each step in seconds, raising ValueError when the variable is not valid."""
    value = environ.get(TIMEOUT_VARIABLE, DEFAULT_TIMEOUT_SECONDS)
    if not VALID_TIMEOUT.fullmatch(value):
        raise ValueError(f'{TIMEOUT_VARIABLE} must be a whole number of seconds from 1 to 999999999, got {value!r}')
    return int(value)


def layout_error(folder):
    """Returns what the folder lacks to be a coverage target, or None when it has everything."""
    if not (folder / '.coveragerc').is_file():
        return f'no .coveragerc in {folder.resolve()}'
    if not (folder / 'tests').is_dir():
        return f'no tests folder in {folder.resolve()}'
    return None


def run_steps(timeout_seconds):
    """Runs each coverage step in order and returns the exit code of the first failure or timeout, or EXIT_PASSED."""
    for step in STEPS:
        try:
            code = subprocess.run(step, check=False, timeout=timeout_seconds).returncode
        except subprocess.TimeoutExpired:
            command = ' '.join(step)
            print(f'error: {command} exceeded the deadline of {timeout_seconds}s ({TIMEOUT_VARIABLE})', file=sys.stderr)
            return EXIT_TIMEOUT
        if code != EXIT_PASSED:
            return code
    return EXIT_PASSED


def main(arguments, folder=TARGET, environ=os.environ):
    """Validates the arguments, the deadline and the target, runs the steps, applies the gate and returns the code."""
    if arguments in (['--help'], ['-h']):
        print(__doc__)
        return EXIT_PASSED
    if arguments:
        print(f'error: unknown option: {arguments[0]}', file=sys.stderr)
        return EXIT_USAGE
    try:
        timeout_seconds = step_timeout(environ)
    except ValueError as error:
        print(f'error: {error}', file=sys.stderr)
        return EXIT_USAGE
    error = layout_error(folder)
    if error:
        print(f'error: {error}', file=sys.stderr)
        return EXIT_USAGE
    return run_steps(timeout_seconds) or check_coverage.main([REPORT])


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
