# tools

Support tools for local environments, part of the workspace core. One folder per tool. A tool with a user interface shows the project's identity, Claude CLI Agents Workspace: the name and the logo or icon of the root `assets/`, never a company's identity. In an installed workspace this folder is read-only: your own tools live in the custom layer, in `custom/tools/<name>/` (`bash scripts/init-repo.sh --type tool`), and POCs in `custom/pocs/`. A tool that takes settings has a `.env.example` next to it; the filled file is `custom/env/<name>.env` (`/local-env tools/<name>`), passed to compose with `--env-file`.

| Item | Type | Goal |
| --- | --- | --- |
| observability | tool | Local Grafana and OTLP receiver for the Claude Code telemetry and the projects' dashboards |
| container-console-docker-ce | tool | Local browser console to watch docker-ce and manage containers, Compose and Kubernetes, opened from a GNOME shortcut |
| container-console-colima | tool | macOS twin of container-console-docker-ce: local browser console to control Colima and manage containers, Compose and Kubernetes, opened from a Dock icon |
| claude-usage | tool | Local report of Claude Code usage per day, session and model, read from the logs in `~/.claude/projects` |
| fable-alert | tool | Visual alert (terminal background and banner) when the Claude Code session runs on Fable, with a status line and a startup recorder |
| login-simulator | tool | Local login in place of Auth0: fixed fictitious users, one-click login, no internet, always on in Docker |
| azurite-console | tool | Page to see and operate the local Azurite: blobs, queues, tables and the access log, with its own compose |
| safe-browsing-simulator | tool | Local Google Safe Browsing (Lookup v4): dangerous URLs and an outage read from a file, no internet and no real key |
| compose.yaml | file | The compose project of every container tool, `claude-cli-agents-tools`: it includes each tool's own `compose.yaml` |

## How to start the tools

`/run-tools` in a session: it shows checkboxes with the tools of this machine and starts the ones you tick. Behind it, `bash scripts/run-tools.sh list --json | status | up <tool>... | down <tool>...` (`--help`).

- The container tools (observability, the two simulators, the Azurite console) run in one compose project, `claude-cli-agents-tools`, so the container console shows them as one group. `tools/compose.yaml` includes each tool's own `compose.yaml`, which still starts that tool alone, for development. By hand: `docker compose --env-file custom/env/azurite-console.env -f tools/compose.yaml up -d --build [<service>...]`.
- Title, description and URL of each tool live in the `x-run-tools` block of its main service. A new container tool shows in `/run-tools` once `tools/compose.yaml` includes it.
- A tool's configuration lives in the custom layer: `custom/env/<tool>.env` and `custom/config/<tool>/`. A tool without it is listed as "configuration missing" and does not start; the others still do.
- Of the two container consoles, only the machine's one shows: `container-console-docker-ce` on Linux and WSL with Docker Engine, `container-console-colima` on macOS with Colima. They are machine services (systemd, launchd), outside the group; `/run-tools` installs one with `make install` or starts its service.
- Each start tags the images it replaces as `<name>:rollback-latest`. Unticking a tool that is up stops nothing; `/run-tools --down` stops.
- A tool still running in its own old project (an install from before the group) moves into the group at its first start: a named volume is copied to the group's name, and the old volume is kept until you confirm its deletion.

## Host ports

A port appears only once. Project: the conventional one when free, otherwise another free one below 20000. Tool: the conventional one; with none, from 20000 up. POC and `docker/`: from 20000 up.

| Port | Owner | Type | Use |
| --- | --- | --- | --- |
| 3000 | `tools/observability` | tool | Grafana |
| 4317, 4318 | `tools/observability` | tool | OTLP gRPC and HTTP |
| 17850 | `tools/container-console-colima` | tool | service (`CONSOLE_LISTEN`); macOS, launchd agent |
| 27850 | `tools/container-console-docker-ce` | tool | service (`CONSOLE_LISTEN`); Linux and WSL, `systemd --user` |
| 28080 | `tools/login-simulator` | tool | login simulator in place of Auth0; generated photos at `172.31.250.10:8080`, network `login-simulator` with the fixed subnet `172.31.250.0/24` |
| 25174 | `tools/azurite-console` | tool | Vite in development |
| 28090 | `tools/safe-browsing-simulator` | tool | Google Safe Browsing simulator (Lookup v4); network `safe-browsing-simulator` |
| 28091 | `tools/azurite-console` | tool | console |
| 29000 | `docker/sonar` | `docker/` | SonarQube |
| 30000–30002 | `tools/azurite-console` | tool | Azurite (blob, queue, table) |

The projects' ports are in the custom layer, in `custom/projects.md`.
