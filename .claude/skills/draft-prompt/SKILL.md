---
name: draft-prompt
description: "Turn the owner's ideas into a plan (maintainers/plans/) or a request (maintainers/requests/, in the format of workspace/templates/request.md), asking only the doubts with no best alternative. Use only when the owner asks."
argument-hint: "[plan | request] [ideas | path]"
disable-model-invocation: true
model: claude-opus-5-5
effort: high
---

Arguments: `$ARGUMENTS`. `plan` or `request` first (default: `request` when a plan with the owner's answers exists for
the subject, else `plan`), then the ideas as free text or the path of a file holding them. Empty: ask for the ideas in
one line and stop.

Never implement here. Follow `.claude/rules/process.md` steps 2 and 3.

1. Read what the ideas touch in `workspace/` and the existing `maintainers/plans/` and `maintainers/requests/`. Reuse
   their terms; never duplicate a plan that exists: extend it.
2. **Plan** (`maintainers/plans/<kebab-name>.md`): status line, the problem, the options with trade-offs, the
   recommendation, the design, and numbered decisions (D-1, D-2...) for the owner. Add a row to
   `maintainers/plans/README.md`.
3. **Request** (`maintainers/requests/<kebab-name>.md`): read `workspace/templates/request.md` fresh and use its
   headings: objective, business rules (BR-n), acceptance criteria (AC-n, each verifiable), out of scope, and "Steps
   and effort" (effort high for hooks, the installer, security and reviews). Name the plan it builds. Add a row to
   `maintainers/requests/README.md` in the order it runs.
4. Ask only the doubts that have no best alternative, numbered, with options. List the rest as assumed decisions the
   owner can overturn. The owner's replies continue this command until delivery.
5. Public text: English, no company names, no personal paths (`.claude/rules/security.md`). Evidence from real use
   that names them stays in `tmp/`.
6. Show the result on screen in the owner's language and save it in English, with one line saying so. Do not commit unless the owner asks (`/commit`). End with the line to run
   a request: `/prompt <name>.md`.
