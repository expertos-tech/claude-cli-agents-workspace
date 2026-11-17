# container-console-colima

- [What it is](#what-it-is)
- [How to run](#how-to-run)
- [How to test](#how-to-test)
- [How to uninstall](#how-to-uninstall)
- [How to deploy](#how-to-deploy)

## What it is

A local, in-browser console for the container environment of a Mac with Colima: it shows and controls the Colima VM, turns its Kubernetes on and off, and manages containers, images, volumes, networks, Compose projects and Kubernetes resources, with live logs and a terminal. It is the macOS/Colima twin of [`container-console-docker-ce`](../container-console-docker-ce/README.md), with the same visual identity: the Claude CLI Agents Workspace project icon and name in the top bar, with "Container Console · Colima" below. The screen is in English by default and switches to Brazilian Portuguese when the browser language starts with `pt`.

It is a Go service that listens only on `127.0.0.1:17850`, without login, and serves the React screen embedded in the binary. A Dock icon opens the address in the default browser, and a LaunchAgent starts the service at every login to the graphical session. Single user.

The file dialog is the native macOS one, through `osascript`. The theme follows the operating system by default, and the `Theme` field in the side menu switches between system, dark and light.

## How to run

Prerequisites: macOS with Colima, the `docker` CLI with Docker Compose v2 and `kubectl` (only for the Kubernetes screen), from Homebrew in `/opt/homebrew/bin`; Go (the version in `go.mod`) and Node, which only the build uses.

In the `tools/container-console-colima` folder:

```bash
make install
```

`make install` builds the front-end and the binary and runs `macos/install-console.sh`, which installs:

- the binary in `~/Library/Application Support/container-console-colima/bin`;
- the LaunchAgent `io.github.expertos-tech.claude-cli-agents-workspace.container-console-colima` in `~/Library/LaunchAgents`, loaded right away because of `RunAtLoad`;
- the app `~/Applications/Container Console (Colima).app`, with the project icon (`web/public/favicon.png`);
- the app in the Dock. If this step fails, the script says how to do it by hand and the installation still holds.

When it finishes, it prints `installed <label> and <app path>`. Running it again is safe. The installer refuses to overwrite a plist or an app with the same name that it did not write. Use `--verbose` to see each step.

Then click "Container Console (Colima)" in the Dock or open <http://127.0.0.1:17850/>. The icon wakes the service up if it does not answer and, if it does not come up within 5 s, shows an alert with the logs path (`~/Library/Logs/container-console-colima/`).

To try it without installing: `make build` and `.data/bin/container-console-colima`.

Optional, to start the runtime at login: `runtime/install-runtime.sh --compose-file <absolute path>` installs the LaunchAgent `io.github.expertos-tech.claude-cli-agents-workspace.container-runtime`, which runs `runtime/login-start.sh` at every login. It starts the Colima VM with Kubernetes off (it retries once, after a `colima stop --force`), turns Kubernetes off if it is on, and runs `docker compose up` on the given file. It writes times and durations to `~/Library/Logs/container-console-colima/runtime.log` and shows a macOS notification if it fails. The plist points to `login-start.sh` in this folder: moving the workspace requires a new installation.

Build checks: `make check` (`gofmt`, `go vet`, `go build`, `npm audit --audit-level=high` and `tsc --noEmit`).

## How to test

The runtime scripts have unit tests, with fake `colima`, `docker`, `osascript` and `launchctl` on `PATH`, which do not touch the VM, Docker or launchd. They need macOS `plutil`:

```bash
bash runtime/tests/test-login-start.sh
```

You check the screen and the Dock icon by hand, on the Mac: install, open from the Dock and go through the overview, environment, containers, images, volumes, networks, Compose and Kubernetes screens.

## How to uninstall

```bash
bash macos/uninstall-console.sh
bash runtime/uninstall-runtime.sh
```

The first one removes only what `install-console.sh` wrote: the Dock icon, the app, the LaunchAgent and the binary. It does not touch the runtime LaunchAgent, the VM, the containers, the logs or the list of Compose projects. The second one unloads the runtime LaunchAgent and removes its plist, without stopping the VM or the containers. Both fail, without changing anything, when they find a plist or app with the same name that they did not write.

## How to deploy

Local only, on the Mac: there is no cloud, server or cost. `make install` is the deployment.
