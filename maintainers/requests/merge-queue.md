# Functional request: one merge at a time per repository

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**State:** ready. **Where it runs:** a work clone of this repository; it changes the product (`/merge` and its gate,
`workspace/rules/security.md` "Hard rules", the `UserPromptSubmit` hook `scripts/session-title.py`, which already
records the person's `/merge`) and the maintenance (`/caw-merge`, a new root hook, the root `CLAUDE.md` line that lists
the root hooks). Source: the owner, 2026-11-18, from a warning of `preferred-language` (two branches that touch the
same files, merged at the same time, can conflict); redesigned by the owner on 2026-11-19, while designing
`plans/session-names.md` (its D-17): a merge that finds another one running on its repository is refused, not queued.
The new hard rule is the owner's decision recorded there (`.claude/rules/product.md`).

## 1. Objective

Two merges never run on the same git repository at the same time: the second is a BLOCKER and does not go on. Work in
clones keeps running in parallel, and merges on different repositories run together. Each merge keeps a log of its
steps, so a merge left unfinished by a session that is gone is recovered or started again, never left blocking the
repository.

## 3. Business rules

- BR-1: the lock is per git repository: each repo of `projects/` (in the product) and this repository (for
  `/caw-merge`). It covers every merge that writes a base of that repository: `/merge` into `developer`,
  `/merge --main` and `/merge --hotfix`; `/caw-merge` in all its forms. Nothing else takes it. Merges on different
  repositories run at the same time.
- BR-2: the queue file `tmp/work/merges/queue` records each merge running: the repository, the kind (`developer`,
  `main`, `hotfix`), the session id and name, the branch, the start time and the last step done. A merge writes its
  entry when it starts and removes it when it ends, together with its closing board and the session rename
  (`requests/session-names.md`); a merge refused or cancelled removes it at once.
- BR-3: `/merge --main` takes the lock of every repo of the project that has an `Unreleased` section when it starts,
  before the plan question, and frees those the confirmed plan leaves out.
- BR-4: the session that holds the lock goes on with its own merge (a `/merge` typed again after a failed phase 1, for
  example). A merge from another session, on a repository held by a running session, is a BLOCKER: the hook sees the
  typed `/merge` (`/caw-merge` at the root) and the session shows at once, in red (a `diff` block, whose `-` lines the
  terminal shows in red), that the merge cannot go on, naming the merge that runs (repository, kind, session name,
  since when) and that it must end or be stopped in its own session first. The gate refuses it too. No answer, phrase
  or insistence lets it through.
- BR-5: each merge writes the log of its execution in `tmp/work/merges/<repo>/<type>_<branch>.log` (`feat/login-retry`
  gives `feat_login-retry.log`), a line per step started and done, with the time and what the step produced (the sha
  of phase 1, the review's verdict, each warning and its decision, the sha merged, the tag).
- BR-6: a queue entry of a session that is gone (not among Claude Code's running sessions; that list unreadable: the
  session asks the person whether that session is still open) warns that an unfinished merge exists, naming it, and
  offers:
  1. Start again (recommended)
  2. Try to go on from where it stopped
- BR-7: "go on": the step reached comes from the merge's log; no log, from the transcript of the old session; neither:
  the session says it cannot go on and that a new review must start, and does BR-8.
- BR-8: "start again", always and only inside the merge's clone in `tmp/work/` (the work clone of a merge into
  `developer`, the release or hotfix clones): list the changes not committed, reset them, merge `origin/developer`
  into the branch, and run the merge again from its first step, as a new analysis. A committed change is never
  dropped, and no clone is deleted or opened again.
- BR-9: once the old merge did something that cannot be done twice (phase 2 merged, `main` pushed, a tag created; seen
  in the log or in git), the two options are not offered: the merge happened, and only its end was not recorded. The
  session reads when it stopped (the last step of the log, else the date of the merge commit or of the tag) and,
  above all, how much entered `developer` after it: the merges, their requests and the size of the change. Time is no
  measure: a merge stopped this morning may be far by the evening. The session judges, and says why, which case it
  is, before anything runs:
  - **Near**: little entered `developer` since. The session asks:

    ```text
    An unfinished merge was found: <kind> <repo> <version>, stopped on <date> at <time> (session <name>).
    Since then only these entered developer: <x>, <y>, <z>.
      (1) Only finalize it: that merge is already the final version
      (2) Finalize it, then start a new one with what entered since
    ```

    Missing in both: `main` merged down into `developer`, the requests moved to `qa/` or `done/` with their
    Execution block, the clones closed, the summary, the queue entry. (2) then runs the merge the person typed from
    its first step.
  - **Far**: much entered `developer` since. The session says how far it is (the merges that entered since, by
    session name, and the size of the change), concludes it (the same list, with `main` merged down into `developer`
    through a clone and the gate, never a blind merge, since `developer` moved), records in its log and in the
    Execution block of its requests that it was concluded late, by which session and when, and then starts the merge
    the person typed from its first step, as a new analysis. Each step is announced as it ends.
  - Either case is a warning of the summary of the merge that runs now (`rules/security.md` "Warnings", risk
    `MEDIUM`): "an unfinished merge was concluded by this session".
- BR-10: every merge, before its first step, checks the queue and the logs for unfinished merges, into `developer` or
  `main`: on its own repositories it runs BR-6 to BR-9 first; on other repositories it only lists them, in one line
  each, pointing at `--sweep`.
- BR-11: `/merge --sweep` lists every merge of the workspace that is stalled (its session gone) or late (past a step
  that cannot be done twice, with no recorded end), oldest first, and runs BR-6 to BR-9 on each, one at a time, with
  the person's answers. Nothing stalled or late: it says so in one line. It merges nothing new.
