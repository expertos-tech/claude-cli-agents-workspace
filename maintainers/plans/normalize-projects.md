# `/normalize-projects`: projects marked with the workspace version

Status: approved design, built in the 0.1.0 publication. Request: `maintainers/requests/normalize-projects.md`.

## 1. The idea

- `/migrate-project` leaves and `/normalize-projects` comes in.
- Each project is analysed in depth before anything changes: what goes to the custom layer, what stays in the
  project, and what must change in the project. Nothing is decided by a fixed list of file names.
- The README of each project and POC gets a marker with the workspace version it was last normalized with:
  `<!-- AI-WORKSPACE-PROJECT 0.1.0 -->`.
- When a session works with a project, the first step is reading the marker:
  - **No marker:** the project is not a workspace project and needs normalizing.
  - **Older marker with pending migrations:** it needs updating. The warning and the authorization question repeat at
    every interaction until the normalization happens.
  - **Up to date:** work goes on as usual.

It solves three problems:

1. There is no way to know whether a project already follows the workspace standard.
2. A project can bring its own `CLAUDE.md` or skills that compete with the workspace rules.
3. When the workspace changes what it asks of projects, nothing warns the ones left behind.

It is also how existing work enters a fresh installation: projects moved by hand into `projects/` and POCs moved
into `custom/pocs/` have no marker, so they are treated as not normalized and go through the same analysis and
migration. The installation never converts an older workspace; it is always fresh.

It also brings each project in `projects/` to the `developer` branch, one project at a time, with the person's
authorization.

## 2. What changes compared with `/migrate-project`

| | `/migrate-project` | `/normalize-projects` |
| --- | --- | --- |
| Goal | Copy an outside project and write a plan to rewrite it to the standard | Make the workspace rules apply in the project, without rewriting code |
| Writing | Directly in `projects/`, on a branch outside `developer` | In a clone in `tmp/work/`, on `feat/ai-workspace-migration`, tested, then through the gate into `developer` and released to `main` |
| Reach | One project coming from outside | Every project and POC, including those already inside |
| After | A rewrite plan | A marker the workspace reads at every interaction |

Bringing the code to the standard (architecture, tests, coverage) is no longer the skill's job: it becomes an ordinary
request, when the person wants it. Normalizing is structural and cheap; rewriting is a product decision.

## 3. The workspace version

- `VERSION` at the root of the product, in semver, is the single source of the number.
- The version goes up at each GitHub release, with a `vX.Y.Z` tag (Conventional Commits decide: `feat` raises the
  minor, `fix` the patch, `!` the major).
- The number in the marker is the one in `VERSION`.

**Not every version asks something of the projects.** If the warning showed at every patch of the workspace, it would
become noise and people would learn to ignore it. So:

- The changes that ask something of the projects live in a `migrations/` folder of the product, one per version:
  `migrations/0.4.0.md` describes what to do in a project marked with an earlier version.
- **A project is out of date only when a migration newer than its marker exists.** A project marked 0.1.0, in a
  workspace 0.3.0 whose last migration is 0.1.0, is up to date.
- On normalizing, the marker gets the current version, and the migrations between the old marker and the current
  version run in order.

The marker still says "the last workspace version" of the project, and the warning shows only when there is real work.

## 4. The marker

```markdown
<!-- AI-WORKSPACE-PROJECT 0.1.0 -->
# Project name
```

- It sits on the first line of the `README.md` at the root of the repository. It is an HTML comment, which git servers
  do not render.
- A repository without a README gets one, with the name and a "How to test" section.
- POC: the same marker in the README of the POC folder, `custom/pocs/<poc>/`. The POC lives inside the custom
  repository, so the marker goes in the folder, not at the repository root.
- The format is fixed and read by a script with `^<!-- AI-WORKSPACE-PROJECT ([0-9]+\.[0-9]+\.[0-9]+) -->$`. Nobody has
  to interpret free text.
