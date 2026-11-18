# 0002 Workspace projects and their normalization

Status: accepted

## Context

A project can enter the workspace from anywhere: created by `init-repo.sh`, cloned by hand into `projects/`, moved
from an older setup, or brought by the person from another machine. Nothing told whether a project already followed
the workspace's contract, a project could carry its own instruction files that compete with the workspace rules, and a
change to what the workspace asks of projects had no way to reach the ones left behind. Copying a project in and
writing a plan to rewrite it mixed two decisions: bringing it under the workspace's rules, which is structural and
cheap, and bringing its code to the standard, which is a product decision.

## Options

- **A rule in text** ("check the project before working"): depends on the model remembering it, and fails in the long
  sessions where it matters.
- **A fixed list of instruction files to move:** every tool has its own names, they change, and a list always misses
  something.
- **A marker read by scripts, and a normalization by analysis:** a version marker in each project's `README.md`, read
  by a script at every interaction, and a skill whose analysts judge each piece of the repository by what it does,
  with the person's approval before anything changes.

## Decision

- **The marker.** Line 1 of the `README.md` of each project (of each POC folder): `<!-- AI-WORKSPACE-PROJECT x.y.z -->`,
  read with a fixed expression. For a project, the one committed on `developer` counts. `init-repo.sh` writes it.
- **Versions that ask something.** `VERSION` is the single number. `migrations/<x.y.z>.md` describes what a version asks
  of the projects; a project is out of date only when a migration newer than its marker exists, so a release that asks
  nothing never warns. `migrations/0.1.0.md` is the first normalization and holds the project contract.
- **The state in scripts.** `scripts/aiwp-project-state.sh` prints the state (no marker, up to date, out of date with
  the pending migrations, the workspace's own repository); it is read only.
- **A warning at every interaction, never a block.** The `UserPromptSubmit` hook (inside `session-title.py`, one
  process) detects the projects a message names and adds their state to the context with the order to warn and ask for
  authorization to run `/normalize-projects`; `aiwp-cmds.sh open` and the gate print the same. Refused, the request
  goes on and the warning comes back at the next message. A block would stop an urgent fix in a project not normalized
  yet.
- **`/normalize-projects` in two stages.** Stage 1: four analysts (instructions, company and environment, build and
  test, conformity), each called with Opus and high effort, read a fresh clone; their findings become a plan in
  `custom/migrations/`, one line per finding with a destination (custom layer, stays in the project, changes in the
  project, gap, security alert); the person approves it and chooses the language of the documentation. Stage 2:
  `developer` on the remote, annotated checkpoint tags on the old heads, pushed; a clone on
  `feat/ai-workspace-migration`; the approved lines in commits (custom layer first, complete documentation in the
  chosen language, the report `AI-WORKSPACE-MIGRATION.md`, the marker last); the test with the person; `/merge` into
  `developer`; `aiwp-cmds.sh release` into `main`, or a pull request when `main` is protected. A POC gets the same
  analysis and approval, then commits in `custom/`.
- **What it never does.** It rewrites no code, writes no test and fixes no security gap: gaps go to the report,
  security alerts (file, line, type, never the value) to the person at the end and, only as a count, to the report.
  Instruction files whose content moved are removed, not archived: the checkpoint tags and the history keep them; a
  team that still uses them keeps them in place, excluded in the workspace only (`custom/claude-md-excludes.txt`,
  merged into `claudeMdExcludes` by `setup-claude.sh`).
- **The steps that touch `projects/` are script commands.** `aiwp-cmds.sh developer` (switch only when nothing is
  stranded; `--create` pushes `developer`), `checkpoint` (never moves a tag) and `bring` (`--from`), next to `gate`,
  `release` and `apply`. `guard-bash` asks before `release` (and, until 0005, before `checkpoint` and `developer --create`, which now print a warning and leave the decision to the permission mode). The checkpoint tags
  are the one case where the workspace pushes a tag.
- **The gate judges a normalization on what it adds.** On `feat/ai-workspace-migration`, and only for a project that
  needs it (no marker or out of date), the gate requires the marker of the workspace version, refuses any added or
  changed file other than documentation, images, `.gitignore` and the sample `.env`, runs the lint checks of
  `validate.sh` on the changed files only and judges secrets by the scan of the commits the branch adds: a key already
  in the base does not block, a new secret or env file does. `--untested`, when the person chose to go on without
  running the branch, makes `guard-bash` ask. `release` pushes `main` before moving the local ref, so a
  refused push leaves both unchanged.
- **The workspace's own repository** is recognized (its name or its layout) and never normalized.

## Reason

- A marker read by a script costs no context and cannot be forgotten; warning instead of blocking keeps urgent work
  possible.
- Analysis by purpose finds what a list of names misses; the person's approval keeps every move a decision.
- Judging only what the normalization adds keeps a project's existing debt from blocking the step that makes it
  visible, while every protection still holds for what the branch brings.

## Consequences

- Every project and POC carries the marker; a project moved in by hand is warned about until it is normalized.
- A release that asks something of the projects adds a file to `migrations/`; the next message that names an older
  project warns.
- The first normalization of an existing project creates `developer` on its remote when missing, pushes two tags and
  leaves `feat/ai-workspace-migration` on the remote as its record.

## Change history
