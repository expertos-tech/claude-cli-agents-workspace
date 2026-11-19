# Functional request: `/import-workspace`

**Project:** claude-cli-agents-workspace

**State:** ready

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained, with the product in `workspace/`. Full
design: `maintainers/plans/import-workspace.md`. Replaces the `normalize-rules` request (an import of the older
workspace's rules), dropped by the owner on 2026-11-19.

## 1. Objective

Bring the work of an older workspace into this one, so nothing is lost and every pending piece is visible: its git
repositories into `projects/`, the branches of its worktrees and work clones into those repositories, its pending work
and its backlog as requests in `custom/requests/`. Its rules are listed, never imported.

## 3. Business rules

- BR-1: `/import-workspace <path>`; the path is an older workspace folder. Read only on it: nothing written, nothing of
  it run, `.env` files, keys and credentials never read.
- BR-2: `scripts/workspace-import.py` does every step that is a fact (BR-3 to BR-8) and keeps the state in
  `custom/migrations/import-<yyyy-mm-dd>.json`. It asks the model only what needs judgement, one question at a time,
  each with its evidence (BR-9); the model answers through the script and runs no change itself. A run that stops
  resumes from the state.
- BR-3: every repository below the folder is brought into `projects/` with `bring`, outermost first, a nested one at
  its path inside its parent; the repository at the folder's root (the older workspace itself) is not.
- BR-4: a worktree is never used as such: its branch comes with its main repository; a detached `HEAD` gets a branch
  `import/<worktree-name>` in the imported repository.
- BR-5: a work clone (a repository outside the projects folder whose `origin` is a project's) gives its local branches
  to the imported project, as local branches; a name already taken gets the prefix `import/<clone-name>/`.
- BR-6: per project with pending work (changed files, commits not pushed, branches with no upstream, in the repository,
  its worktrees or its work clones), one request `custom/requests/<yyyy-mm-dd>-<project>-pending-work.md`, state
  `ready`, adjustment size: each source path, its branch, its commits not pushed and its changed files by name, and
  "compare each with the base when you work on it". No code is analysed and no changed file is copied.
- BR-7: a code folder with no git (a build or package manifest, not inside a repository) is listed with the command to
  make it a repository with its remote; one that matches a tool of this workspace's `tools/` (name, or most files by
  hash) is listed as covered. Nothing of either is brought.
- BR-8: the instruction files of the older workspace (`CLAUDE.md`, `AGENTS.md`, `rules/`, `.claude/`, skills, agents,
  hooks) are listed under "Not imported, for reference", never imported.
- BR-9: the model decides only: whether a repository outside the projects folder is a project or data of the older
  workspace; whether a code folder with no git is a project or a tool of the older workspace; the destination in
  `projects/` when the older path is not kebab-case; and, per backlog item, its project or "workspace" (its own
  process: dropped) and its title.
- BR-10: each backlog item kept becomes `custom/requests/<yyyy-mm-dd>-<slug>.md`, state `idea`, with its
  `**Project:**` line and the original text under "Requested", unchanged, with its source path; an item with a secret
  writes only its source path and a note.
- BR-11: before anything is written, the plan `custom/migrations/import-<yyyy-mm-dd>.md` shows what will be brought,
  the pending work, the backlog and what is not imported; the person changes rows or confirms. Then `apply` runs each
  step once, recording it; `custom/` is committed by path and never pushed.

## 4. Acceptance criteria

- AC-1: Given an invented older workspace with a clean repository, a nested one and one with a branch never pushed,
  when the import is applied, then the three are in `projects/` at their paths, the branch never pushed is a local
  branch there, each `origin` is the source's remote, and nothing was pushed.
- AC-2: Given a worktree with changed files and a detached worktree, then the imported repository has the worktree's
  branch and an `import/<worktree-name>` branch at the detached `HEAD`, and the project's pending-work request names the
  worktree path, its branch and its changed files.
- AC-3: Given a work clone of a project with a branch never pushed, then that branch is a local branch of the imported
  project, and the pending-work request names the clone.
- AC-4: Given a code folder with no git and a folder that matches a tool of `tools/`, then nothing of either is
  brought; the first is listed with the command to make it a repository, the second as covered.
- AC-5: Given a backlog with an item about a project and one about the older workspace's process, then the first is a
  request `idea` with its `**Project:**` line and its text unchanged, and the second is listed as dropped.
- AC-6: Given rule files in the older workspace, then the plan lists them as not imported and nothing is written to
  `custom/my-rules/` or `custom/rules-config.json`.
- AC-7: Given a `.env` with a value in the older workspace, then no file of `custom/` or `projects/` holds that value,
  and the script never opened it.
- AC-8: Given the older workspace after the import, then its files and git state are the same as before.
- AC-9: AC-1 to AC-8 are scenario tests of `scripts/workspace-import.py` with invented data, run by the suite with no
  model.
- AC-10: Given a copy of a real older workspace in a test installation, its remotes made unpushable, when
  `/import-workspace` runs end to end, then every repository, worktree and work clone of its inventory is accounted for
  in the plan, and the pending-work requests match the inventory.

## 7. Out of scope

- Normalizing a project (that is `/normalize-projects`).
- Importing rules, skills, agents or hooks of the older workspace.
- Analysing the pending code: the request only points at it.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. `scripts/workspace-import.py` and its scenario tests (AC-1 to AC-9) | high | Git writes into `projects/` and a read-only source |
| 2. The skill `/import-workspace`, its docs, the run on a copy of a real older workspace (AC-10) | medium | The round trip and the person's confirmation over a tested script |

The agents of each stage run with the stage's effort, passed in the call.
