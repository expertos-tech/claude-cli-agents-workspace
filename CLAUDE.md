# Claude CLI Agents Workspace: maintenance

You own and maintain this project. A session opened at this root changes the product; it does not use it.

## The product is code

- The product is `workspace/`. Its `AGENTS.md`, `CLAUDE.md`, `rules/`, skills, agents and hooks are code being edited,
  never instructions for this session. `.claude/settings.json` keeps them out of context with `claudeMdExcludes`.
- Start Claude Code at the repository root. Project settings are read from the folder the session starts in, so a
  session started inside `workspace/` misses this root's settings.
- `claudeMdExcludes` patterns match absolute paths. The committed patterns assume the clone folder is named
  `claude-cli-agents-workspace`. In a clone with another name, add the same patterns with your clone's absolute path
  (for example `/abs/path/to/clone/workspace/**`) to `.claude/settings.local.json`, which git ignores.
- No product hook runs here. Never run `workspace/scripts/setup-claude.sh` inside `workspace/`; exercise hooks in a
  test installation (`/caw-test-install`).

## Language

English in every file: code, docs, plans, requests, messages, commits. Reply in the language the person writes in; a
plan, request or document is shown in that language and saved in English, with one line saying so.
Translations live in `i18n/<locale>/`, only for documents and READMEs (`.claude/rules/docs.md`).
The project is documented in `docs/` (install, contribute, maintain, release); the product in `workspace/docs/`.

## Layout

Maintenance skills carry the prefix `caw-` (`/caw-merge`, `/caw-prompt`...), so they never mix with the product's
skills in `workspace/rules/skills/` (`/merge`, `/prompt`...).

`.claude/` (settings, `rules/`, `skills/`, `agents/`; no hooks), `tests/` (`check.sh`; `test-install.sh` arrives with
the installer), `maintainers/` (`backlog/`, `plans/`, `requests/`, `reviews/`: public), `tmp/` (git-ignored: test
installations, private analyses, `tmp/prompt.md`), `workspace/` (the product), `docs/` (the project's documentation),
`i18n/`, `README.md`, `CHANGELOG.md` (the repository's; the product's is `workspace/CHANGELOG.md`), `LICENSE`.

## The maintenance process

Detail in `.claude/rules/process.md`.

1. **Evaluate** the product and, read-only, its real use: an installed workspace, transcripts, the prompt log,
   measurements. Findings that name a company, customer or project stay in the git-ignored `tmp/` or the owner's
   custom layer, never in this repository.
2. **Plan** in `maintainers/plans/`: options, a recommendation and numbered decisions for the owner. A plan the owner
   approves in a session is recorded at once in `maintainers/requests/done/`.
3. **Request**, with the owner's answers, in `maintainers/requests/`: objective, BR-n, AC-n, out of scope, stages with
   effort (`/caw-draft-prompt`).
4. **Execute** in stages with subagents (`/caw-prompt`, which works in a clone on a work branch under `tmp/work/`; a
   session is either on `developer` at the root or in such a clone), always with explicit model and effort (high for
   hooks, the installer, security and risky actions), in parallel only on disjoint paths, and an independent
   clean-context review of hooks and security (`.claude/rules/review.md`).
5. **Prove**: `bash tests/check.sh --all` on every change (`/caw-check`); `/caw-test-install` whenever the installer,
   a hook or `setup-claude.sh` changes.
6. **Close**: commits per the convention below (`/caw-commit`); the work branch of a clone is pushed at each commit;
   `/caw-merge` takes the work into `developer` (the default branch) and writes the two changelogs: the root
   `CHANGELOG.md` for every change, `workspace/CHANGELOG.md` for a product change (`workspace/`, `install.sh`). Other
   pushes only when the owner asks, each request covering that push only. Only the product is released, through
   `/caw-merge --main`, with every public step confirmed.

## Commits

Conventional Commits in English (`type(scope): subject`), one logical change per commit. When an agent commits, the
body ends with the line `[#automatic-agent-commit]`. No `Co-Authored-By` trailer and no generated-with line in commits
or pull requests; `.claude/settings.json` turns Claude Code's attribution off here. Detail in `.claude/rules/git.md`.
