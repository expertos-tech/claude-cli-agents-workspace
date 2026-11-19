# request-in-progress.md

**Status:** decided by the owner (D-1, D-2); request: `maintainers/requests/request-in-progress.md`.

## Problem

A request has three states today: pending, qa and done. Nothing records that a request is **being run**: from the
moment `/request` (`/caw-request`) opens its clone until `/merge` (`/caw-merge`) takes it into `developer`, the file
stays in the pending folder, exactly like one nobody started.

So every reader of the pending list takes a running request for a free one: the closing board's `➜ Next` and the
"Recommended order" of `maintainers/requests/README.md` send the owner to `/caw-request <name>` for a request that is
already open in another session. On the day this plan was written, three of the four open clones of `tmp/work/`
(`normalize-rules`, `preferred-language`, `warnings-board`) were requests the README still listed as "Ready", and a
fourth session was pointed at a request already in `qa/`.

The owner's idea: move the request to a `doing/` folder when its work starts, and show a status column (pending,
doing) in the requests README.

## Where each side keeps its requests

- **Product.** `custom/requests/` is the custom layer, a git repo of its own, shared by every session of the
  installation (they all run at the root checkout) and committed and pushed by path by the session itself
  (`rules/git.md` "Waves" step 3). A move there is seen by every other session at once and moves no base.
- **Maintenance.** `maintainers/requests/` is part of this repository, on `developer`, and `bash tests/caw-work.sh
  open` creates the work branch from `origin/developer`. A move committed in the clone is invisible to the other
  sessions until `/caw-merge`; a move committed on `developer` at the root reaches the new branch and the other
  sessions only once pushed, and `developer` moves only by `/caw-merge` (a hard rule of `.claude/rules/security.md`).

## Options for the maintenance (D-1)

| Option | How | Trade-offs |
| --- | --- | --- |
| A. **Chosen by the owner:** a `doing/` folder on `developer`, moved before the branch | `/caw-request` moves the file to `requests/doing/`, sets its README row to `doing`, commits on `developer` and pushes it; then opens the clone, whose branch already holds the move | One narrow exception to the hard rule of the push of `developer` (below); the README is the true state on `developer` for every session; `/caw-merge` moves `doing/` to `qa/` with no rename conflict |
| B. "doing" derived from the open clones | `caw-work.sh open --request <name>` records it in the clone; `caw-work.sh requests` prints the live status | No hard rule touched, but no committed status: the README never shows it |

## The start commit: the exception

The owner's decision: the start commit is plain, with no suite, no review and no terms scan, because it adds nothing
new. What keeps it from becoming a way around `/caw-merge` is its shape, checked before the push; anything else is
refused and nothing is pushed:

- It is made by a script (`bash tests/caw-work.sh start <name>`), never by hand, so it needs no prompt: `bash
  tests/caw-work.sh` is already allowed, and the one prompt of a task stays the push of `developer` by `/caw-merge`.
- The root is on `developer`, with nothing uncommitted, and `developer` equals `origin/developer` after a fetch: no
  local commit of another change can leave with it. (On the day of this plan the root `developer` was 8 commits ahead
  of the remote: `start` would refuse until `/caw-merge` takes them.)
- The request file is already on `origin/developer`: the commit is a pure rename of it, `requests/<name>` to
  `requests/doing/<name>`, with no line changed, plus the status cell of its row in the README.
- One commit, `chore(requests): start <name>` with the line `[#automatic-agent-commit]`, pushed with a plain
  fast-forward push (never forced). The remote moved meanwhile: fetch, redo the commit once, else stop and report.
- Discard (`bash tests/caw-work.sh close <work> --discard`) makes the reverse commit through the same check: back to
  `requests/`, status `pending`.

## Recommendation

- **Product:** a `custom/requests/doing/` folder, moved right after `bash scripts/aiwp-cmds.sh open` (the order does
  not matter there, because `custom/` is not the repo of the branch, and after the open a failed clone leaves nothing
  stale).
- **Maintenance:** option A with the start commit above.

## Design

### Product (`workspace/`)

1. `/request <name>` resolves a bare name in `custom/requests/<name>`, then `custom/requests/doing/<name>`.
2. Right after `bash scripts/aiwp-cmds.sh open` (the work branch exists), a request read from `custom/requests/`
   moves to `custom/requests/doing/<name>` (`git -C custom mv`), committed and pushed by path, like the other
   checkpoints of `custom/`. `open` takes `--request <file>` and records it in the work folder.
3. A request found in `doing/`: "A request found in `doing/`", below.
4. A wave that stops with work left appends `## Stopped` as today, and the file stays in `doing/`: its clone is still
   open. The next `/request <name>` finds it there and resumes.
5. `/merge` moves the request from `doing/` (or from `custom/requests/`, for one that never went through `doing/`) to
   `qa/<project>/`. `/merge --hotfix` and `/draft-request` do not change.
6. `bash scripts/aiwp-cmds.sh close <work> --discard`: the request recorded by `open` goes back to `custom/requests/`,
   committed by path. `status` names the request of each work, and a file in `doing/` with no open work that records
   it as `stale`.
