# Functional request: Product /merge --main points a failure of the full check to the wrong step

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Created 2026-11-17 as a backlog item (defect, priority low, target workspace); source: the review of the merge of `requests/done/review-and-translation-cadence.md` into `developer`.

## What

`workspace/rules/skills/merge/SKILL.md` "Release" step 2 says a failing test or check "is a BLOCKER of step 4", but step 4 dates the version; the fix-and-rerun loop is in step 3. The agent may run the final review with a red suite.

## Done when

Step 2: a failure is fixed in the clone and step 2 runs again before step 3.

## Effort

low

---

## Execution — 2026-11-17, merged into developer (with `request-lifecycle.md`)

- **Done:** the "Release" section of `workspace/rules/skills/merge/SKILL.md` was rewritten (327598a): a failing check
  is a BLOCKER gathered in step 5 with the other findings, with no reference to a wrong step.
- **Done when:** met.
