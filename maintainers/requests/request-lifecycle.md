# Functional request: the request lifecycle, the release per project, a free project layout and `caw-*` layer skills

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**State:** ready. Approved by the owner on 2026-11-17 (plan shown in pt-BR in the session, recorded here in English).

**Where it runs:** at the repository root: the product in `workspace/` and the maintenance (`.claude/`, `CLAUDE.md`,
`docs/`, `maintainers/`). It changes the mandatory core (`/merge`, `/prompt`, the hooks, the layout) with the owner's
decisions below.

## 1. Objective

Give every request one lifecycle that matches the branches: pending, on `developer` (qa), released (done). Record what
each merge did. Make the release validate everything that waits in qa against what was done, per project, with the
project's own changelog at its root. Let a project have any layout. Keep the maintenance skills as thin layers over
the product's skills instead of copies.

## 3. Business rules

- BR-1 (D-1) Lifecycle, here and in the product: pending in `maintainers/requests/` (product: `custom/requests/`),
  `qa/` once on `developer` (product: `custom/requests/qa/<project>/`), `done/` once released (product:
  `custom/requests/done/<project>/`). An approved plan is recorded as a pending request. A request never moves while
  its stages run; `/merge` moves it to `qa/`, `/merge --main` moves it to `done/` and adds "Released in vX.Y.Z".
- BR-2 (D-2) At each merge into `developer`, `/merge` appends to the request, after a `---`, one block
  `## Execution — <date>, merged into developer at <sha>`: done by stage with commits, decisions taken while running,
  deviations, the status of each acceptance criterion (proven how / pending what / failed why), checks, what is left.
  A request with no file gets one in `qa/` with a "Requested" section summarizing the owner's words. Here and in the
  product.
- BR-3 (D-3) `/merge --main` validates everything in `qa/` (the suite, the final review "what enters and what leaves"
  against each qa item, every acceptance criterion, pending ones included), gathers every finding of every item, and
  asks per finding: (1) fix now, in the release clone on `fix/release-vX-Y-Z`, or (2) create a request with the fix.
  For a BLOCKER, (1) is strongly recommended; (2) stops the release. Here and in the product.
- BR-4 (D-4) Validating on `developer` without a release is out of scope: recorded as the pending request
  `qa-validation-on-developer.md`.
- BR-5 (D-5, D-10) In the product, the release unit is the project: `/merge --main <project>` releases every
  repository of the project, nested ones included, each with its own version, dated changelog and tag. Then the
  project's root repository gets the project version: in its `CHANGELOG.md` a section with a "Components" table
  (repository, version, link) and the changes of the project as a whole (a repository added or removed, shared docs,
  compose, CI); in its `README.md` the production versions table; its own tag. The project version bumps by the
  largest bump of the release (an internal minor or a `feat` at the root: minor; fixes only: patch; a breaking change:
  major). A project of one repository: its changelog is the project's. A plain folder with no root repository: each
  repository is released, and the release says there is no project changelog.
- BR-6 (D-10) Any project layout: any folder at any depth of `projects/` may be a repository, inside another one too;
  whether the parent ignores its children is the developer's choice. A path belongs to the nearest `.git`. No tool
  refuses a layout; `guard-bash` protects the whole tree of `projects/` whatever the repository.
- BR-7 (D-6) The skills are renamed: `/prompt` → `/request`, `/draft-prompt` → `/draft-request`
  (`rules/prompt-project.md` → `rules/request-writing.md`); the default file `tmp/request.md`. Here: `/caw-request`,
  `/caw-draft-request`, `tmp/request.md`, `tmp/requests/`.
- BR-8 (D-8) Logs live in `<root>/logs/`: the prompt log in `<workspace>/logs/prompts/<project>/<year>-W<week>.md`
  (`logs/` joins the writable folders of `scripts/aiwp.sh`); its configuration `sources.json` in
  `custom/config/prompt-log/`. Here: `logs/`, git-ignored.
- BR-9 There is no backlog: an idea or a finding is a pending request in the "Adjustment" format, with the state
  `idea` (decisions open) or `ready`. `custom/backlog/`, `templates/backlog-item.md` and `maintainers/backlog/` go;
  the existing backlog items become requests. A RECOMMENDED finding at a merge into `developer` becomes a `ready`
  request.
- BR-10 `/merge --main [<project>] [instructions]`: free text after the arguments changes the default. Before acting,
  the skill states what it understood, every conflict with its concrete effect and the options, and asks. A conflict
  is anything that leaves `main` or production in a state that matches no version, or breaks a dependency between
  repositories. Here and in the product.
- BR-11 The maintenance skills with a product counterpart (`/caw-merge`, `/caw-request`, `/caw-commit`,
  `/caw-draft-request`) are layers: their frontmatter; then `@workspace/rules/skills/<skill>/SKILL.md`; then `---` and
  the mandatory sections "Ignore from the product skill", "Mapping" and "CAW rules". The layer wins on conflict.
  `tests/check.sh` fails on a layer whose `@` target does not exist or that lacks a section. `CLAUDE.md` allows a
  `caw-*` skill to take a product skill as its base.
- BR-12 The requests in `maintainers/requests/done/` not released yet move to `qa/` with their "Execution" block;
  `normalize-projects.md` (released in 0.1.0) stays in `done/`.

## 4. Acceptance criteria

- AC-1: Given a merge into `developer` from a request file, then the file is in `qa/` with an "Execution" block; with
  no file, a new `qa/` file holds "Requested" and "Execution".
- AC-2: Given `/merge --main` with a pending acceptance criterion in `qa/`, then it is listed as a finding with the
  options of BR-3, and nothing is released before the owner answers.
- AC-3: Given a project root repository with two nested repositories, then `open`, `status`, the gate, `guard-bash`,
  `setup-claude.sh` and the project state handle each repository at its depth, and a release dates each one and
  writes the root's "Components" table and production versions.
- AC-4: Given `/merge --main` with an instruction that releases part of what is on `developer`, then the conflict is
  shown before any change.
- AC-5: `/request`, `/draft-request`, `custom/requests/`, `logs/` and `tmp/request.md` work; nothing refers to the old
  names.
- AC-6: `tests/check.sh` fails on a broken `caw-*` layer; every layer passes.
- AC-7: `bash tests/check.sh --base origin/developer --i18n-pending`, the suites of every changed script and
  `/caw-test-install` pass; an independent review has no BLOCKER open.

## 7. Out of scope

- `--qa` (validation on `developer` without a release): `qa-validation-on-developer.md`.
- Migrating installed workspaces: there are none yet.
- Translations: pending until the next release.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Check `@` in skills; this record; the `--qa` request | low | Research and text |
| 2. Product: free layout (`lib/projects.sh`, `init-repo.sh`, `aiwp-cmds.sh`, `aiwp-gate.sh`, `guard-bash`, `setup-claude.sh`, project state) with tests | high | Hooks and the gate, independent review |
| 3. Product: `custom/requests/`, `logs/`, renamed skills, `session-title.py`, `prompt-log.py`, `measure.py`, `aiwp.sh` writable list, with tests | high | Hooks and permissions |
| 4. Product: `/request`, `/merge` (qa, execution, release per project, root changelog, instructions), `/normalize-projects`, rules, templates, docs | high | Mandatory core |
| 5. Maintenance: `caw-*` layers and their check, `qa/`, backlog to requests, `done/` to `qa/`, `logs/`, rules, `docs/` | medium | Text over decided behavior |
| 6. Suite, test installation, independent review, commits, `/caw-merge` | high | Proof of a core change |

Stages 2 and 3 run in parallel (disjoint paths); 4 needs both; 5 needs 4.
