# Functional request: Old names left in a decision record and in pending requests

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Source: the review of `request-lifecycle.md` (2026-11-17), a RECOMMENDED finding.

## What

`workspace/docs/decisions/0001-base-design.md` (lines 11 and 16) still lists `/prompt` in the mandatory core and the backlog in the custom layer; pending requests keep old paths: `final-review.md` (`maintainers/backlog/`), `import-from-fork.md` (`rules/skills/prompt/SKILL.md`), `rules.md` (`/prompt`), `review-effort-wording.md` (`caw-draft-prompt`), `prompt-log-results.md` (`custom/prompts/log/sources.json`). AC-5 of `request-lifecycle.md`.

## Where

Those files.

## Done when

0001 gets a "partly superseded" status line per `workspace/rules/docs.md` "Decision records" (or a new record); the pending requests name the new paths.

## Effort

low

## Execution — 2026-11-18, merged into developer

- **Done:** record 0001 names `/request` in the mandatory core and no longer lists a backlog in the custom layer or in
  `maintainers/`, with a change history line (74aa04e); its status line already said "partly superseded by 0003". The
  pending requests name the current paths: `final-review.md`, `import-from-fork.md`, `review-effort-wording.md`,
  `prompt-log-results.md`, and so do the plans `fork-my-rules.md` and `distribution.md`, the designs of pending
  requests (2210f6c). Two entries of the unreleased 0.2.0 in the root `CHANGELOG.md` adjusted (ab21088).
- **Decisions:** `rules.md` had moved to `qa/` since this request was written: left as the record of what ran (its
  Execution block already notes `/request` in place of `/prompt`). The built plans `rules-config.md` and
  `normalize-projects.md`, and the history lines of 0001, keep the old names as history.
  `workspace/scripts/tests/test_prompt_log.py` writes the old `custom/prompts/log/sources.json` on purpose: it proves
  that place is no longer read. No product changelog entry: the fix completes renames of the same unreleased version.
- **Deviations:** the two plans were not in the list; fixed because pending requests are built from them.
- **Done when:** met. AC-5 of `qa/request-lifecycle.md` (nothing refers to the old names) is met for the pending
  requests and the decision record.
- **Checks:** `bash tests/check.sh --base origin/developer --i18n-pending` passed (50 translations pending; repo-terms
  skipped: no terms list); a search of the pending requests, the plans and the decision records for the old names
  finds only the history named above. No review: documentation only (`.claude/rules/review.md`).
- **Left:** `review-effort-wording.md` may be half done: `.claude/skills/caw-draft-request/SKILL.md` no longer says
  every review is effort high; only `docs/maintenance.md` is left to check.
