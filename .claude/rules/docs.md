---
paths:
  - "README.md"
  - "**/README.md"
  - "docs/**"
  - "workspace/docs/**"
  - "workspace/tools/*/docs/**"
  - "i18n/**"
  - "maintainers/**"
---

@workspace/rules/docs.md

Read that file in full before the task the session index names for it (`.claude/session-index.md`, given at the
session start), and follow it with the sections below over it: they win where they differ. Its `paths:` do not
limit it here.

---

## Ignore from the product rule

- Placement and language, "a change to an English document updates its translations in the same commit": here they
  are brought up to date once, at the release (CAW rules).
- The rules of a project, a POC, a component, an SDK and a project root repo: this repository is none of them. Its
  two changelogs are written by `/caw-merge` (`CLAUDE.md` "The maintenance process", step 6).

## Mapping

| Product | Here |
| --- | --- |
| `/merge`, `/merge --main`, `/merge --hotfix` | `/caw-merge`, `/caw-merge --main`, `/caw-merge --hotfix` |
| the root `CHANGELOG.md`, the version of the repository | `workspace/CHANGELOG.md`, the product's version, for a product change (`workspace/`, `install.sh`); the root `CHANGELOG.md` for every change, its sections dated by the product release |
| Decision records of the workspace (`docs/decisions/`) | `workspace/docs/decisions/` |

## CAW rules

- Translations: `i18n/pt-BR/<path>` and `i18n/es/<path>` for every `README.md` of the repository (the root one,
  `maintainers/` and the product's), every page of the root `docs/` and of `workspace/docs/` except decision records,
  and every page of `workspace/tools/*/docs/`. Nothing else is translated (`CLAUDE.md`, `.claude/`, the other files of
  `maintainers/`, rules, skills, agents, scripts, changelogs).
- A translated document outside the product carries, right under its H1, the language links line:
  `English · [Português (Brasil)](<path to i18n/pt-BR/...>) · [Español](<path to i18n/es/...>)`; each translation
  carries the same line with its own language unlinked.
- Translations are brought up to date once, at the release (`/caw-merge --main`), by one `docs-writer` call with effort
  `medium`, for every pending one; between releases the suite reports them as pending (`--i18n-pending`). Line 1 of
  each translation is exactly
  `<!-- source: <path from the repository root> sha256:<sha256 of the English file> -->`; recompute it after the last
  edit (`sha256sum <path>`). The strict suite (the release) fails on a missing, stale or orphan translation.
- Links in a translation point to the same-locale translation when it exists, else to the English original, with a
  path relative to the translation (`../../LICENSE`). Check every link you add resolves.
- The root `docs/` documents the project: how to install and use it, contribute, maintain and release it; the
  product's own guide stays in `workspace/docs/`. The root `README.md` stays short and links to `docs/`.
- `maintainers/` is public: no company names, no personal paths (`security.md`).
