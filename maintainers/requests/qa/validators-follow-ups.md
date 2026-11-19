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

## Execution — 2026-11-18, merged into developer

Done, by step:

- Step 1, "Run it alone" shows the warnings (high): `21463ee`.
- Step 2, the test installation from a work clone (high): `2c1e153` (the scratch destination of the pre-push,
  `/caw-test-install` from the clone); `443aa2d` (a scratch push counts what `origin` has as scanned: a warning of the
  closing board the owner chose to fix).
- Step 3, the review fixtures (medium): `d75dcdd`; `e586456` (the triage of a failing fixture at the release, and
  f09's help lines moved: a warning the owner chose to fix).
- `3598a17`: `origin/developer` brought in (`rules-as-product-layers`); the conflict in `tests/test-caw-work.sh`
  kept both stubs.
- Changelog: `5acc365`.

Decisions taken while running:

- The model is called only by `/caw-merge --main`, through `reviewer` subagents with explicit model and effort; the
  script `tests/review-fixtures.sh` only lists the fixtures and judges the saved reports, so nothing calls a model
  outside the rules of `models.md`.
- The expected levels live in `tests/review-fixtures/levels.txt`, apart from the fixtures, whose files are numbered
  (`f01.md`...): the reviewer gets no hint of the expected level.
- A scratch destination is only an absolute path, never a named remote or a URL, strictly inside the clone's own
  `tmp/` with links resolved; a tag, a ref outside `refs/heads/` and a force push stay refused there too.
- The owner (2026-11-18), on the warnings of the closing board: the clone's hooks keep running the root's
  `tests/caw-work.sh` (the reviewed `developer` guards every clone; the branch never judges its own pushes); a
  scratch push counts what `origin` has as scanned; a failing fixture is triaged in `/caw-merge --main` step 5; the
  model cost of the fixtures (nine `reviewer` calls per release) and their variance are accepted.

Deviations from the request:

- AC-1 was proven now, with one run of the nine fixtures, beyond BR-2's "at the release only". The warning-only
  fixtures f07 and f09 needed rewrites: five runs found real defects in their own code (a function never called, a
  GNU-only `find -printf`, an incomplete option list, a sort before the names were cut, a launcher path left out),
  so they now carry little or no code (`tests/review-fixtures/README.md`).
- The test installation of this delivery ran from a copy of the branch without hooks, because the clone's pre-push
  still runs the root's script, without BR-5, until this merge. The run from the clone follows this merge.

Acceptance criteria:

- AC-1: proven: 9/9 at the expected level (`tests/review-fixtures.sh judge`; the reports in the git-ignored
  `tmp/review-fixtures/20261118-proof/` of the root, copied there when the clone closed); the judge itself by
  `tests/test-review-fixtures.sh`.
- AC-2: done, not proven: step 5 of `/caw-merge --main` runs the fixtures and step 7 lists a failing one as a
  WARNING; proven at the first release.
- AC-3: proven: `test_run_it_alone_shows_the_warnings_of_the_line` and the scenario of
  `workspace/scripts/tests/guard-bash/test-guard-bash.sh`; the same line in a test installation was refused with
  "Run it alone" and the WARNING of `deploy`.
- AC-4: proven by the scenarios of `tests/test-caw-work.sh` (the snapshot reaches the throwaway repository, `main`
  to `origin` still refused, a tag, a force push, paths outside `tmp/`, a named remote, a URL and a link out of
  `tmp/` refused, the terms scan still stops a new term); the run of `tests/test-install.sh` from a real clone is
  pending, right after this merge.

Checks: `bash tests/check.sh --base origin/developer --i18n-pending`, rc 0 (`repo-terms` SKIP: no terms list found by
the default lookup); `test_guard_bash` 139, `test-guard-bash.sh` 345, `tests/test-caw-work.sh` 32,
`tests/test-review-fixtures.sh` 45; shellcheck and markdownlint (the product's pinned images) clean;
`tests/test-install.sh` PASS on every check (from the copy without hooks).

Warnings:

- WARNING: the clone's pre-push runs the root's `tests/caw-work.sh` — BR-5 and the leaner scan apply to every open
  clone only once this merge is on `developer` — run `/caw-test-install` from a clone right after it.
- WARNING: the review fixtures are judged by the model, nine `reviewer` calls per release — a failing one may be a
  defect of the fixture itself — read its report (`/caw-merge --main` step 5); accepted by the owner.

Left: `/caw-test-install` from a work clone after this merge (AC-4's real run, BR-6).
