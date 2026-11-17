# /caw-merge --main does not say what to do when developer moves

| Field | Value |
| --- | --- |
| Type | defect |
| Status | idea |
| Priority | medium |
| Target | maintenance |
| Created | 2026-11-17 |
| Source | the review of the fix eb40e43 (release commit checked before it merges) |

## Problem

During the strict suite or the final review of a release, another session merges into `developer`. "From a clone" step 5 then says "back to step 1", which reopens a clone that exists and runs the non-strict phase 1 and the diff-only review: the new commits would reach `main` without the strict suite or the final review.

## Expected result

Release step 6: `origin/developer` moved: merge it in the clone, put its entries into the dated `X.Y.Z` sections, and go back to step 4.

## Where

`.claude/skills/caw-merge/SKILL.md`, "Release" step 6.
