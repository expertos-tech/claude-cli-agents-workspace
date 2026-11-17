# Changelog

All notable changes to Claude CLI Agents Workspace are documented in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - Unreleased

### Added

- `/merge` writes the project's `CHANGELOG.md` at every merge into `developer`, always under a named version (`## [X.Y.Z] - Unreleased`): a `feat` makes it a minor, anything else a patch, and a fix of something that entered the same unreleased version adjusts its entry instead of adding a "Fixed" one (`rules/docs.md`). With no argument, `/merge` takes the clone of the session.
- `/merge --main <project> [instructions]` releases the project: every repo in it with its own version, dated `CHANGELOG.md` and annotated tag `vX.Y.Z` (`aiwp-cmds.sh release <repo> --tag vX.Y.Z`, which never moves a tag), then the project version in its root repo, whose `CHANGELOG.md` gets a "Components" table and whose `README.md` keeps the production versions. It first states its plan and every conflict an instruction would cause (a partial release that breaks a dependency between the repos), and asks.
- Plans, requests and documents Claude writes to a file are saved in English and shown in your language.
- `/merge --main` ends with a final review of everything since the last release, in two clean-context rounds: what enters and what leaves (the inventory of what was added, changed and removed, each traced to its request; regressions; whether each change does what was asked; the `CHANGELOG.md`), then a general reading of the whole tree. An unexplained removal or a regression stops the release.
- `scripts/check-workspace.sh --i18n-pending` (the gate of the product repository) lists missing or outdated translations as pending instead of failing.
- `/merge --hotfix <project> <description>` fixes an error in production from `main`, never from `developer`: a clone from the remote `main` (`aiwp-cmds.sh open --from-main`), only what the error needs, the gate against `main` and a review of the fix (a change unrelated to the error is a BLOCKER), your OK, then `main` by fast-forward (`aiwp-cmds.sh hotfix`), the patch version `vX.Y.(Z+1)` and its tag when you say to publish (`hotfix-tag`), and right after it `main` merged into `developer` (`hotfix-down`: a merge commit; a conflict goes through a `fix/<slug>-developer` clone and the gate). The question "publish to production with the fix?" comes before the push of a `main` that deploys by itself, after it otherwise. Each of the three commands asks for your confirmation.
- A repo whose remote `main` holds a commit its remote `developer` does not (a hotfix not merged down, after a cancel or a crash) is blocked, computed from git with no state file: the gate refuses every merge into its `developer` (except the branch that brings `main` down) and `release` refuses its release; `aiwp-project-state.sh`, `aiwp-cmds.sh open` and the warning of a message that names the project say so.

- A request lifecycle in `custom/requests/`: pending (state `idea` or `ready`), `qa/<project>/` once `/merge` takes it into `developer` (with an "Execution" block: what was done, decisions, deviations, the status of each acceptance criterion), `done/<project>/` once released. `/merge --main` validates every request waiting in `qa/<project>/` against the code, gathers every finding, and asks per finding: fix now in the release clone, or a request.

### Changed

- `/prompt` and `/draft-prompt` are renamed `/request` and `/draft-request` (`rules/request-writing.md`); `/request` opens the work clone before the first change to a project or POC, and its default file is `tmp/request.md`. Requests live in `custom/requests/` instead of `custom/prompts/`.
- Any project layout: a folder of `projects/` at any depth may be a repo, inside another repo too; no tool refuses a layout. A clone of a nested repo is named after its path with each `/` as `--` (`billing--billing-api`).
- The prompt log moves to `logs/prompts/` at the workspace root (a new writable folder), never versioned; `prompt-log.py sync --scan` removes any secret from it. Its sources move to `custom/config/prompt-log/sources.json`.
- `/commit`, the implementer and the docs writer no longer write `CHANGELOG.md`; `/merge` does.
- The gate of the product repository (`scripts/check-workspace.sh`, a maintenance tool) requires a `pt-BR` and an `es` translation of every `README.md` of the repository and of every page of its root `docs/`, besides the product's documents.

### Removed

- The backlog (`custom/backlog/`, `templates/backlog-item.md`): an idea is a request in state `idea`.

### After updating

- Your custom layer, in this order: `git -C custom mv prompts requests` (the requests and their archive move together); move `custom/requests/log/sources.json` to `custom/config/prompt-log/sources.json`; copy the rest of `custom/requests/log/` to `logs/prompts/` and remove it from `custom/` (`git -C custom rm -r requests/log`); turn each file of `custom/backlog/` into a request in `custom/requests/` with `**State:** idea`; commit and push `custom/`.
- A project whose `CHANGELOG.md` has a plain `## [Unreleased]` section gets it named by the next `/merge` (`## [X.Y.Z] - Unreleased`); nothing to do by hand.

## [0.1.0] - 2026-11-16

Initial public release.

### Added

- The installer (`install.sh`), which installs the data folder and creates the workspace, and the `aiwp` command: new workspaces with a read-only core and a manifest, a registry of installed workspaces (`aiwp list`, `aiwp forget`), `aiwp update` over every registered workspace by command only (with backup and journal), rollback and repair. Opening detects a new release and never updates.
- Rules for Claude Code sessions (`AGENTS.md`, `rules/`), with subagents and skills generated into `.claude/` by `scripts/setup-claude.sh`.
- Work in clones under `tmp/work/` and the merge gate (`/merge`, `scripts/aiwp-cmds.sh`, `scripts/aiwp-gate.sh`), with release and Terraform apply on request.
- Hooks: `guard-bash` (it also refuses `chmod`, `chown` and `git init` on the read-only core, and `aiwp update`, `rollback`, `repair`, `forget` and the opening inside a session), `guard-subagent-model`, the `Stop` check, session names, the prompt log and the release notice at session start.
- Filled `.env` files in the custom layer, `custom/env/<name>.env`, created from the `.env.example` templates of the core by `/local-env` and read by compose with `--env-file`.
- The custom layer (`custom/`) for company data, written requests, lessons and extra rules.
- Workspace projects: the marker `<!-- AI-WORKSPACE-PROJECT x.y.z -->` on line 1 of each project's and POC's `README.md` (written by `scripts/init-repo.sh`), `migrations/` with what each version asks of the projects (`migrations/0.1.0.md`), `scripts/aiwp-project-state.sh`, and a warning at every message that names a project without the marker or out of date (the `UserPromptSubmit` hook, `aiwp-cmds.sh open` and the gate), which asks to normalize it and never blocks.
- `/normalize-projects`: lists the state of the projects, or brings a project or POC into the workspace (`--from` a URL or a folder): four Opus analysts and a plan in `custom/migrations/` that the person approves with the language of the documentation; then checkpoint tags pushed before any change, a tested branch `feat/ai-workspace-migration` with the complete documentation and `AI-WORKSPACE-MIGRATION.md`, `/merge` into `developer` and the release of `main` (a pull request when `main` is protected). New `aiwp-cmds.sh` commands `developer`, `checkpoint` and `bring`; the gate judges a normalization on what it adds; `custom/claude-md-excludes.txt` keeps a team's instruction files out of the sessions.
- Validation tools in Docker (`scripts/validate.sh`) and the product gate (`scripts/check-workspace.sh`).
- Request writing (`/draft-prompt`, `/prompt`, `templates/request.md`), the single-agent mode and performance measurement.
- Local tools in `tools/`, with your own tools in the custom layer (`custom/tools/`): observability, container consoles, login and Safe Browsing simulators (their real configuration lives in `custom/config/<tool>/`), Azurite console, usage report and Fable alert.
