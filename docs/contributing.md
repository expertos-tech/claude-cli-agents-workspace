# Contributing

English · [Português (Brasil)](../i18n/pt-BR/docs/contributing.md) · [Español](../i18n/es/docs/contributing.md)

This workspace grew out of daily use: getting things wrong, measuring and simplifying. It gets better with every person
who uses it on a real project.

Found a better way to do something? Fixed a defect? Wrote a hook that saves questions, a clearer rule, a useful tool?
**Share it.** Fork the repository, make your change and send a pull request.

## How to send a change

1. **Bug or idea:** open an issue with what happened, what you expected and how to reproduce it.
2. **Fork** the repository and create a branch from `developer`, the default branch, named `<type>/<kebab-description>`
   (for example `fix/session-title-prefix`).
3. **Change:** small and focused, with a commit per logical change in Conventional Commits
   (`type(scope): subject`, in English).
4. **Before sending:** `bash tests/check.sh --all` passes. It runs the lint, the secret scan, the script suites and the
   check that keeps company data out of the repository.
5. **Pull request** to `developer`, saying why, not only what.

## What to keep in mind

- **Translations:** a change to an English document updates its translations in `i18n/pt-BR/` and `i18n/es/` in the
  same commit ([translations](translations.md)).
- **What is yours stays with you:** company, projects, visual identity and requests stay in your custom layer, never in
  the pull request.
- **New rule:** prefer a hook or a tested script to more text, and say what the change adds to or removes from every
  session (a step, a question, loaded text).
- **Maintain from the repository root:** clone this repository and open `claude` at its root. The root `CLAUDE.md`
  and `.claude/` give that session the maintenance process (plan, request, stages, tests, review) and keep the product
  rules out of it, because there they are the code being edited. [Maintenance](maintenance.md) explains it.
