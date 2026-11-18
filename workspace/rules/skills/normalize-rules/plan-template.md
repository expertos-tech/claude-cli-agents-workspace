# Rules migration plan: `<folder name>`

- Older workspace: `<absolute path>`; a git repository: `<yes, HEAD <sha> | no>`.
- Analysed: `<date>`, this workspace at version `<VERSION>`.
- Excluded as projects and POCs: `<number>` (listed at the end).
- State: proposed | confirmed on `<date>` | written on `<date>` | refused.

## Rules not imported

What the core or `custom/my-rules/` already covers. Information, not a decision.

| # | Item (origin) | Covered by |
| --- | --- | --- |
| 1 | `<what>` (`<path>`) | `<core piece and section>` |

## Decision

Assessment: the verdict (own rule, own skill or agent, replaces a core rule, needs core support, not worth keeping)
and what the item would change. Status: `import` or `reject`, the recommendation until the person confirms; after
stage 2, `done <commit>` or `failed: <reason>` on the `import` rows.

| # | Item (origin) | Assessment | Status | Why |
| --- | --- | --- | --- | --- |
| 1 | `<what>` (`<path>`) | `<verdict>: <what it changes>` | import | `<one or two sentences, naming the core piece>` |

## Proposed texts

One per `import` row, as it will be written, secrets as placeholders.

### 1. `<custom/my-rules/<file>>`

```markdown
<the text>
```

## Secrets

Never a value: where it was found, its type, the placeholder used and where the person sets the value.

| # | Found in | Type | Placeholder | Set it in |
| --- | --- | --- | --- | --- |

## Answers of the person

- `<date>`: `<the changes by row number, the edited texts, the confirmation>`.

## Projects found

```text
Projects found in the workspace given, in case you want to migrate them:
* /normalize-projects --from <absolute path>
```
