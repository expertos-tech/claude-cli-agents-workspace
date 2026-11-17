# `/run-tools`: the tools in one compose project, picked by checkbox

Status: approved design. Request: `maintainers/requests/run-tools.md`.

## 1. Goal

1. The tools have one template compose file that starts all of them.
2. In the container console, all the tools show as a single group.
3. A new skill, `/run-tools`, shows checkboxes with the tools available on this machine, and the person ticks what to
   start.
4. Of the two container consoles, `docker-ce` and `colima`, only the one that matches what is installed on the machine
   shows.

## 2. How the tools start today

| Tool | How it runs | Compose project | Ports | Configuration |
| --- | --- | --- | --- | --- |
| `observability` | compose | `observability` | 3000, 4317, 4318 | none |
| `login-simulator` | compose | `login-simulator` | 28080 | `LOGIN_SIMULATOR_CONFIG` (data in `custom/config/`) |
| `safe-browsing-simulator` | compose | `safe-browsing-simulator` | 28090 | `SAFE_BROWSING_THREATS` (data in `custom/config/`) |
| `azurite-console` | compose (Azurite and the page) | `azurite-console` | 28091; Azurite on 30000–30002 | `AZURITE_ACCOUNT_KEY` and `DOCKER_SOCKET_GID` in `custom/env/azurite-console.env` |
| `container-console-docker-ce` | user systemd service (Linux and WSL) | not a container | 27850 | none |
| `container-console-colima` | launchd agent (macOS) | not a container | 17850 | none |
| `claude-usage`, `fable-alert` | script and plugin, on demand | do not start | — | — |

The console groups containers by the `com.docker.compose.project` label. Each tool is its own project, so four groups
show.

## 3. The single compose file

`tools/compose.yaml` joins the tools in one project:

```yaml
name: claude-cli-agents-tools
include:
  - observability/compose.yaml
  - login-simulator/compose.yaml
  - safe-browsing-simulator/compose.yaml
  - azurite-console/compose.yaml
```

- **One group:** every service gets the same project label, so the console shows one group. The console needs no
  change.
- **Start everything:** `docker compose -f tools/compose.yaml up -d`. To start some tools only, name the services:
  `... up -d login-simulator`.
- **Template:** configuration paths are variables with defaults that point to `custom/config/<tool>/`, and the env files
  come from `custom/env/<tool>.env`. Without the custom layer, a tool that needs configuration says what is missing and
  does not start.
- **The per-tool compose files stay:** each folder still starts on its own, for tests and development. The root file
  only includes them; no definition is duplicated.
- **Publishing with rollback:** before each build, the current images get the `rollback-latest` tag, as
  `aiwp-cmds.sh up` does. It is the rule of every publish to the local Docker.

**Changing the group has a cost.** Containers running in separate projects must be recreated in the new project.
Before that, check where each tool keeps data:

- **Bind-mounted folder** (the Grafana `.data`): nothing is lost.
- **Named volume:** the volume name changes with the project, and the data would stay in the old volume. In that case
  the skill copies the volume first, and deleting the old one asks for confirmation, like every database deletion.

## 4. The consoles stay out of the group

Both consoles are machine services (systemd or launchd), not containers. They talk to Docker and, for Colima, control
the VM itself, which does not work well from inside a container. So the console does not join the compose group.

`/run-tools` treats the console as a machine tool: it installs or starts the service (`make install` or
`systemctl --user start` on Linux; the `macos/` installer on a Mac). In the console, the single group shows the
container tools.

## 5. The `/run-tools` skill

### The script behind it

`scripts/run-tools.sh`, in the core and with tests, does the deterministic work. The skill only talks to the person.

| Command | Does |
| --- | --- |
| `list --json` | The tools available on this machine, each with id, title, description, kind (`compose` or `machine`), state (`up`, `stopped`, `not installed`), ports and what is missing (configuration, busy port) |
| `up <id>...` | Tags the rollback, builds and starts the chosen tools; waits until they are healthy and prints the URLs |
| `down <id>...` | Stops the chosen tools, without deleting volumes |
| `status` | The same as `list`, as a table |

### Title and description of each tool

They live in the tool's own compose file, in an `x-run-tools` extension of each service (title, description, URL). A
new tool shows in the list just by joining the `include` of the root file. The two machine tools, the consoles, are
declared in the script.

### Which console shows

| Machine | Listed |
| --- | --- |
| Linux or WSL with Docker Engine (`docker version` reports "Docker Engine - Community", or the `docker-ce` package is installed) | `container-console-docker-ce` |
| macOS with `colima` installed | `container-console-colima` |
| Both, or neither | Both, or neither. Nothing is installed on its own |

### The flow

1. The skill runs `run-tools.sh list --json`.
2. It shows checkboxes (`AskUserQuestion` with `multiSelect`). Each option carries the title, the URL and the state in
   its description ("already up", "configuration missing in `custom/config/...`").
3. It runs `run-tools.sh up` with the ticked tools.
4. It ends with a table: tool, URL and state.

**Checkbox limit:** each question takes at most 4 options, and each call takes up to 4 questions. With five tools per
machine, the list is split into questions by kind, up to 16 tools:

| Question | Options |
| --- | --- |
| Observability and consoles | `observability`, `azurite-console`, the machine's container console |
| Simulators | `login-simulator`, `safe-browsing-simulator` |

## 6. What changes in the product

| File | Change |
| --- | --- |
| `tools/compose.yaml` | New: the root compose file |
| `tools/*/compose.yaml` | The `x-run-tools` extension on each service; configuration paths with defaults in `custom/` |
| `scripts/run-tools.sh` and its suite | New, with tests for detection (Docker CE, Colima, none), missing configuration and busy port |
| `rules/skills/run-tools/` | New |
| README, `tools/README.md`, usage guide | "How to start the tools" becomes `/run-tools`. The quick start gains the observability step through the skill |

Nothing writes in the installed read-only core: builds go to the outputs each tool's git ignores.

## 7. Decisions

- Ticking starts a tool. Unticking a tool that is up stops nothing; stopping is an explicit request
  (`/run-tools --down`).
- The group name in the console is `claude-cli-agents-tools`.
- The consoles stay machine services, started by `/run-tools`, outside the compose group.
- Each tool keeps its own compose file; the root file only includes them.
