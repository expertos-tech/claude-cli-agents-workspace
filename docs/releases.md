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

`/caw-merge --main`, only when the owner asks. The version is the `Unreleased` one of `workspace/CHANGELOG.md`.

1. A release clone `tmp/work/<yyyy-mm-dd>-release-vX-Y-Z/` on the branch `fix/release-vX-Y-Z`.
2. A full check in a clean context: the suite from the last tag, the test installation and a review of the range.
3. Fixes of what it finds, as commits in the clone.
4. `workspace/VERSION` to `X.Y.Z`, the product section dated, the root section dated and linked to the release, the
   translations of the changed documents, and the commit `chore(release): X.Y.Z`.
5. The clone enters `developer` as in any merge.
6. Each public step is confirmed by the owner, one by one: `main` (a fast-forward from `developer`, or a pull request
   when refused), the tag `vX.Y.Z` (never moved or deleted) and the GitHub release, with the product changelog section
   as its notes.
7. A check that a fresh installation picks up the new tag.

A refused or failed public step stops the release there. Nothing is forced.

## Installers and tags

The installer and `aiwp` only take `vX.Y.Z` tags, never a branch: a workspace runs a released version
([how updates work](commands-and-updates.md)).
