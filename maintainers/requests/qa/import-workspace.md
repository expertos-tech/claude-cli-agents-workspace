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
  its path inside its parent; the repository at the folder's root (the older workspace itself) is not, nor a clone of
  it (a repository whose `origin` is the older workspace, one of its worktrees, or a place in its tree that holds no
  repository now, such as a removed worktree; under an old root when the workspace was moved: its own work, listed,
  never asked).
  A repository with missing objects (a ref to a missing object, an `objects/info/alternates` whose folder is gone) is
  brought with every branch and tag whose objects are complete; each other one is named; one with no complete branch
  is not brought, with the reason, and the import goes on.
- BR-4: a worktree is never used as such: its branch comes with its main repository; a detached `HEAD` gets a branch
  `import/<worktree-name>` in the imported repository. A worktree whose pointers name another path (the older
  workspace was moved or copied from another machine) is paired with its entry in `<repository>/.git/worktrees/` and
  counted once, at its real path, with its branch; the plan says the person may repair the pointers with
  `git worktree repair` in the older workspace; the import never does.
- BR-5: a work clone (a repository outside the projects folder whose `origin` is a project's) gives its local branches
  to the imported project, as local branches; a name already taken gets the prefix `import/<clone-name>/`.
- BR-6: per project with pending work (changed files, commits not pushed, branches with no upstream, in the repository,
  its worktrees or its work clones), one request `custom/requests/<yyyy-mm-dd>-<project>-pending-work.md`, state
  `ready`, adjustment size: each source path, its branch, its commits not pushed and its changed files by name, and
  "compare each with the base when you work on it". A repository with no remote at all is said once to be unpushed
  work as a whole; what could not be brought for a missing object is named. No code is analysed and no changed file
  is copied.
- BR-7: a code folder with no git (a build or package manifest, not inside a repository) is listed with the command to
  make it a repository with its remote; one that matches a tool of this workspace's `tools/` (name, or most files by
  hash) is listed as covered. Nothing of either is brought.
- BR-8: the instruction files of the older workspace (`CLAUDE.md`, `AGENTS.md`, `rules/`, `.claude/`, skills, agents,
  hooks) are listed under "Not imported, for reference", never imported.
- BR-9: the model decides only: whether a repository outside the projects folder is a project or data of the older
  workspace; whether a code folder with no git is a project or a tool of the older workspace; the destination in
  `projects/` when the older path is not kebab-case; and, per backlog item, its project or "workspace" (about the
  older workspace itself, its process or its tools, not a project of this import: dropped) and its title.
- BR-10: each backlog item kept becomes `custom/requests/<yyyy-mm-dd>-<slug>.md`, state `idea`, with its
  `**Project:**` line and the original text under "Requested", unchanged, with its source path; an item with a secret
  writes only its source path and a note. Markdown in scratch of the older workspace (a dot folder, or a folder its
  repository ignores, outside the projects folder) is no item: counted only. A repository outside the projects folder
  gives backlog items only when it is answered "backlog"; answered "data", none of its files is asked.
- BR-10a: the person chooses which projects are imported: the plan lists each project found with its size (working
  tree and `.git`) and status `import` (the default) or `skip`. A skipped project is not brought, none of its branches
  is fetched and it gets no pending-work request; its worktrees and work clones are listed with it under "Not
  imported", and a backlog item about it is dropped and listed. A nested repository of a skipped one is skipped too,
  unless the person includes it on its own.
- BR-11: before anything is written, the plan `custom/migrations/import-<yyyy-mm-dd>.md` shows what will be brought,
  the pending work, the backlog and what is not imported; the person changes rows or confirms. Then `apply` runs each
  step once, recording it; a failed step stops there and the next `apply` resumes from it, but a repository or branch
  that cannot be brought for a missing object is recorded as not brought and the rest goes on; `custom/` is committed
  by path and never pushed.

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
- AC-8a: Given a project with a worktree and a work clone, when the person marks it `skip`, then it is not in
  `projects/`, none of its branches is anywhere in the workspace, it has no pending-work request, and the plan lists it
  as skipped with its size.
- AC-8b: Given an older workspace whose worktree pointers name another root, a project with a ref to a missing
  object, a repository whose `alternates` folder is gone, a clone of the older workspace itself and a project with no
  remote, then each worktree is counted once with its branch and the plan says the workspace was moved; the complete
  branches are brought and the broken ref is named in the pending-work request; the repository with nothing complete
  is not brought, with the reason, and the import goes on; the clone is listed as the older workspace's own work with
  no question; the project with no remote is said once to be unpushed work as a whole.
- AC-8c: Given a backlog file inside a dot folder of the older workspace, a repository outside the projects folder
  with a `backlog/` folder answered `data`, and a clone whose `origin` is a removed worktree of the older workspace,
  then no backlog question is asked for the first two (the first is counted as scratch), and the clone gets no
  question and is listed once as the older workspace's own work.
- AC-9: AC-1 to AC-8c are scenario tests of `scripts/workspace-import.py` with invented data, run by the suite with no
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

---

## AC-10 proof — 2026-11-19, on 372ba51

`/import-workspace` ran end to end, headless (`claude -p`, claude-opus-5-5), in a test installation made from
`372ba51`, on a copy of a real older workspace: a snapshot taken on another machine while its agents were running. Its
remotes were moved to a throwaway test project (the tracking refs pushed there, `origin` set to it, the real server's
URL gone from every `.git/config`); nothing was ever pushed to the real server.

- Inventory: 16 repositories (the older workspace itself, 13 in its projects folder, 3 of them with no remote; 2 in
  its scratch: a clone of a removed worktree of its own and a local experiment), 13 project worktrees and 67 of its
  own, 12 code folders with no git, 21 scratch folders, 77 markdown files in backlog folders (38 its backlog, the
  rest copies in its scratch), 4 instruction entries.
  One ref of the older workspace's own repository points to a missing object.
