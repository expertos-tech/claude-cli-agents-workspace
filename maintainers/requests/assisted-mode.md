# Functional request: `/pilot assisted`, a guided mode for people new to the workspace

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**State:** ready. **Where it runs:** at the repository root, where the project is maintained, with the product in
`workspace/`. Design: `maintainers/plans/assisted-mode.md` (D-3 answered by the owner; D-1, D-2, D-4 to D-7 assumed,
below). It runs after `autonomous-work`, which creates `/caw-pilot` and changes the flow the boxes describe.

## 1. Objective

A person who never used the workspace gets lost in its flow: clones, the gate, `/merge`, the read-only core, the
public repository of the maintenance. They learn it from refusals, which say what is blocked and not what to do.
`/pilot` gets a third mode, `assisted`: `auto` plus short explanation boxes at those moments, each with a selection
below it. A new installation starts in `assisted`; once the person switches to `auto`, `auto` is their default. The
same in the maintenance, through `/caw-pilot`.

## 3. Business rules

- BR-1: `/pilot` takes `assisted`, `auto` or `manual`. `assisted` runs the checks as `auto` does and adds the boxes.
  It changes only what the agent says: no rule, hook, deny rule or gate allows or refuses anything differently.
- BR-2: the default mode lives per installation, in a git-ignored file of the installation, never in `custom/`
  (assumed decision). No file, or a value it does not know: `assisted`. `/pilot auto` and `/pilot assisted` write it;
  `/pilot manual` changes this session only, as today. `/pilot` with no argument shows the mode in force and the
  default.
- BR-3: an installation that existed before this version (it has a prompt log or a project in `projects/`) gets the
  default `auto` when it is updated (assumed decision); a new installation has no file.
- BR-4: `/pilot` turned off by `custom/rules-config.json`: `auto`, no boxes.
- BR-5: a session learns the mode at its start, as one line of the start context, from a start hook that exists today:
  no new hook entry. The rules of the boxes load only in `assisted`.
- BR-6: a box comes before the action it explains, in this format; labels and footer fixed in English, the values in
  the language of the conversation; at most one per reply; never inside the closing board; never in a subagent:

  ```text
  ╭─ ASSISTED · <group> · <title> ───────────────────
  │ What:  <what is about to happen, one line>
  │ Why:   <the reason or the risk, one or two lines>
  │ How:   <the workspace's way: the command, ready to copy>
  ╰─ /pilot auto turns these boxes off ──────────────
  ```

- BR-7: right below every box, a selection, and the agent waits: "Continue" (the work goes on as asked); "Don't show
  this again" (the work goes on, and the boxes of that group stop for the rest of the session); and, where the
  situation has one, the better way as an option of its own. A mute is written as the line `Assisted: muted <group>`
  in the reply, so it survives a compaction, and never to a file. A new session shows every group again, until `auto`.
- BR-8: the product's situations, each shown every time it happens until its group is muted:

  | # | Group | When | The box says | Extra option |
  | --- | --- | --- | --- | --- |
  | 1 | Start | The first reply of a session | What the workspace is; `/draft-request`, `/request`, `/merge`, `/run-tools`, `/pilot`; how to leave the mode | — |
  | 2 | Context | A new task in a session that already closed one (a closing board shown, or a different subject) | A large context makes the agent mix tasks and invent; `/clear` and start from the request | Clear and start from the request |
  | 3 | Branches | A commit, push or merge asked on `main`, `master` or `developer` | Work goes in a clone, into `developer` only by `/merge`, `main` only by `/merge --main` | Do it in a clone |
  | 4 | Branches | A change asked straight in `projects/` | Changes happen in a clone under `tmp/work/` | Do it in a clone |
  | 5 | Requests | A large or vague request typed in the prompt | `/draft-request` turns it into a request with acceptance criteria | Draft the request first |
  | 6 | Core | A change asked to the core | The core is read-only; own rules go to `custom/my-rules/` (`/rules`); the core changes by `aiwp update` | Write it as my own rule |
  | 7 | Secrets | A secret or a `.env` in the conversation | Where it goes (`custom/env/<tool>.env`), never a repo or the chat | — |
  | 8 | Refusals | A refusal of a hook or the gate | The refusal in plain words and the allowed way to the same goal | The allowed way |
  | 9 | Next steps | The closing board shown | What comes next: `/merge`, `/clear`, `/request <file>` | — |