- The marker that counts is the one on `developer`, the state of `projects/<repo>`. A clone in `tmp/work/` may be
  ahead, but it counts only after passing the gate.

## 5. Stage 1: the analysis

Before anything changes, the skill analyses the whole repository. It does not look for a fixed list of file or folder
names: every tool has its own conventions, they change, and a list always misses something. The analysts read the
repository and judge each piece by what it does.

**How:** parallel subagents, each with `model: opus` and `effort: high` passed in the call, reading the project's
`developer` in a fresh clone (read-only for them). Each one owns one question:

| Analyst | Question |
| --- | --- |
| Instructions | What in this repository tells an AI tool, or a person, how to work here (any instruction file, prompt, rule, skill, agent, editor or assistant configuration, process doc)? For each piece: is it still true, does it compete with the workspace rules, and who else uses it (a team on other tools)? |
| Company and environment | What is specific to the company or the machine rather than to the code: tenant, subscription, internal URLs, people, customer names, deployment environments, secrets or secret-shaped values? |
| Build and test | How is the project built, run and tested today, really (scripts, CI, compose, README)? What does it need (runtimes, `.env`, services)? Is there a test suite and does it pass? |
| Conformity | What in the repository falls short of the workspace's project contract (README with "How to test", `developer` branch, git-ignored `.env`, tests, the language of code, layout)? |

The consolidation turns the four reports into a **migration plan**, one line per finding, each with a destination:

| Destination | What goes there | Example |
| --- | --- | --- |
| **Custom layer** | Company- or environment-specific knowledge the sessions need when working on this project | The tenant and resource names from an old `CLAUDE.md` become a custom rule scoped to the project's paths (`paths:` with `projects/<repo>/**` and `tmp/work/*-<repo>*/**`) |
| **Stays in the project** | Real project knowledge useful to anyone, with or without AI | Architecture notes, conventions, run instructions: kept or moved into the project's `docs/` or README, rewritten as documentation |
| **Changes in the project** | What the workspace contract requires, without rewriting code | Marker, "How to test", `.gitignore` for `.env`, removal of instruction files that now live elsewhere |
| **Gap, reported only** | Missing unit tests, low coverage, off-standard code or architecture, outdated dependencies | Listed in the migration report at the project root; the skill creates nothing. The workspace's own quality gates take it from there in normal work |
| **Security alert, reported only** | Secrets or tokens already committed, a committed `.env`, vulnerable dependencies | Nothing is fixed and nothing blocks: if it is like that today, it stays like that. Shown as an alert at the end of the skill and kept in the private plan (section 5.2) |

Instruction files whose content was moved are **removed** from the project, not archived: the checkpoint tag and the git
history keep them, and an archive folder would keep competing with the workspace rules. In a team repository whose
colleagues still use those files, the person can keep them in place; the workspace then excludes them
(`claudeMdExcludes` and a list in `custom/`).

### 5.1 The project documentation

Every migration writes the complete documentation of the project from the analysis, whether the project has a `docs/`
folder or not: overview, architecture, setup and run (the variables of `.env.example`, never values), configuration,
tests, deployment and operations. Existing documentation is reviewed: what is right stays, what is wrong is fixed, what
is missing is written. The README links to it and has the "How to test" section.

- **Language:** before writing any documentation, the skill always asks which language to use, together with the plan
  approval, once per project. The answer is recorded in the project's line of `custom/projects.md`, so later sessions
  keep the same language when they edit the docs.
- The documentation describes the project. Secrets, account and tenant identifiers stay out (they go to the custom
  layer).
- A documentation subagent writes it, with its effort passed in the call.

### 5.2 Security gaps never block

A security gap that exists today does not stop the migration and is not fixed by it. Three rules make that hold:

1. **The gate judges only what the branch adds.** In the normalization, the secret scan of `/merge` judges the lines
   the branch adds, not whole changed files, so a key already committed in a file the migration touches does not
   block. A new secret still blocks; the migration never adds one.