- BR-12: all of the above holds in the maintenance, with `/caw-merge` and `/caw-merge --sweep` on this repository.

## 4. Acceptance criteria

- AC-1: Given a merge running on a repository, when another session types `/merge` on the same repository, then the
  red BLOCKER names the merge that runs and nothing of the second merge runs; asking again changes nothing.
- AC-2: Given a release of a project running, when a merge into `developer` of one of its repos starts in another
  session, then it is refused the same way.
- AC-3: Given the session holding the lock, when the person types `/merge` again after a failed phase 1, then it goes
  on.
- AC-4: Given merges on two different repositories, then both run at the same time.
- AC-5: Given a merge that ended (merged, refused, cancelled), then its queue entry is gone and the next merge on that
  repository runs with no warning.
- AC-6: Given a merge whose session was killed before phase 2, when another merge on that repository starts, then the
  two options are shown; "start again" resets only the changes not committed of its clone, merges
  `origin/developer` and starts from the first step; every commit is still there.
- AC-7: Given a merge whose session was killed with its log present, when "go on" is chosen, then it resumes from the
  first step the log does not mark done; with no log and no transcript, then it says it cannot go on and starts again.
- AC-8: Given a release whose session was killed after `main` was pushed, with one small merge entered in
  `developer` since, when another merge on that repository starts, then the session names that merge, asks "only
  finalize" or "finalize and start a new one", and does what was chosen.
- AC-8a: Given the same release with many merges entered in `developer` since, then the session says how far it is,
  concludes it with `main` merged down through the gate, records the late conclusion in its log and requests, and
  starts the new merge as a new analysis; the summary carries the warning.
- AC-8b: Given an unfinished merge on another repository, when a merge starts, then it lists it in one line pointing
  at `--sweep` and goes on with its own.
- AC-8c: Given two stalled merges and one late merge, when the person runs `/merge --sweep`, then the three are listed
  oldest first and each goes through BR-6 to BR-9; given none, then it says so in one line.
- AC-9: Given two `/caw-merge` at the same time in this repository, or a stalled `/caw-merge`, then the rules above
  hold there too, `/caw-merge --sweep` included.

## 7. Out of scope

- A queue that waits: a refused merge never waits and never starts on its own (the file of BR-2 only records the
  merges that run).
- Any way to run two merges on one repository at once.
- Solving conflicts on its own: a merge still brings its base into the branch and stops on a conflict, as today.
- Session names, the release session's included: `requests/session-names.md`.

## 11. Steps and effort

| Step | Effort | Why |
| --- | --- | --- |
| 1. Product: the hard rule, the queue file, the lock and its BLOCKER in the hook and the gate, the log, the unfinished merge, the check at each merge and `--sweep`, with their scenario tests | high | Concurrency in the gate, a new hard rule |
| 2. Maintenance: `/caw-merge` with the same rules and `--sweep`, the root hook and the `CLAUDE.md` line | high | Concurrency in the merge, a root hook |
| 3. Proof: two sessions merging on one repository at once, a killed one before and after the point of no return, and `--sweep`, headless | medium | The end-to-end check |

The subagents of each step run with the step's effort, passed in the call.

## Decisions

Decided by the owner on 2026-11-19:

- A new row of the closed list of `workspace/rules/security.md` "Hard rules": two merges on the same git repository
  at the same time (into `developer`, `main` or by a hotfix). A BLOCKER is a BLOCKER: shown in red at once, it does not
  go on, with no override.
- The lock per git repository, for the merge into `developer` and into `main` (BR-1); the same session goes on, another
  session is refused (BR-4).
- The queue file records the state; its entry leaves with the closing board and the rename (BR-2).
- The log of each merge, and the recovery from it, else from the session's transcript, else a new review (BR-5,
  BR-7).
- "Start again" resets what is not committed, merges `developer` into the branch and starts as a new analysis, always
  in the clone (BR-8).
- An unfinished merge past a step that cannot be done twice only lacks its end. How much entered `developer` since,
  not the time, says whether it is near or far, and the session judges it: near, it asks "only finalize" or "finalize
  and start a new one"; far, it concludes that one and starts a new one, announcing each step (BR-9).
- Every merge first checks for unfinished merges, into `developer` or `main` (BR-10); `--sweep` cleans and checks what
  is stalled or late (BR-11).
- The root hook stays, and the root `CLAUDE.md` lists it beside the two that exist; the whole flow holds for the
  `caw-` versions (BR-12).

The owner accepted the decisions below as proposed ("follow your suggestions, or leave it to `/request` to decide
while running"): `/request` may refine them, never reverse them.

- `/merge --hotfix` takes the same lock: it writes `main` and `developer` of its repo.
- A release takes its lock at its start, on every repo of the project with an `Unreleased` section, and frees those the
  plan leaves out (BR-3): no other merge slips in while the person answers.
- A session whose state Claude Code's running sessions cannot tell (that list is not a documented interface): the
  session asks the person (BR-6), so it never starts again over a merge still running.
- "Start again" holds for every merge, in its clone, listing the changes not committed before the reset (BR-8).
- The log sits in a folder per repository, `tmp/work/merges/<repo>/<type>_<branch>.log` (the repo's path under
  `projects/`, each `/` written `--`; this repository's name at the root): `feat/login` may exist in two repositories.
- In BR-9, the far case is announced and runs, with no question: the merge already happened, and the new one cannot
  start before it is concluded.
- On other repositories, BR-10 only lists the unfinished merges: a merge never stops for a repository it does not
  touch.
