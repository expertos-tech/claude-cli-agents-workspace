# container-console-docker-ce

- [What it is](#what-it-is)
- [How to run](#how-to-run)
- [How to test](#how-to-test)
- [How to uninstall](#how-to-uninstall)
- [How to deploy](#how-to-deploy)
- [Documentation](#documentation)

## What it is

A local, in-browser console for the container environment of this Linux machine with docker-ce: it shows the state of the Docker daemon and manages containers (grouped by Compose project), images, volumes, networks, Compose projects and Kubernetes resources, with live logs and a terminal, and it cleans up what no active container uses. The screen is in English by default and switches to Brazilian Portuguese when the browser language starts with `pt`.

It is a Go service that listens only on `127.0.0.1:27850`, without login, and serves the React screen embedded in the binary. A desktop launcher opens the address in the default browser, and the service starts by itself at every login to the graphical session. Single user.

The environment screen is read-only: controlling docker-ce requires root, so the console never starts or stops the daemon. When the daemon is off, the screen says so and shows the command `sudo systemctl start docker` for you to run.

The theme follows the operating system by default, and the `Theme` field in the side menu switches between system, dark and light.

## How to run

Prerequisites: docker-ce with Docker Compose v2 and your user in the `docker` group, `kubectl` (only for the Kubernetes screen), `zenity` (only for the file dialog), `xdg-open`, `systemd --user`, Go (the version in `go.mod`) and Node 24, which only the build uses.

In the `tools/container-console-docker-ce` folder, with Node 24 on `PATH`:

```bash
make install
```

`make install` builds the front-end and the binary and runs `linux/install-console.sh`, which installs the binary in `~/.local/bin`, the `systemd --user` unit `container-console-docker-ce.service` and the launcher `container-console-docker-ce.desktop`, with the Claude CLI Agents Workspace project icon (`web/public/favicon.png`, cropped from the logo in the root `assets/`). When it finishes, it prints `installed container-console-docker-ce.service and <launcher path>`. Running it again is safe.

Then click "Container Console" in the applications menu or open <http://127.0.0.1:27850/>. The launcher wakes the service up if it is stopped.

To try it without installing: `make build` and `.data/bin/container-console-docker-ce`.

There is no login agent for Docker: `dockerd` starts with the system, and the Grafana of `tools/observability` comes back with it on its own, through the `restart: unless-stopped` policy.

Build checks: `make check` (`gofmt`, `go vet`, `go build`, `npm audit --audit-level=high` and `tsc --noEmit`).

## How to test

There are no automated tests: the tool is verified by compiling (`make check`, plus `bash scripts/validate.sh --only secrets` from the workspace root) and by manual tests. The manual tests, with steps and expected results, one block per requirement, are in [`docs/manual-tests.md`](docs/manual-tests.md): the screens, the launcher, the unit and the machine restart.

## How to uninstall

```bash
bash linux/uninstall-console.sh
```

It removes the unit, the launcher, the copied icon and the binary. It does not touch Docker, the containers, the log, the list of Compose projects or `~/.config/container-console-docker-ce/env`.

## How to deploy

Local only, on this machine: there is no cloud, server or cost. `make install` is the deployment.

## Documentation

| Page | Content |
| --- | --- |
| [docs/overview.md](docs/overview.md) | What it is, for whom, scope |
| [docs/architecture.md](docs/architecture.md) | Components and flows |
| [docs/api.md](docs/api.md) | REST and WebSocket contract |
| [docs/operations.md](docs/operations.md) | Configuration, logs and common failures |
| [docs/manual-tests.md](docs/manual-tests.md) | Tests you run, per requirement |
