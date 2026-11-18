# observability

- [What it is](#what-it-is)
- [How to run](#how-to-run)
- [Configure Claude Code](#configure-claude-code)
- [How to test](#how-to-test)
- [How to add dashboards](#how-to-add-dashboards)
- [Claude Code dashboard](#claude-code-dashboard)
- [Where the data lives](#where-the-data-lives)
- [Personal data](#personal-data)

## What it is

The workspace's local telemetry stack, with the `grafana/otel-lgtm` image: Grafana, Prometheus, Loki, Tempo and the OTLP receiver in a single container. It runs only on the local machine, with no login, reachable only through `127.0.0.1`.

| Port | Use |
| --- | --- |
| `3000` | Grafana: <http://localhost:3000> |
| `4317` | OTLP gRPC (Claude Code telemetry points here) |
| `4318` | OTLP HTTP |

## How to run

`/run-tools` in a session, ticking Observability, or from the workspace root:

```bash
bash scripts/run-tools.sh up observability
```

It runs in `claude-cli-agents-tools`, the compose project of every tool (`tools/compose.yaml`). To restart it by hand: `docker compose -f tools/compose.yaml restart otel-lgtm`. This folder's `compose.yaml` still starts it alone (project `observability`), for development; stop it before `/run-tools`, which otherwise moves it into the group.

Another project reaches `otel-lgtm:4317` through the `observability` network: with this stack already up, its compose file declares `networks: {observability: {external: true}}` and each service that sends telemetry lists `observability` in `networks`, together with `default` if it also talks to the project's other services.

Grafana follows the operating system theme, even if it changes with the page open. To pin another one, use Administration > General > Default preferences (`/org`), field `Interface theme`: `System preference`, `Dark` or `Light`. The choice applies to the whole organization and lives in `.data/`. The command palette (`Search...` at the top, `Change theme`) only offers `Dark` and `Light` and loses the choice on reload: access is anonymous, with no user profile, and `/profile` redirects to the login. The fixed colors of the dashboard have a contrast of at least 3:1 in both themes.

Claude Code telemetry is configured in `~/.claude/settings.json`; the variables are in [Configure Claude Code](#configure-claude-code).

## Configure Claude Code

The file `settings-telemetry.json` has the `env` block with the 11 variables that turn telemetry on and point it at this stack:

| Variable | Value | What it does |
| --- | --- | --- |
| `CLAUDE_CODE_ENABLE_TELEMETRY` | `1` | Turns telemetry on |
| `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA` | `1` | Turns tracing on, which is still in beta |
| `OTEL_METRICS_EXPORTER` | `otlp` | Sends the metrics through OTLP |
| `OTEL_LOGS_EXPORTER` | `otlp` | Sends the events through OTLP |
| `OTEL_TRACES_EXPORTER` | `otlp` | Sends the traces through OTLP |
| `OTEL_EXPORTER_OTLP_PROTOCOL` | `grpc` | Uses gRPC for the three signals |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4317` | Address of this stack's OTLP gRPC receiver |
| `OTEL_RESOURCE_ATTRIBUTES` | `deployment.environment.name=dev` | Tags all data with the environment |
| `OTEL_LOG_USER_PROMPTS` | `0` | Does not send the prompt text; this is already the default, and the value stays explicit |
| `OTEL_LOG_TOOL_DETAILS` | `1` | Sends the tool details: Bash commands, MCP server and tool names, skill names, the input of each tool and the full error text. It stays on because it keeps the real names of agents, skills, plugins and MCP in the cost and token counters; without it, those names become `custom` or `third-party` |
| `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` | `cumulative` | Sends the metrics as cumulative counters |

Do not change `cumulative`: the Claude Code default is `delta`, and Prometheus drops `delta` metrics without a warning.

To install, from the workspace root, back up the settings and merge the block into them, without deleting what exists:

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq -s '.[0] * .[1]' ~/.claude/settings.json.bak tools/observability/settings-telemetry.json > ~/.claude/settings.json
```

The variables only apply to the sessions opened after the change.

The dashboard reads `ttft_ms` from the `api_request` events in Loki. The official documentation lists this field only in the traces, but the `api_request` events of Claude Code 2.1.309 also carry it.

### Check that the data arrives

With the stack up and after a few minutes of Claude Code use:

```bash
# Metrics in Prometheus
curl -s -G http://localhost:3000/api/datasources/proxy/uid/prometheus/api/v1/query \
  --data-urlencode 'query=sum by (model) (claude_code_token_usage_tokens_total)'

# Events in Loki
curl -s -G http://localhost:3000/api/datasources/proxy/uid/loki/loki/api/v1/query_range \
  --data-urlencode 'query={service_name="claude-code"} | event_name="api_request"' \
  --data-urlencode 'limit=5'
```

If nothing arrives, run a session with a debug log, in a folder outside the workspace, and look for the telemetry lines. The command makes one call to the model; delete `telemetry.log` afterwards.

```bash
claude -p "answer only: ok" --debug-file telemetry.log
grep '\[3P telemetry\]' telemetry.log
```

### Turn it off

```bash
cp ~/.claude/settings.json ~/.claude/settings.json.bak
jq '.env |= with_entries(select(.key | test("^(OTEL_|CLAUDE_CODE_ENABLE_TELEMETRY$|CLAUDE_CODE_ENHANCED_TELEMETRY_BETA$)") | not))' \
  ~/.claude/settings.json.bak > ~/.claude/settings.json
bash scripts/run-tools.sh down observability
```

Stopping does not delete the data (see [Where the data lives](#where-the-data-lives)).

### Cowork limit

Cowork does not send to this stack. It runs the exporter inside its own virtual machine, and its telemetry is only configured in the Anthropic admin console, on the Team and Enterprise plans. The Code tab of the desktop app reads the same settings as the terminal and sends normally.

## How to test

```bash
bash tools/observability/tests/run-smoke.sh
```

Each run starts its own Compose project (`observability-smoke-<pid>`), with its own network, temporary data in a folder inside `~`, fictitious projects and free `127.0.0.1` ports chosen by Docker, so several runs can happen at the same time. It checks the criteria through the Grafana HTTP API, including that every query of the dashboard is accepted with no data (`tests/check_dashboard_queries.py`) and what they return with fictitious telemetry of two models (`tests/check_dashboard_behavior.py`), and removes everything at the end. It needs `python3`. It does not touch the real stack, which may be running at the same time. On failure, it shows the Grafana provisioning lines and keeps the full log in a temporary file. Use `--verbose` to see the progress and the full logs.

## How to add dashboards

| Dashboard of | Where to put the JSON | Folder in Grafana | To appear |
| --- | --- | --- | --- |
| Claude Code and the workspace | `dashboards/workspace/<name>.json` | `workspace` | Within 15 s, no restart |
| POC | `dashboards/workspace/<poc-name>.json` | `workspace` | Within 15 s, no restart |
| Project | `projects/<name>/observability/dashboards/*.json` or `projects/<client>/<name>/observability/dashboards/*.json`, in the project's own repository | `<name>` | First JSON of the project: restart the container. After that: within 15 s, no restart |

- No file of this tool changes when a project is added.
- A project without `observability/dashboards/*.json` creates no folder in Grafana, and `<client>` never creates one. A subfolder of a repository in `projects/<name>/` does not create one either: the first folder with `.git` is always the project. Projects with the same `<name>` share the folder.
- Dashboards are read-only in Grafana: edit the JSON. Deleting the JSON deletes the dashboard within 15 s.
- A removed project loses its dashboards on the next restart, but its folder stays empty in Grafana: delete it by hand.
- The dashboards built into the image (RED Metrics and JVM) are left out on purpose.

## Claude Code dashboard

The `Claude Code: usage` dashboard shows cost, tokens, sessions, tools, errors and latency of the selected period, with a filter by model. The description of each panel says what it measures and whether the filter applies.

The model colors repeat in each panel that shows models: to change a color or add a model, edit `fieldConfig.overrides` of all of them in `dashboards/workspace/claude-code.json`; the smoke test fails if the maps diverge.

The totals come from the `api_request` events in Loki, because each event has the exact time of the call. The Prometheus counter does not work for this: `last_over_time` returns the total of the whole session, and `increase` loses the first sample and extrapolates.

Lines changed, commits and active time use the counter, with a delta per session: the last value of the period minus the last one before it, with a new session starting from 0. They are approximate (`approx.` in the title): they underestimate a resumed session, because the counter restarts. The model filter applies to lines changed, but not to commits, active time, prompts and tools (`all models` in the title).

The model list of the filter is approximate and comes from Prometheus, because Grafana does not list as a variable value an event field that is not an indexed label in Loki. It shows the models with an increase in the counter or with a new counter in the period, and the usage of the last 60 seconds may not show yet.

## Where the data lives

In `tools/observability/.data/`, ignored by git and by the checks of `scripts/validate.sh`. It is a bind mount: `docker compose down -v` does not delete the data. To reset the stack, delete this folder with the container stopped.

| Signal | Retention | Source |
| --- | --- | --- |
| Metrics (Prometheus) | 365 days | `PROMETHEUS_EXTRA_ARGS` in `compose.yaml` (image default: 15 days) |
| Traces (Tempo) | 365 days | `TEMPO_EXTRA_ARGS` in `compose.yaml` (image default: 14 days) |
| Logs (Loki) | No limit | Image default; `LOKI_EXTRA_ARGS` in `compose.yaml` also removes the 30-day limit per query |
| Profiles (Pyroscope) | 31 days | Image default |

## Personal data

The collector deletes from new telemetry, in the metrics, the logs and the traces, on the item and on the resource: `user.email`, `user.id`, `user.account_uuid`, `user.account_id`, `organization.id`, `process.owner` (and the `process_owner` variant), `tool_input`, `tool_parameters`, `full_command`, `file_path`, `bash_argv0`, `process.command_args` and `process.executable.*` (`grafana/otelcol-config.yaml`, a copy of the image's configuration that must be redone when the image is updated). `session.id` stays, and the tool name goes on in `tool_name`.

History is not rewritten: data recorded before these attributes were dropped keeps them until it expires by the retention of the table above, and in the logs it does not expire.

Claude Code still SENDS this data: the email and the account ids in every signal and, with `OTEL_LOG_TOOL_DETAILS=1`, the input and the parameters of the tools. The protection is in the local collector, which deletes them before writing. So pointing `OTEL_EXPORTER_OTLP_ENDPOINT` at a shared server bypasses it: nothing above would be removed on the way. Before doing that, review `OTEL_LOG_TOOL_DETAILS`. What is not on the collector's list stays recorded; `error`, the full error text in `tool_result`, which may carry paths with the login, is also deleted, and the profiles (Pyroscope) do not go through this cleanup. The prompt text is not sent with `OTEL_LOG_USER_PROMPTS=0`. With the local collector, this OTLP telemetry does not leave the machine; Anthropic's operational telemetry is a separate flow, which these variables do not control.
