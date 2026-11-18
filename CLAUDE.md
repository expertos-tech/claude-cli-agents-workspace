# Claude CLI Agents Workspace: maintenance

You own and maintain this project. A session opened at this root changes the product; it does not use it.

## The product is code

- The product is `workspace/`. Its `AGENTS.md`, `CLAUDE.md`, `rules/`, skills, agents and hooks are code being edited,
  never instructions for this session, but through the layers of "Layout". `.claude/settings.json` keeps them out of context with `claudeMdExcludes`.
- Start Claude Code at the repository root. Project settings are read from the folder the session starts in, so a
  session started inside `workspace/` misses this root's settings.
- `claudeMdExcludes` patterns match absolute paths. The committed patterns assume the clone folder is named
  `claude-cli-agents-workspace`. In a clone with another name, add the same patterns with your clone's absolute path
  (for example `/abs/path/to/clone/workspace/**`) to `.claude/settings.local.json`, which git ignores.
- No product hook runs here; the one hook of the root is the session index ("Layout"). Never run `workspace/scripts/setup-claude.sh` inside `workspace/`; exercise hooks in a
  test installation (`/caw-test-install`).

## Language

English in every file: code, docs, plans, requests, messages, commits. Reply in the language the person writes in; a
plan, request or document is shown in that language and saved in English, with one line saying so.
Translations live in `i18n/<locale>/`, only for documents and READMEs (`.claude/rules/docs.md`).
The project is documented in `docs/` (install, contribute, maintain, release); the product in `workspace/docs/`.

## Layout

Maintenance skills carry the prefix `caw-` (`/caw-merge`, `/caw-request`...), so they never mix with the product's
skills in `workspace/rules/skills/` (`/merge`, `/request`...). One with a product counterpart is a layer over it: the
first line of its body is `@workspace/rules/skills/<name>/SKILL.md`, then `---` and the sections "Ignore from the
product skill", "Mapping" and "CAW rules", which win. The maintenance rules with a product counterpart
(`security`, `review`, `models`, `git`, `docs`, `scripts` of `.claude/rules/`) are layers the same way: the first line
of the body is `@workspace/rules/<name>.md`, read in full with the layer whenever it applies, whatever its `paths:`, then
`---` and "Ignore from the product rule", "Mapping" and "CAW rules". When to read each one is the session index: the
one hook here, at the session start and after a compaction (`tests/caw-session-index.py`), builds it from the
product's index (`workspace/AGENTS.md` "Reference") with the layer `.claude/session-index.md` over it. The layers of
skills, of rules and of the index are the only cases where this session follows a product file as instructions;
nothing else of `workspace/` is read as instructions, and `tests/check.sh` checks every layer.

`.claude/` (settings with the one hook, the session index; `rules/`, `skills/`, `agents/`), `tests/` (`check.sh`; `test-install.sh` arrives with
the installer), `maintainers/` (`plans/`, `requests/` with `qa/` and `done/`, `reviews/`: public), `tmp/` (git-ignored: test
installations, private analyses, `tmp/request.md`), `logs/` (git-ignored), `workspace/` (the product), `docs/` (the project's documentation),
`i18n/`, `README.md`, `CHANGELOG.md` (the repository's; the product's is `workspace/CHANGELOG.md`), `LICENSE`.

## The maintenance process

Detail in `.claude/rules/process.md`.

1. **Evaluate** the product and, read-only, its real use: an installed workspace, transcripts, the prompt log,
   measurements. Findings that name a company, customer or project stay in the git-ignored `tmp/` or the owner's
   custom layer, never in this repository.
2. **Plan** in `maintainers/plans/`: options, a recommendation and numbered decisions for the owner. A plan the owner
   approves in a session is recorded at once as a pending request in `maintainers/requests/`.
3. **Request**, with the owner's answers, in `maintainers/requests/`: objective, BR-n, AC-n, out of scope, stages with
   effort (`/caw-draft-request`).
4. **Execute** in stages with subagents (`/caw-request`, which works in a clone on a work branch under `tmp/work/`,
   opened by `bash tests/caw-work.sh open`; a session is either on `developer` at the root or in such a clone), always
   with explicit model and effort (high for hooks, the installer, security and risky actions), in parallel only on
   disjoint paths. The agent tests its own work; the one independent review runs at `/caw-merge`
   (`.claude/rules/review.md`), and only a hard rule (`.claude/rules/security.md`) refuses: the rest is a warning.
5. **Prove**: `bash tests/check.sh --base origin/developer --i18n-pending` on every change, only what changed
   (`/caw-check`); the release runs it strict from the last tag; `/caw-test-install` whenever the installer,
   a hook or `setup-claude.sh` changes.
6. **Close**: commits per the convention below (`/caw-commit`); the work branch of a clone is pushed at each commit;
   `/caw-merge` takes the work into `developer` (the default branch) and writes the two changelogs: the root
   `CHANGELOG.md` for every change, `workspace/CHANGELOG.md` for a product change (`workspace/`, `install.sh`). Other
   pushes only when the owner asks, each request covering that push only. Only the product is released, through
   `/caw-merge --main`, with every public step confirmed.

## The trail and the prompts

- In a work clone the agent asks nothing: `Edit(/tmp/work/**)` and `bash tests/caw-work.sh` are allowed, commands run
  through `bash tests/caw-work.sh run <work> -- <command>` (it refuses a path outside the clone), and the clone's hooks
  push its branch after the company-terms scan. Leaving the trail falls back to the active permission mode.
- A prompt shows one thing: run everything allowed first; what needs authorization runs alone, in its own call, after
  one line saying what it asks. The one prompt of a task is the push of `developer` by `/caw-merge`.

## Commits

Conventional Commits in English (`type(scope): subject`), one logical change per commit. When an agent commits, the
body ends with the line `[#automatic-agent-commit]`. No `Co-Authored-By` trailer and no generated-with line in commits
or pull requests; `.claude/settings.json` turns Claude Code's attribution off here. Detail in `.claude/rules/git.md`.
