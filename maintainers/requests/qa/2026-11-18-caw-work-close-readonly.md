# caw-work close with read-only files

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

## Requested

The owner, 2026-11-18, answering W-9 of the merge of `preferred-language` with "fix": `bash tests/caw-work.sh close`
deleted the remote work branch, then stopped on "Permission denied" over the read-only files of a test installation
inside the clone (`tmp/test-install/`, 444 and 555 by design), leaving a clone with no `.git` that a second `close`
refused as "not a clone made by open".

**What:** `close` (and `close --discard`) deletes a work folder that holds read-only files completely, and deletes the
remote work branch only after the folder is gone.
**Done when:** a clone with a test installation closes in one run; a failed delete keeps the remote branch and a
second `close` finishes.
**Effort:** high

---

## Execution — 2026-11-18, merged into developer

Done:

- `e67d6e5` `tests/caw-work.sh`: `remove_folder` makes the work folder writable (`chmod -R u+rwX`, never through a
  symlink) and deletes it, then checks it is gone; only then `delete_remote_branch` deletes the remote branch, for a
  work branch name only, never forced, from the root repository (the clone is gone by then). A failed delete exits 1,
  names up to five paths left and keeps the remote branch. `--help` of `close` says so. Three scenarios in
  `tests/test-caw-work.sh`: the observed case end to end, `--discard` with a read-only tree, and a failed delete (an
  `rm` stub) that keeps the branch until a later `close` finishes.
- Changelog: the `tests/caw-work.sh` entry of 0.2.0 adjusted (the same unreleased version: no "Fixed" entry).

Deviations: the remote delete runs from the root repository instead of through the clone's pre-push hook; the work
branch pattern of `caw-work.sh` takes the place of the hook's refusal of `developer`, `main` and tags.

Done when: proven by the scenarios (the three new ones failed before the fix with "Permission denied" and the remote
branch already deleted).

Checks: `bash tests/check.sh --base origin/developer --i18n-pending` rc 0 (repo-terms skipped: no terms list found);
`tests/test-caw-work.sh` 39 scenarios; shellcheck -x clean (the gate's pinned image).

The merge review (APPROVED_WITH_WARNINGS), both accepted by the owner ("ignore warnings", 2026-11-18):

- W-10: an `rm -rf` that fails partway for a reason other than permissions may have removed the clone's `.git`; a
  second `close` then refuses it and only `--discard` clears it, leaving the remote branch (named in the error).
- W-11: the remote delete is a `git push --delete` from the root, outside the clone's pre-push hook, limited to a
  work branch name and never forced.

Left: nothing.
