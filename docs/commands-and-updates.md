# Commands and updates

English · [Português (Brasil)](../i18n/pt-BR/docs/commands-and-updates.md) · [Español](../i18n/es/docs/commands-and-updates.md)

## Commands

| Command | Does |
| --- | --- |
| `aiwp` | Opens the workspace in the current folder: checks for a new release and only says so, then starts `claude` with the arguments you give after `--` |
| `aiwp new <folder>` | Creates a new workspace: copies the product, asks for your custom repository, builds `.claude/`, adds it to the registry |
| `aiwp list` | Lists the registered workspaces with their version and state |
| `aiwp forget <folder>` | Removes a workspace from the registry; never touches the folder |
| `aiwp update` | Lists the registered workspaces and asks: update all, choose which, or cancel |
| `aiwp update --all` | Updates every registered workspace without asking; pinned ones stay as they are |
| `aiwp update <folder>` | Updates only that workspace |
| `aiwp rollback` | Goes back to the version of the newest backup and pins the workspace to it |
| `aiwp repair` | Restores core files that differ from the manifest or have the wrong permission |
| `aiwp check` | Says in one line whether a newer release exists, without updating anything |
| `aiwp version` | Shows the installed version and the workspace's |

## How updates work

There are three places:

| Place | What it is |
| --- | --- |
| This repository | Where the workspace is developed. Releases are tags `vX.Y.Z` |
| Your local data folder: `${XDG_DATA_HOME:-~/.local/share}/claude-cli-agents-workspace` on Linux and WSL, `~/Library/Application Support/claude-cli-agents-workspace` on macOS | The full repository, cloned by the installer. `aiwp` moves it to the newest release tag. Nobody edits it |
| Each workspace you create | A copy of `workspace/` only, plus your `custom/`, `projects/` and `tmp/` |

The data folder keeps `workspaces.json`, the registry of every installed workspace (path, version, created, updated).
`aiwp new` registers a workspace, and the first `aiwp` run in one that is not registered adds it. `aiwp list` shows each
with its state: up to date, update available, core changed, folder missing, pinned, or stopped halfway.

- **Checking:** `aiwp` looks for a new tag (`git ls-remote --tags`) at most once a day, with a 5 s limit. Offline, it
  goes on. When there is a new release it prints "A new workspace version X was detected (this workspace: Y). Run
  `aiwp update` to update; opening this workspace on Y." and opens on the current version. Opening never updates. In a
  session, the session start hook gives the same notice: close the session and run `aiwp update` in a terminal.
- **Updating, only by command, in a terminal, with no session open:** `aiwp update` lists every registered workspace
  and asks `[1] Update all` (the default), `[2] Choose which` (by number) or `[3] Cancel`. It moves the data folder to
  the newest release once, then updates each chosen workspace and ends with a summary table. A workspace whose core
  changed, or whose folder is missing, is skipped and reported; the others go on. `aiwp update <folder>` updates only
  that one; `aiwp update --all` updates all without asking, and leaves pinned workspaces (after `aiwp rollback`) as they
  are; naming a pinned workspace by number or folder updates it and clears the pin. With no terminal, `--all` or a
  folder is required. Before swapping a workspace where `claude` is running, `aiwp update` names the process and asks;
  with `--all` it skips that workspace unless you add `--force`. The exit code is 1 when a workspace was skipped for a
  changed core, a running `claude` or an error.
- **Never inside a session:** from a Claude Code session (its Bash tool, a hook) `aiwp` refuses `update`, `rollback`,
  `repair`, `forget`, the opening and `new` over a registered folder, and `guard-bash` denies them too: they change the
  rules of the open session. `aiwp list`, `check`, `version` and `--help` work anywhere. An unknown command is a usage
  error: arguments for `claude` go after `--`.
- **Read-only core:** the product files in a workspace are read-only (folders and executables 555, files 444), and the
  workspace has no `.git`: `custom/` and each project are the repositories. Writable are only `custom/`, `projects/`,
  `tmp/`, `.claude/`, `.history/` and a closed list of generated tool outputs (the Grafana data, `node_modules`, built
  pages and console binaries). To remove a workspace, give write permission back first:
  `chmod -R u+w <folder> && rm -rf <folder>` (push `custom/` and your projects before).
- **Manifest:** each workspace records the version and the hash of every file it got. An update replaces only what the
  new release changed, deletes what it removed, and skips a workspace whose core differs from the manifest (the update
  shows it in the summary); `aiwp repair` restores it.
- **Backup:** files are swapped by rename, after a backup in `.aiwp/backup/<version>/` (the last 3 are kept), with a
  journal. If an update dies halfway, `aiwp` refuses to open the workspace until `aiwp repair` (or `aiwp update`)
  restores it. `aiwp rollback` returns to the version of the newest backup.
- **Only `workspace/` is installed**, by an inclusion list. Nothing else in this repository ever reaches your
  workspace.
