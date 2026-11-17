# Backlog

The backlog of the workspace itself: ideas, defects, improvements and technical debts of the product in `workspace/`
that have not become a request yet. One item per file. No rule loads this folder: Claude reads or changes an item only
when you ask.

## Create an item

1. Create `maintainers/backlog/<short-kebab-title>.md`, for example `export-usage-report.md`.
2. Fill the table and the sections below, and delete what does not apply.

Or ask Claude. Never write a secret, a personal detail or a company term: the backlog is public.

```markdown
# Short title

| Field | Value |
| --- | --- |
| Type | feature, defect, improvement or technical debt |
| Status | idea, ready, in progress, done or dropped |
| Priority | high, medium or low |
| Target | workspace, or tools/<name> |
| Created | YYYY-MM-DD |
| Source | who asked, or where it came up |

## Problem

What is wrong or missing, and who feels it, in 2 to 5 lines.

## Expected result

What changes when the item is done.

## Acceptance criteria

- AC-1: Given ..., when ..., then ...

## Out of scope

- What this item does not cover.

## Notes

Links, dependencies and decisions already taken.
```

## Fields

| Status | When |
| --- | --- |
| `idea` | Recorded, no acceptance criteria yet |
| `ready` | Has acceptance criteria and can become a request |
| `in progress` | Became a request and is running |
| `done` | Delivered |
| `dropped` | Will not be done; say why in "Notes" |

A done or dropped item stays in its file, with the status updated, to keep the reason.

## Turn an item into a request

The acceptance criteria and the out-of-scope list have the same format as the product's request template
(`workspace/templates/request.md`). Copy them into a request in `maintainers/requests/`, or ask Claude to
implement the item by its file name. What the item lacks becomes a question before the work starts.
