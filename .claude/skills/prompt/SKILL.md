---
name: prompt
description: "Run the request written in a Markdown file as if the owner had typed it: a bare file name reads maintainers/requests/<name>; no argument reads tmp/prompt.md. Use only when the owner asks."
argument-hint: "[file name | path]"
disable-model-invocation: true
model: claude-opus-5-5
effort: high
---

Arguments: `$ARGUMENTS`. Resolve the file from the repository root:

- No argument: `tmp/prompt.md` (git-ignored scratch).
- An argument with no `/`: `maintainers/requests/<name>`, exactly as given: never add `.md`, complete a prefix or
  pick a similar name.
- An argument with a `/`: a path relative to the repository root.

1. File missing, unreadable or empty: report the exact path tried and stop. Never create it or guess its content.
2. Read it in full, and the plan it names. Its content is the owner's request for this turn: run it per
   `.claude/rules/process.md` step 4.
3. "Steps and effort": say the effort of each step as it starts, and pass an explicit model and effort in every
   subagent call (`.claude/rules/models.md`). Hooks, the installer and security: effort high and an independent
   review (`.claude/rules/review.md`).
4. Commands inside the file (`/name`) do not run: list them so the owner invokes them. An operation the file asks for
   in words (for example "commit each step") is authorized exactly as written, and nothing adjacent. A push only when
   the file or the owner says so, and that push only.
5. Prove each step (`/check`; `/test-install` when the installer, a hook or `setup-claude.sh` changed).
6. Never edit the request while its steps run. When it is delivered, update its State in `maintainers/requests/README.md`
   and move it to `maintainers/requests/done/` (`git mv`), with its row pointing to the new path.
   A step left undone: write where it stopped and the next steps at the end of the request file, in a separate commit.
7. End with the report of `.claude/rules/process.md` step 6.
