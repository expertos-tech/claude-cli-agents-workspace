---
name: caw-draft-request
description: "Turn the owner's ideas into a plan (maintainers/plans/) or a request (maintainers/requests/, in the format of workspace/templates/request.md), asking only the doubts with no best alternative. Use only when the owner asks."
argument-hint: "[plan | request] [ideas | path]"
disable-model-invocation: true
model: claude-opus-5-5
effort: high
---

@workspace/rules/skills/draft-request/SKILL.md

Read that file in full and follow it as the procedure, with the sections below over it: they win where they differ.

---

## Ignore from the product skill

- Saving to `custom/requests/` and the commit and push in `custom/`: here the files go to `maintainers/` and are
  committed only when the owner asks (`/caw-commit`).
- The role of a separate Claude project (`rules/request-writing.md` "Role"): this session drafts at the repository
  root.

## Mapping

| Product | Here |
| --- | --- |
| `custom/requests/<file>` | `maintainers/requests/<kebab-name>.md` |
| `rules/request-writing.md` | its procedure, plus `.claude/rules/process.md` steps 2 and 3 |
| `/request <file>` | `/caw-request <name>.md` |
| the user | the owner |

## CAW rules

- Arguments: `plan` or `request` first (default: `request` when a plan with the owner's answers exists for the
  subject, else `plan`), then the ideas as free text or the path of a file holding them. Empty: ask for the ideas in
  one line and stop. Never implement here.
- Read what the ideas touch in `workspace/` and the existing `maintainers/plans/` and `maintainers/requests/`; never
  duplicate a plan that exists: extend it.
- **Plan** (`maintainers/plans/<kebab-name>.md`): status line, the problem, the options with trade-offs, the
  recommendation, the design, and numbered decisions (D-1, D-2...). Add a row to `maintainers/plans/README.md`.
- **Request** (`maintainers/requests/<kebab-name>.md`, pending, `**State:** idea` or `ready`): the headings of
  `workspace/templates/request.md`, the effort of each stage by `.claude/rules/models.md`. Name the plan it builds.
  Add a row to `maintainers/requests/README.md` in the order it runs.
- Public text: English, no company names, no personal paths (`.claude/rules/security.md`).
- Show the result in the owner's language and save it in English, with one line saying so. End with the line to run
  a request: `/caw-request <name>.md`.
