# Functional request: `/normalize-projects`

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** in the maintenance of the repository, at its root, with the product in `workspace/`. Built with the
0.1.0 publication and run for the first time in the test installation, on a throwaway project with a local bare
remote, never on existing projects before that. Full design: `plans/normalize-projects.md`.

## 1. Objective

Bring each project and POC into the workspace in two stages: a deep analysis that decides what goes to the custom
layer, what stays in the project and what must change in it, approved by the person; then a migration on a tested
branch that ends merged into `developer` and `main`, with a checkpoint before it and everything on the remote. Mark each
project with the workspace version and warn at every interaction when a project is not a workspace project or is behind.
Replaces `/migrate-project`.

## 3. Business rules

- BR-1: the marker is the first line of the repository's `README.md` (or of the POC folder's):
  `<!-- AI-WORKSPACE-PROJECT x.y.z -->`, read by a fixed expression; the one on `developer` counts.
- BR-2: the product's `VERSION` and `migrations/<version>.md` with what each version asks of the projects; a project is
  out of date only when a migration newer than its marker exists. The first is `migrations/0.1.0.md`.
- BR-3: the skill names no specific files or folders to look for. Stage 1 is a deep, complete analysis of the
  repository by parallel subagents, each called with `model: opus` and `effort: high`: instructions (anything that
  tells an AI tool or a person how to work here), company and environment, build and test, conformity with the
  project contract. They read a fresh clone and change nothing.
- BR-4: the consolidation writes a migration plan to `custom/migrations/<repo>-<date>.md`, one line per finding, each
  with a destination: custom layer (company- or environment-specific knowledge, as a custom rule scoped to the
  project's paths), stays in the project (real project knowledge, as documentation), changes in the project (what the
  contract requires, without rewriting code). The person approves, edits
  or drops each line; nothing changes before that.
- BR-4a: gaps are only reported: missing unit tests, coverage, off-standard code or architecture, dependencies go to
  the migration report `AI-WORKSPACE-MIGRATION.md` at the project root; the skill creates no test, no request and no
  code. The workspace's quality gates take it from there.
- BR-4b: security gaps never block and are never fixed: what is like that today stays like that. They are shown as an
  alert at the end of the skill (file, line, type, never the value, with the recommendation to rotate) and kept in the
  private plan; the migration report only gives their count. In the normalization, the secret scan of the gate judges
  only the lines the branch adds; a new secret still blocks. The migration never copies a secret value anywhere.
- BR-4c: every migration writes the complete project documentation from the analysis (overview, architecture, setup
  and run with the variables of `.env.example` and no values, configuration, tests, deployment, operations), whether a
  `docs/` folder exists or not; existing docs are reviewed, fixed and completed. Before writing it, the skill always
  asks which language to use; the answer is recorded in the project's line of `custom/projects.md`.
- BR-5: instruction files whose content was moved are removed from the project, not archived. In a team repository
  the person may keep them in place, excluded in the workspace only (`claudeMdExcludes` and a list in `custom/`).
- BR-6: stage 2, per project: `projects/<repo>` on `developer` (asking before switching branch or creating `developer`
  on the remote; without a remote, it stops); annotated checkpoint tags `ai-workspace-migration/<date>/developer` and
  `.../main` on the current heads, pushed after the person confirms, before any change; a clone in `tmp/work/` on
  `feat/ai-workspace-migration` from `developer`; the approved plan applied in commits (custom layer first, marker
  last); "How to test" in the README (the gate relies on it).
- BR-7: test with the person: the skill shows how to run the branch and asks whether the person can run it now; it
  runs the suite and the app, and for a UI the screens through Claude in Chrome (not inside WSL) or a headless browser
  in Docker, with screenshots. The person confirms; if it cannot run here, the person chooses between stopping and
  going on untested, and the summary records the choice.
