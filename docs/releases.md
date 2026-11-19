# Releases

English · [Português (Brasil)](../i18n/pt-BR/docs/releases.md) · [Español](../i18n/es/docs/releases.md)

Only the product is released. The maintenance of the repository is recorded but never released on its own.

## Branches

- `developer` is the default branch: every change enters it, through `/caw-merge`.
- `main` moves only by a product release, or by a hotfix of the product ([below](#hotfix)).

## The two changelogs

| File | What it records |
| --- | --- |
| `CHANGELOG.md` (root) | The repository: every change. A maintenance change (`CLAUDE.md`, `.claude/`, `tests/`, `maintainers/`, `i18n/`, `docs/`, the root `README.md`) in detail; a product change as one summary line under `### Product` |
| `workspace/CHANGELOG.md` | The product: only a change to `workspace/` or `install.sh`, in detail, for someone who uses the workspace |

Both follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

- A version in progress is `## [X.Y.Z] - Unreleased`.
- The bump follows the Conventional Commit types of what enters each changelog.
- A fix of something that entered the same unreleased version is not a fix: it adds no `### Fixed` entry and no bump.
  The original entry is adjusted only when the behavior it describes changed.
- The versions of the root changelog are never released on their own: a section is dated by the product release that
  ships it, and links to it.
- Maintenance changes alone are never released: with no `Unreleased` version in `workspace/CHANGELOG.md`, there is
  nothing to release.

## Releasing the product

`/caw-merge --main [instructions]`, only when the owner asks. The version is the `Unreleased` one of
`workspace/CHANGELOG.md`; with none, there is nothing to release.

1. The plan: what is released, and every conflict an instruction causes, with its effect and the options, before
   anything changes (for example "only caw, not the product": `main` can only move to `developer` as a whole).
2. A release clone `tmp/work/<yyyy-mm-dd>-release-vX-Y-Z/` on the branch `fix/release-vX-Y-Z`.
3. The translations: one agent brings every pending one up to date.
4. `workspace/VERSION` to `X.Y.Z`, the product section dated, the root section dated and linked to the release, the
   requests of `maintainers/requests/qa/` moved to `done/`, and the commit `chore(release): X.Y.Z`, so the checks
   below judge them.
5. The full suite, strict, from the last tag (translations included), and the test installation. Then the review
   fixtures (`tests/review-fixtures/`), once: made-up changes, one per hard rule, each reviewed by a `reviewer` at the
   effort of a merge into `developer`; a fixture not judged at its expected level is a warning of the release.
6. The final review of everything since the last tag, widened as needed, against every request waiting in `qa/`: a
   `reviewer` with a clean context asks the three questions (what was asked against what was done, every acceptance
   criterion and Execution block included; what went beyond the request, each change traced to its request or a
   consequence; what existed and was lost, so nothing that works is removed without a request), and checks the
   changelogs. Effort `high`; a range too large for one context is split in parts, reviewed in parallel. There is no separate
   general round.
7. The findings, once, in one list: a BLOCKER is fixed in the release clone, or sent to a request, which stops the
   release; a WARNING is the owner's to decide: fix now, a request or leave as is.
8. The clone enters `developer`, at the commit the suite and the review judged.
9. Each public step is confirmed by the owner, one by one: `main` (a fast-forward from `developer`, or a pull request
   when refused), the tag `vX.Y.Z` (never moved or deleted) and the GitHub release, with the product changelog section
   as its notes.
10. A check that a fresh installation picks up the new tag.

A refused or failed public step stops the release there. Nothing is forced.

## Hotfix

`/caw-merge --hotfix <description>`, only when the owner asks: an error of the released product, fixed from `main`
so nothing not yet released reaches the installations. A fix that touches only the maintenance is not a hotfix: it
follows the normal flow through `developer`.

1. A clone on `fix/<slug>`, from the remote `main`; only what the error needs, with its test.
2. The patch version: `workspace/VERSION` to `X.Y.(Z+1)`, a dated section in both changelogs, the commit
   `chore(release): X.Y.Z`.
3. The strict suite from the last tag and the test installation; no commit that only `developer` has.
4. A review of the fix against `main` (the three questions; effort by content): every change not linked to the error is a BLOCKER.
5. The owner's OK, then `main` by fast-forward. Then "publish?": yes, the tag `vX.Y.(Z+1)` and the GitHub release,
   each confirmed; no, no tag.
6. Right after, `main` is merged into `developer`: a merge commit when it is clean; a conflict is resolved in a
   branch that goes through `/caw-merge`, with the `Unreleased` sections kept on top of the patch section.

Until `developer` holds `main`, `/caw-merge` and `/caw-request` refuse to start: the merge down comes first
(`/caw-merge --hotfix --down`). It is computed from git, so it survives a cancelled or crashed session.

## Installers and tags

The installer and `aiwp` only take `vX.Y.Z` tags, never a branch: a workspace runs a released version
([how updates work](commands-and-updates.md)).
