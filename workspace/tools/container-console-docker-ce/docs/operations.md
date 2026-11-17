# `container-console-docker-ce` operations

- [Install, update and remove](#install-update-and-remove)
- [The unit and the launcher](#the-unit-and-the-launcher)
- [Configuration](#configuration)
- [Files and logs](#files-and-logs)
- [Monitoring](#monitoring)
- [Common failures](#common-failures)

Guide for whoever operates the tool, who is the same person who uses it. Local tool: no cloud, no server, no infrastructure cost. No alerts.

## Install, update and remove

| Task | Command, in the `tools/container-console-docker-ce` folder |
| --- | --- |
| Install or update the console | `make install`, with Node 24 on `PATH` (running it again is safe) |
| Only build, without installing | `make build` and `.data/bin/container-console-docker-ce` |
| Check the build | `make check` |
| Remove the console | `bash linux/uninstall-console.sh` |

The installer refuses to overwrite a unit or a launcher with the same name that it did not write, recognized by the comment `Installed by container-console-docker-ce`. The uninstaller undoes only what the installer wrote and does not touch Docker, the containers, the log, the list of Compose projects or `~/.config/container-console-docker-ce/env`.

## The unit and the launcher

| Piece | When it runs | What it does |
| --- | --- | --- |
| `container-console-docker-ce.service` (`systemd --user`) | From the login to the graphical session on (`WantedBy=graphical-session.target`, `Restart=on-failure`) | Keeps the service on `127.0.0.1:27850`. If the process fails, systemd starts it again |
| `container-console-docker-ce.desktop` | When you click the launcher | Runs `systemctl --user start container-console-docker-ce.service` and opens the address with `xdg-open` |

- The unit starts from the graphical session because the file dialog needs `DISPLAY` or `WAYLAND_DISPLAY`, which the session exports to the user manager.
- `KillMode=process`: restarting the service sends no signal to the CLIs in progress. The job record is lost, and a CLI that still writes output may end with the pipe closed. After a restart, check the real state in the list.
- Docker does not depend on the console: `dockerd` starts with the system, and Grafana comes back with it on its own, through the `restart: unless-stopped` policy of `tools/observability`.

## Configuration

The service reads `CONSOLE_*` variables at startup. An invalid value prevents the start and is listed on standard error. All of them have a default; the installation sets none.

To try a variable, stop the unit with `systemctl --user stop container-console-docker-ce.service` and run the binary by hand (`CONSOLE_MAX_TERMINALS=2 .data/bin/container-console-docker-ce`). To keep a variable, write `VARIABLE=value`, one per line, in `~/.config/container-console-docker-ce/env`, and run `systemctl --user restart container-console-docker-ce.service`.

Network, context and paths:

| Variable | Default | Note |
| --- | --- | --- |
| `CONSOLE_LISTEN` | `127.0.0.1:27850` | The host can only be `127.0.0.1`; any other address prevents the start |
| `CONSOLE_DOCKER_HOST` | `unix:///var/run/docker.sock` | Must start with `unix://` |
| `CONSOLE_KUBE_CONTEXT` | Empty | Empty passes no `--context`, and the current kubeconfig context applies |
| `CONSOLE_STATE_DIR` | `$XDG_STATE_HOME/container-console-docker-ce`, or `~/.local/state/container-console-docker-ce` | List of Compose projects |
| `CONSOLE_LOG_FILE` | `console.log` in `CONSOLE_STATE_DIR` | Truncated at every start |
| `CONSOLE_PATH_PREPEND` | Empty | Folders placed in front of the inherited `PATH` |
| `CONSOLE_DOCKER_BIN`, `CONSOLE_KUBECTL_BIN`, `CONSOLE_ZENITY_BIN` | Bare name (`docker`, `kubectl`, `zenity`) | Bare name or absolute path |

Deadlines (a duration, such as `90s` or `5m`):

| Variable | Default |
| --- | --- |
| `CONSOLE_TIMEOUT_READ` | `5s` (queries) |
| `CONSOLE_TIMEOUT_DOCKER_ACTION` | `90s` |
| `CONSOLE_TIMEOUT_DOCKER_PULL` | `30m` |
| `CONSOLE_TIMEOUT_COMPOSE_ACTION` | `15m` |
| `CONSOLE_TIMEOUT_KUBE_ACTION` | `2m` |
| `CONSOLE_TIMEOUT_FILE_PICKER` | `5m` |
| `CONSOLE_TIMEOUT_PROCESS_WAIT` | `5s` |
| `CONSOLE_TIMEOUT_HTTP_HEADER` | `5s` |
| `CONSOLE_TIMEOUT_HTTP_READ` | `30s` |
| `CONSOLE_TIMEOUT_HTTP_IDLE` | `60s` |
| `CONSOLE_TIMEOUT_WS_WRITE` | `5s` |
| `CONSOLE_TIMEOUT_SHUTDOWN` | `10s` |

Pace of the live topics and limits:

| Variable | Default |
| --- | --- |
| `CONSOLE_INTERVAL_ENVIRONMENT`, `CONSOLE_INTERVAL_KUBERNETES` | `1s` |
| `CONSOLE_INTERVAL_DOCKER_SYNC` | `5s` |
| `CONSOLE_INTERVAL_DOCKER_DEBOUNCE` | `150ms` |
| `CONSOLE_INTERVAL_EVENTS_RETRY` | `2s` |
| `CONSOLE_MAX_BODY_BYTES` | `1048576` (1 MiB) |
| `CONSOLE_MAX_HEADER_BYTES` | `65536` |
| `CONSOLE_WS_READ_BYTES` | `65536` |
| `CONSOLE_MAX_TERMINALS` | `8` |
| `CONSOLE_JOBS_KEPT` | `50` |
| `CONSOLE_JOB_OUTPUT_LINES` | `200` |
| `CONSOLE_REPLICAS_MAXIMUM` | `1000` |

## Files and logs

| What | Where |
| --- | --- |
| Service log (JSON, with no terminal content and no container logs) | `~/.local/state/container-console-docker-ce/console.log` |
| Service start errors, such as a busy port | `journalctl --user -u container-console-docker-ce.service` |
| Installed binary | `~/.local/bin/container-console-docker-ce` |
| Known Compose projects (name and path) | `~/.local/state/container-console-docker-ce/compose-projects.json` |
| Unit | `~/.config/systemd/user/container-console-docker-ce.service` |
| Optional variables | `~/.config/container-console-docker-ce/env` |
| Launcher | `~/.local/share/applications/container-console-docker-ce.desktop` |
| Icon, an unchanged copy of `web/public/favicon.png` | `~/.local/share/container-console-docker-ce/favicon.png` |
| Grafana data | `tools/observability/.data/` (bind mount) |

## Monitoring

- Service health: `curl -s http://127.0.0.1:27850/healthz` returns `{"status":"ok"}`.
- Unit: `systemctl --user status container-console-docker-ce.service`.
- Docker: `systemctl status docker` and `docker info`.
- Kubernetes: `kubectl config current-context` and `kubectl get --raw /version`.
- Grafana: <http://localhost:3000>.

## Common failures

| Symptom | Likely cause | What to do |
| --- | --- | --- |
| The launcher opens the browser, but the page does not load | The unit did not start: busy port or start error | Read `journalctl --user -u container-console-docker-ce.service`. If the unit does not exist, run `make install` |
| The screen shows the environment as off | `dockerd` does not answer on the socket | Run `sudo systemctl start docker`. The console never runs that command, because it requires root |
| The screen shows the environment as unknown, with `permission denied` | The user is not in the `docker` group, or the session predates joining it | `sudo usermod -aG docker $USER` and log in again |
| The screen shows the environment as unknown, with a missing binary as the reason | `docker` is not on the unit's `PATH` | Set `CONSOLE_PATH_PREPEND` or `CONSOLE_DOCKER_BIN` |
| Docker actions unavailable with Docker on | A socket different from the configured one | Check `CONSOLE_DOCKER_HOST` and the output of `docker context ls` |
| Docker comes back on its own after `sudo systemctl stop docker` | `docker.socket` is still active, and the console's `docker info` read reactivates the daemon | To keep it stopped: `sudo systemctl stop docker.socket docker.service` |
| Kubernetes unavailable | No cluster answers in the context used | Check `kubectl config current-context` and `CONSOLE_KUBE_CONTEXT`. The screen shows the error and keeps trying |
| `kubectl` says the context does not exist | `CONSOLE_KUBE_CONTEXT` points to a name outside the kubeconfig, or the unit reads another kubeconfig | `kubectl config get-contexts`. A non-default `KUBECONFIG` goes in `~/.config/container-console-docker-ce/env` |
| "Choose file" fails with `Failed to open display` | The unit started without the graphical session variables | In a terminal of the session: `systemctl --user import-environment DISPLAY WAYLAND_DISPLAY` and `systemctl --user restart container-console-docker-ce.service`. The path field keeps working |
| "Choose file" fails with a missing binary | `zenity` is not installed | Install the `zenity` package or set `CONSOLE_ZENITY_BIN`. The path field keeps working |
| `docker pull` fails with `docker-credential-*: executable file not found` | `credsStore` in `~/.docker/config.json` points to a program that does not exist on this machine | Remove the key or point it to an installed helper |
| Port 3000, 4317 or 4318 busy when Grafana starts | Another stack uses the port | Stop the other stack |
| The launcher does not show up in the menu after `make install` | The menu has not read the launcher folder yet | `update-desktop-database ~/.local/share/applications` and, if it persists, log in again |
