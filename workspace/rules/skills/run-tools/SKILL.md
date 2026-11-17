---
name: run-tools
description: "Start the workspace's local tools by ticking checkboxes: observability, the login and Safe Browsing simulators, the Azurite console (one compose group, claude-cli-agents-tools) and this machine's container console. --down stops the tools named or ticked. Use only when the user asks."
argument-hint: "[--down [tool...]]"
disable-model-invocation: true
model: claude-opus-5-5
effort: medium
---

Arguments: `$ARGUMENTS`. None: choose and start. `--down`, alone or with tool ids: stop.

`bash scripts/run-tools.sh` does all the work (`--help`); this skill only talks to the person and calls it. Never edit a
compose file, never read or print a file of `custom/env/`, and never run `docker compose` on the tools by hand.

## Start

1. Run `bash scripts/run-tools.sh list --json`. It fails: show the error and stop.
2. Show checkboxes in one `AskUserQuestion` call, `multiSelect: true`, one question per kind:
   - "Observability and consoles": every tool whose id does not end in `-simulator`, the machine's console included;
   - "Simulators": the ids ending in `-simulator`.

   Each option: the label is the title; the description is the URL and the state in plain words: "already up",
   "stopped", "not installed: /run-tools installs it", "runs in its old project: starting moves it into the group",
   and each line of `missing` ("configuration missing: ...", "port ... busy: ..."). A question takes 2 to 4 options:
   a kind with one tool joins the other question when it fits; more than 4 tools of a kind split into more questions
   (at most 4 questions, 16 tools); a tool left out is named in the reply. No tool at all: say so and stop.
3. Nothing ticked: say that nothing was started and stop. Unticking a tool that is up stops nothing.
4. Run `bash scripts/run-tools.sh up <ids ticked>`. A first build or a console installation can pass 3 minutes: run it
   in the background and say so.
5. Reply in the language of the conversation:
   - the table the script prints at the end: tool, URL, state;
   - each `refused:` line with its fix: a missing `custom/config/<tool>/...` file (the tool's README says what goes in
     it), a missing variable (`/local-env tools/<tool>`, then the person fills the value in an editor), a busy port
     (what holds it), a network another stack uses (stop that stack, then `/run-tools` again);
   - each `old volume kept: <name>` line: the data is already in the group's volume. Ask, in its own question, whether
     to delete the old one, "Keep" first. Only on an explicit "Delete" run `docker volume rm <name>`, one volume per
     command; the guard asks again before it runs.

## Stop (`--down`)

1. Tool ids given: `bash scripts/run-tools.sh down <ids>`.
2. None: `bash scripts/run-tools.sh list --json`, then the same checkboxes with only the tools in state `up` (none:
   say so and stop), then `down` with the ticked ones.
3. Reply with `bash scripts/run-tools.sh status`. `down` stops only: containers, volumes and images stay.
