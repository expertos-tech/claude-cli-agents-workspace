---
paths:
  - "README.md"
  - "**/README.md"
  - "workspace/docs/**"
  - "workspace/tools/*/docs/**"
  - "i18n/**"
  - "maintainers/**"
---

# docs.md

- English, direct, no generic intro. Each page has one role: reference, explanation or how-to.
- Documentation changes in the same commit as what it describes.
- Translations: `i18n/pt-BR/<path>` and `i18n/es/<path>` for the root `README.md`, every `README.md` under `workspace/`,
  every page of `workspace/docs/` except decision records, and every page of `workspace/tools/*/docs/`. Nothing else is
  translated (`CLAUDE.md`, `.claude/`, `maintainers/`, rules, skills, agents, scripts, changelogs).
- A change to an English document updates both translations in the same commit. Line 1 of each translation is exactly
  `<!-- source: <path from the repository root> sha256:<sha256 of the English file> -->`; recompute it after the last
  edit (`sha256sum <path>`). The gate fails on a missing, stale or orphan translation.
- Links in a translation point to the same-locale translation when it exists, else to the English original, with a
  path relative to the translation (`../../LICENSE`). Check every link you add resolves.
- `maintainers/` is public: no company names, no personal paths (`security.md`).
- Decision records of the product follow `workspace/rules/docs.md` "Decision records".
