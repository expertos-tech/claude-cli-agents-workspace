---
paths:
  - "**/README.md"
  - "**/CHANGELOG.md"
  - "**/docs/**/*.md"
---

# docs.md

## Placement and language

- Documentation changes in the same commit as the code it describes.
- The workspace core and its tools: English only. Translations of its documents live in `i18n/<locale>/` of the product repository, each starting with `<!-- source: <path> sha256:<hash of the English file> -->`; a change to an English document updates its translations in the same commit.
- A project or POC: `docs/`, `README.md` and `CHANGELOG.md` in the language its own rules or `custom/rules/` choose; none chosen: English. An `sdk/` meant for external use: English.
- Each page has one role: reference, explanation or how-to guide.

## README.md (every project, component and SDK)

- Covers: what it is, how to run, how to test, how to deploy (or how to install and consume, for a component or SDK).
- Short; link to `docs/` for detail.

## CHANGELOG.md

- Projects, components and SDKs: every delivery that changes behavior adds its entry under `Unreleased`, in the existing subsection of its type (`### Added`, `### Changed`, `### Fixed`). Format: Keep a Changelog, SemVer, newest first. A change of form only (spelling, formatting, a broken link) needs no entry.
- A version section only when the human asks: rename `Unreleased` to `[x.y.z] - YYYY-MM-DD` in a commit of its own.
- The workspace: `CHANGELOG.md` gets one section per release, written by the release process of the product repository; a session never edits it.

## docs/ of a project

- Overview: what, why, users, scope.
- Architecture: components and flows, with a diagram as code.
- Decision records (below).
- Operation and deployment guide: configuration, deploy, rollback, monitoring, common failures.
- Infra costs, when the project has infra (`rules/infra.md`).
- `docs/README.md` as the index of the pages.
- A library with no runtime of its own needs no operation guide and no infra costs.

## Decision records

- A record only for a choice that is hard to reverse or that changes how the project or the workspace works: the stack, the architecture, a mechanism (hook, gate, tool) added or removed, a test or security policy. It holds context, options, decision, reason, consequences.
- Anything smaller edits the record it adjusts and adds one line to its `## Change history`: `YYYY-MM-DD — what changed — why — who asked`.
- Workspace: one file per decision, `docs/decisions/NNNN-<kebab-title>.md`, in English, with a `Status:` line under the title (`accepted`, `partly superseded by NNNN`, `superseded by NNNN`). The number is the next one free. The index is `docs/decisions/README.md`.
- A project keeps one `docs/decisions.md`, with a `## D-n <title>` section per decision. A project that already has another format keeps it.
- A record another one replaces gets its `Status:` line changed and a history line pointing to the new one.

## Writing

- Direct text: no generic intro, no repetition, no theory that does not change a decision.
- A comparison ends with a winner, "tie" or "depends on X".
- A page with 3 or more sections and more than 60 lines gets a table of contents under the title.
