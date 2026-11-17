# Release tag after a pull request into a protected main

| Field | Value |
| --- | --- |
| Type | improvement |
| Status | idea |
| Priority | medium |
| Target | workspace |
| Created | 2026-11-17 |
| Source | the stage that added `aiwp-cmds.sh release --tag` (`requests/done/merge-versioned-changelog.md`) |

## Problem

When the remote refuses the push of a protected `main`, `release --pr-if-refused --tag vX.Y.Z` opens a pull request and
creates no tag. GitHub merges it with a merge commit or a squash, so `main` is no longer equal to `developer`, and a
rerun of `release --tag` stops with "main has commits that are not in developer": the version is never tagged.

## Expected result

A tag-only path (for example `release <repo> --tag-only vX.Y.Z`) that tags the merge commit of the release on the
remote `main` once the pull request is merged, with the same never-move checks; `/merge --main` calls it after the
merge.