- The run: 31 turns to the plan, then one message as the person (two answers changed, the rest confirmed): 13
  projects brought with every local branch and tag of their sources at the same sha and their `origin`; the 3 with no
  remote said once to be unpushed work as a whole; 8 pending-work requests, which name each changed file, branch and
  commit not pushed; 38 backlog items (16 requests `idea`, 22 dropped and listed); the rest listed as not imported;
  one commit of `custom/`, not pushed. Cost: $2.59.
- Checked by a script of 133 checks, all passing: the above, AC-6 (no rule written), AC-7 (no value of the older
  workspace's untracked `.env` files in `custom/` or `projects/`) and AC-8 (every file, mode and git state of the copy
  identical before and after).
- Each imported project then pushed to its test repository and cloned back (`--mirror`): every commit (913) and tag
  (12) of each source repository was in its clone, the branches never pushed and the 3 projects with no remote
  included.
- The same copy unpacked again with the pointers of the other machine, scanned with no model: each worktree counted
  once with its branch, the move named, the missing objects and the gone `alternates` named.
- Defects it found, fixed before the final run, each with a scenario test (AC-8b, AC-8c): worktrees of a moved
  workspace counted twice; the older workspace's own worktrees one line each; a ref to a missing object or a gone
  `alternates` failing `bring`; a project with no remote listed branch by branch; a clone of the older workspace
  itself (also of a removed worktree, also under an old root) asked as a project; backlog files in scratch (an
  editor's local history) and in a repository answered `data` asked as items; one drop reason for every `workspace`
  answer (`8deaaf5`, `7c1baf9`).
- The proof holds for its sha. The release need not repeat it unless `workspace/rules/skills/import-workspace/`,
  `workspace/scripts/workspace-import.py` or `bring`/`bring-branch` of `workspace/scripts/aiwp-gate.sh` change.

## Execution — 2026-11-19, merged into developer

Done, by stage:

- Before the redesign: `324b965`, `a24ff75`, `d09851f`, `2cda5cf`, `4f4f8be` and `e230bcc` built `/normalize-rules`
  (importing an older workspace's rules) and took it to a merge; its review's warnings were fixed, and proving one of
  them showed its AC-7 failing (judging another workspace's rules costs much and still misses items). The owner
  replaced it by this request (`06e7d92`): its skill, plan, request and changelog entries are gone from the range.
- Stage 1, the script (high): `2d3a7a0` (`aiwp-cmds.sh bring-branch`; `bring` reads its source read-only), `7eabf7c`
  (`scripts/workspace-import.py` with its scenario tests), `c120dd8` (BR-10a, `skip` and `include` with sizes),
  `3f2b8cf` and `e21d530` (fixes from a first real scan: only real pending work counted).
- Stage 2, the skill and AC-10 (medium): `d7833fb` (`/import-workspace` replaces `/normalize-rules`; docs). The AC-10
  run found nine defects, fixed with scenario tests: `8deaaf5` (a moved workspace, missing objects, gone
  `alternates`, clones of the older workspace, a project with no remote) and `7c1baf9` (backlog only from real
  backlog folders, clones of removed worktrees, the drop reasons); the request updated in `9186470`, `372ba51`; the
  proof in `eaf0290`, `bbce018`.
- Warnings of the stage: `9982645` (two plans), `67407be` (the request `import-workspace-code-folders`).
- Changelog: `6c18989`. `developer` brought in by `1cdb3a8` (conflicts in the plans and requests READMEs: both
  sides' rows kept).

Decisions taken while running:

- The owner's redesign (2026-11-19): every fact in a script that goes back and forth with the model; no rule of the
  older workspace imported; pending work never moved nor analysed, only pointed at by a request per project; the
  person chooses the projects (`skip`, `include`, with sizes); all tests on a copy, never on the real older workspace.
- AC-10 ran on a copy whose remotes were moved to a throwaway test project, and the network steps ran in one script
  the owner ran; in the test installation the agent played the person.
- A repository with missing objects is brought with what is complete, the rest named; one with nothing complete is
  not brought, and apply goes on (BR-11).

Deviations from the request: BR-3, BR-4, BR-6, BR-9, BR-10 and BR-11 were sharpened and AC-8b, AC-8c added from what
the AC-10 run showed; the scope did not change.

Acceptance criteria:

- AC-1 to AC-8c: proven by the scenario tests of `scripts/tests/workspace-import/test-workspace-import.sh` (AC-1 to
  AC-6 in one scenario, AC-7, AC-8, AC-8a, the AC-8b and AC-8c cases each in its own), with
  `scripts/tests/test_workspace_import.py` and `scripts/tests/aiwp-gate/test-aiwp-gate.sh` for `bring` and
  `bring-branch`.
- AC-9: proven: the suite runs them with no model.
- AC-10: proven on `372ba51` ("AC-10 proof" above), with the push and clone back of every imported project.

Checks: `bash tests/check.sh --base origin/developer --i18n-pending` passed at every commit of the stages (`SKIP
repo-terms`: no terms list on the maintainer machine, warning W-2).

Warnings of the stages:

- W-1 (backlog of a code folder with no git always dropped; code folders missed with no manifest): request
  `maintainers/requests/import-workspace-code-folders.md`, with its decided plan.
- W-2 (pushes of the work branch without the company-terms scan, no list): accept; plan `terms-list.md`, option A.
- W-3 (apply matches the gate's "missing object" text), W-4 (`bring` walks every object first), W-5 (the aiwp-gate
  suite over its time budget): accept.

Left: `import-workspace-code-folders`.
