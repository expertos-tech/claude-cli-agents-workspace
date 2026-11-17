# Changelog

The history of this repository: the maintenance of the project (`CLAUDE.md`, `.claude/`, `tests/`, `maintainers/`,
`i18n/`, this `README.md`) in detail, and each product change as a summary under "Product". The product's own
changelog, with the detail, is [`workspace/CHANGELOG.md`](workspace/CHANGELOG.md).

Only the product is released (tags `vX.Y.Z` and GitHub releases). The versions here are never released on their own:
a section is dated by the product release that ships it, and points to it.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the versions
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - Unreleased

### Product

- `/merge` writes a versioned changelog at every merge, and `/merge --main` releases that version with a tag
  ([product changelog](workspace/CHANGELOG.md)).
- Plans and requests are shown in the person's language and saved in English.

### Added

- This changelog of the repository, next to the product's.
- `/caw-merge`: the work of a session into `developer` through the suite and a clean-context review, writing both
  changelogs; `/caw-merge --main` releases the product version.
- `maintainers/requests/done/`: delivered requests, and every plan the owner approves, recorded at approval.

### Changed

- `developer` is the default branch; `main` moves only by a product release.
- `/caw-prompt` works in a clone on a work branch under `tmp/work/`, and finds a bare file name in
  `maintainers/requests/`, then `tmp/prompts/`, then `tmp/`.
- The maintenance skills carry the prefix `caw-`, apart from the product's.
- Plans and requests are shown to the owner in their language and saved in English.

### Removed

- `/release`: replaced by `/caw-merge --main`.

## [0.1.0] - 2026-11-16

### Product

- Released [v0.1.0](https://github.com/expertos-tech/claude-cli-agents-workspace/releases/tag/v0.1.0): see its
  [changelog](https://github.com/expertos-tech/claude-cli-agents-workspace/blob/v0.1.0/workspace/CHANGELOG.md).

### Added

- The maintenance at the repository root: the process, rules, skills and agents for whoever maintains the product,
  the repository suite (`tests/check.sh`) and the test installation (`tests/test-install.sh`).
