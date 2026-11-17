# Functional request: review.md's final review brief names Unreleased sections already dated

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Created 2026-11-17 as a backlog item (defect, priority low, target maintenance); source: the review of the fix eb40e43 (release commit checked before it merges).

## What

`.claude/rules/review.md` "Final review" gives the brief "the `Unreleased` sections of the changelogs" and says it runs after the translations and the suite, with no mention of the version and dates commit; since that commit now comes first, those sections are dated when the review runs.

## Done when

The brief names the changelog sections of the version being released, and the order lists the version and dates commit before the suite.

## Where

`.claude/rules/review.md`, "Final review".

## Effort

low
