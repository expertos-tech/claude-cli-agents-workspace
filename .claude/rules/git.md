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
- Waves: replaced by the stages and the closing board of `process.md` steps 4 and 6; its warnings board (step 2 and
  the board) holds here, through `process.md` step 6.
- Commits: the hooks that refuse a secret (no product hook runs here); the workspace, custom layer and project scopes
  (CAW rules).
- Return points: the checkpoint tags of a normalization, and "Deleting a whole project, POC or tool".

## Mapping

| Product | Here |
| --- | --- |
| the human | the owner |
| `bash scripts/aiwp-cmds.sh open <work> <repo> [--branch <type>/<slug>]` | `bash tests/caw-work.sh open <type>/<slug>` |
| `bash scripts/aiwp-cmds.sh run`, `status`, `close` | `bash tests/caw-work.sh run`, `status`, `close` |
| `bash scripts/aiwp-cmds.sh open ... --request <file>`, the move to `custom/requests/doing/` after the clones open, committed by path in `custom/` | `bash tests/caw-work.sh start <name>` at the root before the clone opens (the start commit, "Remote"), then `bash tests/caw-work.sh open <type>/<slug> --request <name>` |
| `open --resume`, `close <work> --discard`, `close <work> --discard --start-over` | the same options of `bash tests/caw-work.sh`; `--discard` puts the request back by the reverse commit ("Remote") |
| `custom/requests/doing/` | `maintainers/requests/doing/`, with the Status `doing` of its row in `maintainers/requests/README.md` |
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
- The one exception to `developer` moving only by `/caw-merge`: the start commit of a request,
  `chore(requests): start <name>` (`bash tests/caw-work.sh start <name>`), and its reverse,
  `chore(requests): put back <name>` (`bash tests/caw-work.sh close <work> --discard`). The script makes and pushes
  them with no suite, review or terms scan and no prompt, because they add nothing new, and only within its checks:
  the root on `developer`, with nothing uncommitted, equal to `origin/developer` after a fetch; the request file
  already on `origin/developer`; one commit that is a pure rename of it between `maintainers/requests/` and
  `maintainers/requests/doing/` plus the Status cell of its README row; a plain fast-forward push (the remote moved
  meanwhile: fetched and made again once). Anything else is refused with the reason and nothing is pushed. Never by
  hand.
- Never rewrite published history: no force push, no rebase or amend of a pushed commit, no moved or deleted tag.
- Tags only through `/caw-merge --main`.
