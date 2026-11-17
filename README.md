# Claude CLI Agents Workspace

<p align="center"><img src="workspace/assets/logo.png" alt="Claude CLI Agents Workspace" width="320"></p>

<p align="center">English · <a href="i18n/pt-BR/README.md">Português (Brasil)</a> · <a href="i18n/es/README.md">Español</a></p>

A workspace for the **Claude Code CLI**. You say **what** you want, and Claude decides **how**, working in an isolated
clone where everything is allowed. The heavy checks and the questions for you happen in one place: the gate that brings
the work into the project's base branch.

> **Made for the CLI.** Hooks, permissions, skills and session names are designed and tested in the terminal Claude
> Code (`claude`). The Claude app (desktop or web) and the IDE extensions can probably open the workspace, but they may
> handle hooks, permissions and commands differently; there, what this page describes is not guaranteed.

## What you get

- **Rules** for the agent: one page that applies to every session (`AGENTS.md`) and rules per subject (git, security,
  quality, docs, frontend, infrastructure, models, review), read when the subject comes up.
- **Skills**: slash commands for the daily flow (`/merge`, `/commit`, `/push`, `/validate`, `/draft-prompt`,
  `/prompt`, `/pilot`, `/local-env`, `/normalize-projects`).
- **Agents**: subagents for requirements, architecture, implementation, tests, review, verification, infrastructure,
  scripts, documentation and research, each with its model and effort.
