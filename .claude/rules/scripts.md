---
paths:
  - "tests/**"
  - "install.sh"
  - "**/*.sh"
  - "**/*.py"
  - "workspace/scripts/**"
---

# scripts.md

- Follow the style of `workspace/scripts/`: `#!/usr/bin/env bash` and `set -euo pipefail` (or `-uo` with explicit
  checks), a `--help` with usage, what it does and examples, every argument validated, exit codes `0` success, `1` a
  failed check, `2` a usage error, no hard-coded personal path or project name, git through `git -C <repo>`.
- Portable forms where it must run on macOS: no GNU-only `sed -i`, `stat -c` or `readlink -f`.
- Python runs with `python3 -I`, standard library first, a docstring on every function.
- Tests: a script in `workspace/scripts/` has scenario tests in `workspace/scripts/tests/` (the paths, a few error
  paths, one regression test per defect) and its suite is listed in `workspace/scripts/check-workspace.sh`. A script in
  `tests/` is exercised by running it.
- Lint and format through the product's containers, the same the gate uses: shellcheck
  (`bash workspace/scripts/validate.sh --only shell`), ruff check and ruff format with
  `workspace/docker/config/ruff.toml` (`--only python`). `bash tests/check.sh --all` runs them on the changed files of
  `workspace/`; a script in `tests/` gets `bash -n` and shellcheck by hand.
- A command that may pass 3 minutes runs in the background. Never edit a script while a run of it is going.
- Temporary files go to the scratchpad or `tmp/`, never into a tracked folder.
