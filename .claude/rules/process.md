# process.md

How the project is maintained. Every change goes through these steps; a typo fix may skip 2 and 3.

## 1. Evaluate

- Read the product in `workspace/` as code: what it does, its tests, its docs.
- Real use is evidence, read only: an installed work workspace, session transcripts, the prompt log, measurements
  (`workspace/scripts/performance/measure.py`). Never edit an installed workspace or its custom layer from here.
- A finding that names a company, a customer, a person or a project stays in the git-ignored `tmp/` or in the owner's
  custom layer. What reaches the repository is the general lesson, written without those names (`security.md`).

## 2. Plan

- A loose text of the owner (dictated, hurried) starts as a draft plan of `/caw-draft-prompt`: organized, with the
  gaps as questions, `Status: draft`, a criticality and its row in "Pending, by priority" of
  `maintainers/plans/README.md`.
- A plan lives in `maintainers/plans/<kebab-name>.md`: the problem, the options with their trade-offs, a
  recommendation, and numbered decisions (D-1, D-2...) for the owner to answer.
- Ask only what has no best alternative; list the rest as assumed decisions the owner can overturn.
- The plan stays the design reference after the request is written; update its status line when the request is built.
- A plan the owner approves in a session (plan mode) is recorded at once, in English and in the request format, as a
  pending request `maintainers/requests/<kebab-name>.md` (`**State:** ready`), with its row in the README.
- A plan is saved in the owner's language, a request in English (`CLAUDE.md` "Language"); both are shown in the
  owner's language, with one line naming the file and the language it is saved in.

## 3. Request

- With the owner's answers, write `maintainers/requests/<kebab-name>.md` in the format of `workspace/templates/request.md`:
  objective, business rules (BR-n), acceptance criteria (AC-n, verifiable), out of scope, and the stages with the
  effort of each.
- Add the request to the table of `maintainers/requests/README.md`, in the order it runs, with the Status `pending`.
- `/caw-new-request` writes plans and requests; `requirements-analyst` finds the gaps of a long or ambiguous one.

## 4. Execute

- One stage at a time (`/caw-request <name>`). Say the effort of each stage as it starts.
- Subagents always get an explicit model and effort (`models.md`). Writers run in parallel only on disjoint paths.
- `/caw-request` works in a clone on a work branch under `tmp/work/<yyyy-mm-dd>-<slug>/` (`claudeMdExcludes` covers
  `tmp/**`), so several requests run in separate sessions, each in its own clone. Respect the order in
  `maintainers/requests/README.md`: a request starts only after the ones it depends on are merged. `/caw-merge` takes
  each into `developer`, one at a time, with `bash tests/check.sh --base origin/developer --i18n-pending` green.
- A request of `maintainers/requests/` moves once, to `maintainers/requests/doing/`, before its clone opens:
  `/caw-request` runs `bash tests/caw-work.sh start <name>` at the root (the move and the Status `doing` of its README
  row, one commit pushed to `developer` within the checks of the script, the one exception of `security.md`), then
  opens the clone with `--request <name>`, so its branch holds the move. A request found in `doing/` is resumed or
  started over, never started again (`/caw-request`).
- Release once per batch of requests, after the final review, not once per request; installed workspaces then get one
  reviewed update.
- Hooks, the installer, security and risky actions: effort high. The agent is the developer of the stage: it
  implements, tests what it did, fixes and tests again; the stage closes with its own tests and the suite passing. No
  independent review runs during the stages, hooks and security included: the one review runs at `/caw-merge`
  (`review.md`). A doubt that is not a hard rule (`security.md`) never stops a stage: it goes to the warnings board
  as a warning (step 6).
- A stage that cannot finish: write where it stopped and the next steps into the request, or into `tmp/request.md`.

## 5. Prove

- Every change: `bash tests/check.sh --base origin/developer --i18n-pending` (`/caw-check`): only what changed, with
  the translations left pending. The release runs it strict: `--all --base <last tag>`. A failing check is fixed,
  never skipped. The release also runs the review fixtures once (`tests/review-fixtures/`): they call the model, so
  never at each commit; a failing one is a warning of the release.
- A change to the installer, a hook or `workspace/scripts/setup-claude.sh`: `/caw-test-install` too.
- A claim in a plan, request or doc is checked against the code or a run before it is written.

## 6. Close

- Commit per `git.md` (`/caw-commit`), one logical change per commit. Translations are not updated per commit: one
  agent brings them all up to date at the release (`docs.md`).
- The request lifecycle (`maintainers/requests/README.md`): pending in `requests/` (`idea` or `ready`), `doing/` from
  its start until its merge, `qa/` once `/caw-merge` takes it into `developer` with its "Execution" block, `done/`
  once `/caw-merge --main` releases it. A request moves once, to `doing/`, before its clone opens, and never again
  while its stages run: a stage that stops leaves it there; `bash tests/caw-work.sh close <work> --discard` puts it
  back. There is no backlog: an idea is a request in state `idea`.
- The closing board, the summary of `/caw-merge` and any "next request" line never offer a request in `doing/` (the
  Status `doing` of its README row) as one to run: `Left` and `➜ Next` name it `<name> in progress: <work>` (the
  `request=` line of `bash tests/caw-work.sh status`), the words `in progress:` in English like the labels, with no
  `/caw-request` command. A request in `doing/` that comes, in the order of the README, before the one `➜ Next`
  offers is always named in the board itself, at the end of `➜ Next` (`; <name> in progress: <work>`), never only in
  the text above it. The one exception is this stage's own request with stages left: `/caw-request <name>` resumes it.
- `/caw-merge` takes the work into `developer` and writes the root `CHANGELOG.md` and, for a product change,
  `workspace/CHANGELOG.md`. Other pushes only when the owner asks, each request covering that push only. Only the
  product is released, through `/caw-merge --main`; the root sections are dated by that release.
- A stage that gathered warnings shows first the warnings board of `workspace/rules/git.md` "Waves" (step 2 there:
  its format, the stop until the owner has decided every warning, the answers), the last thing of the reply, with no
  closing board. `fix` is committed in the clone; `request` is a `ready` request in `maintainers/requests/` with its
  row in the README, committed in the clone. No warnings: the closing board comes straight.
- End with the closing board, the last thing of the reply: it is the delivery report. Its labels stay as below; the
  values are in the language of the conversation. A stage that cannot finish writes where it stopped into the request
  first (step 4), the decisions of the warnings board among them, and the board names it.

```text
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
STAGE CLOSED: <request> — <stage>
Done:       <what changed: commits (sha, title), branch pushed>
Verified:   <command and result; each skip named>
Left:       <next stages, with effort | /caw-merge | <name> in progress: <work> | nothing>
Pending:    <decisions for the owner, findings, refused push | none>
Warnings:   <the decision of each warning of the board: W-1 accept, W-2 fix in <sha>, W-3 request <file> | none>
Request:    maintainers/requests/<file>.md | tmp/request.md | none
➜ Next: <the command to run, and where: /caw-merge from the clone, /caw-request <name>>[; <name> in progress: <work>, each request of doing/ ahead of it]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
