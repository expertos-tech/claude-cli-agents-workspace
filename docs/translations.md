# Translations

English · [Português (Brasil)](../i18n/pt-BR/docs/translations.md) · [Español](../i18n/es/docs/translations.md)

The documents are written in English and translated to two locales: `pt-BR` and `es`. The rule is
`.claude/rules/docs.md`; the suite checks it.

## What is translated

- the root `README.md` and every `README.md` of the repository, including the product's and the tools';
- the pages of the root `docs/`;
- the pages of `workspace/docs/`, except the decision records (`workspace/docs/decisions/`);
- the pages of `workspace/tools/*/docs/`.

## What is never translated

Rules, skills, agents, scripts and hooks, `CLAUDE.md`, `.claude/`, the files of `maintainers/` other than its
READMEs, the changelogs and the decision
records. They stay in English.

## Where a translation lives

`i18n/<locale>/<same path as the English file>`, with `<locale>` `pt-BR` or `es`. The translation of
`docs/hooks.md` is `i18n/pt-BR/docs/hooks.md` and `i18n/es/docs/hooks.md`. Keep the structure of the English file.
Code, paths, commands and the market's technical terms stay in English.

## The source line

Line 1 of each translation is exactly:

```text
<!-- source: <path from the repository root> sha256:<sha256 of the English file> -->
```

Recompute it after the last edit of the English file (`sha256sum <path>`).

## When

Translations are brought up to date once per release, by one agent with effort medium, for every pending one
(`/caw-merge --main`). Between releases a change to an English document leaves its translations pending.

## Language links

Right under the H1, each translated document outside `workspace/` has a line that links to its translations
(`English · Português (Brasil) · Español`); the translations carry the same line, linking back. In the root `README.md` it is centered, in HTML.

## Links in a translation

A link points to the same-locale translation when it exists, else to the English original, with a path relative to the
translation.

## The check

The suite has an `i18n` step. With `--i18n-pending`, the mode of every merge into `developer`, it lists each missing,
stale (hash differs) or orphan translation (one whose English source does not exist) as `pending:` and passes. Without
it, the strict mode of the release, each of them fails the suite.
