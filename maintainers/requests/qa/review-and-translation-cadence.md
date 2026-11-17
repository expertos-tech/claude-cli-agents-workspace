# Functional request: reviews by risk, translations at the release, and a final review before `main`

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root: the maintenance (`.claude/`, `CLAUDE.md`, `docs/`) and, for the final
review, the product's `/merge --main`. Approved by the owner on 2026-11-17; recorded at approval
(`.claude/rules/process.md` step 2).

## 1. Objective

Make each merge cost what its risk asks. A merge into `developer` checks and reviews only the difference that enters,
with an effort by risk, and leaves the translations pending. The release, the merge into `main`, brings every
translation up to date in one call and ends with a stronger final review: what enters and what leaves, so nothing that
works is removed without a request, then a general reading of the whole tree. The final review applies here and in the
product.

## 3. Business rules

- BR-1: At a merge into `developer`, the suite judges only what changed: `tests/check.sh --base origin/developer
  --i18n-pending`, without `--all`. The release runs it strict: `--all --base <last tag>`, translations included.
- BR-2: At a merge into `developer`, the review covers only `origin/developer..<sha>`; what is already on `developer`
  was reviewed. Effort `high` for a hook, the installer, `setup-claude.sh`, a gate script, a permission or deny rule
  or secrets; `medium` for other code or rules; no review for documentation alone.
- BR-3: Only a BLOCKER blocks a merge. Each RECOMMENDED becomes a backlog item and is fixed when the owner asks.
- BR-4: Translations are not updated per commit. At the release, one `docs-writer` call (claude-sonnet-5-5, effort
  medium) brings every pending translation up to date. Between releases the suite lists them as `pending:` and passes
  (`check-workspace.sh --i18n-pending`); the strict mode fails on them as before.
- BR-5: The release ends with a final review on everything since the last tag, in two rounds with a clean context:
  1. what enters and what leaves (effort high): the inventory of what was added, changed and removed, each traced to
     its request or a consequence; regressions (something that worked and is removed or changed with no request; a
     test removed or weakened; a weaker protection); intent (a change that does not do what was asked, does more, or
     reads it wrong); the changelogs. UNEXPLAINED removals and regressions are BLOCKERs;
  2. general (effort medium): the whole tree, for contradictions between rules, docs and code, dead references,
     translations that disagree with the English, leftovers.
- BR-6: The product's `/merge --main` gets the same final review, after the project's full tests and `validate.sh`.

## 4. Acceptance criteria

- AC-1: Given a stale translation, `tests/check.sh --base origin/developer --i18n-pending` passes and lists it as
  `pending:`; without `--i18n-pending` it fails. A strict run is never served from a pending run's cache.
- AC-2: `/caw-merge`, `/caw-check`, `review.md`, `models.md`, `process.md`, `docs.md` and `CLAUDE.md` say BR-1 to BR-5;
  the product's `/merge`, `rules/review.md` and `rules/git.md` say BR-6.
- AC-3: `docs/maintenance.md`, `docs/releases.md`, `docs/translations.md` and `docs/contributing.md` describe the new
  cadence; their translations stay pending until the next release.
- AC-4: The check-workspace suite passes with scenarios for the pending mode.

## 7. Out of scope

- The product's reviews at a merge into `developer` of a project (unchanged: one review, effort high).
- Translating the documents changed here before the next release.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. `--i18n-pending` in `check-workspace.sh`, with scenario tests | medium | A check of the product gate |
| 2. Rules and skills of the maintenance and of the product, the docs in English | medium | Text over decided behavior |
| 3. Suite, review of the difference, commits | medium | Proof |

The agents of each stage run with the stage's effort, passed in the call.

---

## Execution — 2026-11-17, merged into developer at fb442c1

- **Done:** `check-workspace.sh --i18n-pending` (b5ea3b0); the final review of the product `/merge --main` (b2a584f);
  reviews by risk, translations at the release, the final review here (ff4e45d); the release commit checked and
  reviewed before it merges (eb40e43, the review's BLOCKER).
- **Decisions taken while running:** none.
- **Deviations:** none.
- **Acceptance criteria:** AC-1, AC-2, AC-3, AC-4: proven (the check-workspace suite, 815, with the pending-mode
  scenarios; the rules and pages read against the request by the review).
- **Checks:** the suite, shellcheck, markdownlint, an independent review (one BLOCKER, fixed and reviewed again).
- **Left:** six RECOMMENDED findings, now pending requests (`process-merge-check-command`, `review-effort-wording`,
  `review-docs-only-scope`, `merge-release-step-reference`, `release-developer-moved`,
  `review-final-brief-unreleased`).
