# Functional request: `tools-hub`, the page of the tools and of the workspace

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained, with the product in `workspace/`.
Prerequisites: the 0.1.0 publication (installer, `aiwp` with manifest and read-only core, local data folder) and the
`/run-tools` request delivered (`run-tools.sh` and the `x-run-tools` extensions). Full design:
`maintainers/plans/tools-hub.md`.

## 1. Objective

One local page, with the look of the container console and one icon (the workspace's), to see and activate the tools
and to manage the workspace itself (version, update, integrity). An item in the system menu, always in the user's
folders, opens the page. On Windows, the hub only creates the shortcut; the rest runs in WSL.

## 3. Business rules

- RN-1: `workspace/tools/tools-hub/`: a Go service and a React/Vite page, in the same structure as the console; a user
  service (systemd `--user` on Linux and WSL, a LaunchAgent on macOS), started at login, listening on `127.0.0.1:27800`
  only.
- RN-2: [Active]: a card per tool that is up (workspace icon, name, description, URL, state); the card opens the tool
  in a new tab. [Inactive]: a dimmed card with **Activate**; without configuration, Activate is disabled and says what
  is missing; a console not installed shows **Install** (shows what it installs, asks for confirmation); a console of
  another engine does not show.
- RN-3: active cards have **Deactivate**, with confirmation.
- RN-4: `safe-browsing-simulator` shows, with the API URL and the state; its card opens its README. `claude-usage` and
  `fable-alert` do not show.
- RN-5: the page only activates, deactivates or installs an id that `run-tools.sh list` returned; no free command.
  Origin protection reused from the console (`CrossOriginProtection`, the `Origin` check).
- RN-6: the menu item "Claude CLI Agents Workspace", with the workspace icon: `~/.local/share/applications` (Linux),
  `~/Applications` (macOS), the user's Start menu created from inside WSL through `powershell.exe` (Windows). No
  administrator and no `sudo`. The consoles keep their own shortcut.
- RN-7: the **Workspace** area: installed and newest version (`git ls-remote --tags`, once a day, result kept), the
  notes between them, **Update** and **Back to the previous version**; integrity against the manifest, with
  **Repair**; custom layer (remote, commits not pushed, **Push** on request); projects (version marker, branch, open
  clones).
- RN-8: only `aiwp` writes in the installed core. Update: downloads into the data folder, assembles in `tmp/update/`,
  checks hashes, swaps by rename with backup and journal, back to 555; keeps the backup of the previous version (only
  the last one). The update runs in a separate process (`systemd-run --user`, a `launchctl` job) that survives the
  hub's restart; the page reconnects and shows the progress from the journal.
- RN-9: a `/workspace` skill with the same board and `update`/`rollback`; `guard-bash` asks before `aiwp update`,
  `rollback` and `repair`.
- RN-10: nothing of the repository root (its maintenance) reaches a work workspace.

## 4. Acceptance criteria

- AC-1: Given the hub installed, when the person opens the menu item, then the hub starts if stopped and the page
  opens at `http://127.0.0.1:27800`.
- AC-2: Given an inactive tool with its configuration, when Activate is clicked, then it starts, moves to [Active] and
  the card opens its URL.
- AC-3: Given the machine's console not installed, when Install is clicked and confirmed, then it is installed in the
  user's folders and the button becomes Activate.
- AC-4: Given a request to the page with an id outside the list or with an `Origin` of another site, then it is
  refused.
- AC-5: Given a new release published, when the person clicks Update, then the data folder moves to the new tag, files
  change by rename, permissions go back to 555, the hub restarts and the page shows the end from the journal; Back to
  the previous version restores the backup.
- AC-6: Given the update process killed halfway, when `aiwp` runs again, then it rolls back from the backup before
  anything else.
- AC-7: Given Windows with WSL, when the installer runs, then the shortcut shows in the user's Start menu without
  asking for administrator rights.

## 7. Out of scope

- Icons per tool (decided: one, the workspace's).
- Prebuilt binaries in the releases (the consoles are still built on the machine; the Install button says what is
  missing).

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Service and page: [Active], [Inactive], Activate, Deactivate, Install | high | A local page that triggers actions on the machine |
| 2. Menu item on the three systems, and uninstall | medium | Per-user installers; the consoles' pattern exists |
| 3. Workspace area: version and update (`aiwp` with backup, journal and separate process), `/workspace` and the `guard-bash` questions | high | Swaps the installed core; a destructive step with a way back |
| 4. Workspace area: integrity, custom layer and projects | medium | Reads state and calls existing actions |

The agents of each stage run with the stage's effort, passed in the call.
