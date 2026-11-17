# Releases

English · [Português (Brasil)](../i18n/pt-BR/docs/releases.md) · [Español](../i18n/es/docs/releases.md)

Only the product is released. The maintenance of the repository is recorded but never released on its own.

## Branches

- `developer` is the default branch: every change enters it, through `/caw-merge`.
- `main` moves only by a product release.

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
5. The full suite, strict, from the last tag (translations included), and the test installation.
6. The final review of everything since the last tag against every request waiting in `qa/`, in two rounds with a
   clean context: **what enters and what leaves** (effort high: the inventory of what was added, changed and removed,
   each traced to its request; every acceptance criterion, pending ones included; every Execution block checked
   against the code; regressions, so nothing that works is removed without a request; whether each change does what
   was asked; the changelogs), then a **general** reading of the whole tree (effort medium: contradictions, dead
   references, leftovers).
7. The findings, once, in one list: per finding, fix now in the release clone or a request; a BLOCKER sent to a
   request stops the release.
8. The clone enters `developer`, at the commit the suite and the review judged.
9. Each public step is confirmed by the owner, one by one: `main` (a fast-forward from `developer`, or a pull request
   when refused), the tag `vX.Y.Z` (never moved or deleted) and the GitHub release, with the product changelog section
   as its notes.
10. A check that a fresh installation picks up the new tag.

A refused or failed public step stops the release there. Nothing is forced.

## Installers and tags

The installer and `aiwp` only take `vX.Y.Z` tags, never a branch: a workspace runs a released version
([how updates work](commands-and-updates.md)).
