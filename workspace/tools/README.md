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
