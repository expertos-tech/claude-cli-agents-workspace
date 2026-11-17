---
name: test-install
description: "Install a disposable work workspace from the current tree into tmp/test-install/<date>/ and exercise the hooks and scripts end to end. Use after a change to the installer, a hook or setup-claude.sh, and before a release."
argument-hint: "[--keep]"
model: claude-opus-5-5
effort: high
---

Arguments: `$ARGUMENTS`. `--keep`: leave the installation in place for inspection; default: leave it too, and say its
path (it is git-ignored and disposable).

Never copy `workspace/` by hand to fake an installation: always go through `install.sh` and `aiwp new`.

## Procedure

1. Run `bash tests/test-install.sh` (in the background if it may pass 3 minutes). It snapshots the current tree
   (commits and working changes, git-ignored files left out) into a throwaway bare repository tagged
   `v<workspace/VERSION>`, and runs `install.sh` with a temporary HOME and data folder, no terminal and
   `AIWP_WORKSPACE`, so the installer itself creates the workspace (`aiwp new`, a local custom skeleton), all under
   `tmp/test-install/<timestamp>/`.
2. It checks the installation and prints PASS or FAIL per check: no `.git` at its root; core folders and executables
   555, other core files 444; the writable folders present (`custom/`, `projects/`, `tmp/`, `.claude/`, `.history/`
   and the closed list of tool outputs at the top of `workspace/scripts/aiwp.sh`); the manifest lists exactly the
   files of `workspace/` with their hashes and modes; the workspace is in the registry (`workspaces.json`); `aiwp
   repair` finds nothing to repair.
3. **It fails if any file from outside `workspace/` appears** in the installation: the root `CLAUDE.md`, `.claude/`,
   `tests/`, `maintainers/`, `tmp/`, `i18n/`, `install.sh`, `README.md`, `LICENSE`.
4. Start a Claude Code session in the installation with the `open a session:` command the script prints (in a
   terminal, or in tmux for a driven test) and exercise the hooks the change touched, and always the mandatory
   ones: `guard-bash` (a refused git write in `projects/` and the core, a refused `chmod` on a core path),
   `guard-subagent-model`, `Stop`, `session-title`, `prompt-log`, and `setup-claude.sh` at session start.
5. Report: the installation path (the script prints it, with the HOME it used), each check with pass or fail, and what
   was exercised by hand. To remove an installation: `chmod -R u+w <dir> && rm -rf <dir>`.

Never run the product's `setup-claude.sh` or hooks inside `workspace/` of this repository.
