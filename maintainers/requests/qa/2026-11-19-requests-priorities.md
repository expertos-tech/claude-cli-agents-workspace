# Functional request: the order of the pending requests before the first release

**Project:** claude-cli-agents-workspace

**State:** done in a session. Size: adjustment. Created 2026-11-19 from the owner's words.

## Requested

The owner named `assisted-mode`, `draft-prompt` and `final-review` as the last requests before the first installation
and the first release, and asked to revise `maintainers/requests/README.md` with what exists, what is running, and the
priorities reorganized where needed.

## Execution — 2026-11-19, merged into developer

- **Done:** `maintainers/requests/README.md` (4e0c74a): the recommended order names the requests running now
  (`request-in-progress`, at its merge, and `assisted-mode`); round 0 is what comes before the first installation and
  `/caw-merge --main`: `request-in-progress` and `assisted-mode`, then `draft-prompt` and the four findings of
  `/caw-merge` in one session (`release-developer-moved` and `release-main-sha-check` first), then `final-review` last
  with `rules-size-budget` folded in. Round 1 is the next release (`import-workspace-code-folders`, which may also run
  now on disjoint paths, `import-from-fork`, `measure-quality-indicators`, `merge-project-name`,
  `release-per-project-proof`, `merge-queue`); round 2 the later ones. The tables follow the rounds. The requests
  that cited a round follow it: `aiwp-remove` and `gate-audit-gaps` to round 2, `rules-size-budget` to round 0.
  Root `CHANGELOG.md` (6fc6cee).
- **Decisions:** the four findings of `/caw-merge` enter round 0, though the owner named only three requests: they
  fix `/caw-merge --main` itself, which the first release runs. The owner can overturn it.
- **Deviations:** none.
- **Done when:** every pending request file has its row and a round or "no round"; checked against
  `git ls-tree origin/developer maintainers/requests/`.
- **Checks:** `bash tests/check.sh --base origin/developer --i18n-pending` passed (repo-terms skipped: no terms list).
- **Warnings:** none.
- **Left:** `request-in-progress` changes the same tables (a Status column): its merge resolves the conflict, with
  `assisted-mode` as `doing`.