7. The closing board, the summary of `/merge` and any "next request" line never offer a request in `doing/`; when
   they would, they name it as `in progress: <work>`.
8. `rules/git.md` "Requests" gets the `doing/` row, and "A request never moves while its waves run" becomes "moves
   once, to `doing/`, when its clone opens".

### Maintenance (option A)

1. `bash tests/caw-work.sh start <name>`: the start commit above, then nothing else; `/caw-request` runs it before
   `open`, so the branch is created from an `origin/developer` that already holds the move.
2. `/caw-request` resolves a bare name in `maintainers/requests/<name>`, then `maintainers/requests/doing/<name>`
   (then `tmp/requests/`, `tmp/`); a request found in `doing/`: "A request found in `doing/`", below.
3. A stage that stops with work left writes `## Stopped` in the clone, as today; the file stays in `doing/`.
4. `/caw-merge` moves the request from `doing/` (or from `requests/`, for one that never went through `doing/`) to
   `qa/`, and its README row from the pending tables to "QA".
5. `maintainers/requests/README.md`: a "Status" column (`pending` | `doing`) in the tables of pending requests, and a
   "Lifecycle" row for `requests/doing/` (moved by `/caw-request`, before its clone opens).
6. The closing board of `process.md` step 6 and the summary of `/caw-merge`: `➜ Next` and `Left` never name a request
   in `doing/`; they name it as `in progress`.
7. The rules that change with it, through this plan: the hard rule "`developer` or `main` moved outside
   `/caw-merge`" of `.claude/rules/security.md` and "Remote" of `.claude/rules/git.md` gain the start commit as their
   one exception; "A request never moves while its stages run" (`process.md` step 6, the requests README) becomes
   "moves once, to `doing/`, before its clone opens".

### A request found in `doing/` (D-2)

The same on both sides. Before anything, `/request` (`/caw-request`) says that the request was started and not
finished, with what it knows of that work: the work folder and its branch, the last commit (sha, date, title), files
not committed, and the `## Stopped` section when there is one. Then one question, two answers:

- **Resume:** reuse the clone of that branch (`open` already reuses a clone of the same branch), or open a new clone
  of the remote branch when the work folder is gone, and go on from the `## Stopped` section or from the last commit.
  The request stays in `doing/`; no start commit.
- **Start over:** discard the half-done work, then start as a new run: delete the work folder and the remote work
  branch (product: in each repo of the work; maintenance: `origin/<branch>`), then open a new clone of the same branch
  name from the base. The request stays in `doing/`; no start commit. Product: a `## Stopped` section in the file gets
  a line under it, `Discarded on <yyyy-mm-dd>: started over.`, so the next reader does not resume from it;
  maintenance: that section lived on the deleted branch.

The question shows the last commit and the files not committed because the work may still be running in another
session; starting over deletes it. A work folder with commits not on the remote: the question says how many will be
lost.

## Decisions

- **D-1 (decided by the owner).** Maintenance: option A, the start commit as a plain commit with no validation, made
  before the branch so the branch already holds it. The shape check above is what this plan adds to it.
- **D-2 (decided by the owner).** A request found in `doing/`: say it was not finished and ask whether to resume it
  or start over; starting over deletes the half-done branch and starts again.

## Assumed decisions

- Open: the owner first wrote `/merge|caw-merge`, but the move happens when the work starts, which only `/request`
  does. Decided: `/request` and `/caw-request` start the `doing` state; `/merge` and `/caw-merge` end it (to `qa/`).
  Reason: only `/request` creates the work branch.
- Open: the shape of the start commit. Decided: the checks of "The start commit: the exception". Reason: with no
  validation, the shape is what keeps the push of `developer` from carrying anything else.
- Open: the order in the product. Decided: after `open`. Reason: `custom/` is not the branch's repo, and a failed
  open leaves no stale `doing/`.
- Open: `doing/` per project, like `qa/<project>/`. Decided: one flat `doing/`. Reason: the `**Project:**` line
  already names the project, and a request may touch several.
- Open: a README with a status column in the product. Decided: none; the folder is the state, as for `qa/` and
  `done/`. Reason: `custom/requests/` has no README today.
- Open: `tmp/request.md` and a request typed in the conversation. Decided: they do not move to `doing/`. Reason: no
  list suggests them, so they cause no duplicate run.
- Open: two sessions starting the same request at the same moment. Decided: no lock; the second `start` finds the
  file already moved (maintenance) or the second `git mv` fails (product). Reason: the race is rare and both fail
  safe.

## Stages of the request

| Stage | Effort | Why |
| --- | --- | --- |
| Product: `rules/git.md`, `/request`, `/merge`, `aiwp-cmds.sh` (`open --request`, `status`, `close --discard`, the start over) and their scenario tests | high | mandatory core and a script that commits in `custom/` |
| Maintenance: `tests/caw-work.sh start`, the reverse of `close --discard` and the start over with their scenario tests, `/caw-request`, `/caw-merge`, `security.md`, `git.md`, `process.md`, the requests README | high | a push of `developer` and an exception to a hard rule |
