# Functional request: the follow-ups of validators-warn-not-block

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**State:** ready. **Where it runs:** at the repository root, where the project is maintained; it changes the product
(`guard-bash`) and the maintenance (`tests/`, `/caw-merge`). Source: the merge of `validators-warn-not-block`
(2026-11-18): its review's warnings on AC-2 and BR-11, and the warnings of its closing board. The drift between the
two lists of hard rules (AC-7) is `rules-as-product-layers`.

## 1. Objective

Close what `validators-warn-not-block` left open: prove that the review still stops each hard rule and lets the rest
through as warnings, show every warning of `guard-bash` even when it refuses a line, and let the test installation
run inside a work clone, so a change to a hook is proven where it was made.

## 3. Business rules

- BR-1: a set of review fixtures, one diff per hard rule of `workspace/rules/security.md` "Hard rules" (a secret
  committed, a force push to a shared branch, a git write in `projects/` outside the gate, a merge without the
  person's order, a database or Grafana's data deleted without confirmation, an irreversible change nobody asked
  for), each expected as BLOCKER; and at least three expected as WARNING only (a lint failure, a dependency with a
  known vulnerability, a scenario that needs someone writing code to escape a check on purpose).
- BR-2: the fixtures run against the `reviewer` agent with the effort of a merge into `developer` (`medium`), each
  judged by the level of its findings; a run reports per fixture the expected and the actual level. They run at the
  release (`/caw-merge --main`, with the full suite), never at each commit: they call the model.
- BR-3: a fixture that fails at the release is a WARNING of the release for the owner to decide, never a refusal by
  itself (the review rules may need the fix, not the release).
- BR-4: when `guard-bash` refuses a line with "Run it alone", the warnings of the other commands of that line are
  shown with the refusal, in the format of `workspace/rules/security.md` "Warnings", as they are with an ask.
- BR-5: a work clone's pre-push lets through a push whose destination is a local folder inside that clone's `tmp/`
  (the throwaway repository of `tests/test-install.sh`), for any branch; every other push of `main`, `developer`, a
  tag or a force push stays refused, and the company-terms scan still runs on it.
- BR-6: `/caw-test-install` runs from the work clone itself, with no hook-free copy of the branch.

## 4. Acceptance criteria

- AC-1: Given the fixtures of BR-1, when they run, then each hard-rule fixture is reported BLOCKER and each
  warning-only fixture has no BLOCKER; the run prints one line per fixture with the expected and the actual level.
- AC-2: Given `/caw-merge --main`, then the fixtures run once with the full suite, and a failing one appears in the
  findings of the release as a WARNING.
- AC-3: Given the line `bash scripts/aiwp-cmds.sh release billing-api && bash scripts/aiwp-cmds.sh deploy
  billing-api`, when `guard-bash` judges it, then it refuses with "Run it alone" and shows the WARNING of `deploy`
  (a test of the hook's suite).
- AC-4: Given a work clone, when `bash tests/test-install.sh` runs in it, then the snapshot reaches its throwaway
  repository and the installation checks run; a push of `main` to `origin` from the same clone is still refused
  (scenario tests of `tests/test-caw-work.sh`).

## 7. Out of scope

- The severity of trivy's secret scanner in `secrets` (still HIGH and CRITICAL): accepted by the owner.
- The agreement of the two lists of hard rules: `rules-as-product-layers`.
- Any other change to the review rules or to the hard rules.

## 11. Steps and effort

| Step | Effort | Why |
| --- | --- | --- |
| 1. "Run it alone" shows the line's warnings (BR-4, AC-3) | high | A hook of the mandatory core |
| 2. The pre-push lets the test installation through, and `/caw-test-install` runs from the clone (BR-5, BR-6, AC-4) | high | A hook that guards what leaves the machine |
| 3. The review fixtures and their run at the release (BR-1 to BR-3, AC-1, AC-2) | medium | Tests and a step of `/caw-merge --main` |

The subagents of each step run with the step's effort, passed in the call.

## Assumed decisions

- Open: the severity of trivy's secret scanner. Decided: HIGH and CRITICAL, unchanged. Reason: gitleaks is the
  main scanner, and a MEDIUM false positive would now stop the gate, because `secrets` is a hard rule.
- Open: where the fixtures run. Decided: at the release only. Reason: they call the model, so they are not
  deterministic and cost tokens; once per release is enough to catch a review rule that drifted.
- Open: how the test installation gets past the pre-push. Decided: the hook lets through a local destination inside
  the clone's `tmp/`, an allowlist, instead of `tests/test-install.sh` turning the hooks off. Reason: turning hooks
  off is the kind of bypass the hooks exist to stop.
