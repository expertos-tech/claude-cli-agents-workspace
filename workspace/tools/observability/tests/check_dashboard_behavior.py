#!/usr/bin/env python3
"""Proves what the dashboard queries return: posts fictitious telemetry over OTLP and reads it back via /api/ds/query.

Prometheus rejects samples more than 10 minutes behind its newest one (out_of_order_time_window in the image),
so counters use a 5-minute window with samples 8 minutes old, while Loki events use a 3-hour window with events
4 hours old.
"""

import argparse
import json
import re
import sys
import time
import urllib.request

from check_dashboard_queries import ALL_MODELS, run_query, variable_targets

NEW_MODEL = 'claude-test-new'
OLD_MODEL = 'claude-test-old'
POLL_TIMEOUT_SECONDS = 120
TOLERANCE = 1e-6
MINUTE_MS = 60_000
HOUR_MS = 60 * MINUTE_MS
EVENT_COST = {NEW_MODEL: 2.0, OLD_MODEL: 5.0}
EVENT_TOKENS = {NEW_MODEL: 100, OLD_MODEL: 1000}
OLD_SESSION = {'model': OLD_MODEL, 'session.id': 'smoke-session-old'}
NEW_SESSION = {'model': NEW_MODEL, 'session.id': 'smoke-session-new'}
# Name, unit, labels and the values 8 minutes ago and 1 minute ago. The old model only reports its lifetime
# total, as an idle session does. Expected deltas: Commits 2 + 3 (new session), Lines changed 4 + 5, Active time 30.
COUNTERS = (
    ('claude_code.token.usage', 'tokens', dict(OLD_SESSION, type='input'), (9000.0, 9000.0)),
    ('claude_code.token.usage', 'tokens', dict(NEW_SESSION, type='input'), (None, 400.0)),
    ('claude_code.cost.usage', 'USD', OLD_SESSION, (900.0, 900.0)),
    ('claude_code.cost.usage', 'USD', NEW_SESSION, (None, 40.0)),
    ('claude_code.commit.count', '', {'session.id': 'smoke-a'}, (5.0, 7.0)),
    ('claude_code.commit.count', '', {'session.id': 'smoke-b'}, (None, 3.0)),
    ('claude_code.active_time', 's', {'session.id': 'smoke-a', 'type': 'cli'}, (100.0, 130.0)),
    (
        'claude_code.lines_of_code.count',
        '',
        {'session.id': 'smoke-a', 'model': NEW_MODEL, 'type': 'added'},
        (10.0, 14.0),
    ),
    (
        'claude_code.lines_of_code.count',
        '',
        {'session.id': 'smoke-a', 'model': OLD_MODEL, 'type': 'added'},
        (20.0, 25.0),
    ),
)


def attributes(**values):
    """Returns OTLP string attributes."""
    return [{'key': key, 'value': {'stringValue': value}} for key, value in values.items()]


def post_otlp(otlp, signal, payload):
    """Posts one OTLP/HTTP JSON payload and fails on a refused request."""
    data = json.dumps(payload).encode()
    request = urllib.request.Request(f'{otlp}/v1/{signal}', data, {'Content-Type': 'application/json'})
    with urllib.request.urlopen(request, timeout=10):
        pass


def api_request_event(model, when_ms, session):
    """Returns one fictitious api_request log record."""
    tokens = EVENT_TOKENS[model]
    fields = {
        'event.name': 'api_request',
        'model': model,
        'session.id': session,
        'query_source': 'repl_main_thread',
        'effort': 'high',
        'cost_usd': str(EVENT_COST[model]),
        'input_tokens': str(tokens),
        'output_tokens': str(tokens),
        'cache_read_tokens': str(tokens),
        'cache_creation_tokens': str(tokens),
        'duration_ms': '1000',
        'ttft_ms': '100',
    }
    return {
        'timeUnixNano': str(when_ms * 1_000_000),
        'body': {'stringValue': 'claude_code.api_request'},
        'attributes': attributes(**fields),
    }


