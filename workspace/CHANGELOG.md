# Changelog

All notable changes to Claude CLI Agents Workspace are documented in this file. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - Unreleased

### Added

- `/merge` writes the project's `CHANGELOG.md` at every merge into `developer`, always under a named version (`## [X.Y.Z] - Unreleased`): a `feat` makes it a minor, anything else a patch, and a fix of something that entered the same unreleased version adjusts its entry instead of adding a "Fixed" one (`rules/docs.md`). With no argument, `/merge` takes the clone of the session.
- `/merge --main <repo>` releases that version: a release clone on `fix/release-vX-Y-Z`, a full check in a clean context, its fixes, the dated `CHANGELOG.md`, the gate into `developer`, then `main` and the annotated tag `vX.Y.Z` (`aiwp-cmds.sh release <repo> --tag vX.Y.Z`, which never moves a tag).
- Plans, requests and documents Claude writes to a file are saved in English and shown in your language.

### Changed

- `/prompt` opens the work clone before the first change to a project or POC.
- `/commit`, the implementer and the docs writer no longer write `CHANGELOG.md`; `/merge` does.
- After updating: a project whose `CHANGELOG.md` has a plain `## [Unreleased]` section gets it named by the next `/merge` (`## [X.Y.Z] - Unreleased`); nothing to do by hand.

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
