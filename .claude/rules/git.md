@workspace/rules/git.md

The sections below win where they differ; its `paths:` do not limit it here.

---

## Ignore from the product rule

- Repos, its first bullet (`custom/`, `projects/`, the installation with no `.git`): the repos here are this
  repository at the root, on `developer`, and its clones in `tmp/work/`.
- Authorization: the bullets of `projects/` and of the custom layer; the clone bullet's amend, rebase and reset of a
  pushed commit (CAW rules); the tags it lists, but the release tag.
- Work area: `projects/<repo>` on its base, the `.env` files `open` copies, and the normalization.
- Gate: all of it but "Never merge with a BLOCKER open or a failing check" and the blocked repo, which hold for
  `developer` and `main` here: the gate is `/caw-merge` (`.claude/skills/caw-merge/SKILL.md`), never a script run by
  hand.
- Waves: replaced by the stages and the closing board of `process.md` steps 4 and 6.
- Commits: the hooks that refuse a secret (no product hook runs here); the workspace, custom layer and project scopes
  (CAW rules).
- Return points: the checkpoint tags of a normalization, and "Deleting a whole project, POC or tool".

## Mapping

| Product | Here |
| --- | --- |
| the human | the owner |
| `bash scripts/aiwp-cmds.sh open <work> <repo> [--branch <type>/<slug>]` | `bash tests/caw-work.sh open <type>/<slug>` |
| `bash scripts/aiwp-cmds.sh run`, `status`, `close` | `bash tests/caw-work.sh run`, `status`, `close` |
| the secret scan of the commits that leave | the company-terms scan of what leaves (`security.md`) |
| `/merge`, `/merge --main`, `/merge --hotfix` | `/caw-merge`, `/caw-merge --main`, `/caw-merge --hotfix` |
| `custom/requests/`, `qa/<project>/`, `done/<project>/` | `maintainers/requests/`, `qa/`, `done/` (`process.md` step 6) |
| `/docker-deploy` | `/caw-docker-deploy` |

## CAW rules

### Commits

- Both paths of a move go in the same commit.
- No generated-with line either, in commits or pull requests.
- Types: the product's, plus `style`.
- Scopes: the product's (`ai`, `agents`, `skills`, `scripts`, `docker`, `docs`, `decisions`, `templates`, a tool
  name), plus `maintenance` (root `CLAUDE.md`, `.claude/`), `tests`, `plans`, `requests`, `i18n`, `release`.

### Remote

- `developer` is the default branch and the base of every change; `main` moves only by `/caw-merge --main`, the
  release of a product version. Maintenance changes alone are never released: they wait on `developer`.
- A work clone's git hooks push its branch after each commit, amend, rebase or merge, only after the company-terms
  scan of what leaves passes; they refuse `developer`, `main`, a tag and a force push.
- `/caw-merge` pushes `developer`: running it is the owner's order, and that push is the one prompt of a task
  (`ask: Bash(git push *)`). Any other push only when the owner asks; each request covers that push only, never a
  later one.
- Never rewrite published history: no force push, no rebase or amend of a pushed commit, no moved or deleted tag.
- Tags only through `/caw-merge --main`.
