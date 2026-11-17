# Functional request: process.md names the old suite command for a merge

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Created 2026-11-17 as a backlog item (defect, priority low, target maintenance); source: the review of the merge of `requests/done/review-and-translation-cadence.md` into `developer`.

## What

`.claude/rules/process.md` step 4 still says `/caw-merge` takes each request into `developer` "with `bash tests/check.sh --all` green", while step 5 and `/caw-merge` run `--base origin/developer --i18n-pending` without `--all`. An agent that follows step 4 runs the strict suite and fails on the translations left pending for the release.

## Done when

Step 4 names `bash tests/check.sh --base origin/developer --i18n-pending`.

## Effort

low
