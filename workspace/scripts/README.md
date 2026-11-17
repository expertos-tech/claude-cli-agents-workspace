# scripts/

Catalog of the workspace scripts. Rules: `rules/scripts.md`. Check this list before writing a long command.
Run as `bash scripts/<name>.sh`. Each script prints its full reference with `--help`: this page only says what exists.
In an installed workspace the scripts never write in the core: their output goes to `custom/`, `projects/`, `tmp/`, `logs/`, `.history/` or a tool output folder (`bash scripts/aiwp.sh _writable` lists them).

## Validation

| Script | Does | Example |
| --- | --- | --- |
| `validate.sh` | Runs the validation tools of `docker/compose.yaml` in Docker and prints PASS/FAIL per check: `secrets`, `vuln`, `iac`, `shell`, `dockerfile`, `markdown`, `mermaid`, `terraform`, `python`, `typescript`, `coverage` (and `cost`). The `secrets` check also fails when git tracks a `.env` or a `local.settings.json`. Compose reads `custom/env/docker.env` (else the defaults of `docker/.env.example`) and mounts the workspace read-only | `bash scripts/validate.sh --path projects/billing --only secrets,markdown` |
| `aiwp-cmds.sh` | Work area: `open` a clone of a project (or of `custom/`, for a POC) in `tmp/work/<work>/`, on the branch of the request, pushed at every commit after a secret scan of the commits; `run`, `status`, `push`, `close`; `up` publishes to the local Docker with a rollback tag first, `rollback` returns to it. Its `_stop-check` is the `Stop` hook | `bash scripts/aiwp-cmds.sh --help` |
| `aiwp-gate.sh` | The only ways into `projects/`, called through `aiwp-cmds.sh`: `gate` (phase 1: updated base, full tests, `validate.sh`, env files and secrets, the audit of what leaves the base; phase 2 `--merge`: fast-forward of the checked sha; a normalization branch is judged on what it adds), `release` (`developer` to `main`, and with `--tag vX.Y.Z` the annotated release tag, never moved; a pull request when `main` is protected), `apply` (Terraform plan from `main`, then apply of that plan), and the steps of `/normalize-projects`: `developer`, `checkpoint` (the annotated tags, pushed) and `bring` (`--from`) | `bash scripts/aiwp-gate.sh --help` |
| `check-workspace.sh` | Gate of the product repository, a maintenance tool (in an installed workspace it prints one line and exits 2), for the checkout that holds it (only the product folder, when it sits in a subfolder of its git repo): unique decision numbers, no term of the terms list (`AIWP_TERMS_FILE`, else `custom/core-terms.txt`) in the repo, every document translated (`i18n`, only when the repository root holds `i18n/`), valid `rules/agents/settings.json`, POC files that parse, `validate.sh` on the changed files, and the script suites whose inputs changed | `bash scripts/check-workspace.sh` |
| `check-ledger.sh` | Library sourced by the two scripts above: records each PASS under a hash of its inputs, so a check runs once per state of the code (`CACHED <check>`). Not run by hand | — |
| `heavy-run.sh` | Runs a task heavy on CPU or GPU (graphics, 3D rendering): at once under 88 °C, else once the hotter of CPU and GPU reads 85 °C or less; no queue (`rules/machine-load.md`). Exit 75: still hot after 30 minutes, nothing ran | `bash scripts/heavy-run.sh -- <render command>` |
| `performance/measure.py` | Measures the workspace from the session transcripts (process, validation and gate, questions, context, time to the first edit) and writes `custom/performance/<date>-<name>.md`, compared with the previous report and the last five. Runs only with the observability stack up | `python3 -I -B scripts/performance/measure.py --name <name>` |
| `prompt-log.py` | Records every human prompt from the session transcripts (the workspace root plus the folders of `custom/config/prompt-log/sources.json`) in `logs/prompts/<project>/<year>-W<week>.md`, with the agent commits and gate merges that followed, and day and week summaries built from that data. Only adds: an expired transcript keeps its records. `--context` is a `SessionStart` hook (prints the last day with activity, never fails the session); `--scan` runs gitleaks in Docker on every week file and removes what it finds; `logs/` is not a repository, so nothing is committed or pushed | `python3 -I -B scripts/prompt-log.py sync --scan` |
| `sonar.sh` | Optional SonarQube stack (`up`, `down`, `status`, `scan`), only when the human asks. Reads `custom/env/docker-sonar.env`; the scan mounts the folder read-only and keeps `.scannerwork` in the container's `/tmp` | `bash scripts/sonar.sh scan --key billing --path projects/billing` |

