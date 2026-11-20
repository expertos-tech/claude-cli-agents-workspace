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
