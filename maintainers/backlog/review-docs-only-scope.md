# Instruction files count as documentation and skip the review

| Field | Value |
| --- | --- |
| Type | defect |
| Status | idea |
| Priority | low |
| Target | maintenance |
| Created | 2026-11-17 |
| Source | the review of the merge of `requests/done/review-and-translation-cadence.md` into `developer` |

## Problem

`.claude/rules/review.md` "When" treats every `*.md` outside `.claude/` and `workspace/rules/` as documentation, so a merge that only edits `CLAUDE.md`, `workspace/AGENTS.md`, `workspace/CLAUDE.md` or `workspace/templates/*.md` (instructions, some of them mandatory core) gets no review until the release.

## Expected result

Those paths are out of "documentation only": effort medium, and high when they touch security or secrets.