- **Hooks** that hold only what must never happen without you: git writes outside the gate, cloud changes, database
  deletions, secrets in a commit. [Hooks that run on your machine](#hooks-that-run-on-your-machine) lists them all.
- **A merge gate**: work happens in a clone under `tmp/work/`, and `/merge` brings it to the project's `developer`
  branch after the full test suite, the validations, a secret scan and a review against your request.
- **A custom layer**: your own private git repository in `custom/` for your company, cloud, visual identity, projects
  list, requests and lessons. It never goes into this repository.
- **Tools**: a local Grafana for the Claude Code telemetry, a container console (Docker CE on Linux, Colima on macOS),
  login and Safe Browsing simulators, an Azurite console, a usage report and a model alert. Each one has its README in
  `workspace/tools/`.

## Requirements

- **Linux or macOS.** On **Windows, only through WSL2**: install a Linux distribution (Ubuntu, for example) and do
  everything inside it, with the same layout as on Linux. The workspace, the projects, Docker and `claude` live in the
  WSL file system (`~/...`), never in `/mnt/c`. There is no native Windows version.
- `git`, `bash`, `python3` and Docker.
- The Claude Code CLI installed and logged in: `claude` opens a session.
- **Optional, but important: the observability stack** (`workspace/tools/observability/`, a local Grafana at
  <http://localhost:3000>). It shows what each session costs in tokens, time and model; without measurement there is no
  way to know whether a rule change made the work better or worse.
- **Recommended: [Claude in Chrome](https://claude.com/chrome)**, the extension that lets Claude open pages in your
  Chrome, click, read the console and take screenshots, so it can check layouts and screen flows by itself
  (`/pilot auto`). It does not work inside WSL: on Windows, those tests stay with you (`/pilot manual`).

## Quick start

### 1. Install and create the workspace

```bash
curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash
```

`curl | bash` runs whatever the script holds at that moment. To read it before running it:

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh
less install.sh
bash install.sh
```

The installer checks the prerequisites and says what is missing, without installing anything on its own. It clones
the repository into your local data folder at the newest release tag, puts the `aiwp` command in `~/.local/bin`, and
then creates your workspace with `aiwp new` and adds it to the registry of workspaces. It needs no administrator
rights and no `sudo`.

It asks where the workspace goes, on the terminal (it works under `curl | bash`), by the folder it runs in:

- **An empty folder:** `1) Install here` or `2) Give another path`.
- **A folder with content:** only the path, of a new or empty folder. A bad answer is asked again.

`aiwp new` then asks for the URL of your custom repository: create an empty private repository on your git server and
give its URL. An empty repository gets a skeleton and a first commit; an empty answer starts a local repository.

To skip the questions, give the folder:

```bash
curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash -s -- ~/my-workspace
AIWP_WORKSPACE=~/my-workspace bash install.sh
```

The argument wins over `AIWP_WORKSPACE`. With no terminal and no folder, the installer installs only the data folder
and prints how to create a workspace later (`aiwp new <folder>`). Running the installer again updates the data folder
and never a workspace: `aiwp update` does that. When the data folder is installed already, the question also offers
to only update it (`3)`, or an empty path).

### 2. Create another workspace

```bash
aiwp new ~/other-workspace
```

Each workspace is a copy of the product in its own folder, and all of them share the installation in the data folder.

### 3. Open it

```bash
cd ~/my-workspace && aiwp
```

`aiwp` checks for a new release and, when there is one, says so and tells you to run `aiwp update`; it never updates.
Then it starts `claude` on the workspace's current version. Always open the session
at the workspace root, even to work on one project: that is where the rules and the hooks apply. The Claude Code auto
mode is recommended: the workspace leaves the judgment of what is destructive to it and keeps in hooks only what must
never happen.

### 4. Bring a project and ask

```bash
git clone <your project url> projects/my-app
git -C projects/my-app switch developer
```

Then, in the session:

```text
in my-app, add a GET /health endpoint that answers 200 with the application version
```

Claude asks only what blocks the start, opens a clone in `tmp/work/<date>-<subject>/my-app/`, tells you the path and
works only there, with tests. Each commit goes to the remote after a secret scan. When it is done:

```text
/merge <date>-<subject>/my-app
```

The gate brings the updated `developer`, runs the whole suite and the validations, scans for secrets, shows what leaves
the base and asks for a review against your request. You are asked only if something shows up that the request does
not explain. For larger requests, write the request with `/draft-prompt` and run it with `/prompt`. The full guide is
[workspace/docs/usage.md](workspace/docs/usage.md).

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

## Hooks that run on your machine

The workspace runs these hooks in every session opened in a workspace (`workspace/rules/agents/settings.json`). They
are scripts in `workspace/scripts/`; each prints its full reference with `--help`. Anything they do not cover follows
the Claude Code permission mode you chose.

| Hook | When | What it does |
| --- | --- | --- |
| `guard-bash.sh` | Before every Bash command | Denies git writes in `projects/` and in the core outside the gate, Terraform changes outside `aiwp-cmds.sh apply`, `git push --no-verify`, a commit in `custom/` that carries a `.env` or a secret, `chmod`, `chown` or `git init` on core paths, and `aiwp update`, `rollback`, `repair`, `forget` and the opening inside a session (they change the rules of the open session or start `claude` inside it). Asks before deleting a database or a Docker volume, before a release, an apply or a discarded clone, and before git configuration that can run a command. It is a speed bump with your confirmation behind it, not a sandbox |
| `guard-subagent-model.sh` | Before every subagent call | Denies forks and models outside the allowed list, asks before a Fable subagent, and sets a model on a call that would inherit one |
| `setup-claude.sh` | Session start | Builds the git-ignored `.claude/` from the product rules, skills and agents plus your custom layer |
| `release-notice.sh` | Session start | Runs `aiwp check` (one answer per day, a short timeout, silent offline) and, when a newer release exists, has Claude tell you to close the session and run `aiwp update` in a terminal. It never updates anything |
| `prompt-log.py` | Session start | Records your prompts from the session transcripts in `custom/prompts/log/`, by project and week, and shows a summary of the last day. It never pushes |
| `session-title.py` | Each prompt you send | Names the session after the project on `/prompt` (`my-app-1`, `my-app-2`...), and reminds the session when a project you name is not normalized or is behind the workspace version |
| `aiwp-cmds.sh _stop-check` | When Claude ends an answer | Keeps the answer from ending with a commit that is only on your machine in a work clone |

Secret scans use gitleaks in Docker. No hook sends data anywhere: the only network calls are git's own, to your
remotes and to this repository's tags.

## The custom layer

`custom/` is **your** private git repository, separate from the product, and the only place for what belongs to you:
company name and spelling, cloud and tenant, visual identity, the list of your projects, written requests, lessons,
filled `.env` files (`custom/env/`, always git-ignored) and the prompt log. The workspace works without it and asks,
when it needs to, for the cloud, the visual identity and the folder of each project. It never goes into a pull request
to this repository.

## Repository layout

| Path | What it is |
| --- | --- |
| `workspace/` | The product: `AGENTS.md`, `rules/`, `scripts/`, `tools/`, `docker/`, `docs/`, `assets/`, `templates/`, `VERSION`, `CHANGELOG.md`. This is what gets installed |
| `CLAUDE.md`, `.claude/` | The maintenance of the repository, at its root: the process, rules, skills and agents for whoever maintains the product, and the settings that keep the product's rules out of that session |
| `tests/` | The repository's suite (`check.sh`) and the test installation |
| `maintainers/` | The maintainers' work, in the open: backlog, plans, requests and reviews |
| `i18n/` | Translations of the documents and READMEs (`pt-BR`, `es`), with the same structure as the repository |
| `install.sh` | The installer |
| `tmp/` | Git-ignored scratch: test installations and private notes |

## Get involved

This workspace grew out of daily use: getting things wrong, measuring and simplifying. It gets better with every person
who uses it on a real project.

Found a better way to do something? Fixed a defect? Wrote a hook that saves questions, a clearer rule, a useful tool?
**Share it.** Fork the repository, make your change and send a pull request.

- **Bug or idea:** open an issue with what happened, what you expected and how to reproduce it.
- **Change:** a fork, a branch, and a small, focused pull request that says why, not only what.
- **Maintain from the repository root:** clone this repository and open `claude` at its root. The root `CLAUDE.md`
  and `.claude/` give that session the maintenance process (plan, request, stages, tests, review) and keep the product
  rules out of it, because there they are the code being edited.
- **Before sending:** `bash tests/check.sh --all` passes. It runs the lint, the secret scan, the script suites
  and the check that keeps company data out of the repository.
- **Translations:** a change to an English document updates its translations in `i18n/pt-BR/` and `i18n/es/` in the
  same commit.
- **What is yours stays with you:** company, projects, visual identity and requests stay in your custom layer, never in
  the pull request.
- **New rule:** prefer a hook or a tested script to more text, and say what the change adds to or removes from every
  session (a step, a question, loaded text).

## License

[MIT](LICENSE).
