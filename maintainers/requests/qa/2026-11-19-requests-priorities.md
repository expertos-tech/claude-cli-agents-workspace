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
  that cited a round follow it: `aiwp-remove` and `gate-audit-gaps` to round 2, `rules-size-budget` to round 0;
  `prompt-log-results` to round 2, `measure-quality-indicators` to round 1, and `onboard` no longer beside
  `import-workspace`, which is in qa (the fix of W-2). Root `CHANGELOG.md` (6fc6cee).
- **Decisions:** the four findings of `/caw-merge` enter round 0, though the owner named only three requests: they
  fix `/caw-merge --main` itself, which the first release runs. The owner can overturn it.
- **Deviations:** at the merge, `developer` had taken in `request-in-progress` (the Status column of the tables),
  `assisted-mode` and `session-names`: the README was rebuilt over it. Nothing runs now, `session-names` stays in
  round 0 after `draft-prompt` (where its own session put it), and `merge-queue` goes to round 1, never with the four
  findings of `/caw-merge` (both change it).
- **Done when:** every pending request file has its row and a round or "no round"; checked against
  `git ls-tree origin/developer maintainers/requests/`.
- **Checks:** `bash tests/check.sh --base origin/developer --i18n-pending` passed (repo-terms skipped: no terms list).
- **Warnings:** the merge review: W-1 accept (`final-review.md` still says it runs after `fork-my-rules` and the hub,
  which the new order puts in round 2; the owner reviews that request before running it), W-2 fix (three requests
  still cited their old round).
- **Left:** nothing.
