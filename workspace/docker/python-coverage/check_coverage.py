#!/usr/bin/env python3
"""Fails when any module of a coverage.py JSON report is below the per-module gate of rules/quality.md."""

import json
import sys

MINIMUM_PERCENT = 85
EXIT_PASSED = 0
EXIT_BELOW_GATE = 1
EXIT_INVALID_REPORT = 2
SUMMARY_COUNTS = ('num_statements', 'covered_lines', 'num_branches', 'covered_branches')


class InvalidReport(ValueError):
    """The report cannot be read or lacks the data the gate needs."""


def percent(covered, total):
    """Returns the covered percentage truncated to one decimal, so 84.96 never prints as a passing 85.0."""
    return 100.0 if total == 0 else covered * 1000 // total / 10


def is_count(value):
    """Tells whether a value is a non-negative integer; a JSON boolean is not a count."""
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def module_summary(name, entry):
    """Returns the validated summary of one module, raising InvalidReport when a count is missing or impossible."""
    summary = entry.get('summary') if isinstance(entry, dict) else None
    if not isinstance(summary, dict) or not all(is_count(summary.get(key)) for key in SUMMARY_COUNTS):
        raise InvalidReport(f'{name}: summary lacks line or branch counts; does .coveragerc set branch = True?')
    if summary['covered_lines'] > summary['num_statements'] or summary['covered_branches'] > summary['num_branches']:
        raise InvalidReport(f'{name}: covered count above the total')
    return summary


def report_modules(report):
    """Returns the measured modules of a report, raising InvalidReport when it has none or was not branch-measured."""
    if not isinstance(report, dict) or not isinstance(report.get('files'), dict):
        raise InvalidReport('report has no files object')
    if not report['files']:
        raise InvalidReport('report measured no module; check source and omit in .coveragerc')
    meta = report.get('meta')
    if not isinstance(meta, dict) or meta.get('branch_coverage') is not True:
        raise InvalidReport('report has no branch data; set branch = True in .coveragerc')
    return report['files']


def evaluate(report):
    """Returns (passed, line) for each module, sorted by module name, with both percentages and their counts."""
    results = []
    for name, entry in sorted(report_modules(report).items()):
        summary = module_summary(name, entry)
        lines = percent(summary['covered_lines'], summary['num_statements'])
        branches = percent(summary['covered_branches'], summary['num_branches'])
        passed = lines >= MINIMUM_PERCENT and branches >= MINIMUM_PERCENT
        results.append(
            (
                passed,
                f'{"PASS" if passed else "FAIL"} {name}: '
                f'lines {lines:.1f}% ({summary["covered_lines"]}/{summary["num_statements"]}), '
                f'branches {branches:.1f}% ({summary["covered_branches"]}/{summary["num_branches"]})',
            )
        )
    return results


def load_report(path):
    """Returns the parsed JSON report, raising InvalidReport when it cannot be read or parsed."""
    try:
        with open(path, encoding='utf-8') as file:
            return json.load(file)
    except (OSError, ValueError) as error:
        raise InvalidReport(f'cannot read {path}: {error}') from error


def main(arguments):
    """Prints one line per module and returns the process exit code."""
    if len(arguments) != 1:
        print('usage: check_coverage.py <coverage-json-report>', file=sys.stderr)
        return EXIT_INVALID_REPORT
    try:
        results = evaluate(load_report(arguments[0]))
    except InvalidReport as error:
        print(f'error: {error}', file=sys.stderr)
        return EXIT_INVALID_REPORT
    for _, line in results:
        print(line)
    return EXIT_PASSED if all(passed for passed, _ in results) else EXIT_BELOW_GATE


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
