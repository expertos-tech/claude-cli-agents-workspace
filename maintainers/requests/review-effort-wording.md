# Functional request: Docs and /caw-draft-prompt still say every review is effort high

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Created 2026-11-17 as a backlog item (defect, priority low, target maintenance); source: the review of the merge of `requests/done/review-and-translation-cadence.md` into `developer`.

## What

`docs/maintenance.md` (the paragraph above the subagents table) and `.claude/skills/caw-draft-prompt/SKILL.md` ("Steps and effort") say every review runs with effort high, while `.claude/rules/models.md` and `review.md` set the effort by risk. New requests would keep asking for high on every review.

## Done when

Both say the effort goes by risk, as `models.md` does.

## Effort

low
