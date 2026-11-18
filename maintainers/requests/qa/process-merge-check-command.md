# Functional request: process.md names the old suite command for a merge

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Created 2026-11-17 as a backlog item (defect, priority low, target maintenance); source: the review of the merge of `requests/done/review-and-translation-cadence.md` into `developer`.

## What

`.claude/rules/process.md` step 4 still says `/caw-merge` takes each request into `developer` "with `bash tests/check.sh --all` green", while step 5 and `/caw-merge` run `--base origin/developer --i18n-pending` without `--all`. An agent that follows step 4 runs the strict suite and fails on the translations left pending for the release.

## Done when

Step 4 names `bash tests/check.sh --base origin/developer --i18n-pending`.

## Effort

low

## Execution — 2026-11-18, merged into developer

- **Done:** `.claude/rules/process.md` step 4 names `bash tests/check.sh --base origin/developer --i18n-pending` for
  the merge into `developer` (d92a4fa). The same session added the closing board on the owner's order
  (`qa/2026-11-18-maintenance-closing-board.md`).
- **Decisions:** the other mentions of `tests/check.sh --all` (`.claude/rules/security.md`, `.claude/rules/scripts.md`,
  `docs/maintenance.md`) describe what the strict run does, not the merge command: left as they are. The pt-BR and es
  `docs/maintenance.md` still say `--all` on every change: pending translations, updated at the release.
- **Done when:** met.
- **Checks:** `bash tests/check.sh --base origin/developer --i18n-pending` passed (50 translations pending; repo-terms
  and secrets skipped: no terms list, no targets); markdownlint-cli2 on a copy of `process.md`: 0 issues.
- **Left:** nothing.
