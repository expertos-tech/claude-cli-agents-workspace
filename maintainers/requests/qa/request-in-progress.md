# Functional request: the "doing" state of a request

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**State:** ready. **Where it runs:** a work clone of this repository; it changes the product (`workspace/rules/git.md`,
`/request`, `/merge`, `workspace/scripts/aiwp-cmds.sh`) and the maintenance (`tests/caw-work.sh`, `/caw-request`,
`/caw-merge`, `.claude/rules/security.md`, `.claude/rules/git.md`, `.claude/rules/process.md`,
`maintainers/requests/README.md`). Design: `maintainers/plans/request-in-progress.md`. Source: the owner, 2026-11-18:
closing boards send the owner to run requests that are already running in another session.

## 1. Objective

A request that is being run is marked as such from the start of its work until its merge into `developer`, so no list,
closing board or summary offers it again as free, and running it again asks whether to resume it or start over. The
same in the product and in the maintenance; only where the state is stored differs.

## 3. Business rules

- BR-1: A request has a fourth state, `doing`, between pending and qa. Product: the file moves to
  `custom/requests/doing/<name>` right after `bash scripts/aiwp-cmds.sh open`, committed and pushed by path in
  `custom/`. Maintenance: the file moves to `maintainers/requests/doing/<name>` and its README row gets the status
  `doing`, in one commit pushed to `origin/developer` before `bash tests/caw-work.sh open`, so the work branch holds
  the move.
- BR-2: The maintenance start commit is made only by `bash tests/caw-work.sh start <name>`, with no suite, review or
  terms scan, and is pushed only when: the root is on `developer`, with nothing uncommitted, equal to
  `origin/developer` after a fetch; the request file is already on `origin/developer`; the commit is a pure rename of
  it plus the status cell of its README row. Anything else: refused, with the reason, and nothing pushed. The push is
  a plain fast-forward, never forced; the remote moved meanwhile: fetch and redo it once, else stop and report. It is
  the one exception to the hard rule "`developer` moved outside `/caw-merge`".
- BR-3: A bare name resolves in the pending folder, then in `doing/` (maintenance: then `tmp/requests/`, `tmp/`).
- BR-4: A request found in `doing/`: the reply says it was started and not finished, with its work folder, branch,
  last commit (sha, date, title), files not committed, commits not on the remote and its `## Stopped` section if any,
  then asks: resume or start over. Resume: reuse the clone of that branch, or open one from the remote branch when the
  folder is gone, and go on from `## Stopped` or the last commit. Start over: delete the work folder and the remote
  work branch, then open a new clone of the same branch name from the base; in the product a `## Stopped` section gets
  the line `Discarded on <yyyy-mm-dd>: started over.` under it. Neither makes a start commit.
- BR-5: A stage or wave that stops with work left keeps the request in `doing/`. `close <work> --discard` puts it back
  in pending: in the product by a commit by path in `custom/`; in the maintenance by the reverse commit, under the
  checks of BR-2, with the status `pending`.
- BR-6: `/merge` and `/caw-merge` move the request from `doing/` (or from the pending folder, for one that never went
  through `doing/`) to `qa/`; in the maintenance its README row moves to "QA".
- BR-7: The closing board, the summary of `/merge` and `/caw-merge` and any "next request" line never offer a request
  in `doing/`: they name it as `in progress: <work>`. The pending tables of `maintainers/requests/README.md` get a
  "Status" column (`pending` | `doing`). `bash scripts/aiwp-cmds.sh status` names the request of each work and lists
  a file of `custom/requests/doing/` that no open work records as `stale`.
- BR-8: The rules say it: product `rules/git.md` "Requests" (the `doing/` row; a request moves once, to `doing/`, when
  its clone opens); maintenance `.claude/rules/security.md` and `.claude/rules/git.md` "Remote" (the start commit as
  the one exception), `process.md` step 6 and the "Lifecycle" of the requests README (moved before its clone opens).

## 4. Acceptance criteria

- AC-1: Given a ready request in `maintainers/requests/` and a root `developer` equal to its remote, when
  `/caw-request` runs it, then `origin/developer` gets one commit `chore(requests): start <name>` holding only the
  rename and the README status cell, before the clone opens, and the clone's branch holds `requests/doing/<name>`.
