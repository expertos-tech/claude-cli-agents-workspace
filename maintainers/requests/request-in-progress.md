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
