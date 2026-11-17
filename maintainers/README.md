# maintainers

English · [Português (Brasil)](../i18n/pt-BR/maintainers/README.md) · [Español](../i18n/es/maintainers/README.md)

The work of whoever maintains the product, in the open. Nothing here is ever copied into an installed workspace, and
nothing here names a company, a customer or a person: private evidence from real use stays in the git-ignored `tmp/`.
The process that writes these files is in the root `CLAUDE.md` and `.claude/rules/process.md`.

| Folder | What it holds |
| --- | --- |
| `plans/` | Designs: the problem, the options, a recommendation and the numbered decisions for the owner |
| `requests/` | Functional requests: pending at its root (`idea` or `ready`, run with `/caw-request`), `qa/` once on `developer`, `done/` once released. An idea is a request in state `idea`; there is no backlog |
| `reviews/` | Reports of independent reviews (for example a final review before a release); created by the first one |
