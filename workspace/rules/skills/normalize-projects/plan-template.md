# Migration plan: `<repo>`

- Project: `projects/<repo>` (or `custom/pocs/<poc>`); remote: `<url, no credentials>`.
- Marker: `<none | x.y.z>`; workspace: `<VERSION>`; migrations applied: `<x.y.z, ...>`.
- Analysed: `<date>`, `developer` at `<sha>` (a POC: `custom/` at `<sha>`).
- Documentation language: `<asked; the answer goes here>`.
- Instruction files a team still uses: `<none | kept and excluded | removed>`.
- State: proposed | approved on `<date>` | applied on `<date>` | refused.

## Findings

One line per finding. Destination: `custom` (custom layer), `stays` (in the project, as documentation), `change` (in
the project, as the contract asks), `gap` (reported only), `alert` (security, reported only). Status: `proposed`,
`approved`, `edited`, `dropped`, `done`.

| # | Finding | Where | Destination | Action | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | `<what>` | `<path:line>` | `<destination>` | `<what will be done>` | proposed |

## Security alerts

Never a value: file, line and type. Each is shown to the person at the end of the skill, with the recommendation to
rotate it; the project's report gives only their number.

| # | File | Line | Type | In history only |
| --- | --- | --- | --- | --- |

## Answers of the person

- `<date>`: `<the approval, the edits, the language>`.

## Result

- Checkpoint tags: `<tag> <sha>`, `<tag> <sha>`.
- Branch: `<feat/ai-workspace-migration>` at `<sha>`; `developer` at `<sha>`; `main` at `<sha> | pull request <link>`.
- Test: `<what ran and the result | untested, by the person's choice>`.
