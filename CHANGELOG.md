# Changelog

The history of this repository: the maintenance of the project (`CLAUDE.md`, `.claude/`, `tests/`, `maintainers/`,
`i18n/`, `docs/`, `README.md`) in detail, and each product change as a summary under "Product". The product's own
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
- The i18n check of the product gate also requires the translations of every README and of the root `docs/`, and can
  report them as pending (`--i18n-pending`).
- `/merge --main` ends with a final review of what enters and what leaves, then a general one.
- A request lifecycle (pending, `qa/`, `done/`) with an Execution block at each merge; the release per project with
  the project's own changelog in its root repo; any project layout, nested repos included; `/prompt` becomes
  `/request`; the prompt log moves to `logs/`; no backlog.
- `/merge --hotfix`: an error in production fixed from `main` as a patch version, then merged down into `developer`;
  the repo is blocked until it is.
- `/run-tools` and `tools/compose.yaml`: the local tools started by checkbox, the container ones in one compose group,
  their configuration from `custom/`.

### Added

- This changelog of the repository, next to the product's.
- `/caw-merge`: the work of a session into `developer` through the suite and a clean-context review, writing both
  changelogs; `/caw-merge --main` releases the product version. Every push it makes comes right after a passing suite
  on that same commit, so nothing reaches this public repository without the company-terms scan.
- Requests in `maintainers/requests/` for the features discussed and not built yet (among them a hotfix flow from
  `main`, and the findings of the reviews), in the order they run, and the
  `/rules` lessons and the local delivery of `/fork-my-rules` in the `rules` and `fork-my-rules` requests.
- `maintainers/requests/done/`: delivered requests, and every plan the owner approves, recorded at approval.
- `maintainers/requests/qa/`: the requests on `developer` not released yet, each with what each merge did; the
  backlog becomes pending requests (`idea` or `ready`).
- `tests/check.sh` checks every `caw-*` layer: its product skill exists and its three sections are there.
- `/caw-merge --hotfix <description>`: a fix of the released product from `main`, as a patch version with its tag
  and GitHub release when the owner says to publish, then `main` merged into `developer` (`--down` resumes it); a
  maintenance-only fix is not a hotfix. `/caw-merge` and `/caw-request` refuse to start while `main` is not in
  `developer`.
- `docs/`: the documentation of the project: getting started, features, commands and updates, hooks, the repository,
  contributing, maintenance, releases and translations.
- `pt-BR` and `es` translations of `docs/` and of every README outside the product, each with a language links line.

### Changed

- `developer` is the default branch; `main` moves only by a product release.
- `/caw-prompt` works in a clone on a work branch under `tmp/work/`, and finds a bare file name in
  `maintainers/requests/`, then `tmp/prompts/`, then `tmp/`.
- The maintenance skills carry the prefix `caw-`, apart from the product's; `/caw-merge`, `/caw-request` (was
  `/caw-prompt`), `/caw-commit` and `/caw-draft-request` are layers over the product skill of the same purpose.
- An approved plan is recorded as a pending request, no longer in `done/`.
- Plans and requests are shown to the owner in their language and saved in English.
- A merge into `developer` checks and reviews only the difference that enters, with the review effort by risk and no
  review for documentation alone; a RECOMMENDED finding becomes a backlog item.
- Translations are brought up to date once per release, by one agent; between releases they are listed as pending.
- `/caw-merge --main` ends with the same final review as the product's: what enters and what leaves, then general.
- `README.md` keeps the intro, "Get involved", a short "Quick start", the index of `docs/` and the license.
- `docs/features.md` lists `/run-tools` and the tools' compose group.

### Removed

- `/release`: replaced by `/caw-merge --main`.

## [0.1.0] - 2026-11-16

### Product

- Released [v0.1.0](https://github.com/expertos-tech/claude-cli-agents-workspace/releases/tag/v0.1.0): see its
  [changelog](https://github.com/expertos-tech/claude-cli-agents-workspace/blob/v0.1.0/workspace/CHANGELOG.md).

### Added

- The maintenance at the repository root: the process, rules, skills and agents for whoever maintains the product,
  the repository suite (`tests/check.sh`) and the test installation (`tests/test-install.sh`).
