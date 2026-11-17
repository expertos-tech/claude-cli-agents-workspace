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

# docs.md

- English, direct, no generic intro. Each page has one role: reference, explanation or how-to.
- Documentation changes in the same commit as what it describes.
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
- Decision records of the product follow `workspace/rules/docs.md` "Decision records".
