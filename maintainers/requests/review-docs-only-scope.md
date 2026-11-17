# Functional request: Instruction files count as documentation and skip the review

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Created 2026-11-17 as a backlog item (defect, priority low, target maintenance); source: the review of the merge of `requests/done/review-and-translation-cadence.md` into `developer`.

## What

`.claude/rules/review.md` "When" treats every `*.md` outside `.claude/` and `workspace/rules/` as documentation, so a merge that only edits `CLAUDE.md`, `workspace/AGENTS.md`, `workspace/CLAUDE.md` or `workspace/templates/*.md` (instructions, some of them mandatory core) gets no review until the release.

## Done when

Those paths are out of "documentation only": effort medium, and high when they touch security or secrets.

## Effort

low
