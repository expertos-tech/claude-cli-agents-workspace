# `/pilot assisted`: a guided mode for people new to the workspace

Status: approved, D-3 by the owner, the rest assumed (2026-11-18); built, in `qa/` (2026-11-19). Request: `maintainers/requests/qa/assisted-mode.md`.

## 1. Goal

1. `/pilot` gets a third mode, `assisted`: `auto` (the agent runs every check, visual ones included) plus short
   explanation boxes at the moments a newcomer gets the workspace wrong, each saying what happens, why, and how to do
   it the workspace's way.
2. A person who never used the workspace starts in `assisted`. Once they switch to `auto`, `auto` is their default in
   every later session.
3. The same in the maintenance: `/caw-pilot`, the layer of `/pilot` at the repository root, with boxes about the
   maintenance process (plan, request, clone, `/caw-merge`, the public repository).

## 2. Today

- `/pilot [auto|manual]` (`workspace/rules/skills/pilot/SKILL.md`) sets who runs the checks a human could do by hand,
  for the session only: "no file, no other session". Every session starts in `auto` (`workspace/rules/quality.md`
  "Verification mode").
- Nothing teaches the flow. A newcomer learns it from refusals: `guard-bash` blocks a push to `main`, the gate refuses
  a merge, the core is read-only. The refusal says what is blocked, not what to do instead.
- `/caw-pilot` does not exist; `autonomous-work` (BR-14) plans it as the layer of `/pilot`, with the maintenance's
  checks.
- The product starts sessions with `SessionStart` hooks (`setup-claude.sh --quiet`, `release-notice.sh`,
  `prompt-log.py sync --context`). The root has no hooks (`CLAUDE.md`).

## 3. The modes

| Mode | Checks a human could run | Boxes | Lasts |
| --- | --- | --- | --- |
| `assisted` | the agent, as `auto` | yes | default of a new installation, until changed |
| `auto` | the agent | no | becomes the default once chosen |
| `manual` | the person, with a list | no | this session only |

- `assisted` changes only what the agent says, never what it may do: every rule, hook and gate stays the same.
- `/pilot auto` and `/pilot assisted` write the default; `/pilot manual` stays a session choice (it depends on the
  task: a real login, a device), as today.
- Subagents never show boxes: the brief keeps the verification mode only.

## 4. The default per person

The default lives per installation, in a git-ignored file the person's sessions read (e.g. `.claude/pilot-mode`,
writable in an installed workspace): one person per installation is the proxy for "never used it". Not in `custom/`:
it is shared by the team through git, so a new teammate would inherit `auto` from whoever set it.

- No file: `assisted`. `/pilot auto` writes `auto`; `/pilot assisted` writes `assisted` (to come back).
- An installation that existed before this version must not turn `assisted` for a person who already knows it
  (D-2).
- `/pilot` turned off by `custom/rules-config.json`: no way to leave the mode, so `auto` and no boxes.

How a session learns the mode: one line in the `SessionStart` context (`Pilot mode: assisted` plus the path of the
boxes rule), from an existing start hook, so no new mandatory hook. In `assisted`, the session reads
`rules/assisted.md`; in `auto` it never loads, so it costs nothing to those who left it.

## 5. The boxes

### Format

Short, fixed, in the language of the conversation, before the action it explains:

```text
╭─ ASSISTED · <group> · <title> ───────────────────
│ What:  <what is about to happen, one line>
│ Why:   <the reason or the risk, one or two lines>
│ How:   <the workspace's way: the command, ready to copy>
╰─ /pilot auto turns these boxes off ──────────────
```