- BR-9: the maintenance, through `/caw-pilot` (a `caw-` layer over `/pilot`): the same modes, format and selection;
  the default in a git-ignored file at the root; the root learns the mode through an import in the root `CLAUDE.md`
  of that file, the text before it saying `assisted` unless the file says otherwise (assumed decision). Situations:

  | # | Group | When | The box says | Extra option |
  | --- | --- | --- | --- | --- |
  | M1 | Start | The first reply of a session at the root | The root maintains the product; `workspace/` is code; plan → request → `/caw-request` → `/caw-merge` | — |
  | M2 | Requests | A change asked with no request | Small: go on in a clone; large: `/caw-draft-request` first | Draft the request first |
  | M3 | Branches | A commit or push asked on `developer` or `main` | Work in a clone (`/caw-request`), into `developer` by `/caw-merge`, `main` only by `/caw-merge --main` | Do it in a clone |
  | M4 | Public | Something private in a file to commit | The repository is public: names, paths and terms stay in `tmp/` | — |
  | M5 | Context | A new task after a closing board | Same as 2 | Clear and start from the request |
  | M6 | Translations | A translation asked between releases | Translations are done once, at the release | — |

- BR-10: every command a box names exists in the version it ships in.

## 4. Acceptance criteria

- AC-1: Given a new installation, when a session starts, then its start context says `assisted`, and the first reply
  shows the Start box with the selection.
- AC-2: Given `assisted`, when the person runs `/pilot auto`, then the default file says `auto`, and a new session
  starts in `auto`, shows no box and does not load the rules of the boxes.
- AC-3: Given any default, when the person runs `/pilot manual`, then the default file does not change, and a new
  session starts in the default.
- AC-4: Given an installation with a prompt log or a project, when it is updated to this version, then its default is
  `auto`; given a fresh installation, then it has no default file and starts in `assisted` (`/caw-test-install`).
- AC-5: Given `assisted`, when the person asks for a push to `main`, then the Branches box shows with "Continue",
  "Don't show this again" and "Do it in a clone", and `guard-bash` still refuses the push if the person continues.
- AC-6: Given "Don't show this again" chosen on a Context box, when a second new task starts in the same session,
  then no Context box shows while the other groups still do, and a new session shows the Context box again.
- AC-7: Given `pilot` turned off in `custom/rules-config.json`, when a session starts, then it is in `auto` with no
  box.
- AC-8: Given `assisted`, when the session briefs a subagent, then the brief carries the verification mode `auto` and
  nothing about boxes.
- AC-9: Given no default file at the root, when a maintenance session starts, then it is in `assisted` and shows the
  M1 box; after `/caw-pilot auto`, a new session shows none; `tests/check.sh` passes the `caw-layers` check for
  `/caw-pilot`.
- AC-10: The start hook's scenario tests cover no file, `auto`, `assisted`, an unknown value and `pilot` turned off.

## 7. Out of scope

- Any change to what a hook, a deny rule or the gate allows or refuses.
- A new hook entry in the product; a hook at the root.
- Mutes kept across sessions; `manual` as a default.
- Translated box labels.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. The mode and its default: `/pilot assisted`, the default file, the start context line, the update of existing installations, `pilot` turned off (BR-1 to BR-5) | high | Changes a start hook and the installer |
| 2. The boxes: the format, the selection, the groups and the product's situations, `rules/quality.md`, `README.md` and `docs/usage.md` (BR-6 to BR-8, BR-10) | medium | Rules and docs with a clear scope |
| 3. The maintenance: `/caw-pilot`, the root import (check first that a missing imported file is skipped silently; if not, stop and ask the owner), `CLAUDE.md`, `.gitignore`, `docs/maintenance.md` (BR-9) | medium | Changes how the root session loads |
| 4. Proof in real sessions: AC-1, AC-5, AC-6 and AC-9, in a test installation and at the root | medium | Session behavior, checked by hand |

The subagents of each stage run with the stage's effort, passed in the call. Stage 1 gets an independent review
(`.claude/rules/review.md`) before it closes.

## Assumed decisions

- Open: where the default lives (D-1). Decided: per installation, git-ignored, not in `custom/`. Reason: `custom/` is
  shared by the team, so a new teammate would inherit someone else's `auto`.
- Open: an existing installation on update (D-2). Decided: `auto`. Reason: those who already use it would otherwise
  start seeing boxes.
- Open: how the root learns the mode (D-4). Decided: an import in the root `CLAUDE.md`, checked first. Reason: the
  root stays hook-free.
- Open: the order (D-5). Decided: after `autonomous-work`. Reason: it creates `/caw-pilot` and changes the flow the
  boxes describe.
- Open: `manual` as a default (D-6). Decided: never. Reason: it depends on the task.
- Open: box labels (D-7). Decided: fixed in English, values in the conversation's language. Reason: like the closing
  board.
- Open: an unknown value in the default file. Decided: `assisted`. Reason: the safe side for a newcomer.
- Open: acceptance criteria. Decided: AC-1 to AC-10, derived from the BRs. Reason: the ideas bring only the rules.
