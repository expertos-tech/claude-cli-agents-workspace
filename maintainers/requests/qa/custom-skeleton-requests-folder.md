# Functional request: a new custom layer starts with its requests/ folder

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Created 2026-11-20; source: a test installation with `--developer`.

## What

The skeleton of a new custom layer (`aiwp new`, also for an empty remote) writes a `README.md` that describes
`requests/` as if it were there, but the folder is created only at the first use, so a new workspace has none and a
session that lists it fails. The skeleton creates `requests/`, empty but kept by git (a `.gitkeep`), in the same
commit; the README line on `requests/` also names `doing/` (in progress), which it leaves out today (assumed
decision).

## Where

`workspace/scripts/aiwp.sh`, `custom_skeleton`.

## Done when

- `aiwp new` creates `custom/requests/` in its first commit of the custom layer, with an empty remote too.
- The README of the new custom layer lists `requests/` with `doing/`, `qa/<project>/` and `done/<project>/`.

## Out of scope

Custom layers that already exist: nothing changes in them (`aiwp update` never touches `custom/`).

## Effort

high: `aiwp new` is a step of the installer (`.claude/rules/models.md`).

---

## Execution — 2026-11-20, merged into developer

- **Done:** `custom_skeleton` of `workspace/scripts/aiwp.sh` creates `requests/` with an empty `.gitkeep` before its
  `git add -A`, so the folder is in the first commit of the custom layer, for a new local repository and for an empty
  remote alike; the README line on `requests/` names `doing/` while in progress, then `qa/<project>/` and
  `done/<project>/` (9e200db). Two checks added to the scenarios of `workspace/scripts/tests/aiwp/test-aiwp.sh`, one
  per case, and a shellcheck fix of one of them (4679172). The request lifecycle entries of both changelogs
  (3f85af5).
- **Decisions:** the assumed decision of the request holds: the README names `doing/`. The README line on
  `requests/` entered in this same unreleased version (v0.1.0 had none), so the changelogs adjust its entry, with no
  Fixed entry.
- **Deviations:** none.
- **Done when:** `aiwp new` creates `custom/requests/` in its first commit, with an empty remote too: proven by the
  scenarios (the local skeleton with no terminal, and `--custom` on an empty bare repository: one commit, holding
  `requests/.gitkeep`) and by `tests/test-install.sh`, whose installation's `custom/` has one commit with
  `requests/.gitkeep`. The README lists `requests/` with `doing/`, `qa/<project>/` and `done/<project>/`: proven by a
  scenario and read in the test installation.
- **Checks:** the `aiwp` suite (46 run, 0 failed); `bash tests/check.sh --base origin/developer --i18n-pending`
  passed (repo-terms skipped: no terms list); `bash tests/test-install.sh` from the clone: every check PASS.
- **Warnings:** none.
- **Left:** nothing.
