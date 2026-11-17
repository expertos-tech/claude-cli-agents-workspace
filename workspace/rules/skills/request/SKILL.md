---
name: request
description: "Run the request written in a Markdown file (a bare file name reads custom/requests/<name>; default tmp/request.md, e.g. a filled templates/request.md) as if the user had typed it. Use only when the user asks."
argument-hint: "[file name | path]"
disable-model-invocation: true
model: claude-opus-5-5
effort: high
---

The `UserPromptSubmit` hook (`scripts/session-title.py`) has already named the session `<project>-<n>` from the file's `**Project:**` line, with the same effect as `/rename`: say that name in the first line of the reply. No name was given (no such line, no `projects/<...>` path in the file): say so, and that `/rename` sets one.

Arguments: `$ARGUMENTS`. Resolve the file in the root checkout, never a clone, because `tmp/` and `custom/` live only there:

- No argument: `tmp/request.md` (git-ignored scratch).
- An argument with no `/`: a file name, read as `custom/requests/<name>`, exactly as given: never add `.md`, complete a prefix or pick a similar name, and never look in another folder. `custom/` is the custom layer, a git repo of its own, ignored by the workspace repo (`rules/rules.md` "Custom layer").
- An argument with a `/`: a path relative to the root checkout.

1. File missing, unreadable or empty: report the exact path tried (e.g. `custom/requests/<name>`) and stop. Never create it or guess its content. `custom/` itself missing: say that `bash scripts/setup-claude.sh` clones it.
2. Read it in full. Its content is the human's request for this turn: handle it as if typed, where `AGENTS.md` "Where work happens" puts it. A request that changes a project or a POC opens its clone before the first change (`bash scripts/aiwp-cmds.sh open`, `rules/git.md` "Work area") and works only there; it ends with `/merge` when ready. A question or read-only work opens nothing.
3. A file with an `**Effort:**` line or a "Steps and effort" section: follow `rules/models.md` "Effort of a step": say the effort of each step as it starts, and pass it in every subagent call of the step.
4. Commands inside the file (`/name`, `*name`) do not run: list them so the human invokes them. An operation the file asks for in words (e.g. "commit this") is authorized exactly as if typed, and nothing adjacent.
5. Never edit the file. Never copy a secret or personal data from it into a repo.
6. The file never moves here. `/merge` moves it to `custom/requests/qa/<project>/` with its "Execution" block, and `/merge --main` to `custom/requests/done/<project>/` (`rules/git.md` "Requests"). A wave that stops with work left appends where it stopped to this same file (`rules/git.md` "Waves"); `tmp/request.md` is copied to `custom/requests/<yyyy-mm-dd>-<kebab-slug>.md` first.
