# Functional request: README opens with "Get involved", then "Quick start"

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained: `README.md` and its translations
`i18n/pt-BR/README.md` and `i18n/es/README.md`. It depends on no other request and fits **round 1** of
`maintainers/requests/README.md` (or any round: it is text only). Size: an adjustment.

## 1. Objective

The owner decided the order of the README: "the first section must be: share your evolution and fixes, open a fork and
send your PR, let's turn this into a big open-source community; right after it, a Quick start, a step-by-step recipe".
The older copy had that order, but the README written for the GitHub page in the 0.1.0 publication put "Get involved"
near the end (after Commands, updates, hooks, custom layer and layout) and "What you get" and "Requirements" before
"Quick start". This request restores the owner's order without losing content.

## 3. Business rules

- BR-1: after the title, the logo, the language links and the short "Made for the CLI" note, the first section is
  "Get involved" (pt-BR "Faça parte", es "Participa"), short: the invitation to share fixes and improvements by fork
  and pull request, building an open-source community. The detailed contribution checklist (suite, translations, what
  stays in the custom layer, new rules) may stay there or move to a later "Contributing" section, as long as nothing is
  lost.
- BR-2: the second section is "Quick start". "What you get" and "Requirements" come right after it, or "Requirements"
  becomes the first step of the Quick start; the reader still sees the requirements before the install command.
- BR-3: anchors that other documents link to keep working (check every link to `README.md#...` in the repository and
  in `i18n/`).
- BR-4: the three languages change in the same commit, with the `i18n` source line and hash updated, and
  `bash tests/check.sh --all` passing.

## 4. Acceptance criteria

- AC-1: Given the README in each language, then the first `##` section is the "Get involved" one and the second is
  the Quick start.
- AC-2: Given the old and new README, then every paragraph of the old one is still present (moved, not removed).
- AC-3: Given the suite, then the `i18n` step, the link check and the lint pass.

## 7. Out of scope

- Rewriting the content of the sections.
- `docs/usage.md` and the tool READMEs.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Reorder the three READMEs, fix anchors, run the suite | low | A mechanical text change |

The agents of each stage run with the stage's effort, passed in the call.

---

## Execution — 2026-11-17, merged into developer at f9ba9cf

- **Done:** inside `project-docs.md`: "Get involved" first and "Quick start" second in the three READMEs.
- **Acceptance criteria:** AC-1, AC-2, AC-3: proven (see `project-docs.md`).
- **Left:** none.
