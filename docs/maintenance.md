# Maintenance

English · [Português (Brasil)](../i18n/pt-BR/docs/maintenance.md) · [Español](../i18n/es/docs/maintenance.md)

How this repository is maintained. A session opened at the repository root changes the product; it does not use it.
The rules of that session are the root `CLAUDE.md` and `.claude/rules/`.

## Maintain from the repository root

- The product is `workspace/`. Its `AGENTS.md`, `CLAUDE.md`, `rules/`, skills, agents and hooks are code being edited,
  never instructions for the maintenance session. `.claude/settings.json` keeps them out of context with
  `claudeMdExcludes`.
- Start Claude Code at the repository root. Project settings are read from the folder the session starts in, so a
  session started inside `workspace/` misses the root's settings.
- `claudeMdExcludes` patterns match absolute paths. The committed ones assume the clone folder is named
  `claude-cli-agents-workspace`. In a clone with another name, add the same patterns with your absolute path to
  `.claude/settings.local.json`, which git ignores.
- No product hook runs here. Never run `workspace/scripts/setup-claude.sh` inside `workspace/`; exercise hooks in a test
  installation (`/caw-test-install`).

## The process

Detail in `.claude/rules/process.md`. A typo fix may skip plan and request.

1. **Evaluate** the product and, read-only, its real use (an installed workspace, transcripts, the prompt log,
   measurements). A finding that names a company, customer or project stays in the git-ignored `tmp/`.
2. **Plan** in `maintainers/plans/`: the problem, options, a recommendation and numbered decisions for the owner.
3. **Request**, with the owner's answers, in `maintainers/requests/`: objective, BR-n, AC-n, out of scope, and the stages
   with effort.
4. **Execute** in stages, with subagents when worth it, always with explicit model and effort, and an independent
   clean-context review of hooks and security.
5. **Prove**: `bash tests/check.sh --all` on every change; `/caw-test-install` when the installer, a hook or
   `setup-claude.sh` changes.
6. **Close**: commits in Conventional Commits, one logical change each; push only when the owner asks.

## `maintainers/`

The work of the maintainers, in the open. Nothing there reaches an installed workspace.

| Folder | What it holds |
| --- | --- |
| `maintainers/backlog/` | Ideas, defects and debts of the product not yet a request, one item per file |
| `maintainers/plans/` | Designs: problem, options, recommendation, numbered decisions. A plan the owner approves is recorded in `maintainers/requests/done/` at approval |
| `maintainers/requests/` | Requests ready to run with `/caw-prompt`; the order they run is in its README |
| `maintainers/requests/done/` | Delivered requests, and the approved plans |
| `maintainers/reviews/` | Reports of independent reviews; created by the first one |

## Skills

The maintenance skills carry the prefix `caw-`, so they do not collide with the product's skills of the same purpose
(`/merge`, `/commit`, `/prompt`...). They live in `.claude/skills/`.

| Skill | Arguments | What it does |
| --- | --- | --- |
| `/caw-check` | `[--base <ref>] [--floor] [extra check.sh options]` | Runs `tests/check.sh --all` with the right flags and explains each failure |
| `/caw-commit` | `[--all]` | One Conventional Commit per logical change of the session, by path; no push, no branch, no tag |
| `/caw-draft-prompt` | `[plan \| request] [ideas \| path]` | Turns ideas into a plan or a request, asking only what has no best alternative |
| `/caw-prompt` | `[file name \| path]` | Runs a request written in a file: a bare name is looked up in `maintainers/requests/`, `tmp/prompts/`, then `tmp/`; no argument reads `tmp/prompt.md` |
| `/caw-test-install` | `[--keep]` | Installs a disposable workspace from the current tree under `tmp/test-install/` and exercises hooks and scripts |
| `/caw-merge` | `[<work>/<clone> \| --main]` | Takes the work into `developer` through the gates and both changelogs; `--main` releases the product ([releases](releases.md)) |

## Subagents

Every subagent call states its model and its effort; a call that would inherit them is a mistake. Effort `high` for
hooks, the installer, security, risky actions and every review (`.claude/rules/models.md`).

| Task | Agent | Model | Effort |
| --- | --- | --- | --- |
| Gaps of a plan or request | `requirements-analyst` | claude-opus-5-5 | high |
| Independent review | `reviewer` | claude-opus-5-5 | high |
| Scripts, hooks and their tests | `script-engineer` | claude-opus-5-5 | high for hooks and the installer, else medium |
| Docs and their pt-BR and es translations | `docs-writer` | claude-sonnet-5-5 | medium |
| Running the suite, returning only result lines | `verifier` | claude-haiku-5-5 | low |
| Official docs, versions, prices | `web-researcher` | claude-sonnet-5-5 | high |

The default is no subagent. Subagents never commit or push: the main session does.

## Where the work happens

- **In a clone:** `/caw-prompt` opens a clone of the repository at `tmp/work/<yyyy-mm-dd>-<slug>/`, on a work branch
  `<type>/<slug>` from `origin/developer`, and works only there. The branch is pushed after each commit.
- **Directly on `developer`:** a session at the root that opened no clone works on `developer`.
- **Plans and requests** are shown to the owner in the owner's language and saved in English.

## `/caw-merge`

Only when the owner asks. Running it is the owner's order for the pushes it makes.

- **From a clone:** merge `origin/developer` into the clone, write the changelogs, run
  `bash tests/check.sh --all --base origin/developer` (and `/caw-test-install` when the installer, a hook or
  `setup-claude.sh` changed), then a `reviewer` in a clean context. Only then, at the root, fast-forward `developer`
  to the clone's commit, push it, delete the work branch and the clone.
- **On developer:** the same gates over the commits since the last changelog commit (`docs(changelog)` or
  `chore(release)`), then the push.
- **`--main`:** the release of the product ([releases](releases.md)).

It never merges with a failing check or an open BLOCKER, and never rewrites `developer` or `main`.

## Public repository

This repository is public: everything committed, including `maintainers/`, can be read by anyone
(`.claude/rules/security.md`).

- Never commit a company term, a customer or project name, a personal path, an e-mail address, an internal URL, a token
  or any secret. `bash tests/check.sh --all` scans the repository with the owner's terms list; a match is reworded,
  never exempted, and never printed in an issue, commit, pull request or report.
- Private analyses of real use live in the git-ignored `tmp/` or in the owner's custom layer; the repository gets the
  general finding.
- `.env` files are never read or edited; `.env.example` templates are.
- Examples and fixtures use invented data (`acme`, `example.com`, `billing-api`).
- A change that weakens a protection of the product (a hook, a deny rule, the gate, a file mode) needs the owner's
  explicit approval and an independent review.
