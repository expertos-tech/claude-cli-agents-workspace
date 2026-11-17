# git.md

## Commits

- One logical change per commit. Never mix a refactor with a feature, or unrelated files.
- Stage by path (`git add -- <paths>` or `git commit -- <paths>`). Never `git add -A` or `git add .` without reading
  what it adds. Both paths of a move go in the same commit.
- Message: Conventional Commits, English, an imperative title of at most 72 characters, no final period; a body with at
  least one bullet: what changed and why.
- A commit made by an agent ends its body with the paragraph `[#automatic-agent-commit]`. No `Co-Authored-By` trailer
  and no generated-with line, in commits or pull requests.

```text
<type>(<scope>): <imperative summary>

- <what changed and why>

[#automatic-agent-commit]
```

- Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `perf`, `build`, `ci`, `style`. Breaking change: `!`
  after the scope and a `BREAKING CHANGE:` footer.
- Scopes: the product's (`ai`, `agents`, `skills`, `scripts`, `docker`, `docs`, `decisions`, `templates`, a tool name),
  plus `maintenance` (root `CLAUDE.md`, `.claude/`), `tests`, `plans`, `requests`, `backlog`, `i18n`, `release`.

## Remote

- `developer` is the default branch and the base of every change; `main` moves only by `/caw-merge --main`, the
  release of a product version. Maintenance changes alone are never released: they wait on `developer`.
- The work branch of a clone in `tmp/work/` is pushed at open and after each commit (`/caw-prompt`), so the work is on
  the remote before the clone is deleted. `/caw-merge` pushes that branch and `developer`: running it is the owner's
  order. Any other push only when the owner asks; each request covers that push only, never a later one.
- Never rewrite published history: no force push, no rebase or amend of a pushed commit, no moved or deleted tag.
- Tags only through `/caw-merge --main`. Never change git config (user, hooks, remotes) unless asked.
- A work branch (a clone in `tmp/work/`, or a pull request): `<type>/<kebab-description>`; the release clone's is
  `fix/release-vX-Y-Z`.