## Hooks

Wired in `rules/agents/settings.json`. Each reads the hook JSON on stdin.

| Script | Does |
| --- | --- |
| `guard-bash.sh` (+ `guard-bash.py`) | `PreToolUse` on `Bash`. Denies git writes in `projects/` and the core, Terraform changes, `push --no-verify`, and a `custom/` commit carrying a secret. In an installed workspace it also denies `chmod`, `chown`, `chgrp`, `git init` and `git clone` that reach the read-only core (links, globs, `-R`, `find`, `xargs`, `sudo`, `bash -c` followed; the writable paths come from `aiwp.sh _writable`, and if that fails it asks), and `aiwp update`, `rollback`, `repair`, `forget` and the opening (`aiwp` alone, `aiwp -- ...`) inside a session. Asks before deleting a database and before `aiwp-cmds.sh release`, `checkpoint`, `developer --create`, `gate --untested`, `apply --apply` and `close --discard`. Reads the line the way a shell groups it; `--help` lists everything and what it does not see. An internal error asks, never passes silently |
| `release-notice.sh` | `SessionStart`: in an installed workspace, runs `aiwp.sh check --quiet` (one answer per day, bounded time, offline-safe) and, when a newer release exists, adds to the session context that Claude tells you to close the session and run `aiwp update` in a terminal. Detection only; silent otherwise |
| `guard-subagent-model.sh` (+ `guard-subagent-model.py`) | `PreToolUse` on `Agent`. Denies a fork and a model outside the allowed list, asks on Fable, sets `opus` on a call that would inherit. A failure blocks the call |

## Setup and repos

| Script | Does | Example |
| --- | --- | --- |
| `aiwp.sh` | The `aiwp` command (`~/.local/bin/aiwp` links to the copy in the data folder): `new` creates a workspace (the core read-only, a manifest, `custom/`) and registers it in `workspaces.json` of the data folder; no command opens it (release check that only says when a release exists, `setup-claude.sh`, `claude`); `list` and `forget` show and edit the registry; `update` lists the registered workspaces and updates all, the chosen ones, one folder (`<folder>`) or every one (`--all`, `--force`), by command and in a terminal only; `rollback`, `repair`, `check`, `version`. Inside a session it refuses `update`, `rollback`, `repair`, `forget` and the opening. The writable folders of an installed workspace are listed once, at its top; `aiwp.sh _writable` prints them for `guard-bash` | `aiwp new ~/my-workspace` |
| `setup-claude.sh` | Creates or syncs the git-ignored `.claude/` from `rules/agents/`, `rules/skills/` and the `rules/*.md` that carry a `paths:` front matter, plus every `custom/rules/*.md` as `.claude/rules/custom-*.md` and the paths of `custom/claude-md-excludes.txt` in `claudeMdExcludes`; installs the Fable alert once; when `custom/` is missing, asks for its git repo (`--custom-repo <url>`). A `SessionStart` hook runs it with `--quiet`; `--check` only reports | `bash scripts/setup-claude.sh --check` |
| `session-title.py` | `UserPromptSubmit` hook: on `/request <file>`, names the session `<project>-<n>` from the file's `**Project:**` line, `<n>` one more than the highest of that project among the running sessions of the workspace. On every message that names a project of `projects/` or a POC (folder name, path, `**Project:**` line; a path names its nearest repo, nested ones included), adds its state to the context when it has no marker or is out of date, so Claude warns and asks to run `/normalize-projects`; never blocks, bounded time, silent on errors | — (hook) |
| `aiwp-project-state.sh` | Prints whether each project and POC is a workspace project: the marker on line 1 of its `README.md` (of `developer`, read with `git show`) against `VERSION` and `migrations/`: no marker, up to date, out of date with the pending migrations, or the workspace's own repository. Read only; used by the hook, `aiwp-cmds.sh open`, the gate and `/normalize-projects` | `bash scripts/aiwp-project-state.sh billing-api` |
| `init-repo.sh` | Creates a project in `projects/` as an independent git repo, or a POC (`custom/pocs/`) or a tool of yours (`custom/tools/`) in the custom layer, the README of a project or POC starting with the marker of the workspace version; never writes in the core. Never overwrites | `bash scripts/init-repo.sh --type project --name billing-api` |
| `sync-env.sh` | Creates or completes the filled `.env` from a folder's `.env.example`, printing key names only: `custom/env/<name>.env` (mode 600) for `docker`, `docker/sonar` and `tools/<name>`, adding `env/` to `custom/.gitignore` when missing; `<dir>/.env` for a project or clone. Behind `/local-env` | `bash scripts/sync-env.sh --path docker` |
| `lib/env.sh` | Library: where the filled `.env` of a core folder lives and which file compose reads with `--env-file`. Sourced by `sync-env.sh`, `sonar.sh` and `validate.sh` | — |
| `lib/projects.sh` | Library: the layout of `projects/` (which folder is a repo). Sourced by `init-repo.sh`, `history.sh`, `aiwp-project-state.sh` and `aiwp-gate.sh` | — |

