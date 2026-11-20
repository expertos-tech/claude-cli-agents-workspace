# session-names.md

**Status:** decided by the owner (2026-11-19): D-1 to D-19.
D-17 (the concurrency of merges) moved to `maintainers/requests/merge-queue.md`.
Request: `maintainers/requests/session-names.md` (state `ready`).

## Problem

Outside `/request`, a session of the product keeps the title Claude Code generates; on `/request` the hook
`scripts/session-title.py` names it `<project>-<n>`. The list of sessions (`/resume`, the session list) does not say
which session runs which request, nor whether that request ended or was merged.

An older workspace of the owner named every session by activity: about 1,080 lines (a script, a rule section, a skill
`/rename-aiwp`), most of them tied to a session board and to reviewer and architect sessions the product does not have.
`/import-workspace` imports no rule (decided in `plans/import-workspace.md`), so this has to be born in the product. The
owner wants a much smaller design: only the life of a request, and the release, rename a session.

## How a session gets a name (checked in the Claude Code docs, 2026-11-19)

- The model cannot run `/rename`. A hook can: `hookSpecificOutput.sessionTitle`, "the same effect as `/rename`", is
  documented for `UserPromptSubmit` and for `SessionStart` when `source` is `startup`, `resume` or `fork`, not `clear`
  nor `compact`.
- `/clear` fires `SessionStart` with `source: clear`, but a title returned there is ignored. With no argument, `/clear`
  carries a custom title (one from `/rename` or from a hook) into the new session: without care, the session after a
  `/clear` keeps the name of the one before, a duplicate.
- The hook input of `SessionStart` and `UserPromptSubmit` carries `session_title`, the custom title when one is set
  (never the generated one). A hook title overwrites a `/rename` title.
- That the end of a background shell command fires `UserPromptSubmit` is not documented (it is for a background
  subagent reporting back, a scheduled task and a message from another session). The older workspace relied on it and
  it worked; here it is only a speed-up, never a requirement.
- `/rename` does not refuse a duplicate name.

## How `/merge --main` works today (checked in `rules/skills/merge/SKILL.md` and `scripts/aiwp-cmds.sh`, 2026-11-19)

- `/merge --main <project>` releases one project: every repo of it with an `Unreleased` section. Steps: the plan and
  its confirmation; release clones `tmp/work/<yyyy-mm-dd>-release-<project>/`, branch `fix/release-vX-Y-Z`; the full
  checks; one final review; the findings; the versions; into `developer`; into `main` (`aiwp-cmds.sh release`, with
  the tag); the qa requests to `done/`; `close`; the summary.
- Nothing stops two releases at the same time. The tag must be free, and `open` refuses a branch that already exists on
  the remote, so the same release of the same project started twice fails at its clones; two releases of different
  projects run together with no check.
- The concurrency of merges is `requests/merge-queue.md`, redesigned by the owner on 2026-11-19 (D-17): one
  merge at a time per git repository, into `developer` and into `main`. Two releases of different projects still run
  together, so the release session's name carries the project (D-12).

## The design

### The names

| When | Name | Who applies it |
| --- | --- | --- |
| A new session (`startup`, `fork`) | `ai-workspace-NN` | `SessionStart`, at once |
| After `/clear` | `ai-workspace-NN` | `SessionStart` (`clear`) records it as pending for the session id it receives; the first `UserPromptSubmit` of that id applies it |
| `/request <file>` | `rq-<two-words>` | `UserPromptSubmit`, from the request's session line: the first suggestion free, else the second |
| The closing board of `/request` | `rq-done-<two-words>` | The skill, mandatory, through the rename |
| The end of `/merge` into `developer` | `rq-closed-<two-words>` | The skill, mandatory, through the rename |
| `/merge --main <project>` starts | `ai-workspace-release-<project>` | `UserPromptSubmit` |
| `/merge --main` ends | `ai-workspace-closed-release-<project>` | The skill, mandatory, through the rename |
| `/merge --hotfix` starts, its closing board, its end | `fix-<two-words>`, `fix-done-<two-words>`, `fix-closed-<two-words>` | As a request (D-19) |
| `/rename-workspace <text>` | `rq-<text normalized>` | The person |
| `/rename` of Claude Code | whatever the person types | Claude Code alone |

