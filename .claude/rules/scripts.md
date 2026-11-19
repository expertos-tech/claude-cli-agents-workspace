---
paths:
  - "tests/**"
  - "install.sh"
  - "**/*.sh"
  - "**/*.py"
  - "workspace/scripts/**"
---

@workspace/rules/scripts.md

The sections below win where they differ; its `paths:` do not limit it here.

---

## Ignore from the product rule

- Reuse, "Workspace scripts run from the workspace root ... never write in the core": that is how the product runs
  installed. Here the scripts run from the root of this repository or of a work clone.

## Mapping

| Product | Here |
| --- | --- |
| `scripts/`, `scripts/README.md`, `scripts/tests/`, `scripts/check-workspace.sh` | `workspace/scripts/`, its `README.md`, `workspace/scripts/tests/`, `workspace/scripts/check-workspace.sh` |
| `bash scripts/aiwp-cmds.sh run <work>/<clone> -- <command>` | `bash tests/caw-work.sh run <work> -- <command>` |
| `tmp/` of the workspace | `tmp/` of this repository |

## CAW rules

- Follow the style of `workspace/scripts/`: `set -euo pipefail` or `-uo` with explicit checks, a `--help` with usage,
  what it does and examples, exit codes `0` success, `1` a failed check, `2` a usage error.
- Portable forms where it must run on macOS: no GNU-only `sed -i`, `stat -c` or `readlink -f`.
- Python runs with `python3 -I`, standard library first, a docstring on every function.
- A script in `tests/` is exercised by running it, and gets `bash -n` and shellcheck by hand.
- Lint and format through the product's containers, the same the gate uses: shellcheck
  (`bash workspace/scripts/validate.sh --only shell`), ruff check and ruff format with
  `workspace/docker/config/ruff.toml` (`--only python`). `bash tests/check.sh --all` runs them on the changed files of
  `workspace/`.
