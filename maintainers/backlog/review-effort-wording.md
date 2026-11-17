# Docs and /caw-draft-prompt still say every review is effort high

| Field | Value |
| --- | --- |
| Type | defect |
| Status | idea |
| Priority | low |
| Target | maintenance |
| Created | 2026-11-17 |
| Source | the review of the merge of `requests/done/review-and-translation-cadence.md` into `developer` |

## Problem

`docs/maintenance.md` (the paragraph above the subagents table) and `.claude/skills/caw-draft-prompt/SKILL.md` ("Steps and effort") say every review runs with effort high, while `.claude/rules/models.md` and `review.md` set the effort by risk. New requests would keep asking for high on every review.

## Expected result

Both say the effort goes by risk, as `models.md` does.
