#!/usr/bin/env python3
"""Checks that every query of a dashboard is accepted by its datasource, through the path the panels use.

Grafana's /api/ds/query resolves $__range and $__auto itself, so only $model is replaced here.
An empty result is accepted: the check is about the query, not about the data. What the queries
return is checked by check_dashboard_behavior.py.
"""

import argparse
import http.client
import json
import re
import sys
import time
import urllib.error
import urllib.request

ALL_MODELS = '.+'
MIN_TIMESERIES_DATA_POINTS = 800
MODEL_LEGEND = '{{model}}'
HTTP_TIMEOUT_SECONDS = 120
PLUGIN_NOT_READY = 'Plugin not registered'
PLUGIN_WAIT_SECONDS = 60
QUERY_RESULT = re.compile(r'^query_result\((?P<expr>.*)\)$', re.DOTALL)
# Personal or free-text event fields that no panel may use, even only to group, filter, name or show.
FORBIDDEN_FIELDS = re.compile(
    r'\b(user_email|user_id|user_account_\w+|organization_id|prompt|prompt_text|response|tool_input|tool_parameters|process_owner)\b'
)


def panel_targets(dashboard):
    """Yields (panel title, target) for each query of the dashboard panels."""
    for panel in dashboard.get('panels', []):
        for target in panel.get('targets', []):
            yield panel.get('title', '?'), target


def variable_targets(dashboard):
    """Yields (variable name, target) for each query_result variable, as an equivalent panel target."""
    for variable in dashboard.get('templating', {}).get('list', []):
        query = variable.get('query')
        text = query.get('query', '') if isinstance(query, dict) else ''
        match = QUERY_RESULT.match(text)
        if match:
            target = {'refId': 'A', 'datasource': variable['datasource'], 'expr': match.group('expr'), 'instant': True}
            yield f'variable {variable["name"]}', target


def build_request(target, time_from, time_to, model):
    """Returns the /api/ds/query body of one target, with $model already replaced as the frontend does."""
    query = dict(target, expr=target['expr'].replace('$model', model), intervalMs=60000, maxDataPoints=100)
    return {'queries': [query], 'from': time_from, 'to': time_to}


def run_query(grafana, target, time_from, time_to, model):
    """Returns the result of one target, waiting while a fresh Grafana is still registering its plugins."""
    deadline = time.monotonic() + PLUGIN_WAIT_SECONDS
    while True:
        result = send_query(grafana, target, time_from, time_to, model)
        if PLUGIN_NOT_READY not in str(result.get('error')) or time.monotonic() >= deadline:
            return result
        time.sleep(2)


def send_query(grafana, target, time_from, time_to, model):
    """Returns the result of one target, with an error field on any failure, including a non-JSON body."""
    body = json.dumps(build_request(target, time_from, time_to, model)).encode()
    request = urllib.request.Request(f'{grafana}/api/ds/query', body, {'Content-Type': 'application/json'})
    try:
        try:
            with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
                answer = json.load(response)
        except urllib.error.HTTPError as error:
            answer = json.loads(error.read())
    except (OSError, http.client.HTTPException, ValueError) as error:
        return {'error': f'invalid answer: {error}'}
    result = answer.get('results', {}).get(target['refId'])
    return result if result is not None else {'error': answer.get('message', 'no result in the answer')}


def forbidden_uses(dashboard):
    """Returns one failure line per forbidden field in a query, legend, field config or transformation."""
    failures = []
    for panel in dashboard.get('panels', []):
        parts = [panel.get('targets', []), panel.get('transformations', []), panel.get('fieldConfig', {})]
        found = FORBIDDEN_FIELDS.search(json.dumps(parts))
        if found:
            failures.append(f'{panel.get("title", "?")}: uses forbidden field {found.group(1)}')
    return failures


def low_resolution_panels(dashboard):
    """Returns one failure line per time series whose coarse step would make the browser's split lose recent data."""
    return [
        f'{panel.get("title", "?")}: maxDataPoints below {MIN_TIMESERIES_DATA_POINTS}'
        for panel in dashboard.get('panels', [])
        if panel.get('type') == 'timeseries' and panel.get('maxDataPoints', 0) < MIN_TIMESERIES_DATA_POINTS
    ]


def model_colors(panel):
    """Returns the {series name: color} overrides of a panel."""
    colors = {}
    for override in panel.get('fieldConfig', {}).get('overrides', []):
        for prop in override.get('properties', []):
            if prop.get('id') == 'color':
                colors[override['matcher']['options']] = prop['value'].get('fixedColor')
    return colors


def inconsistent_model_colors(dashboard):
    """Returns one failure line per panel by model whose color map is empty or differs from the first one."""
    by_model = [
        panel
        for panel in dashboard.get('panels', [])
        if any(target.get('legendFormat') == MODEL_LEGEND for target in panel.get('targets', []))
    ]
    if not by_model:
        return ['no panel by model found']
    reference = model_colors(by_model[0])
    if not reference:
        return [f'{by_model[0].get("title", "?")}: no model color overrides']
    return [
        f'{panel.get("title", "?")}: model colors differ from {by_model[0].get("title", "?")}'
        for panel in by_model[1:]
        if model_colors(panel) != reference
    ]


def check(grafana, dashboard, time_from, time_to, model):
    """Returns one failure line per rejected query or per panel that breaks a static rule of the dashboard."""
    failures = forbidden_uses(dashboard) + low_resolution_panels(dashboard) + inconsistent_model_colors(dashboard)
    for title, target in list(panel_targets(dashboard)) + list(variable_targets(dashboard)):
        error = run_query(grafana, target, time_from, time_to, model).get('error')
        if error:
            failures.append(f'{title} [{target["refId"]}]: {error}')
    return failures


def main():
    """Parses the arguments, runs the check and returns the process exit code."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--grafana', required=True, help='Grafana base URL, e.g. http://127.0.0.1:33000')
    parser.add_argument('--dashboard', required=True, help='Path of the dashboard JSON')
    parser.add_argument('--from', dest='time_from', default='now-3h', help='Start of the range (default: now-3h)')
    parser.add_argument('--to', dest='time_to', default='now', help='End of the range (default: now)')
    parser.add_argument('--model', default=ALL_MODELS, help='Value of the model variable (default: all models)')
    args = parser.parse_args()
    with open(args.dashboard, encoding='utf-8') as file:
        dashboard = json.load(file)
    failures = check(args.grafana.rstrip('/'), dashboard, args.time_from, args.time_to, args.model)
    for failure in failures:
        print(failure, file=sys.stderr)
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())
