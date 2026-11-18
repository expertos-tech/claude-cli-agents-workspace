# git.md

## Commits

- One logical change per commit. Never mix a refactor with a feature, or unrelated files.
- Stage by path, then commit by the same paths: `git add -- <paths>`, then `git commit -F <file> -- <paths>`; a
  commit by path alone fails for a file git does not track yet. Never `git add -A` or `git add .` without reading what
  it adds. Both paths of a move go in the same commit.
- Write the paths out in the command, never in a shell variable: the session's shell may be zsh, which passes an
  unquoted variable as one word.
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
  plus `maintenance` (root `CLAUDE.md`, `.claude/`), `tests`, `plans`, `requests`, `i18n`, `release`.

## Remote

- `developer` is the default branch and the base of every change; `main` moves only by `/caw-merge --main`, the
  release of a product version. Maintenance changes alone are never released: they wait on `developer`.
- A work clone is opened by `bash tests/caw-work.sh open <type>/<slug>`, and its git hooks push its branch after each
  commit, amend, rebase or merge, only after the company-terms scan of what leaves passes; they refuse `developer`,
  `main`, a tag and a force push. Never push a work branch by hand, and never with `--no-verify`. `/caw-merge` pushes
  `developer`: running it is the owner's order, and that push is the one prompt of a task (`ask: Bash(git push *)`).
  Any other push only when the owner asks; each request covers that push only, never a later one.
- Never rewrite published history: no force push, no rebase or amend of a pushed commit, no moved or deleted tag.
- Tags only through `/caw-merge --main`. Never change git config (user, hooks, remotes) unless asked.
- A work branch (a clone in `tmp/work/`, or a pull request): `<type>/<kebab-description>`; the release clone's is
  `fix/release-vX-Y-Z`.
