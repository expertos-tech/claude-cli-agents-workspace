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

- Projects, components and SDKs: `/merge` is the only writer, at each merge into `developer`, from `git log` and `git diff` of what enters. Format: Keep a Changelog, SemVer, newest first; subsections `### Added`, `### Changed`, `### Fixed`, `### Removed`, `### Security`, written for the reader, no duplicates. A change of form only (spelling, formatting, a broken link) needs no entry. A component with its own `CHANGELOG.md` (the nearest one up the tree from the changed files) gets its own section and version; a changed file no `CHANGELOG.md` covers goes to the root one, created when missing. The root `CHANGELOG.md` is the version of the repository: its version names the release tag.
- The next version is always named: `## [X.Y.Z] - Unreleased`. L is the higher of the newest dated header and the newest `vX.Y.Z` tag (neither: `0.0.0`). No `Unreleased` section: bump L by the Conventional Commit types of what enters: a `feat` → minor; only `fix`, `docs`, `refactor`, `chore`, `test`, `perf`, `build` or `ci` → patch; breaking (`!`) → major from 1.0.0, minor before. A section that is a patch of L (same X.Y) becomes X.(Y+1).0 when a new `feat` enters; a minor or major section keeps its number and only gains entries.
- A fix of something that entered the same `Unreleased` version is not a fix: no `### Fixed` entry and no bump. Adjust the original entry, only when the behavior it describes changed. `### Fixed` is only for what a dated version already published.
- `/merge --main` dates the section (`## [X.Y.Z] - YYYY-MM-DD`) and tags `main` with `vX.Y.Z`. Never edit a dated section.
- The workspace: `CHANGELOG.md` gets one section per release, written by `/merge` of the product repository; a session of an installed workspace never edits it.

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
