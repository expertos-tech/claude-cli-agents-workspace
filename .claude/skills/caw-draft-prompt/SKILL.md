---
name: caw-draft-prompt
description: "Organize a loose text of the owner into a draft plan in maintainers/plans/, in the owner's language, placed in the priority order of its README with a criticality, or printed with screen; /caw-new-request turns it into a request. Use only when the owner asks."
argument-hint: "[screen] [text | path]"
disable-model-invocation: true
model: claude-opus-5-5
effort: medium
---

@workspace/rules/skills/draft-prompt/SKILL.md

Read that file in full and follow it as the procedure, with the sections below over it: they win where they differ.

---

## Ignore from the product skill

- Saving to `custom/plans/` and the commit and push in `custom/`: here the files go to `maintainers/plans/` and are
  committed only when the owner asks (`/caw-commit`).
- The README of the plans in the person's language: `maintainers/plans/README.md` is in English, a translated
  document of this public repository (its translations follow at the release, `.claude/rules/docs.md`).

## Mapping

| Product | Here |
| --- | --- |
| `custom/plans/<yyyy-mm-dd>-<kebab-slug>.md` | `maintainers/plans/<kebab-name>.md` |
| `custom/plans/README.md`, its section "Pending, by priority" | `maintainers/plans/README.md`, its section "Pending, by priority"; the other plans in "Other plans" |
| `rules/request-writing.md` | `workspace/rules/request-writing.md` |
| `/new-request <file>` | `/caw-new-request <file>` |
| the person | the owner |

## CAW rules

- Read the existing `maintainers/plans/` and `maintainers/requests/` to place the row: a pending plan or request
  this one depends on, or one of the same subject, is named among the gaps.
- The plan is saved in the owner's language (`CLAUDE.md` "Language"); its README row in English.
- Public text: no company names, no customer or project names, no personal paths, no internal URLs
  (`.claude/rules/security.md`).
- Nothing is committed; the summary ends with `➜ Next: /caw-new-request maintainers/plans/<name>.md`.