Right below the box, a selection (the session's question tool), and the agent waits for it:

1. **Continue**: the work goes on as asked.
2. **Don't show this again**: the work goes on, and the boxes of this group stop for the rest of the session.
3. Only where the situation has a better way: that way, as an option of its own (e.g. "Clear and start from the
   request", "Draft the request first").

- Every time a situation happens, its box shows, until its group is muted in this session.
- A muted group is muted for this session only: a new session shows every group again, until the person switches to
  `auto`. Nothing about it is written to a file.
- On a mute, the agent writes one line `Assisted: muted <group>` in its reply, so it survives a compaction.
- At most one box per reply; never inside the closing board.

### The situations (product)

The group is what "Don't show this again" mutes.

| # | Group | When | The box says | Extra option |
| --- | --- | --- | --- | --- |
| 1 | Start | The first reply of a session | What the workspace is; the five commands (`/draft-request`, `/request`, `/merge`, `/run-tools`, `/pilot`); how to leave the mode | — |
| 2 | Context | A new task in a session that already closed one (a closing board shown, or a different subject) | A large context makes the agent mix tasks and invent; clear it (`/clear`) and start from the request | Clear and start from the request |
| 3 | Branches | A commit, push or merge asked on `main`, `master` or `developer` | Work goes in a clone and enters `developer` only by `/merge`, `main` only by `/merge --main`; what the gate checks | Do it in a clone |
| 4 | Branches | A change asked straight in `projects/` | Changes happen in a clone under `tmp/work/` (`/request` opens it), so the project is never half changed | Do it in a clone |
| 5 | Requests | A large or vague request typed in the prompt | `/draft-request` turns it into a request with acceptance criteria | Draft the request first |
| 6 | Core | A change asked to the core (`rules/`, `scripts/`...) | The core is read-only; your own rules go to `custom/my-rules/` (`/rules`); the core changes by `aiwp update` | Write it as my own rule |
| 7 | Secrets | A secret or a `.env` in the conversation | Where it goes (`custom/env/<tool>.env`), never in a repo or the chat | — |
| 8 | Refusals | A refusal of a hook or the gate | The refusal in plain words and the allowed way to the same goal | The allowed way |
| 9 | Next steps | The closing board shown | What comes next: `/merge`, `/clear`, `/request <file>` | — |

### The situations (maintenance, `/caw-pilot`)

| # | Group | When | The box says | Extra option |
| --- | --- | --- | --- | --- |
| M1 | Start | The first reply of a session at the root | The root maintains the product; `workspace/` is code; the flow plan → request → `/caw-request` → `/caw-merge` | — |
| M2 | Requests | A change asked with no request | Small: go on in a clone; large: `/caw-draft-request` first | Draft the request first |
| M3 | Branches | A commit or push asked on `developer` or `main` | Work in a clone (`/caw-request`), into `developer` by `/caw-merge`, `main` only by `/caw-merge --main` | Do it in a clone |
| M4 | Public | Something private in a file to commit | The repository is public: names, paths and terms stay in `tmp/` | — |
| M5 | Context | A new task after a closing board | Same as 2 | Clear and start from the request |
| M6 | Translations | A translation asked between releases | Translations are done once, at the release | — |

## 6. The maintenance root

The root has no hooks, so the mode reaches the session another way (D-4):

- **A. An import in the root `CLAUDE.md`:** a line "Pilot mode: `assisted` unless the file below says otherwise",
  then `@.claude/pilot-mode.local.md`, git-ignored, written by `/caw-pilot`. To verify first: that a missing
  imported file is skipped silently.
- **B. A root `SessionStart` hook:** reliable, but the root stops being hook-free.

Recommended: A, if the check passes; else B.

## 7. What changes

- Product: `rules/skills/pilot/SKILL.md` (the third mode, writing the default), `rules/quality.md` "Verification
  mode", a new `rules/assisted.md` (the format and the situations), the start hook that prints the mode, the upgrade
  of existing installations (`setup-claude.sh` or the installer), `README.md` and `docs/usage.md`, the hook tests,
  the `.gitignore` of the installation.
- Maintenance: `.claude/skills/caw-pilot/SKILL.md` (a layer, checked by `tests/check.sh`), the root `CLAUDE.md`,
  `.gitignore`, `docs/maintenance.md`.
- A hook and the installer change: effort high, `/caw-test-install`, and an independent review.

## 8. Decisions

- **D-1** (assumed): the default lives per installation in a git-ignored file, not in `custom/`.
- **D-2** (assumed): an installation updated to this version gets `auto` (it already has history: a prompt log or a
  project in `projects/`).
- **D-3** (owner, 2026-11-18): every box waits for a selection: continue, don't show this group again in this
  session, or the better way when the situation has one. A muted group comes back in a new session, until `auto`.
- **D-4** (assumed): the root learns the mode by the `CLAUDE.md` import (A), checked first; it fails: the owner
  decides on B.
- **D-5** (assumed): after `autonomous-work`, which also creates `/caw-pilot` and changes the flow the boxes describe.
- **D-6** (assumed): `manual` stays a session choice and never becomes the default.
- **D-7** (assumed): the labels of the box are fixed in English (`What`, `Why`, `How`, `Next`) like the closing board;
  the values in the language of the conversation.
