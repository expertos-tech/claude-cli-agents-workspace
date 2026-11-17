# Product /merge --main points a failure of the full check to the wrong step

| Field | Value |
| --- | --- |
| Type | defect |
| Status | idea |
| Priority | low |
| Target | workspace |
| Created | 2026-11-17 |
| Source | the review of the merge of `requests/done/review-and-translation-cadence.md` into `developer` |

## Problem

`workspace/rules/skills/merge/SKILL.md` "Release" step 2 says a failing test or check "is a BLOCKER of step 4", but step 4 dates the version; the fix-and-rerun loop is in step 3. The agent may run the final review with a red suite.

## Expected result

Step 2: a failure is fixed in the clone and step 2 runs again before step 3.