2. **The migration never copies a secret.** Neither the documentation, the custom-layer content nor the report carry a
   value: the docs name the variable and where it is set; the custom layer gets the content without the value.
3. **Where the alert shows:** on screen at the end of the skill (file, line, type, never the value, with the
   recommendation to rotate and remove it) and in the private plan in `custom/migrations/`. The migration report at the
   project root only says that security alerts were shown to the person who ran the migration: listing where the keys
   are in a committed file would advertise them.

### 5.3 The plan and the report

The plan is written to `custom/migrations/<repo>-<date>.md` (it may name company things, so it never goes to the
project) and shown to the person, who approves, edits or drops each line. Nothing changes before that approval.

## 6. The check at every interaction

A text rule ("before anything, check the marker") depends on the model remembering it and would fail in exactly the
long sessions. The check lives in scripts, at three points:

| Where | When it fires | What it does |
| --- | --- | --- |
| `UserPromptSubmit` hook (the same process as `session-title.py`) | At each message that names a project of `projects/` or a POC, by folder name, by path or by the `**Project:**` line of `/prompt` | Reads the marker and injects the state into the context, with the order to warn the person and ask for authorization to run `/normalize-projects <project>` |
| `aiwp-cmds.sh open` | Every change, since all work starts there | Shows the same state. For a project without a marker or out of date, the request goes on, but the warning is in the output and Claude repeats it |
| `aiwp-cmds.sh gate` | Every merge | Warns, without blocking, when the project is still out of date. When the merge is the normalization itself, checks that the marker is right |

The behavior:

- **No marker:** "This project is not a Claude CLI Agents Workspace project and needs normalizing. Run
  `/normalize-projects <project>`?"
- **Out of date:** "This project is on version X; the workspace is on Y, with migrations A and B pending. Update it?"
- **Yes:** the normalization runs before the request.
- **No:** the request goes on, and the warning comes back at the next interaction with the project.

It warns and asks; it never blocks. A block would stop an urgent fix in a project not normalized yet.

## 7. The `/normalize-projects` skill

```text
/normalize-projects                 lists the state of every project and POC
/normalize-projects <project>...    analyses and migrates the ones named, one at a time
/normalize-projects --from <url|path>  brings a project from its remote or from a local folder, then analyses and migrates it
```

Without arguments, the skill only lists, changing nothing:

| Project | Marker | State | `developer` |
| --- | --- | --- | --- |
| `billing-api` | none | not normalized | exists; checkout on `feature/invoices` |
| `landing-page` | 0.1.0 | up to date | exists |

The skill has two stages per project, with the person's approval between them.

**Stage 1, analysis** (section 5): base check, fresh clone, the four analysts, the migration plan, the approval.

**Stage 2, migration:**

1. **Base:** `projects/<repo>` on `developer`, and `developer` on the remote.
   - Checkout on another branch: asks before switching (the other branch is on the remote).
   - No `developer`: asks before creating it on the remote from `main`.
   - No remote: stops and asks the person to create the repository.
2. **Checkpoint:** annotated tags on the current heads, before any change:
   `ai-workspace-migration/<date>/developer` and `ai-workspace-migration/<date>/main`. They are pushed right away,
   after the person confirms, so the return point exists on the remote even if the machine is lost. The summary says
   how to return to them.
3. **Branch:** a clone in `tmp/work/` (`aiwp-cmds.sh open`) on `feat/ai-workspace-migration`, created from `developer`.
   The work branch is on the remote at every commit, as for any work in the workspace.
4. **Apply the approved plan:** one commit per line or group (custom-layer content first, committed in `custom/`;
   then the project changes and the documentation in the chosen language; then the migration report; the marker
   last).
   - **Migration report:** `AI-WORKSPACE-MIGRATION.md` at the project root: what changed, the documentation written
     and its language, the gaps found (missing unit tests, coverage, off-standard code, dependencies), the result of
     the branch test, and only the count of security alerts. It signals; it creates nothing.
