# Repository

English · [Português (Brasil)](../i18n/pt-BR/docs/repository.md) · [Español](../i18n/es/docs/repository.md)

## Repository layout

| Path | What it is |
| --- | --- |
| `workspace/` | The product: `AGENTS.md`, `rules/`, `scripts/`, `tools/`, `docker/`, `docs/`, `assets/`, `templates/`, `VERSION`, `CHANGELOG.md`. This is what gets installed |
| `CLAUDE.md`, `.claude/` | The maintenance of the repository, at its root: the process, rules, skills (`.claude/skills/caw-*`) and agents for whoever maintains the product, and the settings that keep the product's rules out of that session |
| `docs/` | The documentation of the repository: how to use the workspace, contribute, maintain and release it |
| `CHANGELOG.md` | The history of the repository: every change, with the product's changes as summaries ([releases](releases.md)) |
| `tests/` | The repository's suite (`check.sh`) and the test installation |
| `maintainers/` | The maintainers' work, in the open: backlog, plans, requests and reviews |
| `i18n/` | Translations of the documents and READMEs (`pt-BR`, `es`), with the same structure as the repository |
| `install.sh` | The installer |
| `tmp/` | Git-ignored scratch: test installations and private notes |