- BR-8: `/merge` takes the branch into `developer` through the gate; `aiwp-cmds.sh release <repo>` fast-forwards
  `main`, after the person confirms; a protected `main` that refuses the push gets a pull request instead. At the end
  the tags, the branch, `developer` and `main` are on the remote; the skill names each push before doing it.
- BR-9: POCs: the same analysis and approval; the changes are commits in `custom/`, without branch, tags, gate or
  release.
- BR-10: without arguments, the skill only lists the state; `--from <url|path>` brings a project from its remote or from a
  local folder (cloned, keeping local branches never pushed, `origin` pointed to the original remote, uncommitted
  changes in the source reported) and normalizes it; the line in `custom/projects.md` is updated at the end; a summary lists what moved, stayed and changed,
  the tests and their result, the tags and the gaps; then the security alerts.
- BR-11: a warning at every interaction: the `UserPromptSubmit` hook detects the project named (name, path,
  `**Project:**` line) and injects its state; `aiwp-cmds.sh open` shows the same; the gate warns without blocking. Out
  of date or without a marker only warns and asks for authorization, never blocks; when refused, the request goes on
  and the warning comes back at the next interaction.
- BR-11a: existing work enters a fresh installation only this way: projects moved by hand into `projects/` and POCs
  moved into `custom/pocs/` have no marker and are normalized like any other; the installation never converts an
  older workspace, and nothing depends on earlier sessions.
- BR-12: the workspace's own repository (`claude-cli-agents-workspace`) is recognized and never migrated.
- BR-13: `init-repo.sh` writes the marker in new projects and POCs; `scripts/import-project.sh` and the
  `/migrate-project` skill leave. `rules/git.md` names the checkpoint tags as the one case where the workspace pushes a
  tag.

## 4. Acceptance criteria

- AC-1: Given a project without a marker, when the person names it in a request, then the session warns that it is not
  a workspace project and asks for authorization to normalize; when refused, the request goes on.
- AC-2: Given a project marked 0.1.0 and the workspace on 0.3.0 with no migration after 0.1.0, then there is no
  warning.
- AC-3: Given a project with instruction files for other AI tools and company-specific notes, when stage 1 runs, then
  the plan in `custom/migrations/` lists each piece with a destination, the analysts ran with Opus and high effort, and
  nothing in the project changed.
- AC-4: Given the approved plan, when stage 2 ends, then the checkpoint tags exist on the remote at the old heads, the
  company-specific content is in the custom layer, the project has no competing instruction file, the marker is in the
  README on `developer` and `main`, and `feat/ai-workspace-migration`, `developer` and `main` are on the remote.
- AC-4a: Given a project without unit tests and with a token already committed, when normalized, then no test is
  created, the report at the root lists the missing tests, the gate does not block on the old token, and the end of the
  skill shows the alert with file and line and no value.
- AC-4b: Given any project, when stage 1 ends, then the skill has asked the documentation language; when stage 2 ends,
  the complete documentation is in the project in that language and the README links to it.
- AC-5: Given a project off `developer`, when normalized, then the skill asks before switching; without `developer` on
  the remote, it asks before creating it.
- AC-6: Given the branch cannot be run on this machine, then the skill asks whether to stop or go on untested, and the
  summary records the answer.
- AC-7: The suite covers: marker missing, equal, older without migration, older with migration, README without marker,
  POC, the workspace's own repository; and, against a local bare remote, the checkpoint tags, the merge into
  `developer` and the release of `main`.

## 7. Out of scope

- Rewriting project code to the standard, writing missing tests or fixing security gaps (they are only reported).
- Running on existing projects before the test installation.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. State script, `VERSION` and `migrations/`, suite | medium | Clear, testable rules |
| 2. Warning at every interaction (hook, `open`, gate) | high | A new hook on every message |
| 3. Skill: analysts, plan, approval | high | Judgement over real repositories |
| 4. Skill: checkpoint tags, branch, test with the person, `/merge`, release, push | high | Touches real projects and the remote |

The agents of each stage run with the stage's effort, passed in the call.