5. **Test with the person:** the skill shows how to run the branch (from the build-and-test analysis: commands,
   `.env` through `/local-env`, services) and asks whether the person can run it now.
   - It runs what it can: the suite, the app, and, for a UI, the screens through Claude in Chrome (not inside WSL) or
     a headless browser in Docker, with screenshots as evidence.
   - The person confirms the result. If the branch cannot be run here, the person decides between stopping and going
     on untested; the summary records which.
6. **Merge:** `/merge` takes the branch into `developer` through the gate (tests, validate, secrets, review).
7. **Release:** `aiwp-cmds.sh release <repo>` fast-forwards `main` to `developer`, after the person confirms. If `main`
   is protected and refuses the push, the skill opens a pull request instead and says so.
8. **Index:** the project's line in `custom/projects.md`, committed in the custom layer.
9. **Summary:** what moved to the custom layer, what stayed, what changed, the tests run and their result, the
   checkpoint tags, the gaps reported, and what is pending; then the security alerts (section 5.2).

At the end everything is on the remote: the checkpoint tags, the feature branch, `developer` and `main`. Every push
happens inside the flow the person started and approved, and the skill names each one before doing it.

**POCs** live inside the custom repository: the same analysis and approval, then the changes as commits in `custom/`,
without branch, tags, gate or release.

`--from <url|path>` brings a project in, from its remote or from a local folder of an older workspace (cloned, so
local branches never pushed come along; `origin` points to the original remote; uncommitted changes in the source are
reported, since a clone does not carry them). A new project without a remote: `init-repo.sh` creates the repository and
writes the marker.

## 8. Changes in the product

| File | Change |
| --- | --- |
| `VERSION`, `migrations/` | The version and the project migrations, starting with `migrations/0.1.0.md`, which is this normalization |
| `scripts/aiwp-project-state.sh` (or an `aiwp-cmds.sh` command) | New: reads the marker, compares it with `VERSION` and `migrations/` and prints the state. Used by the hook, `open`, `gate` and the skill |
| `scripts/session-title.py` or a sibling hook | Detects the project named and injects its state |
| `scripts/aiwp-cmds.sh`, `scripts/aiwp-gate.sh` | Show the state in `open` and `gate`; `release` accepts the normalization flow |
| `rules/skills/normalize-projects/` | New, with the analyst briefs; `rules/skills/migrate-project/` leaves |
| `scripts/import-project.sh` | Leaves |
| `scripts/init-repo.sh` | Writes the marker in new projects and POCs |
| `AGENTS.md`, `rules/rules.md`, `rules/git.md`, README, usage guide, a decision record | The project contract: marker, the two stages, the checkpoint tags (the one case where the workspace pushes a tag), the check |
| Tests | Suite of the state script (no marker, equal, older without migration, older with migration, README without marker, POC, the workspace's own repository), of the hook, and of the checkpoint and release steps against a local bare remote |

The workspace's own repository (`claude-cli-agents-workspace`) is recognized and never migrated.

## 9. Decisions

- The marker is `AI-WORKSPACE-PROJECT`: short, and it sits in the README of projects that do not need the product
  name.
- The first version is 0.1.0, and the first project migration is `migrations/0.1.0.md`.
- No fixed list of instruction files: a deep analysis by Opus subagents with high effort decides, per piece, between
  the custom layer, the project, or a change; gaps (tests included) are only reported in `AI-WORKSPACE-MIGRATION.md` at
  the project root, and security gaps only alert at the end, never blocking; the person approves the plan.
- Complete project documentation is written from the analysis, always asking the language first.
- Moved instruction files are removed, not archived; the checkpoint tags and git history keep them. A team repository
  may keep them in place, excluded in the workspace only.
- Branch `feat/ai-workspace-migration`, tested with the person (Claude in Chrome or another tool when there is a UI),
  then `developer` through the gate and `main` by release; checkpoint tags before any change; everything ends on the
  remote.
- Out of date only warns and asks; it never blocks.
- The first run is in the test installation, on a throwaway project with a local bare remote, never on existing
  projects before it.
