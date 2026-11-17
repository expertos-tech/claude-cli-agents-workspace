# Claude CLI Agents Workspace

<p align="center"><img src="assets/logo.png" alt="Claude CLI Agents Workspace" width="320"></p>

A workspace to develop with the **Claude Code CLI**: you say **what** you want, and Claude decides **how**, working in an isolated clone where everything is allowed. The heavy checks and the questions for you stay in one place: the gate that takes the work to the project's base.

> **Made for the CLI.** Hooks, permissions, skills and session names were designed and tested in the terminal Claude Code (`claude`). The Claude app (desktop or web) and the IDE extensions can probably open the workspace, but they may handle hooks, permissions and commands differently; there, what this README describes is not guaranteed.

## Get involved

This workspace grew out of daily use: making mistakes, measuring and simplifying. It gets better with every person who uses it on a real project.

Found a better way to do something? Fixed a bug? Wrote a hook that saves questions, a clearer rule, a useful tool? **Share it** as a pull request to the product repository (its README explains how).

- **Bug or idea:** open an issue with what happened, what you expected and how to reproduce it.
- **What is yours stays with you:** company, projects, visual identity and requests live in your custom layer (`custom/`), never in a pull request.
- **A new rule:** prefer a hook or a tested script to more text, and say what the change adds to or removes from every session (a step, a question, loaded text).

## Quick start

From zero to the first merged work, in six steps.

**What you need:**