- AC-2: Given a root `developer` with a commit not on the remote, a file not committed, a request not on
  `origin/developer`, or a change besides the rename and the cell, when `bash tests/caw-work.sh start` runs, then it
  refuses naming the reason and pushes nothing (one scenario test per refusal).
- AC-3: Given a request in `custom/requests/`, when `/request` opens its clone, then the file is in
  `custom/requests/doing/`, committed and pushed in `custom/`.
- AC-4: Given a request in `doing/`, when `/request` or `/caw-request` is called with its name, then the reply shows
  what BR-4 lists and asks resume or start over; resume goes on in the clone of that branch with no new commit on the
  base; start over leaves no old work folder or remote branch and a new clone from the base.
- AC-5: Given a request in `doing/`, when `/merge` or `/caw-merge` takes its work, then it is in `qa/` with its
  Execution block and no longer in `doing/`; in the maintenance its README row is in "QA".
- AC-6: Given a request in `doing/`, when a closing board or a merge summary would suggest running it, then it shows
  `in progress: <work>` and no run command for it.
- AC-7: Given a work that recorded a request, when `close <work> --discard` runs, then the request is back in pending
  (maintenance: by the reverse commit, README status `pending`).
- AC-8: Given a file in `custom/requests/doing/` that no open work records, when `bash scripts/aiwp-cmds.sh status`
  runs, then it is listed as `stale`.

## 7. Out of scope

- `tmp/request.md` and a request typed in the conversation: they do not move to `doing/`.
- `/merge --hotfix` and `/draft-request` (`/caw-draft-request`).
- A lock between two sessions starting the same request at the same moment.
- A `doing/` per project, and a README in `custom/requests/`.

## 11. Steps and effort

| Step | Effort | Why |
| --- | --- | --- |
| Product: `rules/git.md`, `/request`, `/merge`, `aiwp-cmds.sh` (`open --request`, `status`, `close --discard`, the start over) with their scenario tests | high | mandatory core; a script that commits in `custom/` and deletes a remote branch |
| Maintenance: `tests/caw-work.sh start`, the reverse of `close --discard` and the start over with their scenario tests, `/caw-request`, `/caw-merge`, the rules and the requests README | high | a push of `developer` and an exception to a hard rule |

The subagents of each step run with the step's effort, passed in the call.

## Assumed decisions

- Open: the owner first wrote `/merge|caw-merge`. Decided: `/request` and `/caw-request` start `doing`; `/merge` and
  `/caw-merge` end it. Reason: only `/request` creates the work branch.
- Open: the shape of the start commit. Decided: the checks of BR-2. Reason: with no validation, the shape is what keeps
  the push of `developer` from carrying anything else.
- Open: the order in the product. Decided: after `open`. Reason: `custom/` is not the branch's repo, and a failed open
  leaves no stale `doing/`.
- Open: `doing/` layout and a product README. Decided: one flat `doing/`, no README in `custom/requests/`. Reason: the
  `**Project:**` line names the project; the folder is the state, as for `qa/` and `done/`.
- Open: acceptance criteria. Decided: AC-1 to AC-8, derived from the BRs. Reason: the owner gave the rules.

## Authorizations

- Authorized: the start commit and its reverse pushed to `developer` outside `/caw-merge`, with no suite, review or
  terms scan, within the checks of BR-2. Reason: the owner: "a simple commit, with no validation of the README and of
  the moved file; something very simple that needs nothing; made before the branch so it already holds it".
- Authorized: start over deletes the half-done work folder and its remote work branch. Reason: the owner: "start over:
  delete the half-done branch and start again".

---

## Execution — 2026-11-19, merged into developer

Branch `feat/request-in-progress`, clone `tmp/work/2026-11-19-request-in-progress/claude-cli-agents-workspace`.

Done, by stage:

- Stage 1, the product (high): `c616af6` (`aiwp-cmds.sh open --request`, `--resume`, `close --discard`,
  `--discard --start-over`, `status` with `request=` and `stale:`, with scenario tests), `d142422` (`session-title.py`
  reads a bare name in `custom/requests/doing/` too), `1bf1c1f` (`rules/git.md`, `/request`, `/merge`,
  `docs/usage.md`).
