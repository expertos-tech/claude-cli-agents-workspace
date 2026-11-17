# Functional request: the performance measurement counts defects that reach the base and the share of process commits

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained, with the product in `workspace/`
(`scripts/performance/measure.py`, `scripts/tests/test_performance.py`, the performance README). It must run **after
`import-from-fork`**, which also changes `measure.py` (hook median and p90, BR-9 there); it runs after that one, in
round 2 of `maintainers/requests/README.md`.

## 1. Objective

When the owner approved the simplification of the workspace ("make all the necessary changes"), its phase 6, "measure
again", set the indicators that tell whether the cut went too far. `measure.py` now measures process and validation
share, questions, first edit, hooks and cost, but two indicators of that table were never built: **defects that reach
the base** ("start counting; it is the indicator that says whether the cut went too far") and **the share of process
commits** (target below 15%). The closing review was removed without a replacement; "if defects start reaching the
base, it is the first place to look". This request adds both indicators to the report and its comparison with the last
reports.

## 3. Business rules

- BR-1: **Defects that reach the base**, per project and total for the period: commits on `developer` (and `main`)
  that fix something already merged by the gate. Counting rule in decision 1. Each one is listed with project, short
  sha, subject and the merged commit it fixes when it can be found (a `revert` names it; a `fix` touching the same
  files within N days of a gate merge).
- BR-2: **Process commits**, per project and total: the share of agent commits (`[#automatic-agent-commit]`) whose
  type is process work rather than delivery (decision 2), against all agent commits of the period.
- BR-3: both indicators enter the numbers block that travels inside each report, so the next report compares with the
  previous one and with the last five, like the others; older reports without them stay readable (a missing value is
  shown as "not measured").
- BR-4: only git metadata is read (subjects, types, files touched, dates); no file content, no prompt text, the same
  privacy rule as today.
- BR-5: the report says in one line how each indicator is counted, so a reader can judge it.

## 4. Acceptance criteria

- AC-1: Given a project whose `developer` has a gate merge followed, within the window, by a `fix:` agent commit that
  touches the same files, when `measure.py` runs, then the report lists one defect for that project with both shas.
- AC-2: Given a `revert` of a merged commit, then it counts as a defect and names the reverted commit.
- AC-3: Given 20 agent commits of which 3 are process commits, then the share shown is 15%.
- AC-4: Given an older report without these numbers, then the comparison shows "not measured" for them and does not
  fail.
- AC-5: `tests/test_performance.py` covers each rule.

## 7. Out of scope

- Classifying human commits.
- Bringing back a closing review (the indicator only tells whether it is needed).

## Decisions for the owner

1. **What counts as a defect that reached the base.** Recommended: a `revert` of a merged commit, or a `fix:` commit
   on `developer` that touches a file changed by a gate merge in the previous 7 days. Alternative: only commits whose
   request or message says "bug"/"defect".
2. **What is a process commit.** Recommended: commit types `chore`, `ci`, `build` and `docs` that touch only workspace
   process files (prompt log, lessons, requests), against `feat`, `fix`, `refactor`, `perf`, `test` and project docs.
3. **Targets.** Show the old targets (process commits below 15%, defects "counted") next to the values, or only the
   values? Recommended: only the values plus the trend; the old targets were set for the previous design.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Both indicators, the report block, compatibility, with the suite | medium | Clear counting rules over git metadata |

The agents of each stage run with the stage's effort, passed in the call.
