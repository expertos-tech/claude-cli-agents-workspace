# `tools-hub`: the tools page and the workspace icon in the menu

Status: approved design. Depends on `run-tools.md`. Request: `maintainers/requests/tools-hub.md`.

## 1. Goal

- A new tool, `tools-hub`: one page with a card per tool. The icon is always the workspace icon, one for the whole hub.
  - **[Active]:** the tools that are up, with the card enabled.
  - **[Inactive]:** the tools that are not up, each with an **Activate** button.
- The Docker CE and Colima consoles can be activated only when installed. When they are not, the page asks to install
  them first.
- The hub puts an item with the workspace icon in the system menu.
- On Windows, the hub does only that: the menu item.
- The icon always goes to the user's folders, with no administrator and no `sudo`. On macOS, for example, it goes to
  `~/Applications`, not `/Applications`.

## 2. Where it fits

The hub is the graphical side of `/run-tools`. Both use the same script, `scripts/run-tools.sh` (`list --json`, `up`,
`down`), and the same metadata (`x-run-tools` in each tool's compose file). A new tool shows in both places just by
joining the single compose file, and there are never two sources of truth about what is up.

| Piece | Role |
| --- | --- |
| `tools/compose.yaml` | Joins the container tools in one group (`run-tools.md`) |
| `scripts/run-tools.sh` | Detects, lists, starts and stops the tools; tags the rollback before the build |
| `/run-tools` | The same, through the conversation with Claude |
| `tools/tools-hub` | The same, through the page and the menu icon |

## 3. The page

Same look as the container console: the dark bar with the icon and "Claude CLI Agents Workspace", and its palette,
fonts, cards and buttons, in light and dark themes.

**[Active]:** a card per tool that is up, with the workspace icon, the name, the description, the URL and the state.
The card opens the tool in a new tab.

**[Inactive]:** a card per stopped tool, with the workspace icon dimmed and the **Activate** button. What the button
does depends on the case:

| Case | Button | What happens |
| --- | --- | --- |
| Container tool, configuration complete | Activate | `run-tools.sh up <id>`; the card shows progress and moves to [Active] once the tool is healthy |
| Container tool, configuration missing (for example `custom/config/login-simulator/config.json`) | Activate, disabled | The card says what is missing and where |
| Machine console, installed and stopped | Activate | Starts the service (`systemctl --user start` or `launchctl kickstart`) |
| Machine console, not installed | **Install** | Shows what will be installed (service, shortcut, folders, always the user's) and asks for confirmation. Once installed, the button becomes Activate |
| Console that does not match the machine's engine (Colima on Linux, Docker CE on macOS) | not shown | — |

An active card has a discreet **Deactivate** button, which asks for confirmation.

The page refreshes itself every few seconds, like the console, and through the same call shows what was started or
stopped outside it, for example by `/run-tools`.

## 4. How the hub runs

- **User service**, like the consoles: `systemd --user` on Linux and WSL, a LaunchAgent on macOS. It starts at login
  and listens on `127.0.0.1:27800` only.
- **Not a container:** it installs and starts the consoles, which are machine services, and calls `docker compose`.
  From inside a container this would need the Docker socket and the host's systemd.
- **Implementation:** Go with a React and Vite page, in the same structure as the console. It reuses the console's
  action protection (`CrossOriginProtection` and the `Origin` check) and styles.
- **Closed actions:** the page only activates, deactivates or installs an id that `run-tools.sh list` returned. No free
  command passes through the page.
- **Read-only workspace:** the binary and the built page go to the tool's git-ignored outputs (`.data/`, `dist/`),
  which stay writable in the read-only install (`distribution.md`, section 4).

## 5. The icon in the system menu

The menu item is named **Claude CLI Agents Workspace** and uses the workspace icon (`assets/icon.png`). A click starts
the hub when it is stopped and opens the page in the default browser. Everything stays in the user's folders:

| System | Where | How |
| --- | --- | --- |
| Linux | `~/.local/share/applications/claude-cli-agents-workspace.desktop`, icon in `~/.local/share/icons/` | `Exec` starts the service and opens `http://127.0.0.1:27800`, like the Docker CE console shortcut |
| macOS | `~/Applications/Claude CLI Agents Workspace.app` | A minimal app that starts the LaunchAgent and opens the page, like the Colima console app |
| Windows | The user's Start menu: `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Claude CLI Agents Workspace.lnk`, with an `.ico` next to it | Created from inside WSL through `powershell.exe` (WSL interop), with no administrator. The shortcut runs `wsl.exe -d <distro> -- systemctl --user start tools-hub` without a window and opens `http://localhost:27800`. WSL2 forwards `localhost` to Windows |

**On Windows, the hub only creates the shortcut.** The hub, the tools and Docker run in WSL. Windows only gets the
menu item, which opens the page in its browser.

**WSL prerequisite:** systemd enabled (`[boot] systemd=true` in `/etc/wsl.conf`). Without it, the installer warns and
the shortcut calls the binary directly instead of `systemctl`.

**Uninstall:** an `uninstall` per system removes only what the installer marked as its own, as the consoles do.

## 6. Which tools show

| Tool | Shows? | Click on the card |
| --- | --- | --- |
| `observability` | yes | Grafana, `http://localhost:3000` |
| `login-simulator` | yes | the logout page, which lists the users |
| `azurite-console` | yes | `http://127.0.0.1:28091` |
| `safe-browsing-simulator` | yes | No page, only an API. The card shows the API URL and the state, and opens the tool's README |
| `container-console-docker-ce` or `-colima` | the machine's one | `http://127.0.0.1:27850` (docker-ce) or `http://127.0.0.1:17850` (colima) |
| `claude-usage`, `fable-alert` | no | Command line and plugin; they do not start |
| `tools-hub` | no | It is the page itself |

**Icon:** one, the workspace's (`assets/icon.png`), in the system menu, the favicon and every card. Tools have no own
icon; cards differ by the tool's name, description and URL.

## 7. The hub also manages the workspace

Besides the tools, the page has a **Workspace** area, and the `/workspace` skill does the same through the
conversation. Both only read state and call the one program that changes the core: `aiwp` (`distribution.md`).

### What it shows and does

| Area | Shows | Actions |
| --- | --- | --- |
| Version | The installed version (`VERSION`) and the newest published one; the `CHANGELOG.md` notes between them | **Update**, **Back to the previous version** |
| Integrity | Whether a core file differs from the manifest or has the wrong permission | **Repair**, which restores from the copy of the installed version |
| Custom layer | Whether it exists, its remote, commits not pushed yet | **Push**, a request of the person, valid for that push only |
| Projects | The projects of `custom/projects.md`, the marker version of each (`normalize-projects.md`), the checkout branch and the clones open in `tmp/work/` | Opens the normalization request; never normalizes on its own |
| Tools | Sections 3 and 6 | Activate, deactivate, install |

### How it knows a new version exists

- `git ls-remote --tags` on the public repository, which needs no token and has no GitHub API rate limit. Tags are
  `vX.Y.Z`.
- The hub checks once a day and keeps the result in `.history/`. Offline, it shows the last check and its date.
- The request carries only what `git` itself sends to GitHub. No data of the user, the custom layer or the projects
  leaves the machine.

### How it updates a read-only core

Only `aiwp` writes in the core. The hub, the skill and the session never edit a core file: the `deny Edit` rules, the
555 permission and `guard-bash` (which refuses `chmod` and `chown` on the core) apply to all of them. An update takes
four steps:

1. **Download without touching the workspace.** The installation in the user's data folder (writable) fetches the new
   tag. The new version is assembled in `tmp/update/<version>/`, with the new manifest.
2. **Check.** Checks the hashes of the new manifest, and the current manifest against the installed files. A core file
   that differs from the manifest, which only happens when someone changed the permission by hand, stops the update and
   shows under Integrity.
3. **Swap, with a guaranteed way back.**
   - The files about to change are copied to `tmp/update/backup-<current version>/`.
   - Write permission is given back only to the folders and files touched.
   - Each file is swapped by rename: the new one is written next to it and renamed over it. A script or hook already
     running keeps reading the old version until it ends, because the process keeps the file open.
   - Files that left the new version are deleted, and permissions go back to 555 and 444.
   - A journal (`tmp/update/journal`) records each step. If the process dies halfway, the next `aiwp` run rolls back
     from the backup before anything else.
4. **After.**
   - Rebuilds the machine tools that changed: the hub and the console.
   - Restarts their services.
   - Says that open Claude sessions keep the old rules until reopened.
   - Lists what the new version asks of the custom layer and of the projects: the `/normalize-projects` migrations.

**Back to the previous version** takes the same path from the backup. Only the backup of the last version is kept,
until the next update, like the Docker rollback tag.

### The hub updating itself

The hub is part of the core, so an update replaces its own program. The page therefore never runs `aiwp update` inside
the hub's process:

- **Separate process:** the update runs in its own process (`systemd-run --user` on Linux and WSL, a `launchctl` job
  on macOS), which survives the hub's restart.
- **Progress:** kept in the journal. The page loses the connection for a few seconds, reconnects to the new hub and
  keeps showing the progress from the journal.

### The `/workspace` skill

| Command | Does |
| --- | --- |
| `/workspace` | The same board as the page: version, integrity, custom layer, projects, tools |
| `/workspace update` | Shows the notes of the new version and asks for confirmation before running `aiwp update` |
| `/workspace rollback` | Asks for confirmation before going back to the previous version |

- **Mandatory question:** `guard-bash` asks before `aiwp update`, `aiwp rollback` and `aiwp repair`, as it does for
  `release` and `apply`. Even in auto mode, the core is never swapped without the person.
- **When done:** the skill says the current session keeps the old rules and asks the person to open a new session.

## 8. Risks

- **Installing from the page needs build tools.** The consoles are built on the machine, with Go and Node. Without
  them, the Install button says what is missing. Shipping prebuilt binaries in the GitHub releases would solve it; it
  is out of scope for now.
- **A page that triggers actions on the machine.** A local page that installs and starts services is a target for any
  site open in the same browser. Hence: `127.0.0.1` only, origin protection on every action, closed ids and
  confirmation before installing. The console's protection code is reused, not rewritten.
- **WSL and Windows.** `powershell.exe` must be reachable from inside WSL (the default). A distribution with another
  name needs the right `-d <distro>` in the shortcut; the installer records the current distribution name.

## 9. Changes in the product

| File | Change |
| --- | --- |
| `tools/tools-hub/` | New tool: Go service, page, `linux/`, `macos/` and `windows/` installers (the last one is only the shortcut, a `.ps1` called from inside WSL), README and tests |
| `scripts/run-tools.sh` | What `run-tools.md` describes, plus the "not installed" state of the consoles and the install action |
| `tools/*/compose.yaml` | Title, description and URL in `x-run-tools` |
| `tools/README.md` | The hub's row and port 27800 |
| README, quick start | The hub as the recommended way to start the tools, and the note that on Windows only the shortcut is native |

Order: first `run-tools.sh` and `/run-tools`, then the hub on top of them.

## 10. Decisions

- Port 27800, next to the docker-ce console's 27850.
- The hub starts at login, like the consoles: it is light, and the page is always ready.
- Active tools have a Deactivate button, with confirmation. In `/run-tools`, stopping stays an explicit request.
- Tools without a page (`safe-browsing-simulator`) show in the hub with the API URL.
- The consoles keep their own menu shortcut, besides the workspace item.
- The hub and `/workspace` manage the workspace (version, integrity, custom layer, projects, tools), delivered in two
  steps: version and update first, then the rest.
- The version check runs automatically once a day.
- Only the backup of the last version is kept.