## Optional

| Script | Does |
| --- | --- |
| `history.sh` | Adds an entry to the `history.txt` of a project, of a tool of yours (`custom/tools/<name>`) or of a POC, or shows the last ones (`add`, `flush`, `show`); never in the core. No rule asks for history entries; `single-agent.sh import-history` uses it to bring a single-agent session's entries into its target |
| `single-claude.sh` | Run by the human, from a terminal: opens Claude in a project, a tool of yours or a POC folder without the workspace's instructions, hooks and skills (guide in `docs/single-agent.md`) |
| `single-agent.sh` | Support of that mode: target validation, the generated `SINGLE-AGENT.md`, its session names, `import-history` |

## Tests

Each suite runs alone, on throwaway folders: `bash scripts/tests/<name>/test-<name>.sh`. The Python tests (`scripts/tests/test_*.py`) run under the coverage gate: `bash scripts/validate.sh --only coverage`.

| Suite | Covers |
| --- | --- |
| `tests/check-workspace/` | `check-workspace.sh`, the ledger, and the argument handling and tracked-secret check of `validate.sh` |
| `tests/aiwp-cmds/` | `aiwp-cmds.sh`: clones, automatic push, pre-push refusals, Stop hook, close, up and rollback |
| `tests/aiwp-gate/` | `aiwp-gate.sh`: both gate phases, base that moved, conflicts, the audit, release (a protected `main` and its pull request, the `--tag` cases), apply, and the normalization steps against local bare remotes: `developer`, the checkpoint tags, `bring`, the gate that judges what the branch adds |
| `tests/guard-bash/`, `tests/test_guard_bash.py` | `guard-bash.sh` and `guard-bash.py` |
| `tests/guard-subagent-model/`, `tests/test_guard_subagent_model.py` | `guard-subagent-model.sh` and `guard-subagent-model.py` |
| `tests/setup-claude/` | `setup-claude.sh` |
| `tests/aiwp/` | `aiwp.sh`, the root `install.sh` and `release-notice.sh`, offline, on a fixture repository with two releases |
| `tests/sync-env/` | `sync-env.sh` and `lib/env.sh` |
| `tests/heavy-run/` | `heavy-run.sh` |
| `tests/single-agent/` | `single-agent.sh` and `single-claude.sh` |
| `tests/test-projects-layout.sh` | `init-repo.sh` (the marker included), `history.sh`, `lib/projects.sh` |
| `tests/aiwp-project-state/` | `aiwp-project-state.sh`: no marker, equal, older with and without a newer migration, README without marker, POC, the workspace's own repository |

A new suite is added to `SUITES` and `suite_inputs` of `check-workspace.sh`.
