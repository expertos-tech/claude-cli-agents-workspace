# process.md

How the project is maintained. Every change goes through these steps; a typo fix may skip 2 and 3.

## 1. Evaluate

- Read the product in `workspace/` as code: what it does, its tests, its docs.
- Real use is evidence, read only: an installed work workspace, session transcripts, the prompt log, measurements
  (`workspace/scripts/performance/measure.py`). Never edit an installed workspace or its custom layer from here.
- A finding that names a company, a customer, a person or a project stays in the git-ignored `tmp/` or in the owner's
  custom layer. What reaches the repository is the general lesson, written without those names (`security.md`).

## 2. Plan

- A plan lives in `maintainers/plans/<kebab-name>.md`: the problem, the options with their trade-offs, a
  recommendation, and numbered decisions (D-1, D-2...) for the owner to answer.
- Ask only what has no best alternative; list the rest as assumed decisions the owner can overturn.
- The plan stays the design reference after the request is written; update its status line when the request is built.
- A plan the owner approves in a session (plan mode) is recorded at once, in English and in the request format, in
  `maintainers/requests/done/<kebab-name>.md`, with its row in `maintainers/requests/README.md`.
- A plan or request is shown to the owner in the language they wrote in, and saved in English; say so in one line.

## 3. Request

- With the owner's answers, write `maintainers/requests/<kebab-name>.md` in the format of `workspace/templates/request.md`:
  objective, business rules (BR-n), acceptance criteria (AC-n, verifiable), out of scope, and the stages with the
  effort of each.
- Add the request to the table of `maintainers/requests/README.md`, in the order it runs.
- `/caw-draft-prompt` writes plans and requests; `requirements-analyst` finds the gaps of a long or ambiguous one.

## 4. Execute

- One stage at a time (`/caw-prompt <name>`). Say the effort of each stage as it starts.
- Subagents always get an explicit model and effort (`models.md`). Writers run in parallel only on disjoint paths.
- `/caw-prompt` works in a clone on a work branch under `tmp/work/<yyyy-mm-dd>-<slug>/` (`claudeMdExcludes` covers
  `tmp/**`), so several requests run in separate sessions, each in its own clone. Respect the order in
  `maintainers/requests/README.md`: a request starts only after the ones it depends on are merged. `/caw-merge` takes each
  into `developer`, one at a time, with `bash tests/check.sh --all` green.
- Release once per batch of requests, after the final review, not once per request; installed workspaces then get one
  reviewed update.
- Hooks, the installer, security and risky actions: effort high, and an independent review (`review.md`) before the
  stage closes.
- A stage that cannot finish: write where it stopped and the next steps into the request, or into `tmp/prompt.md`.

## 5. Prove

- Every change: `bash tests/check.sh --all` (`/caw-check`). A failing check is fixed, never skipped.
- A change to the installer, a hook or `workspace/scripts/setup-claude.sh`: `/caw-test-install` too.
- A claim in a plan, request or doc is checked against the code or a run before it is written.

## 6. Close

- Commit per `git.md` (`/caw-commit`), one logical change per commit, with the translations of changed documents in the
  same commit (`docs.md`).
- Update the state of the request in `maintainers/requests/README.md` and of its backlog item, if any. A delivered
  request moves to `maintainers/requests/done/` (`git mv`) in the same commit, and its row points to the new path.
- `/caw-merge` takes the work into `developer` and writes `workspace/CHANGELOG.md`; other pushes only when the owner asks,
  each request covering that push only. A release only through `/caw-merge --main`.
- End with a short report: what changed (commits), what was verified (commands and results), what is left.
