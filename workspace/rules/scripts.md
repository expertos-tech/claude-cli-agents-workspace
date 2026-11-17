---
paths:
  - "**/*.sh"
  - "**/scripts/**"
---

# scripts.md

## Reuse

- Before writing a shell command longer than one line: check `scripts/README.md`. If a script fits, use it.
- A script that serves other tasks goes to `scripts/`: parametrized, with `--help`, and an entry in `scripts/README.md` written from its `--help`, not from a plan. A one-off runs inline and is never saved there.
- An existing script that almost fits: evolve it with a new parameter, keep backward compatibility, update its README entry.
- Workspace scripts run from the workspace root (`bash scripts/<name>.sh`) and never write in the core: their output goes to `custom/`, `projects/`, `tmp/` or `.history/`. A project's own scripts run in its clone (`bash scripts/aiwp-cmds.sh run <work>/<clone> -- <command>`).

## Writing a script

- `#!/usr/bin/env bash`, `set -euo pipefail`, every argument validated, non-zero exit on failure, idempotent where possible, no secret, no hard-coded path or project name.
- Output concise by default (a summary and the failures); `--verbose` for the rest.
- Name: `kebab-case.sh`, verb first, or the subsystem noun when it has subcommands.
- Git checks inside a script use `git -C <repo>`, never the caller's cwd.
- A script in `scripts/` is linted (`bash scripts/validate.sh --only shell`) and has scenario tests under `scripts/tests/`: the possible paths, a few error paths, one regression test per defect found. A new suite is added to `SUITES` and `suite_inputs` of `scripts/check-workspace.sh`.
- A script in `tools/<item>/` or `custom/pocs/<item>/` only has to parse (`bash -n`).

## Running

- A command that may pass 3 minutes: run it in the background. Never a polling loop.
- Start a check of a clone only after the commit or merge it checks has returned, never as a parallel call beside it.
- Never edit a script while a background run of it is going: bash reads the file as it runs.
- Inline shell runs in zsh: never name a variable `path` (it replaces `PATH`), and never expect `$list` to split into words; use `bash -c` with an array.
- Searching references across nested repos: `git -C <repo> grep` in each repo, because a recursive `grep` from the outer one can skip ignored paths.
- A temporary file goes to the Claude Code scratchpad, or to `tmp/` of the workspace when a Docker check has to see it. Never into a repo.

## Check ledger

- `scripts/validate.sh` and `scripts/check-workspace.sh` record each PASS in `.history/check-ledger/`, under a hash of the check, its input files and the gate scripts. Same hash: `CACHED <check>`, and the check does not run again. `--no-cache` forces the run. `vuln` and `iac` expire in 24 h.
- A `CACHED` line is a result. Do not run the check again to confirm it.
