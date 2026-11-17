# Decision records

One record per decision about the workspace itself: a choice that is hard to reverse or that changes how the workspace works (a mechanism added or removed, a test or security policy, the layout). Smaller changes edit the record they adjust. The rule is `rules/docs.md` "Decision records".

## How a record is written

- File: `NNNN-kebab-title.md`, in English. `NNNN` is the next free number, with four digits; `scripts/check-workspace.sh` fails when two records share one.
- Title: `# NNNN Title`, then a `Status:` line: `accepted`, `partly superseded by NNNN` or `superseded by NNNN`.
- Sections: `## Context`, `## Options` (when there was a real choice), `## Decision`, `## Reason`, `## Consequences`, and `## Change history`, one line per later adjustment: `YYYY-MM-DD — what changed — why — who asked`.
- A record another one replaces keeps its file: its `Status:` line changes and its history gets a line pointing to the new one.
- A new record is added to the index below in the same commit.
- Decision records are not translated.

## Index

| No. | Decision | Status |
| --- | --- | --- |
| [0001](0001-base-design.md) | Base design: custom layer, work in clones and a merge gate, hooks, a mandatory core, a read-only installed core updated by `aiwp`, the maintenance at the repository root | accepted |
| [0002](0002-workspace-projects-and-normalization.md) | Workspace projects: the version marker, the warning at every interaction, `/normalize-projects` in two stages with checkpoint tags, and a gate that judges a normalization on what it adds | accepted |
