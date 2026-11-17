# Functional request: two changelogs, and only the product is released

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, in the maintenance only (`.claude/`, `CLAUDE.md`, the root `CHANGELOG.md`);
the product is not changed. Approved by the owner on 2026-11-17; recorded at approval (`.claude/rules/process.md`
step 2).

## 1. Objective

Keep two changelogs: the repository's at the root and the product's in `workspace/`. A maintenance change goes only
to the root one; a product change goes to the product's in detail and to the root one as a summary of the feature.
Only the product is released: a release with no product change is no new version.

## 3. Business rules

- BR-1: A product change is a change to `workspace/` or `install.sh`. It goes to `workspace/CHANGELOG.md` in detail,
  and to the root `CHANGELOG.md` as one summary line under `### Product`, pointing to the product changelog.
- BR-2: Every other change (`CLAUDE.md`, `.claude/`, `tests/`, `maintainers/`, `i18n/`, the root `README.md`) goes to
  the root `CHANGELOG.md` only, in detail, under its type.
- BR-3: Both changelogs use `## [X.Y.Z] - Unreleased`, the bump by Conventional Commit types, and the rule that a fix
  of something of the same unreleased version is not a fix (`workspace/rules/docs.md` "CHANGELOG.md").
- BR-4: There is no release of the maintenance: no tag and no GitHub release for a root version. `/caw-merge --main`
  releases only when `workspace/CHANGELOG.md` has an `Unreleased` section; otherwise it says there is nothing to
  release and stops, and the maintenance changes wait on `developer`.
- BR-5: A product release dates the root `Unreleased` section the same day (none: it adds a patch section). Under its
  `### Product`, it adds the line pointing to the GitHub release of `vX.Y.Z` and to the product changelog at that tag.
- BR-6: The root `CHANGELOG.md` starts with `## [0.1.0] - 2026-11-16` (the publication, pointing to v0.1.0) and
  `## [0.2.0] - Unreleased` with the changes made since.

## 4. Acceptance criteria

- AC-1: Given a maintenance-only range, when `/caw-merge` runs, then only the root `CHANGELOG.md` changes.
- AC-2: Given a range that changes `workspace/`, then `workspace/CHANGELOG.md` gets the detail and the root one gets a
  `### Product` summary line.
- AC-3: Given no `Unreleased` section in `workspace/CHANGELOG.md`, when `/caw-merge --main` runs, then it stops with
  "nothing to release" and nothing is tagged.
- AC-4: Given a product release of `vX.Y.Z`, then the root section is dated the same day and links to the release and
  to `workspace/CHANGELOG.md` at `vX.Y.Z`.
- AC-5: `bash tests/check.sh --all` passes and markdownlint passes on the changed files outside `workspace/`.

## 7. Out of scope

- The product's `/merge` (projects keep one changelog per component).
- Tags or GitHub releases for the maintenance.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. `/caw-merge`, `CLAUDE.md`, `git.md`, `process.md`, the root `CHANGELOG.md`, this record | medium | Text over decided behavior |

The agents of each stage run with the stage's effort, passed in the call.

---

## Execution — 2026-11-17, merged into developer at d4c22bd

- **Done:** the root `CHANGELOG.md`, `/caw-merge` writing both changelogs and releasing only the product, the rules
  (d4c22bd); the `/caw-merge` range fixed to start at the last changelog commit (579ea98).
- **Decisions taken while running:** none.
- **Deviations:** none.
- **Acceptance criteria:**
  - AC-1, AC-2: proven by the `/caw-merge` runs of 2b201dc and 67a99c9 (root only for maintenance, both for product).
  - AC-3, AC-4: pending: no `/caw-merge --main` has run yet.
  - AC-5: proven (`tests/check.sh --all`, markdownlint).
- **Checks:** the suite, markdownlint.
- **Left:** AC-3 and AC-4, at the first release.