- Stage 2, the maintenance (high): `396d108` (`tests/caw-work.sh start` and the same options as the product, with
  scenario tests), `20a4a3a` (`/caw-request`, `/caw-merge`, `security.md`, `git.md`, `process.md`), `792eb5c` (the
  requests README with a Status column, `docs/maintenance.md`, `docs/repository.md`).
- Warnings of the stages: `b9aecd7` (W-1), `5dec4f2` and `6948aeb` (W-3).
- `developer` brought in by `8c4ec54` (conflicts in `workspace/scripts/README.md` and the requests README: both
  sides' rows kept, the new rows with the Status column). Changelogs: `e879302`.

Decisions taken while running:

- The product moves the request in `aiwp-cmds.sh open --request` itself, only after every clone opened, and records
  it in `tmp/work/<work>/.request`; the start commit's body names the work and branch, so a resume finds them when
  the folder is gone.
- `open` and `close` move only a pure rename; a pending request not committed is scanned for secrets (the scan of
  `guard-bash`) and committed by its path first (W-3); a request already in `doing/` must be committed as is.
- Start over is `close <work> --discard --start-over`; the remote work branch is deleted with a lease on the sha the
  clone pushed last, never `developer`, `main` or a tag (W-1 wrote this next to the hard rule).
- `caw-work.sh start` refuses a root `developer` only behind its remote instead of moving it (BR-2 says equal).
- This request did not go through `doing/` itself: it is the one that creates it.

Deviations from the request: `session-title.py` (a hook) also changed, so a resumed request names its session;
`close` now refuses an unknown option (exit 2).

Acceptance criteria:

- AC-1, AC-2: proven by the scenarios of `tests/test-caw-work.sh` (the start commit on a throwaway remote, the
  branch holding `doing/`; one scenario per refusal).
- AC-3, AC-8: proven by the scenarios of `workspace/scripts/tests/aiwp-cmds/test-aiwp-cmds.sh`.
- AC-4: the scripts' part (resume, start over leaving no folder nor remote branch) proven by the scenarios of both
  suites; the reply proven by headless rehearsals (`claude -p`, read-only, invented fixtures `billing-export`,
  `acme-login`): `/request` in a test installation and `/caw-request` in the clone show the work folder, branch, last
  commit, files not committed, commits not pushed and the `## Stopped` section, then ask resume or start over, each
  with the right command.
- AC-5: proven by rehearsals: `/merge` moves `doing/` to `qa/<project>/` (step 8), `/caw-merge` moves it to `qa/`
  with the README row to "QA", both paths in one commit.
- AC-6: proven by rehearsals on `6cbae6b` and `0bec432`: the `/merge` and `/caw-merge` summaries and the product
  closing board name the request `<file>.md in progress: <work>`, with no run command for it; the maintenance closing
  board does it at the end of `➜ Next` once the session has `process.md` of `0bec432` in context (a rehearsal in a
  clone under `tmp/work/` loads the root's rules, still the old ones until this merge).
- AC-7: proven by the scenarios of both suites.

Checks: `bash tests/check.sh --base origin/developer --i18n-pending` passed (`SKIP repo-terms`: no terms list);
`test-aiwp-cmds.sh` 44, `test-caw-work.sh` 57, `test_session_title.py` 37; `/caw-test-install` PASS, and the
installed `session-title.py` named a session from a request in `doing/`.

Warnings of the stages: W-1 fix in `b9aecd7`; W-2 (no company-terms scan, no list) accept; W-3 fix in `5dec4f2` and
`6948aeb`; W-4 (open refuses when the secret scan cannot run), W-5 (`close` exit 2 on an unknown option), W-6
(`start` refuses a root only behind its remote), W-7 (a request in `doing/` must be committed as is): accept.

Warnings of the merge review: W-1 (AC-4 to AC-6 not proven by a session run) fix: the rehearsals above; W-2 (start
over fell back to the remote sha with no `caw.pushed`) fix in `06affea`: it refuses and deletes nothing; W-3 (the root
changelog entry missed `open --request` and the `status` lines) fix in `d0972a8`. Warnings of the rehearsals: W-4 (the
boards wrote the request in progress in free text, not `in progress: <work>`) fix in `6cbae6b` and `0bec432`: the form
`<file>.md in progress: <work>`, in English, with its slot in the boards; W-5 (a test installation made inside a clone
hides its own `CLAUDE.md` behind `**/tmp/work/**`) accept.
