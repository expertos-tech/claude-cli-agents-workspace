# assisted.md

The boxes of the `assisted` mode (`/pilot assisted`, `rules/quality.md` "Verification mode"). Read this file only when
the start context says `Pilot mode: assisted` or the person runs `/pilot assisted`; it stops applying when the mode
changes to `auto` or `manual`.

`assisted` is `auto` plus short boxes at the moments a newcomer gets the workspace wrong. It changes only what you say:
every rule, hook, deny rule and gate allows and refuses exactly as in `auto`, and the checks are yours, as in `auto`.

## The box

Right before the action it explains, inside the selection ("The selection"), in this format. The labels and the
footer stay in English; the values are in the language of the conversation.

```text
╭─ ASSISTED · <group> · <title> ───────────────────
│ What:  <what is about to happen, one line>
│ Why:   <the reason or the risk, one or two lines>
│ How:   <the workspace's way: the command, ready to copy>
╰─ /pilot auto turns these boxes off ──────────────
```

- Exactly these lines: `What` one line, `Why` one or two, `How` one (several commands on it, separated by ` · `). No
  other line, list or blank line inside the box; the details go after the selection, in the reply.
- The box goes in the `preview` of every option of the selection, the same box in each, so it shows while the person
  chooses; never as text before the question, which the question hides while it is open. The selection goes through
  the question tool, never as a numbered list in the text.
- No question tool (a run with no person, such as a headless one): the box as text, and the work goes on as
  Continue.
- At most one box per reply. Two situations at once: the one listed first below.
- Never inside the closing board or the warnings board, never in a subagent: a brief carries `VERIFICATION: auto` and
  nothing about boxes (`rules/models.md` "Brief").
- Never a secret, a token or a value of a `.env` in a box.

## The selection

Every box is shown by a selection of the session's question tool, and you wait for it: one single-choice question
whose header is the group and whose text says the situation in one line (the box's title and its `What`), every
option with the box as its `preview`. The options in this order, their labels in English as below, like the labels of
the box (the extra option: as the table names it); a description in the language of the conversation may follow each:

1. **Continue**: the work goes on as asked.
2. **Don't show this again**: the work goes on as asked, and the boxes of that group stop for the rest of the session.
   Write the line `Assisted: muted <group>` in the reply, so it survives a compaction. Never write a mute to a file.
3. Only where the table gives one: the better way, as an option of its own. Chosen: do it that way instead.

- A muted group stays muted until the session ends; the lines `Assisted: muted <group>` in the conversation (or in its
  summary, after a compaction) say which. A new session shows every group again, until the person switches to `auto`.
- Every other situation shows its box every time it happens.
- A selection never authorizes what a rule needs the person to type (a `/merge`, a push to a base): the option only
  starts the workspace's way, and the rules of that way apply.

## The situations

The group is what "Don't show this again" mutes.

| # | Group | When | The box says | Extra option |
| --- | --- | --- | --- | --- |
| 1 | Start | The first reply of a session | What the workspace is (a work environment where Claude works in clones and the person merges); the commands `/new-request`, `/request`, `/merge`, `/run-tools`, `/pilot`; `/pilot auto` to leave the mode | — |
| 2 | Context | A new task in a session that already closed one (a closing board shown, or a different subject) | A large context makes the agent mix tasks and invent; `/clear`, then start from the request (`/request <file>`) | Clear and start from the request |
| 3 | Branches | A commit, push or merge asked on `main`, `master` or `developer` | Work goes in a clone; it enters `developer` only by `/merge`, `main` only by `/merge --main` (`rules/git.md` "Gate") | Do it in a clone |
| 4 | Branches | A change asked straight in `projects/` | Changes happen in a clone under `tmp/work/` (`/request` opens it), so the project is never half changed | Do it in a clone |
| 5 | Requests | A large or vague request typed in the prompt | `/new-request` turns it into a request with acceptance criteria, which `/request` runs; a dictated or tangled text goes first to `/draft-prompt`, which organizes it into a plan | Draft the request first |
| 6 | Core | A change asked to the core (`AGENTS.md`, `rules/`, `scripts/`, `docker/`, `templates/`) | The core is read-only; your own rules go to `custom/my-rules/` (`/rules add <subject>`); the core changes only by `aiwp update` | Write it as my own rule |
| 7 | Secrets | A secret or a `.env` in the conversation | Where it goes: `custom/env/<tool>.env` (`/local-env`), never a repository or the chat | — |
| 8 | Refusals | A refusal of a hook or the gate | The refusal in plain words and the allowed way to the same goal | The allowed way |
| 9 | Next steps | Right before the closing board | What comes next: test the copy, `/merge` to take the work in, `/clear`, `/request <file>` for the next step | — |

- 2: "Clear and start from the request" chosen: write the task as a request first when it has none (`rules/git.md`
  "Waves", step 3), then tell the person to type `/clear` and `/request <file>`; you cannot clear the context yourself.
- 8: the box comes after the refusal and before your next step; never retry the refused command in another form.
- 9: the box and its selection come before the reply that ends with the closing board, which stays the last thing of
  that reply.