- **Linux.** On Windows, only through **WSL2**: install a Linux distribution (Ubuntu, for example) and do everything inside it, with the same layout as on Linux. The workspace, the projects, Docker and `claude` live in the WSL file system (`~/...`), never in `/mnt/c`. There is no native Windows version.
- The Claude Code CLI installed and logged in: `claude` opens a session.
- `git`, Docker Engine, `bash` and `python3`.
- **Optional, but very important: the observability stack** (`tools/observability/`, a local Grafana on <http://localhost:3000>). The workspace works without it, but it is what shows what each session costs, in tokens, time and model, and `scripts/performance/measure.py` only measures with it up. Without measuring, there is no way to know whether a change to the rules made the work better or worse. Start it once and follow its README to turn on the Claude Code telemetry.
- **Recommended: [Claude in Chrome](https://claude.com/chrome)**, the extension that lets Claude open pages in your Chrome, click, read the console and take screenshots. With it, Claude checks layouts and screen flows on its own, as a person would by hand (`/pilot auto`). Install the extension in Chrome and connect it to the session with `/chrome` ([how to use it](https://code.claude.com/docs/en/chrome)). It does not work in WSL: on Windows, those tests stay with you (`/pilot manual`).

### 1. Create your workspace

The installer of the product repository (its README) installs the `aiwp` command and creates your workspace: it asks
for the folder, which must be new or empty (or takes it as an argument or in `AIWP_WORKSPACE`). To create another one:

```bash
aiwp new ~/my-workspace
cd ~/my-workspace
```

The core of the workspace is read only, and the workspace root is not a git repository: `custom/` and each project are the repositories. Every workspace is listed in the registry of the data folder (`aiwp list`; `aiwp forget <folder>` removes an entry and never touches the folder). New releases arrive only by command: `aiwp update`, in a terminal with no session open, lists the registered workspaces and asks to update all, choose which, or cancel; it replaces only the core files that changed, and your `custom/`, `projects/` and `tmp/` are never touched. `aiwp` only says when a new release exists. When a session starts and a new release exists, Claude tells you; close the session and run `aiwp update` in a terminal (Claude never runs it: it changes the rules of the open session).

To remove a workspace, give write permission back first, since the core is read only: `chmod -R u+w <folder> && rm -rf <folder>`. Your custom layer and projects go with it: push them first.

### 2. Connect your custom layer

The custom layer is a **private repository of yours** that holds what belongs to nobody else: your company, the cloud and the tenant, the visual identity, the list of your projects, the written requests, the lessons, the backlog, your own tools (`custom/tools/`) and the filled `.env` files (`custom/env/`, never committed). Create an empty repository on your git server: `aiwp new` asks for its URL (or takes it with `--custom <url>`) and clones it into `custom/`; an empty repository gets a skeleton and a first commit.

Just want to try it out? Leave the URL empty: `aiwp new` creates a local repository with the skeleton, and you can give it a remote later (`git -C custom remote add origin <url>`). What goes in the layer is in `rules/rules.md`, section "Custom layer".

### 3. Bring in a project

A project that already exists, in the session (step 4): `/normalize-projects --from <url of your project or its folder> --name my-app`. It clones the project into `projects/my-app` and normalizes it (how it goes: [docs/usage.md](docs/usage.md), "Projects"). A project you clone by hand, or a POC you move into `custom/pocs/`, works too: the session warns that it is not a workspace project yet and asks to normalize it.

`developer` is the work base; the normalization creates it when the remote lacks it, after asking. A new project: `bash scripts/init-repo.sh --type project --name my-app`, already marked as a workspace project.

### 4. Open the session at the root

```bash
aiwp
```

`aiwp` checks for a new release (it never updates), runs `scripts/setup-claude.sh` and starts `claude`; arguments for `claude` go after `--`.

Always at the workspace root, even to work on a project: that is where the rules and hooks apply. Recommended: Claude Code's auto mode. The workspace leaves to it the judgment of what is destructive and keeps in hooks only what must never happen. Claude replies in the language you write in.

### 5. Ask

```text
in my-app, create a GET /health endpoint that answers 200 with the application version
```

Claude asks only what keeps it from starting and opens a clone in `tmp/work/<date>-<subject>/my-app/`. It says the path and works only there, with tests. Each commit goes to the remote by itself, after a secret scan.

### 6. Take it to the base

```text
/merge <date>-<subject>/my-app
```

Without an argument, `/merge` takes the clone of this session. The gate brings `developer` up to date, runs the whole suite and the validations, looks for secrets, shows what leaves the base and asks for a review against your request. You are asked only if something shows up that the request does not explain. Then `developer` moves to exactly the commit that passed. `/merge` also writes the version of the project's `CHANGELOG.md` before the gate.

**Next:** for larger requests, build the request with `/draft-prompt` and run it with `/prompt`; the session gets the project's name, numbered (`my-app-1`, `my-app-2`...). The full guide is in [docs/usage.md](docs/usage.md).

## How it works

1. **A question or reading:** Claude answers; nothing is opened.
2. **A change to a project or a POC:** a clone in `tmp/work/` (`bash scripts/aiwp-cmds.sh open`). Inside it, commit, rebase, reset and Docker are free, and the branch is always on the remote: a hook does not let the reply end with a commit only on the machine.
3. **Base:** `/merge` goes through the gate, in two phases (verification, review against the request, merge of the verified commit).
4. **Waves:** in a plan in steps, each step closes with a commit, a resume request in `custom/prompts/` and a board of what was done and what is left. The next step starts in a new session.

## What never happens without you

- **`projects/` stays on `developer` and changes only through the gate.** A hook refuses any git write in `projects/` or in the core outside it.
- **`main` and the cloud only at your request.** `main` moves only by `/merge --main <repo>`, a new version with a tag, and Terraform applies only with `bash scripts/aiwp-cmds.sh apply`, from `main` and with the plan confirmed.
- **Deleting a database asks for your confirmation**: a Docker volume, `DROP`, `dropdb` and the like.
- **Publishing to the local Docker is free**, and `bash scripts/aiwp-cmds.sh up` always tags the previous publication first; `rollback` goes back to it.
- **A secret does not leave the machine:** the scan runs before each push and again at the gate.
- **The session does not change the workspace:** rules, scripts, hooks and tools are read only and change only with a new release. `guard-bash` refuses a `chmod`, `chown` or `git init` that reaches the core, and `aiwp update`, `rollback`, `repair`, `forget` and the opening inside a session.
- **The rest follows Claude Code's permission mode.**

The hooks: `scripts/guard-bash.sh` (git, Terraform, databases, secrets, the read-only core; `--help` lists everything), `scripts/release-notice.sh` (at the start of a session, says when a new release exists), `scripts/guard-subagent-model.sh` (the model of each subagent), the `Stop` hook of `scripts/aiwp-cmds.sh` (commits not on the remote), `scripts/session-title.py` (the session name, and the warning about a project named in the message that has no marker or is out of date) and `scripts/prompt-log.py` (the prompt log; at the start of a session, the summary of the last day). The design: [docs/decisions/0001-base-design.md](docs/decisions/0001-base-design.md).

## Commands

| Command | Does |
| --- | --- |
| `/merge [<work>/<clone>]` | Takes the work of a clone (no argument: the one of this session) to the project's `developer`, through the gate, writing the `CHANGELOG.md` |
| `/merge --main <repo>` | The release: a release clone, the full check, the final review (what enters and what leaves, then general), the dated `CHANGELOG.md`, the gate into `developer`, then `main` and the tag `vX.Y.Z` |
| `/commit [--all] [--repo <dir>]` | One commit per logical change, in a clone or in `custom/` |
| `/push [--repo custom \| <work>/<clone>]` | Pushes `custom/`, or pushes again a clone whose automatic push failed |
| `/validate [folder] [--only <checks>] [--sonar]` | Runs the validations in Docker and, optionally, SonarQube |
| `/draft-prompt [ideas \| file]` | Turns your ideas into a request of the right size (adjustment, feature or system), with the effort of each step; asks only what blocks and saves it in `custom/prompts/` |
| `/prompt [name \| path]` | Runs a written request, gives the session the project's name, numbered, and archives the request when it is delivered |
| `/pilot [auto\|manual]` | Shows or changes who runs the tests a human would run by hand: Claude (`auto`, the default) or you (`manual`) |
| `/local-env [folder]` | Creates or completes the filled `.env` from `.env.example`, without showing values: for `docker/`, `docker/sonar/` and a tool of `tools/`, in `custom/env/<name>.env` |
| `/normalize-projects [<project>... \| --from <url \| folder> [--name <path>]]` | Lists the state of every project and POC; or analyses one (four analysts, a plan you approve, the language of its docs) and migrates it on a tested branch, with checkpoint tags, into `developer` and `main` |

The work area has its own command: `bash scripts/aiwp-cmds.sh --help` (`open`, `run`, `status`, `push`, `close`, `up`, `rollback`, `gate`, `release`, `apply`, and `developer`, `checkpoint`, `bring` for the normalization). Claude Code's own commands still apply: `/rewind`, `/rename`, `/usage`.

## Single-agent mode

To work on a project, a tool of yours in `custom/tools/` or a POC of `custom/pocs/` without the workspace's instructions, hooks and skills: `single-claude [<path>] [--commit] [--merge] [--review]`, installed once with `ln -sf "<workspace>/scripts/single-claude.sh" ~/.local/bin/single-claude`. Guide: [docs/single-agent.md](docs/single-agent.md).

## Prompt project

To write requests outside the development session, create a project in Claude just for that: paste into its instructions everything below the `<!-- paste below -->` marker of `rules/prompt-project.md` and connect the workspace folder as reference. `/draft-prompt` follows the same file inside the workspace.

## Local environment

- Validation in Docker: `bash scripts/validate.sh --help`. SonarQube, optional: `bash scripts/sonar.sh --help`.
- Measuring the workspace's performance: `python3 -I -B scripts/performance/measure.py --name <name>` (with observability up) writes `custom/performance/<date>-<name>.md`, compared with the previous measurement and the last five.
- Tasks heavy on CPU or GPU (graphics, 3D rendering) go through `bash scripts/heavy-run.sh`, which waits for the machine to cool down; tests and builds run directly.
- Tools in `tools/`: the local Grafana for the Claude Code telemetry (`tools/observability/`, on <http://localhost:3000>), the container consoles, login and Safe Browsing simulators, the Azurite console, the usage report and the Fable alert. Each one has its README ([tools/README.md](tools/README.md)); the ones that take settings read `custom/env/<name>.env` (`/local-env tools/<name>`). Your own tools live in `custom/tools/` (`bash scripts/init-repo.sh --type tool`).

## Layout

- `AGENTS.md`: Claude's entry point (loaded by `CLAUDE.md`). What applies in every session, in one page.
- `rules/`: rules by topic, the subagents (`rules/agents/`), the commands (`rules/skills/`) and the hooks and permissions configuration (`rules/agents/settings.json`).
- `scripts/`: the work area, the gate, the hooks, validation and repository creation (catalog in [scripts/README.md](scripts/README.md)).
- `docker/`: validation tools in containers.
- `docs/`: usage guide, overview and decision records.
- `assets/`: the project's logo (`logo.png`, `logo-white.png`) and the icon cut from it (`icon.png`).
- `tools/`: the product's local tools, part of the core.
- `templates/`: the forms you copy and fill in: a functional request (`templates/request.md`) and a backlog item (`templates/backlog-item.md`).
- `VERSION` and `CHANGELOG.md`: the installed release and what each release changed.
- `projects/`: one independent git repository per project, never part of the core.
- `custom/`: your custom layer, a git repository of its own, with your tools in `custom/tools/` and the filled `.env` files in `custom/env/` (git-ignored). Performance measurements live in `custom/performance/`, the prompt log, per project and per week, in `custom/prompts/log/` (`scripts/prompt-log.py`), and the backlog in `custom/backlog/`.
- `tmp/work/`: the work clones, one per request, outside git.
