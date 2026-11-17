# Functional request: project documentation in `docs/`, a short README, and translations of every README

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root. It documents the project (this repository and how it is maintained), not
the product, whose guide stays in `workspace/docs/`. It also delivers `readme-get-involved-first` (moved to `done/`).
Approved by the owner on 2026-11-17; recorded at approval (`.claude/rules/process.md` step 2).

## 1. Objective

Move the detail of the root `README.md` into pages of a new root `docs/`, write what the project lacks (contributing,
maintenance, releases, translations, repository), and translate the new pages and every README outside the product
into `pt-BR` and `es`, each with a language links line.

## 3. Business rules

- BR-1: `README.md` keeps, in this order: title, logo, language links, intro, the "Made for the CLI" note,
  "Get involved" (short), "Quick start" (short), "Documentation" (index of `docs/`) and "License". Every paragraph it
  loses is in a page of `docs/`.
- BR-2: `docs/` holds `README.md` (index), `getting-started.md`, `features.md`, `commands-and-updates.md`, `hooks.md`,
  `repository.md`, `contributing.md`, `maintenance.md`, `releases.md` and `translations.md`. The product's guide is
  linked, never duplicated.
- BR-3: every `README.md` of the repository and every page of the root `docs/` has its `pt-BR` and `es` translation
  under `i18n/<locale>/<path>`, with the source line and hash; the suite's i18n check requires them
  (`workspace/scripts/check-workspace.sh`).
- BR-4: every translated document outside the product shows, under its H1, the links to its other languages.
- BR-5: `.claude/rules/docs.md` and `CLAUDE.md` say what is translated and what `docs/` is for.

## 4. Acceptance criteria

- AC-1: Given the new README in each language, the first `##` section is "Get involved" and the second "Quick start".
- AC-2: Given the old README, every paragraph is in the new README or a page of `docs/`.
- AC-3: Given the suite, the i18n check fails on a missing translation of a root `docs/` page or of a README outside
  the product, and passes on the delivered tree; markdownlint passes on the changed files.

## 7. Out of scope

- The product's documentation (`workspace/README.md`, `workspace/docs/`).
- Translating `CLAUDE.md`, `.claude/` or files of `maintainers/` other than its READMEs.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. The i18n check covers root `docs/` and every README, with scenario tests | medium | A check of the product gate |
| 2. The English pages and the short README | medium | Mostly moved text, plus four new pages |
| 3. The `pt-BR` and `es` translations, in parallel by locale | medium | Disjoint paths |
| 4. Suite, markdownlint, commits | medium | Proof |

The agents of each stage run with the stage's effort, passed in the call.