def post_events(otlp, now_ms):
    """Posts the old event before the new one, because Loki rejects entries too far behind in a stream."""
    for model, age_ms, session in (
        (OLD_MODEL, 4 * HOUR_MS, 'smoke-session-old'),
        (NEW_MODEL, MINUTE_MS, 'smoke-session-new'),
    ):
        record = api_request_event(model, now_ms - age_ms, session)
        post_otlp(
            otlp,
            'logs',
            {
                'resourceLogs': [
                    {
                        'resource': {'attributes': attributes(**{'service.name': 'claude-code'})},
                        'scopeLogs': [{'logRecords': [record]}],
                    }
                ]
            },
        )


def counter(name, unit, labels, when_ms, value):
    """Returns one cumulative monotonic OTLP metric with a single sample."""
    point = {
        'startTimeUnixNano': str((when_ms - HOUR_MS) * 1_000_000),
        'timeUnixNano': str(when_ms * 1_000_000),
        'asDouble': value,
        'attributes': attributes(**labels),
    }
    return {
        'name': name,
        'unit': unit,
        'sum': {'aggregationTemporality': 2, 'isMonotonic': True, 'dataPoints': [point]},
    }


def post_counters(otlp, now_ms):
    """Posts each counter 8 minutes ago and 1 minute ago, oldest first, skipping the samples set to None."""
    for index, when_ms in enumerate((now_ms - 8 * MINUTE_MS, now_ms - MINUTE_MS)):
        batch = [
            counter(name, unit, labels, when_ms, values[index])
            for name, unit, labels, values in COUNTERS
            if values[index] is not None
        ]
        post_otlp(
            otlp,
            'metrics',
            {
                'resourceMetrics': [
                    {
                        'resource': {'attributes': attributes(**{'service.name': 'claude-code'})},
                        'scopeMetrics': [{'metrics': batch}],
                    }
                ]
            },
        )


def rows(result):
    """Flattens a query result into (labels, value) pairs."""
    pairs = []
    for frame in result.get('frames', []):
        for index, field in enumerate(frame['schema']['fields']):
            if field['type'] == 'number':
                pairs += [
                    (field.get('labels') or {}, value) for value in frame['data']['values'][index] if value is not None
                ]
    return pairs


class Dashboard:
    """Reads panel values through /api/ds/query in the panels' time window.

    Uses the fixed intervalMs and maxDataPoints of build_request and skips the browser's split of Loki requests,
    so it does not prove what a browser render shows.
    """

    def __init__(self, grafana, dashboard, now_ms):
        """Keeps the panels by title; the clock is injected so every query sees the same instant."""
        self.grafana = grafana
        self.panels = {panel['title']: panel for panel in dashboard['panels'] if panel['type'] != 'row'}
        self.dashboard = dashboard
        self.now_ms = now_ms

    def target_rows(self, target, window_ms, model):
        """Returns the rows of one target, raising on a query error."""
        result = run_query(self.grafana, target, str(self.now_ms - window_ms), str(self.now_ms), model)
        if result.get('error'):
            raise AssertionError(result['error'])
        return rows(result)

    def panel_rows(self, title, window_ms, model=ALL_MODELS):
        """Returns the rows of every target of a panel."""
        return [row for target in self.panels[title]['targets'] for row in self.target_rows(target, window_ms, model)]

    def total(self, title, window_ms, model=ALL_MODELS):
        """Returns the sum of a panel."""
        return sum(value for _, value in self.panel_rows(title, window_ms, model))

    def models(self, title, window_ms, model=ALL_MODELS):
        """Returns the model labels a panel shows."""
        return {labels['model'] for labels, _ in self.panel_rows(title, window_ms, model) if 'model' in labels}

    def variable_models(self, window_ms):
        """Returns the values the model variable lists, after its regex."""
        variable = self.dashboard['templating']['list'][0]
        extract = re.compile(variable['regex'].strip('/'))
        _, target = next(variable_targets(self.dashboard))
        found = set()
        for labels, _ in self.target_rows(target, window_ms, ALL_MODELS):
            match = extract.search(f'{{model="{labels.get("model", "")}"}}')
            if match:
                found.add(match.group(1))
        return found


def close(left, right):
    """Compares two floats with a small tolerance."""
    return abs(left - right) <= TOLERANCE


