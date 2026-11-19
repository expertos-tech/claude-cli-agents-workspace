# Using the workspace

Day-to-day guide. The design and its reasons are in [overview.md](overview.md) and in [decision 0001](decisions/0001-base-design.md).

- [The idea in one sentence](#the-idea-in-one-sentence)
- [Before the first session](#before-the-first-session)
- [Opening a session](#opening-a-session)
- [The registry and updating](#the-registry-and-updating)
- [Making a request](#making-a-request)
- [Where the work happens](#where-the-work-happens)
- [Waves: checkpoint, merge and resume](#waves-checkpoint-merge-and-resume)
- [What Claude asks you](#what-claude-asks-you)
- [Commands](#commands)
- [Review](#review)
- [Tests a human would run by hand](#tests-a-human-would-run-by-hand)
- [Projects](#projects)
- [Several sessions at once](#several-sessions-at-once)
- [Validating](#validating)
- [Changing the workspace itself](#changing-the-workspace-itself)
- [When something goes wrong](#when-something-goes-wrong)
- [Where everything is](#where-everything-is)

## The idea in one sentence

You say **what** you want; Claude decides **how** and does it in an isolated clone, where everything is allowed. The heavy checks and the questions stay in one place: the gate that takes the work to the base.

## Before the first session

Once per workspace:

| Step | Command |
| --- | --- |
| Create the workspace: the read-only core, the custom layer in `custom/` and the `.claude/` folder | the installer does it (it asks for the folder); another one: `aiwp new <folder>` (asks for the URL of the custom layer's repository, or `--custom <url>`; an empty answer starts a local one) |
| Check Docker, used by the validations | `docker info` |
| Create the filled `.env` of the validation tools, `custom/env/docker.env` | `/local-env docker`, in a session; then fill the values in an editor |
| Optional, but the only way to measure the sessions: start the observability stack (a local Grafana) | `/run-tools`, in a session, ticking Observability; then its README turns on the Claude Code telemetry |
| Optional: install the single-agent mode | `ln -sf "<workspace>/scripts/single-claude.sh" ~/.local/bin/single-claude` |

From then on `.claude/` keeps itself up to date: a session start hook runs `setup-claude.sh`.

To remove a workspace, give write permission back first, since the core is read only: `chmod -R u+w <folder> && rm -rf <folder>`. Push `custom/` and your projects before: they go with it.

## Opening a session

```bash
cd <workspace> && aiwp
```

`aiwp` checks for a new release (at most once a day, 5 s limit; offline it goes on) and, when there is one, prints "A new workspace version X was detected (this workspace: Y). Run `aiwp update` to update; opening this workspace on Y." Then it runs `setup-claude.sh` and starts `claude` on the current version, with the arguments you give after `--` (`aiwp -- --resume`). Opening never updates. After an update that was interrupted, it refuses to open until `aiwp repair` (or `aiwp update`) restores the workspace. `claude` alone also opens the workspace: when a new release exists, the session start says so, and Claude tells you to close the session and run `aiwp update` in a terminal.

**Never inside a session.** From a Claude Code session (its Bash tool, a hook) `aiwp` refuses `update`, `rollback`, `repair`, `forget`, the opening and a `new` over a registered folder, and `guard-bash` denies them too: they change the rules of the open session or start `claude` inside it. `aiwp list`, `check`, `version` and `--help` work anywhere. An unknown command is a usage error; arguments for `claude` go after `--`.

- **Always at the workspace root**, even to work on a project: that is where `AGENTS.md`, the rules and the hooks apply.
- **One session per request.** When the subject is over, use `/clear` or open another session. A long session gets expensive: each step reads the whole context again.
- **Effort:** `medium` fits work with a clear scope. Raise it to `high` with `/effort high` when the change touches a hook, a permission, a merge or security, or to debug a hard failure. For a single hard step, write `ultrathink` in the prompt.
- **Session name:** `/request <file>` names the session after the project, numbered (`billing-api-1`, `billing-api-2`...), from the request's `**Project:**` line: the number is one more than the highest among the open sessions of that project. Without `/request`, Claude Code picks a title on its own; `/rename <name>` changes it.
- **Language:** Claude replies in your preferred language of communication, the one `aiwp new` asked when it created the workspace, even when it runs a request file written in English. It is the Claude Code setting `language` in `.claude/settings.local.json` of the workspace (for example `"language": "portuguese"`); `aiwp update` never changes that file. With none set there or in your `~/.claude/settings.json`, Claude replies in the language you write in. To set or change it later, edit that key.

## The registry and updating

The data folder keeps `workspaces.json`, with every installed workspace (path, version, created, updated). `aiwp new` registers a workspace, and the first `aiwp` run in one that is not registered adds it.

| Command | Does |
| --- | --- |
| `aiwp list` | Each registered workspace with its version and state: up to date, update available (X), core changed, folder missing, pinned at X, stopped halfway |
| `aiwp forget <folder>` | Removes the entry (for a folder that is gone, or one you no longer update); never touches the folder |
| `aiwp update` | Lists the registered workspaces (number, version, state, path) and asks `[1] Update all` (the default), `[2] Choose which` (numbers) or `[3] Cancel` |
| `aiwp update <folder>` | Updates only that workspace, without asking |
| `aiwp update --all` | Updates every registered workspace, without asking |

Updating happens only by command, in a terminal, with no session open. `aiwp update` moves the data folder to the newest release once, then updates each chosen workspace: it verifies it against its manifest, backs up what it replaces in `.aiwp/backup/<version>/`, writes a journal, swaps files by rename and shows the changelog. A workspace whose core changed or whose folder is missing is skipped and reported, and the others go on; a summary table ends the run.

- **Pinned workspaces** (after `aiwp rollback`) are left as they are by `--all` and by Update all; choosing one by number or by folder updates it and clears the pin.
- **No terminal:** `--all` or a folder is required; otherwise it is a usage error (exit 2).
- **A running `claude`:** before swapping a workspace where a `claude` process runs (its current folder inside the workspace), it names the pid and asks. With `--all` it skips that workspace unless you add `--force`.
- **Exit code 1** when a workspace was skipped for a changed core, a running `claude` or an error.

## Making a request

**A simple request:** write it in words.

```text
fix the broken link in the README of my-project
```

**A functional request (a feature, a system):** the form is `templates/request.md`. Its headings and bold labels stay in English; the content is in your language. There are two ways to fill it in.

| Way | How |
| --- | --- |
| From loose ideas | `/draft-request I want a monthly report of...`; Claude asks only what blocks, marks the rest as "assumed decision" and saves it in `custom/requests/` |
| Yourself | copy `templates/request.md` to `tmp/request.md` and fill it in |

Then `/request <file>` reads `custom/requests/<file>`; `/request` alone reads `tmp/request.md`.

- The requests of `/draft-request` live in `custom/requests/`, inside the custom layer, a git repository of its own: the history of the requests is versioned there.
- A request goes through three folders: pending at the root of `custom/requests/` (state `idea` or `ready`); `custom/requests/qa/<project>/` once `/merge` took it into `developer`, with an "Execution" block of what was done; `custom/requests/done/<project>/` once `/merge --main` released it, after validating it against the code. An idea is a request in state `idea`; there is no backlog.
- `/draft-request` commits and pushes the request it created, at every version; `/merge` commits and pushes the moves to qa and done, and a wave its resume point ([Waves](#waves-checkpoint-merge-and-resume)).
- `aiwp new` sets up `custom/`: it clones the repository whose URL you give (an empty one gets a skeleton), or starts a local one. If the folder is missing later, the session says so at the start, and `bash scripts/setup-claude.sh --custom-repo <url>` in a terminal clones it.

The written request is as large as what you asked for. `/draft-request` picks one of three sizes before writing, and says which one:

| Size | When | What comes out | Ceiling |
| --- | --- | --- | --- |
| Adjustment | changes a behavior of something that exists ("add a confirmation overlay") | a few lines: what, where, done when, effort | about 120 words |
| Feature | a new capability in a system that exists | objective, rules, acceptance criteria, out of scope, steps and effort | about 400 words, at most 8 rules |
| System | a new system, architecture, infra, external integration, personal data | the full form | no ceiling |

- A rule you did not state is not written, unless without it two different things could be built.
- Too large or too small? Answer "smaller" or "bigger".
- A request of the adjustment size can go straight into the session, with no file.

**Effort per step.** Every written request carries the effort each step asks for: one line in the adjustment size, and the "Steps and effort" table in the others. You set the session with `/effort <level>` before each step; Claude says at the start of each one which level it asks for and passes that level to the step's subagents.

| Effort | When |
| --- | --- |
| `low` | a mechanical change: a text, a label, a rename |
| `medium` | a clear scope; the default |
| `high` | where verification matters: security, personal data, money, permissions, migration, a destructive step, a bug in code that exists |

What to expect:

- Claude asks the **functional gaps**, all at once, before starting. It does not ask your approval for technical decisions.
- A question or a read-only request is answered directly, with no branch and no test.
- At the end, a short summary: what changed, what was verified and how, what is left. A failing check is reported as a failure, with its output.

## Where the work happens

- **A question or reading:** Claude answers; nothing is opened.
- **A change to a project or a POC:** Claude opens a clone in `tmp/work/<date>-<subject>/<clone>/` (`<clone>`: the repo's path relative to `projects/`, each `/` written as `--`) (`bash scripts/aiwp-cmds.sh open`), says the path and works only there. In the clone Claude works without asking: `guard-bash` approves a line when every command of it runs in that clone, every path it names stays in it and nothing acts on a remote system (a push, a publish, a deploy, a cloud CLI, `ssh`); anything it cannot tell follows Claude Code's permission mode. Each commit goes to the remote by itself, after a secret scan of the commits that leave; a commit with a secret or a `.env` stays in the clone.
- **Taking it to the base:** `/merge [<work>/<clone>]`; with no argument, the clone of this session. `/merge` merges `developer` into the clone and writes the version of the project's `CHANGELOG.md` (`## [X.Y.Z] - Unreleased`; the bump rules are in `rules/docs.md`) before the gate. The gate brings `developer` up to date, runs the full suite and the complete `validate.sh`, scans every incoming commit for secrets, writes the audit of what leaves the base (files deleted or renamed away, tests removed or disabled, destructive SQL, infra, dependencies, the warnings) and asks for a review against the request. Only a hard rule stops the gate: a secret or an env file, a failing test command, a check that changes tracked files, the normalization and hotfix scope rules. Every other failing check of `validate.sh` (lint, vulnerabilities, infra, coverage...) is a warning: it goes into the audit under "Warnings", `/merge` lists it in its summary and you decide. `/merge` is typed only by you: the gate refuses phase 2 otherwise. You are asked only about what the request does not explain. Then `developer` moves by fast-forward to exactly the commit that passed, and the clone can be closed (`aiwp-cmds.sh close`).
- **The task's copy:** at the end of a task Claude publishes it to the local Docker with `aiwp-cmds.sh up <work>/<clone>`, as a copy in its own compose group `agent_<MMDD>-<slug>` (`--<clone>` added when another clone of the work owns it), with every port moved to a free one in 61000-65535. It never touches the final stack. Its networks are internal, with an isolated gateway (Docker Engine 28 or later), so a container with no published port reaches neither the host nor the outside; `up` refuses what its isolation needs (host networking, a Docker socket or a bind outside the clone, external networks or volumes, Docker older than 28). A service with a key off the safe list (privileges, capabilities, devices, sysctls...) starts with a warning, and `exec` into it follows the permission mode instead of being approved by the hook. `aiwp-cmds.sh down <work>/<clone>` stops it; `close` and the gate destroy it. Claude works freely inside that group with no prompt (`down -v`, `logs`, `exec` into an isolated container), volumes included; starting or rebuilding it goes through `up` again.
- **`projects/` always stays on `developer`.** Nobody edits there; only the gate moves the base.

## Waves: checkpoint, merge and resume

A wave is each step of a plan in steps (the request's "Steps and effort" table). A request with one step, or none, is one wave, closed when it ends. A question or reading opens no wave.

- **A part goes to the base only when you type `/merge`**, whenever you decide. A base that publishes to production: the gate asks before merging. A migration branch also waits for your order.
- **When the wave closes**, Claude:
  1. makes the checkpoint: a commit in the clone, which goes to the remote by itself (`aiwp-cmds.sh status` shows `not-pushed=0`);
  2. appends to the request that was running, in `custom/requests/`, where it stopped (the work, the clone, the branch and the sha), decisions taken, open items and the next steps with their effort; the request stays pending;
  3. ends the reply with the closing board: what was done and verified, the addresses of the copy, one item to test per acceptance criterion, what is left, the request to resume and the two ways out: `/merge <work>/<clone>` to approve, `aiwp-cmds.sh close <work> --discard` to drop the work. After the board the session stops; the next wave starts in a new session, with `/request <file>`.
- The session does not end its reply with a commit missing from the remote: a hook makes it try again or say why it could not.

Full rule: `rules/git.md`, sections "Gate" and "Waves".

## What Claude asks you

The rest follows Claude Code's permission mode: auto mode judges what is destructive.

| Situation | What happens |
| --- | --- |
| A gate with something the request does not explain, destruction outside the machine, or a base that publishes to production | one question, in one round, before merging |
| A line that mixes an approved command with commands in the clone | refused with "Run it alone": Claude runs the others first and the asked one alone, so the question shows only it |
| Deleting a database: `docker volume rm`, `docker compose down -v`, `DROP`/`TRUNCATE`, deleting a `.data/` folder | Claude says what goes, and the hook asks for your confirmation |
| `aiwp-cmds.sh release` (`main` moves, and the `vX.Y.Z` tag is pushed), run by `/merge --main <project>` | confirmation, and only at your request |
| `aiwp-cmds.sh hotfix`, `hotfix-tag` and `hotfix-down` (the fix into `main`, its patch tag, `main` merged into `developer`), run by `/merge --hotfix` | confirmation, after your OK to the fix; the question "publish to production with the fix?" comes before the push of a `main` that deploys by itself, after it otherwise |
| `aiwp-cmds.sh apply --apply` (Terraform in the cloud) | confirmation of the plan shown, and only at your request |
| Deleting, moving or emptying Grafana's data (`tools/observability/.data`), wherever it runs | confirmation, even in a clone |
| `aiwp-cmds.sh deploy` (updates the final stack of a project, run by `/docker-deploy`), `checkpoint`, `developer --create` and `gate --untested` | the hook prints a warning and the permission mode decides |
| `aiwp-cmds.sh close --discard` (deleting work not merged) | confirmation |
| A git write in `projects/` or in the core, Terraform outside `apply`, `git push --no-verify` | refused by the hook, with the right way |
| A subagent on Fable | the hook asks for your confirmation |
| Deleting a whole project, POC or tool | Claude shows the command; **you** run it |

## Commands

| Command | Does |
| --- | --- |
| `/merge [<work>/<clone>]` | Takes the work of a clone (no argument: the one of this session) to `developer`, through the gate, writing the `CHANGELOG.md` and moving the request to `custom/requests/qa/<project>/` with what was done |
| `/merge --main <project> [instructions]` | The release of the project: every repo in it, each with its own version and tag, then the project version in its root repo; validates every request in `qa/<project>/` against the code (the final review: the three questions on everything since the last tag, widened as needed), asks per finding (fix now or a request), and warns of any conflict an instruction causes before acting |
| `/merge --hotfix <project> <description>` | An error in production: a clone from `main`, only the fix, the gate against `main` and a review of the fix, your OK, then `main`, the patch version `vX.Y.(Z+1)` and its tag when you say to publish, and right after it `main` merged into `developer` (a conflict goes through a resolution branch and the gate). Until `developer` holds `main`, the repo is blocked: `/merge` into its `developer` and its release are refused |
| `/commit [--all] [--repo <dir>]` | One commit per logical change, in a clone or in `custom/` |
| `/push [--repo custom \| <work>/<clone>]` | Pushes `custom/`, or pushes again a clone whose automatic push failed |
| `/docker-deploy [developer\|main] [<repo>]` | Updates the final local Docker stack of a repo from `developer` or `main`, tagging the replaced images for rollback and deleting no volume; only at your request |
| `/validate [folder] [--only <checks>] [--sonar]` | Runs the validations in Docker |
| `/draft-request [ideas \| file]` | Builds a functional request from ideas |
| `/request [name \| path]` | Runs the request written in a file |
| `/rules [exclude <name> \| include <name> \| add <subject> \| replace <rule> \| lessons]` | Shows and changes the rules, skills and agents a session loads (below, "Changing the workspace itself") |
| `/pilot [auto\|manual]` | Shows or changes who runs the manual tests |
| `/local-env [folder]` | Creates or completes a filled `.env` without showing values (`custom/env/<name>.env` for `docker/`, `docker/sonar/` and a tool) |
| `/run-tools [--down [tool...]]` | Starts the local tools you tick (below, "Local tools"); `--down` stops |
| `/normalize-projects [<project>... \| --from <url \| folder>]` | Lists the state of the projects, or brings one into the workspace or up to date (below, "Projects") |

The work area's command: `bash scripts/aiwp-cmds.sh --help` (`open`, `run`, `status`, `push`, `close`, `up`, `down`, `deploy`, `rollback`, `gate`, `release`, `hotfix`, `hotfix-tag`, `hotfix-down`, `apply`, `developer`, `checkpoint`, `bring`).

Claude Code's own commands that help most here:

| Command | For |
| --- | --- |
| `/rewind` (or Esc twice) | undo file edits and take the conversation back to an earlier point |
| `/clear` | start another request with a clean context |
| `/effort`, `/model` | change the effort and the model |
| `/usage` | see the cost and usage of the session |

## Review

- One round per gate, between the two phases, by the `reviewer` subagent: clean context, read only. Into `developer` it sees only the difference that enters; into `main` (release, hotfix) everything since the last tag, widened to callers, dependents and docs.
- One `reviewer` per merge, effort `medium` into `developer` and `high` into `main`; a range too large for one context is split in parts, in parallel. The brief carries what you authorized, and that is never a finding.
- Three questions: what was asked against what was done (each rule and criterion, proven or not), what went beyond the request (a consequence or unexplained), and what existed and was lost (a behavior, a test or a protection removed or weakened with no request). It reports only defects.
- A **BLOCKER** is only a hard rule, a correctness defect, a change outside the request's scope, a risk a mistake reaches or a proof the request requires now; it is fixed in the clone, and the gate runs again. Everything else is a **WARNING**: it never sends the branch back, `/merge` lists it and you decide.
- If Claude disagrees with a finding, it brings both positions and you decide.

## Tests a human would run by hand

The mode belongs to the session and changes with `/pilot`.

| Mode | Who tests | When to use |
| --- | --- | --- |
| `auto` (default) | Claude, visual checks included, with the browser the session has | almost always |
| `manual` | you: Claude gives a numbered list with what changed, where to see it, the steps and what to report back, and waits | when the test needs your eye, a real login or a physical device |

In both modes, unit tests, coverage, lint and the secret scan are Claude's.

## Projects

- Each project is an independent git repository in `projects/`, never part of the core. The list is in `custom/projects.md`.
- **Creating:** ask ("create the project X in projects/client-y"). Claude uses `scripts/init-repo.sh`. The folder of a new project is your decision; if you do not say it, Claude asks.
- **Branches:** the checkout in `projects/` stays on `developer`; the work happens in a clone under `tmp/work/`, on a branch that leaves it and comes back through the gate. `main` moves only when you ask for the release (`/merge --main <project>`, in a release clone `fix/release-vX-Y-Z`, ending in `aiwp-cmds.sh release <repo> --tag vX.Y.Z`): a fast-forward to `developer` and the version tag. An error in production is fixed from `main` (`/merge --hotfix`), as a patch version, and `main` is then merged into `developer`. Terraform applies only from `main`, with `aiwp-cmds.sh apply`, at your request and with the plan confirmed.
- **Local Docker:** `aiwp-cmds.sh up <work>/<clone>` publishes a task's copy in its own `agent_` group and never over the final stack; `aiwp-cmds.sh up <repo>` is refused. The final stack changes only on your order, with `/docker-deploy` (`aiwp-cmds.sh deploy`), which first tags the images it replaces; `aiwp-cmds.sh rollback <repo>` goes back to them. A copy has no rollback tag: run `up` again.
- **Workspace projects:** the first line of each project's `README.md` (and of each POC folder's) is a marker with the workspace version it was last normalized with: `<!-- AI-WORKSPACE-PROJECT 0.1.0 -->`. `bash scripts/aiwp-project-state.sh` shows the state of each one. When a message names a project without the marker, or one that a newer workspace version asks something of (`migrations/`), Claude says so and asks whether to run `/normalize-projects <project>`. Saying no never blocks the request; the warning comes back the next time you name the project. `aiwp-cmds.sh open` and the gate show the same warning.
- **Bringing in an existing project:** `/normalize-projects --from <url | folder>` clones it into `projects/` (from a folder, its local branches come along and `origin` points to its real remote; uncommitted changes there are listed, since a clone does not carry them). A project cloned by hand or a POC moved into `custom/pocs/` is normalized the same way: `/normalize-projects <project>`.
- **How a normalization goes:** first, four analysts read a fresh clone and Claude writes a plan in `custom/migrations/`, one line per finding: what goes to your custom layer (company and environment knowledge), what stays in the project as documentation, what changes in it (marker, "How to test", `.env` ignored, instruction files of other tools removed), and the gaps and security alerts it only reports. You approve, edit or drop each line and choose the language of the documentation. Then, after you confirm each push: `developer` on the remote, checkpoint tags `ai-workspace-migration/<date>/developer` and `.../main` on the old heads, a branch `feat/ai-workspace-migration` with the plan in commits and the complete documentation, a test of the branch with you, `/merge` into `developer` and the release of `main` (a pull request when `main` is protected). It never rewrites code, writes tests or fixes a security gap: the gaps go to `AI-WORKSPACE-MIGRATION.md` at the project root, and the security alerts (file, line and type, never the value) are shown to you at the end. A POC gets the same analysis and approval, with the changes committed in `custom/`.
- **POC or local tool:** a POC lives in `custom/pocs/` and is worked on in a clone of `custom/`, with the gate using its build as the test. A tool lives in `tools/`, part of the core, and changes only with the product. Both only need to compile, pass the secret scan and have a README.
- **Ports:** POCs and `docker/` stacks from 20000 up; tools and projects on their conventional port.
- **Language:** English code is recommended in your projects, not required (`rules/rules.md` "Language").
- **Infrastructure:** you do not size it. Without a number from you, it starts at the smallest size that runs the delivery (consumption plan, one node, one region) and ready to grow: the limits are Terraform variables, and the project's docs say which signal tells it is time to scale and how much the next step costs. If you have a real requirement (a volume, a deadline, a budget ceiling), say it in the request and it becomes a requirement. Before creating a resource that is billed, Claude gives the monthly estimate.
- **Ideas:** an idea not yet ready is a request in `custom/requests/` in state `idea`, in the adjustment size of `templates/request.md` (What, Where, Done when, Effort).

## Local tools

`/run-tools` shows checkboxes with the tools of this machine, grouped in two questions (observability and consoles; simulators), each with its URL and state, and starts the ones you tick. Unticking a tool that is up stops nothing; `/run-tools --down` stops.

- The container tools (observability, the login and Safe Browsing simulators, the Azurite console) run in one compose project, `claude-cli-agents-tools`: the container console shows them as one group (`tools/compose.yaml`).
- Only this machine's container console shows: docker-ce on Linux and WSL with Docker Engine, Colima on macOS. It is a machine service: `/run-tools` installs it (`make install`) or starts it.
- A tool's configuration lives in `custom/`: `custom/env/<tool>.env` (`/local-env tools/<tool>`) and `custom/config/<tool>/`. Without it the tool is listed as "configuration missing" and does not start; a busy port is shown the same way.
- Each start tags the images it replaces as `<name>:rollback-latest`.
- A tool installed before the group, still running in its own compose project, moves into the group at its first start. A named volume (Azurite's) is copied to the group's name first; the old one stays until you confirm its deletion. When a project's stack still uses one of the tool's networks, `/run-tools` says which, changes nothing, and you stop that stack first.

## Several sessions at once

- **One clone per work.** Each session works in its own clone under `tmp/work/`; two sessions share nothing but the remote. Two cannot open the same branch.
- **The gate by fast-forward.** If another session merged first, phase 2 refuses and the gate starts again with the new base.
- **`scripts/heavy-run.sh`.** Before a task heavy on CPU or GPU (graphics, 3D rendering), it reads the temperature: at 88 °C or more, it waits for 85 °C. Tests, builds and containers run directly, with no queue.
- **A shared resource** (a port, a Compose project in use): two clones of the same project compete for the same ports. Start the stack of one at a time, and tell the session what is already running.

## Validating

| What | Command |
| --- | --- |
| A clone or a folder | `/validate tmp/work/<work>/<clone>`, or `bash scripts/validate.sh --path <folder>` |
| Only some checks | `bash scripts/validate.sh --path <dir> --only secrets,markdown` |
| SonarQube, when you want it | `/validate <dir> --sonar` |

The checks live in `docker/compose.yaml`, with a fixed version and digest. A check that already passed for the same content shows as `CACHED` and does not run again; `--no-cache` forces it.

## Changing the workspace itself

- **A session never changes the core.** `AGENTS.md`, `rules/`, `scripts/`, `docker/`, `docs/` and `tools/` are read only: in an installed workspace their files are read only on disk, Claude Code refuses the edit and the hook refuses the write, a `chmod`, a `chown` and a `git init` there. The workspace root is not a git repository: `custom/` and each project are. Your own tools go to `custom/tools/` (`bash scripts/init-repo.sh --type tool`). When a rule gets in the way, Claude writes the proposal in `custom/docs/lessons.md` and tells you.
- **Updates:** a new release reaches the workspace only through `aiwp update`, in a terminal with no session open, which replaces only the core files that changed ([The registry and updating](#the-registry-and-updating)). Opening with `aiwp` only says that one exists.
- **Who changes the product:** a pull request to the product repository, maintained from its root.
- **Your own rules:** `/rules` shows the rules a session loads, with where each comes from, and turns core rules, skills and agents off, replaces a core rule or adds your own, in `custom/rules-config.json` and `custom/my-rules/`; the mandatory core always loads. You can also edit those files by hand. A change reaches the next sessions, never the open one. A workspace that still has `custom/rules/`: rename it with `git -C custom mv rules my-rules`.
- **Lessons:** when something goes wrong because of how the work was done, Claude writes one dated line in `custom/docs/lessons.md`. That file is not loaded in sessions. Review it from time to time and decide, line by line: it becomes a hook (no exception allowed), a sentence in a rule, or it goes.
- **Before adding a rule, ask:** does Claude already do it right without it? Can a hook guarantee it? If the answer to either is yes, the rule does not go in.

## When something goes wrong

| Symptom | What to do |
| --- | --- |
| Claude edited what it should not | `/rewind`, or Esc twice; in a clone, `git restore <file>` as a last resort |
| A command, a skill or a subagent does not show | `bash scripts/setup-claude.sh` and restart the session |
| The hook asks or refuses where it should not | write it in `custom/docs/lessons.md`; the set is in `scripts/guard-bash.py` (`bash scripts/guard-bash.sh --help`) |
| "NOT pushed" in the clone | the pre-push hook refused (a secret, a `.env`) or the remote did not answer: read the output, rewrite the branch in the clone if needed, and `aiwp-cmds.sh push` |
| "The secret scan did not run" | Docker did not answer: start Docker and run `aiwp-cmds.sh push`; the commit stays in the clone until then |
| The publication to Docker went wrong | `bash scripts/aiwp-cmds.sh rollback <repo>` goes back to the previous image of the final stack; a task's copy has no rollback: run `up <work>/<clone>` again |
| `heavy-run.sh` exited with 75 | nothing ran: the machine did not reach 85 °C in 30 minutes. The output has the last reading; run it again later |
| The gate refused phase 2 | the base moved, or the clone changed after phase 1: the gate runs again |
| A rule blocks the simplest solution | Claude stops and shows the options. You can override any rule |

## Where everything is

| What | Where |
| --- | --- |
| What applies in every session | `AGENTS.md` |
| Rules by topic | `rules/*.md` |
| Subagents and commands | `rules/agents/`, `rules/skills/` |
| Hooks and permissions | `rules/agents/settings.json`, `scripts/guard-bash.sh`, `scripts/guard-subagent-model.sh`, `scripts/aiwp-cmds.sh` (the clones' hooks and `Stop`) |
| Scripts | `scripts/README.md` |
| Validation tools | `docker/README.md` |
| Decisions | `docs/decisions/` |
| Lessons | `custom/docs/lessons.md` |
| Written requests | `custom/requests/` (in the custom layer) |
| Requests (pending, `qa/<project>/`, `done/<project>/`) | `custom/requests/` |
| Company: cloud, visual identity, projects and ports | `custom/` (`custom/README.md`) |
| Work clones | `tmp/work/<work>/` (outside git; `aiwp-cmds.sh status`) |