`rq-<two-words>` replaces today's `<project>-<n>`. Every rename the hook applies also tells the model the name (the
context line of today's hook, D-15).

An end name (`rq-done-`, `rq-closed-`, `ai-workspace-closed-release-`) held by a finished session that is still open
(D-18): before the rename, the session asks, right before the closing board, which stays the last thing of the reply:

```text
The session ai-workspace-closed-release-billing-api, already finished, is still open.
  (1) I closed the session   ← recommended
  (2) Use the suffix 02 in this session
```

The answer, at the next prompt, applies the name. (1) with that session still open: asked once more, then `-02`.

### The pieces

- **The hook** (`scripts/session-title.py`, mandatory core): today `UserPromptSubmit` only; it is also registered on
  `SessionStart`. It keeps a state per session id under `.history/` (the name wanted, the name applied) and reads the
  names of the running sessions from Claude Code's registry, plus the claims it keeps for names the registry does not
  show yet (as today's `<project>-<n>`).
- **The rename**: records the wanted name of the session; the hook applies it at its next firing. The `/request` and
  `/merge` skills run it, and `/rename-workspace` is the person's front over it. Run in the background, its end may
  fire the hook within seconds; otherwise the name applies at the person's next prompt.
- **The request's session line**: `/new-request` (today `/draft-request`) writes two name suggestions into the
  request, for when another session holds the first.

### `/rename-workspace`

- `/rename-workspace <text>`: the session becomes `rq-<text>` normalized (lowercase ASCII, no accents, words joined by
  hyphens), with no limit of words: `/rename-workspace Ajuste do Login SSO` gives `rq-ajuste-do-login-sso`.
- A running session already holds that name: `-02` at the end, then `-03`...
- It opens no clone and no branch: a rename changes no repository. It ends with this message, in the person's
  language (shown here in English; the session name repeated in the branch line):

  ```text
  Session renamed to rq-ajuste-do-login-sso.
  This session created no branch. To go on in a new branch, ask for it, for example: "create a branch".
  I open a clone in tmp/work/ with the branch feat/ajuste-do-login-sso.
  ```

- Asked for the branch, the session opens it as `/request` does: `bash scripts/aiwp-cmds.sh open
  <yyyy-mm-dd>-<name> <repo> --branch <type>/<name>`, `<name>` the session name without `rq-`, `<type>` from what the
  person asks (`feat` by default), the project from the person or, when unclear, one question. From then on the usual
  life: the closing board gives `rq-done-<name>`, `/merge` gives `rq-closed-<name>`.

## Decisions

All decided by the owner on 2026-11-19.

- **D-1.** The skill is `/rename-workspace`: skills have autocomplete, so the short name of the older workspace
  (`/rename-aiwp`) saves nothing.
- **D-2.** A new session and a session after `/clear` are named `ai-workspace-NN`; `fork` is a new session, so it gets
  one too; `resume` and `compact` keep the name (D-3).
- **D-3.** A session is renamed on `/request`, when the request's closing board is shown, at the end of the merge into
  `developer`, and at the start and end of the release (D-12). Nothing else of the workspace renames a session: no name
  by activity.
- **D-4.** The pattern of a request is `rq-<two-words>` and nothing more; at the end `rq-done-<two-words>`; at the
  merge `rq-closed-<two-words>`.
- **D-5.** The name comes from the request text, which holds two suggestions, for when another session holds the
  first.
- **D-6.** A name the workspace gives is never the name of another running session.
- **D-7.** Claude Code's `/rename` is entirely Claude Code's: no rule, no validation, no prefix. The next command of the
  workspace that renames applies its own rule over it: a `/rename` title is lost at the closing board or the merge,
  which were already due.
- **D-8.** After `/clear`, the first prompt runs the same naming as a start. `SessionStart` (`clear`) cannot set the
  title, so it records the numbered name as pending for the session id it receives, and the first `UserPromptSubmit`
  of that id applies it. This holds whether `/clear` gives a new session id or not (not documented); a session id with
  no state at all is named the same way at its first prompt.
- **D-9.** The `/request` and `/merge` skills must rename the session with the closing board (`rq-done-`, `rq-closed-`,
  `ai-workspace-closed-release-<project>`). The closing board stays the last thing of the reply (`rules/git.md`
  "Waves"), so the rename runs in the same reply right before the board is printed.
- **D-10.** "Never a duplicate" is among the running sessions (D-6, D-11, D-12): no ledger of past names. `NN` is one
  more than the highest among the running sessions, two digits with a leading zero (three after `99`).
- **D-11.** Both suggestions of a request held by running sessions (rare): no rename; the session says another
  session has the same name and asks the person for a new one, which becomes `rq-<name>` (as `/rename-workspace`).
- **D-12.** The release session is `ai-workspace-release-<project>` when `/merge --main` starts and
  `ai-workspace-closed-release-<project>` when it ends. The owner named it `ai-workspace-release` and accepted the
  project added, because the lock of D-17 is per repository, so two releases of different projects can
  run together, while two of the same project cannot.
- **D-13.** A merge in a session that did not run the request takes the words of `rq-closed-` from the request that
  enters (the words its `/request` used), which `/merge` already knows.
- **D-14.** Merged into D-7.
- **D-15.** The hook keeps telling the model its name at each rename (one context line): it costs almost nothing, and
  the session knows its name for the rename at the end of each stage.
- **D-16.** `/rename-workspace` as in "The design": any text normalized to `rq-<text>`, `-02` when taken, the message,
  the branch on request.

- **D-17. One merge at a time per git repository**, into `developer` and into `main`: a new hard rule of
  `workspace/rules/security.md`, a BLOCKER shown in red at once that never goes on (no override); the same session
  goes on with its own merge; a queue file, a log per merge, and the recovery or new start of an unfinished merge.
  Moved, whole, to `requests/merge-queue.md`, which holds everything about the flow and the concurrency of the merge.
- **D-18.** An end name held by a finished session still open: ask first to close it, (1) "I closed the session"
  (recommended) or (2) the suffix `02` in this session (the box under "The names"). Decided for the release session;
  extended to `rq-done-` and `rq-closed-`, as proposed and accepted by the owner.
- **D-19.** `/merge --hotfix` follows the naming of a request with `fix-` in place of `rq-`: `fix-<two-words>` when
  it starts, `fix-done-<two-words>` with its closing board, `fix-closed-<two-words>` at its end, everything else the
  same (two suggestions, never a duplicate, the questions of D-11 and D-18). The words: from the request the person
  names, else from the description. Decided by the owner at the merge review of this plan (its W-2).

## Out of scope

- A name by activity, `-done-` checks of open work, a session board, reviewer and architect sessions, the record of the
  prompt a session runs.
- The parent session name in subagent labels: `requests/workflow-agent-session-name.md`.
- The maintenance sessions at this root: no product hook runs here.

## Constraints

- `session-title` is a hook of the mandatory core: this plan needs the owner's decision (`.claude/rules/product.md`),
  the stage runs with effort `high`, and `/caw-test-install` proves it in a real session, the `/clear` path and the
  background speed-up included.
- It runs after `requests/draft-prompt.md`, which renames `/draft-request` to `/new-request` and changes
  `session-title.py`, its test and `templates/request.md`, the same files. `requests/merge-queue.md` also changes
  `/merge` and the same hook (the BLOCKER at the typed `/merge`): whichever runs second adapts to the first.