def expectations(board):
    """Returns (description, holds) for each behavior, with AC ids."""
    three_hours, five_hours, five_minutes = 3 * HOUR_MS, 5 * HOUR_MS, 5 * MINUTE_MS
    filterable = [
        title for title, panel in board.panels.items() if 'filtro de modelo se aplica' in panel['description']
    ]
    unfiltered = [
        title
        for title in filterable
        if any('$model' not in target['expr'] for target in board.panels[title]['targets'])
    ]
    by_model = board.panel_rows('Cost by model', three_hours)
    return [
        (
            'AC-9 3h: Cost by model excludes the old model',
            board.models('Cost by model', three_hours) == {NEW_MODEL},
        ),
        (
            'AC-9 5h: Cost by model shows both models, so the old event exists',
            board.models('Cost by model', five_hours) == {NEW_MODEL, OLD_MODEL},
        ),
        (
            'AC-9 variable excludes an idle model, in the 5-minute window Prometheus allows',
            board.variable_models(five_minutes) == {NEW_MODEL},
        ),
        (
            'AC-10 3h: Cost equals the sum by model',
            close(board.total('Cost', three_hours), sum(value for _, value in by_model)) and by_model != [],
        ),
        (
            'AC-10 5h: Total tokens equals the sum by model',
            close(board.total('Total tokens', five_hours), board.total('Tokens by model', five_hours)),
        ),
        ('AC-10 5h: Cost is the fixture total', close(board.total('Cost', five_hours), sum(EVENT_COST.values()))),
        ('AC-11 every panel the filter applies to uses $model', not unfiltered),
        (
            'AC-11 filter narrows Cost',
            close(board.total('Cost', five_hours, NEW_MODEL), EVENT_COST[NEW_MODEL])
            and close(board.total('Cost', five_hours, OLD_MODEL), EVENT_COST[OLD_MODEL]),
        ),
        (
            'AC-11 filter narrows Cost by model',
            board.models('Cost by model', five_hours, NEW_MODEL) == {NEW_MODEL},
        ),
        (
            'AC-11 filter narrows Lines changed',
            close(board.total('Lines changed (approx.)', five_minutes, NEW_MODEL), 4)
            and close(board.total('Lines changed (approx.)', five_minutes, OLD_MODEL), 5),
        ),
        (
            'AC-13 Commits is the per-session delta, new session from 0',
            close(board.total('Commits (all models) (approx.)', five_minutes), 5),
        ),
        (
            'AC-13 Lines changed is the per-session delta',
            close(board.total('Lines changed (approx.)', five_minutes), 9),
        ),
        (
            'AC-13 Active time is the per-session delta',
            close(board.total('Active time (all models) (approx.)', five_minutes), 30),
        ),
    ]


def wait_for_data(board):
    """Waits until the fixtures of Loki and Prometheus are readable, within a deadline."""
    deadline = time.monotonic() + POLL_TIMEOUT_SECONDS
    while time.monotonic() < deadline:
        ready = (
            board.models('Cost by model', 5 * HOUR_MS) == {NEW_MODEL, OLD_MODEL}
            and board.total('Commits (all models) (approx.)', 5 * MINUTE_MS) > 0
        )
        if ready and board.variable_models(5 * MINUTE_MS):
            return
        time.sleep(2)
    raise AssertionError(f'fixtures not readable after {POLL_TIMEOUT_SECONDS}s')


def main():
    """Posts the fixtures, runs the expectations and returns the process exit code."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--grafana', required=True, help='Grafana base URL')
    parser.add_argument('--otlp', required=True, help='OTLP/HTTP base URL of an isolated stack; never the real one')
    parser.add_argument('--dashboard', required=True, help='Path of the dashboard JSON')
    args = parser.parse_args()
    with open(args.dashboard, encoding='utf-8') as file:
        dashboard = json.load(file)
    now_ms = int(time.time() * 1000)
    board = Dashboard(args.grafana.rstrip('/'), dashboard, now_ms)
    failed = 0
    try:
        post_events(args.otlp.rstrip('/'), now_ms)
        post_counters(args.otlp.rstrip('/'), now_ms)
        wait_for_data(board)
        for description, holds in expectations(board):
            print(f'{"PASS" if holds else "FAIL"} {description}')
            failed += 0 if holds else 1
    except (AssertionError, KeyError, StopIteration, OSError) as error:
        print(f'FAIL dashboard behavior: {error!r}', file=sys.stderr)
        return 1
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
