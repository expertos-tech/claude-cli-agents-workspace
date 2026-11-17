---
name: pilot
description: "Set or show this session's verification mode: auto (the agent runs every check a human could do by hand, visual ones included) or manual (the human gets a checklist and the agent waits). Use only when the user asks."
argument-hint: "[auto|manual]"
disable-model-invocation: true
model: claude-opus-5-5
effort: low
---

Arguments: `$ARGUMENTS`. `auto`, `manual` or empty. The mode and what each one does: `rules/quality.md` "Verification mode". It authorizes changing this session's mode only: no file, no other session.

1. Empty: reply with the mode in force, `auto` when no `/pilot` ran in this session. Change nothing.
2. `auto` or `manual`: from now on, this session and every subagent it briefs follow that mode, until another `/pilot` or the end of the session. A check already shown to the human as a manual list stays open: under `auto`, run the items still not returned yourself.
3. Anything else: reply with the valid options (`/pilot`, `/pilot auto`, `/pilot manual`); the mode does not change.
4. Reply in the language of the conversation, one line starting with `Verification mode:` and the mode in force, so the line survives a compaction.
