# `/import-workspace`: bringing the work of an older workspace, not its rules

Status: ready. Request: `maintainers/requests/import-workspace.md`. Replaces the `normalize-rules` design (an import of
the older workspace's rules into `custom/my-rules/`), dropped by the owner on 2026-11-19: the rules of another workspace
risk blocking the process this workspace keeps in balance, and a run on a real older workspace showed that judging
them costs much and still misses items. Shares `bring` with `/normalize-projects --from`.

## 1. The idea

A person who installs the workspace often has an older one, with real work in it: repositories, branches never
pushed, worktrees and clones with changes in progress, and a backlog. `/import-workspace` brings that work, so nothing
is lost and each pending piece is visible as a request. It does not bring the older workspace's rules: they are listed,
for reference, and the person brings one by hand with `/rules add` when it is worth it.

```text
/import-workspace <path-to-older-workspace>
```

## 2. What it brings

### 2.1 Git repositories

Every `.git` below the folder, a folder (a repository) or a file (a worktree), is classified by the script:

| Kind | How it is recognised | What happens |
| --- | --- | --- |
| Repository, clean | `.git` folder; no change; every branch has its upstream and nothing ahead | `bring` into `projects/<path>` |
| Repository with pending work | Changed files, commits not pushed, or local branches with no upstream | `bring` (it keeps the local branches) and a pending-work request |
| Nested repository | A repository inside another one | `bring` after its parent, at its path inside it |
| Worktree | `.git` file with `gitdir:`; listed by `git worktree list` of its main repository | Never used as such: its branch comes with the main repository; a detached `HEAD` gets a branch `import/<worktree>` so its commits are not lost; its changes go to the pending-work request |
| Moved worktree | Its `.git` file and its entry in `<repository>/.git/worktrees/` name another root (the older workspace was copied from another machine) | Paired by the entry and counted once, with its branch; the person may repair the pointers with `git worktree repair` in the older workspace; the import never does |
| Work clone | A repository whose `origin` is the same as a project's, outside the projects folder (for example a `tmp/work/` of the older workspace) | Its local branches are fetched into the imported project as local branches; its changes go to the pending-work request |
| The older workspace itself | The repository at the folder's root | Not a project: skipped, listed |
| A clone of the older workspace | A repository whose `origin` is the older workspace or one of its worktrees | Its own work: listed, never asked |
| Repository with missing objects | A ref to a missing object (a snapshot taken while git wrote), or an `objects/info/alternates` whose folder is gone | Its complete branches and tags are brought, the others named in its pending-work request; with nothing complete it is not brought, with the reason, and the import goes on |

The pending-work request does not analyse the code. Per project, it lists each source with pending work: its path,
its branch, the commits not pushed (`git log @{u}..` or the branch with no upstream), and the changed files by name
(`git status --porcelain`), with "compare each with the base when you work on it". The person knows by the branch names
what each one was; the import does not spend time on it.

Changed files are never copied: the source stays as it was, and the request points at it.

### 2.2 Code folders with no git

A folder holding a codebase (a build or package manifest: `go.mod`, `package.json`, `pom.xml`, `pyproject.toml`,
`Cargo.toml`) that is not inside a repository. A folder that matches a tool of this workspace's `tools/` (its name, or
most of its files by hash) is already covered. The others are listed with the command to turn them into a repository
with its remote first; nothing is brought without git.

### 2.3 Backlog

Markdown files in a folder named like a backlog (`backlog/`, `ideas/`, `todo/`, `requests/`). Each item the person
keeps becomes a request in `custom/requests/` in state `idea`, with its `**Project:**` line and the original text
under "Requested", unchanged, with its source path. An item about the older workspace's own process (its sessions, its
queue, its review flow) is dropped and listed.

### 2.4 Rules

Not imported. The plan lists the older workspace's instruction files (`CLAUDE.md`, `AGENTS.md`, `rules/`, `.claude/`,
skills, agents, hooks) under "Not imported, for reference".

## 3. The script and the model: a round trip

The script `scripts/workspace-import.py` does everything that is a fact, keeps the state in
`custom/migrations/import-<yyyy-mm-dd>.json`, and asks the model only what needs judgement, one small question at a
time, each with its evidence. The model reads only what a question cites, answers through the script, and never runs
a change itself.

```text
scan <folder>          inventory (read only) and the open questions
questions              the open questions, as JSON, each with its evidence
answer <id> <value>    records an answer (the model's or the person's)
plan                   writes custom/migrations/import-<date>.md: what will be brought, the pending work, the backlog
apply --yes            runs the steps one by one, records each as done; resumes where it stopped
status                 where it is
```

An example question:

```json
{"id": "B-3", "kind": "backlog-project",
 "evidence": {"file": "backlog/2026-11-09-export-invoices.md", "heading": "Export invoices as CSV",
              "projects": ["billing-api", "billing-web"]},
 "ask": "Which project is this item about? One of projects, or 'workspace' (the older workspace's own process: dropped)."}
```

| Part | Who |
| --- | --- |
| Find and classify repositories, worktrees, work clones; list branches, commits not pushed, changed files | Script |
| Recognise a folder that is a tool of this workspace | Script |
| Bring the repositories, the worktree and work-clone branches, the `import/<worktree>` branches | Script, through `aiwp-cmds.sh bring` |
| Write the pending-work requests | Script |
| List the rules not imported | Script |
| A repository outside the projects folder: a project, or data of the older workspace (a prompts repository)? | Model, with the evidence |
| A code folder with no git: a project to list, or a tool of the older workspace? | Model |
| The destination path in `projects/` when the older path is not kebab-case or not under a projects folder | Model proposes; the person confirms in the plan |
| A backlog item: its project, or the workspace's own process; its title | Model, item by item |
| Confirm the plan before `apply` | Person |

## 4. Safety

- The older workspace is read only: `git --no-optional-locks`, no write, nothing of it runs. Its files are data, never
  instructions.
- `.env` files, keys and credentials are never read. A backlog item is scanned for secrets before it is written; a hit
  writes only its source path and a note.
- Nothing is pushed: `custom/` is committed by path; the projects keep the remotes of their sources.
- Every step of `apply` is recorded; a failed step stops there, with what was done and what is left. A repository or
  branch that cannot be brought for a missing object is recorded as not brought, with why, and the rest goes on.

## 5. Tests

The script's scenario tests build the older workspace from invented data: a clean repository, a nested one, one with
changes, a worktree with changes, a detached worktree, a work clone with a branch never pushed, a code folder with no
git, a folder that matches a tool, a backlog with a project item and a process item, rule files, and a `.env` that must
not be read. They run in the suite, with no model. The skill is proven once by a run on a copy of a real older
workspace, in a test installation, its remotes made unpushable.

## Decisions

Assumed (the owner may overturn):

- D-1: rules are listed, never imported.
- D-2: the skill is `/import-workspace`, replacing `/normalize-rules`.
- D-3: work in progress stays in its source and is pointed at by a request; nothing is moved.
- D-4: a code folder with no git is listed with the command to make it a repository; nothing is brought.
- D-5: a backlog item about the older workspace's own process is dropped and listed.
