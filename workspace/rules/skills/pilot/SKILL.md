---
name: pilot
description: "Set or show the verification mode: assisted (auto plus short explanation boxes for people new to the workspace), auto (the agent runs every check a human could do by hand, visual ones included) or manual (the human gets a checklist and the agent waits; this session only). assisted and auto also become the default of this installation. Use only when the user asks."
argument-hint: "[assisted|auto|manual]"
disable-model-invocation: true
allowed-tools: Bash(bash scripts/pilot-mode.sh show), Bash(bash scripts/pilot-mode.sh set auto), Bash(bash scripts/pilot-mode.sh set assisted)
model: claude-opus-5-5
effort: low
---

Arguments: `$ARGUMENTS`. `assisted`, `auto`, `manual` or empty. The modes and what each one does: `rules/quality.md` "Verification mode". `assisted` runs every check as `auto` does and adds the boxes of `rules/assisted.md`; it changes only what the agent says, never what a hook, a deny rule or the gate allows.

The default of this installation is the mode every new session starts in, told by the start context line `Pilot mode: ...`. It lives in `.claude/pilot-mode`, git-ignored, written only by `bash scripts/pilot-mode.sh set <auto|assisted>` (never by Edit or Write: `.claude/` is denied to them), and `bash scripts/pilot-mode.sh show` reads it. `manual` is never a default.

1. Empty: run `bash scripts/pilot-mode.sh show` and reply with the mode in force and the default. The mode in force is the last `/pilot` of this session, else the mode of the start context line (`assisted` when the session has none). Change nothing.
2. `auto` or `assisted`: run `bash scripts/pilot-mode.sh set <mode>`, alone in its call. From now on this session follows that mode, until another `/pilot` or the end of the session, and every later session starts in it. `assisted`: read `rules/assisted.md` in full now and follow it. `auto`: the boxes stop. A failed write: say so in one line; this session still follows the mode.
3. `manual`: this session only, as before; never run the script, the default does not change. The boxes stop.
4. A check already shown to the human as a manual list stays open: under `auto` or `assisted`, run the items still not returned yourself.
5. Subagents: in `assisted` and `auto` every brief carries `VERIFICATION: auto` and nothing about boxes; in `manual`, `VERIFICATION: manual`. A subagent never shows a box.
6. Anything else: reply with the valid options (`/pilot`, `/pilot assisted`, `/pilot auto`, `/pilot manual`); nothing changes.
7. Reply in the language of the conversation, one line starting with `Verification mode:`, the mode in force and the default (`Verification mode: manual (default: auto)`), so the line survives a compaction.
