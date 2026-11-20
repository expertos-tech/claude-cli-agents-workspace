---
name: caw-new-request
description: "Turn the owner's ideas, or a draft plan of /caw-draft-prompt, into a plan (maintainers/plans/) or a request (maintainers/requests/, in the format of workspace/templates/request.md), asking only the doubts with no best alternative; a summary on screen. Use only when the owner asks."
argument-hint: "[plan | request] [ideas | path]"
disable-model-invocation: true
model: claude-opus-5-5
effort: high
---

@workspace/rules/skills/new-request/SKILL.md

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
| a plan of `/draft-prompt` in `custom/plans/`, `custom/plans/README.md` | a draft plan of `/caw-draft-prompt` in `maintainers/plans/`, `maintainers/plans/README.md` (in English; the other plans in its table "Other plans") |
| the plan's status line `request: custom/requests/<file>` | `request: maintainers/requests/<name>.md` |
| `rules/request-writing.md` | its procedure, plus `.claude/rules/process.md` steps 2 and 3 |
| `/request <file>` | `/caw-request <name>.md` |
| the user | the owner |

## CAW rules

- Arguments: `plan` or `request` first, then the ideas as free text or the path of a file holding them. Default:
  `request` when the path is a draft plan of `/caw-draft-prompt` (`Status: draft`) or a plan with the owner's answers
  exists for the subject, else `plan`. Empty: ask for the ideas in one line and stop. Never implement here.
- Read what the ideas touch in `workspace/` and the existing `maintainers/plans/` and `maintainers/requests/`; never
  duplicate a plan that exists: extend it.
- **Plan** (`maintainers/plans/<kebab-name>.md`): status line, the problem, the options with trade-offs, the
  recommendation, the design, and numbered decisions (D-1, D-2...). Add a row to `maintainers/plans/README.md`.
- **A draft plan given** (`process.md` steps 2 and 3): its final guidance holds (the product's "Flow" step 1: evaluate,
  research with generic terms, improvements `I-n` accepted one by one). The open points become the plan's decisions:
  the blocking ones asked with the improvements, in one message; the rest assumed, which the owner can overturn.
  Then write into the plan, below its sections and in its language, the problem, the options with trade-offs, the
  recommendation, the design with the accepted improvements, and the decisions with the owner's answers; then the
  request, whose delivery moves the plan's README row from "Pending, by priority" to "Other plans" and sets its status
  line. With `plan`, only the plan is written, and its row stays in "Pending, by priority" until a request is
  written from it.
- **Request** (`maintainers/requests/<kebab-name>.md`, pending, `**State:** idea` or `ready`): the headings of
  `workspace/templates/request.md`, the effort of each stage by `.claude/rules/models.md`. Name the plan it builds.
  Add a row to `maintainers/requests/README.md` in the order it runs.
- Public text: no company names, no personal paths (`.claude/rules/security.md`). A request is saved in English, a
  plan in the owner's language (`CLAUDE.md` "Language"). On screen, in the owner's language: a request by the summary
  of the product's "Delivery", its run line `➜ Run: /caw-request <name>.md`; a plan by its title, file and language,
  the recommendation in a line and every decision still open, never the whole plan unless the owner asks.
