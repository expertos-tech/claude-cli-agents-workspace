# Functional request: `developer` as default branch, `/merge` with a versioned changelog, `/merge --main` as the release

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained, with the product in `workspace/`. It runs
before `import-from-fork`, whose release then uses `/merge --main`. Approved by the owner in a planning session on
2026-11-17; recorded here at approval (`.claude/rules/process.md` step 2).

## 1. Objective

One flow for every delivery, in the product and in this maintenance repository. Work started by `/prompt` happens in a
clone on a work branch under `tmp/work/`. `/merge` takes it into `developer` after the gates and a clean-context
review, and always writes the CHANGELOG under a versioned `Unreleased` section. `/merge --main` publishes that version:
fuller tests, fixes in a release clone, then `developer` and `main`. The product skill is the source; the maintenance
repository gets a copy with the same behavior, and the owner then says what differs here.

## 3. Business rules

- BR-1 (D-1) Version bump by the Conventional Commit types of what enters. A `feat` → minor. Only `fix`, `docs`,
  `refactor`, `chore`, `test`, `perf`, `build` or `ci` → patch. Breaking (`!`) → major from 1.0.0, minor before.
- BR-2 (A-1) Header `## [X.Y.Z] - Unreleased`; at release it becomes `## [X.Y.Z] - YYYY-MM-DD` (Keep a Changelog).
- BR-3 (A-2) L = the newest dated header (else the newest `vX.Y.Z` tag, else `0.0.0`); U = the `Unreleased` header.
  - No U: U = L bumped per BR-1.
  - U is a patch of L (same X.Y) and a new `feat` enters: U = X.(Y+1).0.
  - U already a minor or major over L: U is kept and the entries are added.
- BR-4 (D-5) A fix of something that entered the same `Unreleased` version is not a fix. It adds no `Fixed` entry and
  does not count for the bump. It updates the original entry, and only when the described behavior changed. `Fixed` is
  only for what a dated version already published.
- BR-5 (A-3) `/merge` is the only writer of the CHANGELOG. It writes from `git log` and `git diff` of what enters, under
  Added, Changed, Fixed, Removed and Security, for the reader, without duplicates. `/commit` and the implementer stop
  writing it. Each component with its own `CHANGELOG.md` (the nearest one up the tree from the changed files) gets its
  own section and version.
- BR-6 (A-4) The CHANGELOG commit is made in the clone, after `developer` is merged into the branch and before gate
  phase 1. A conflict with another merge's section is resolved in the clone (union of entries, version by BR-3).
- BR-7 (A-5) Product `/prompt`: a prompt that will change a repository opens its clone before the first change. A
  question or read-only prompt opens nothing.
- BR-8 (A-6) Product `/merge` with no argument uses the clones this session opened (named in the conversation). None
  named: `aiwp-cmds.sh status`. One clone with commits ahead → that one; several → ask which; none → "nothing to
  merge".
- BR-9 (D-2) `/merge --main <repo>` always opens `tmp/work/<date>-release-vX-Y-Z/<repo>` on `fix/release-vX-Y-Z`
  (hyphens: `open` accepts only `<type>/<kebab>`). Then:
  1. A clean-context `reviewer` (effort high) runs the full tests and `validate.sh` there and reviews `main..developer`
     against the CHANGELOG.
  2. Fixes are made in that clone (BR-4), and the CHANGELOG gets its date.
  3. The clone goes through the gate into `developer`.
  4. `aiwp-cmds.sh release <repo> --tag vX.Y.Z` runs, then `close`.
- BR-10 (D-3) `aiwp-cmds.sh release --tag vX.Y.Z` creates an annotated tag on the released `main` and pushes it.
  - It fails before anything moves if the tag exists on another commit, here or on the remote.
  - A tag is never moved.
  - On the pull request path, there is no tag until that PR is merged.
- BR-11 (A-7, D-4) The maintenance copy uses plain git commands in the skill, with no new script. In a clone it
  pushes the branch after each commit. `/merge` pushes the work branch and `developer`, because the owner ran it.
  Phase 1 is `tests/check.sh --all --base origin/developer` in the clone, plus `/test-install` when the installer, a
  hook or `setup-claude.sh` changed. Phase 2 is a fast-forward of `developer` at the root.
  A session working directly on `developer` gets a `/merge` that runs `/check`, writes the CHANGELOG from the commits
  since its last change, commits and pushes.
- BR-12 (A-8) In the maintenance repository, `/merge --main` replaces `/release` and takes over its steps:
  `workspace/VERSION`, the CHANGELOG date, `check.sh --base <last tag>`, `/test-install`, translations and review.
  Then main, tag and GitHub release follow, each public step confirmed by the owner. `/release` is removed.
- BR-13 (D-6) A plan, request or document is shown to the person in the language of the request and written to its
  file in English, with one line saying so. This applies to the product and to the maintenance repository.
- BR-14 `developer` is the default branch of the public repository; `main` moves only by `/merge --main`.

## 4. Acceptance criteria

- AC-1: Given a test installation with a throwaway project and a bare remote, when a `fix` is merged by `/merge`, then
  `## [0.0.1] - Unreleased` holds its entry; when a `feat` follows, the header becomes `## [0.1.0] - Unreleased`.
- AC-2: Given a `fix` of that same feature, when it is merged, then the Added entry is adjusted and no Fixed entry
  appears.
- AC-3: Given `/merge --main <repo>`, then a release clone on `fix/release-v0-1-0` exists, the CHANGELOG is dated, the
  remote `main` equals `developer`, and the remote has the annotated tag `v0.1.0`.
- AC-4: The `aiwp-gate` suite covers: tag created and pushed, tag on the same commit, tag on another commit (nothing
  moves), bad version (exit 2), PR path (no tag), no remote (local tag).
- AC-5: `bash tests/check.sh --all` passes, `/test-install` passes, and an independent review has no BLOCKER open.
- AC-6: `gh repo view --json defaultBranchRef` shows `developer`.

## 7. Out of scope

- Version files of project manifests (`package.json`, `pom.xml`...): only the CHANGELOG and the tag.
- The rules that differ in the maintenance repository: the owner gives them after this request.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 0. `developer` fast-forwarded, pushed and made the default branch | low | Asked by the owner explicitly |
| 1. This record and its row in `maintainers/requests/README.md` | medium | Text |
| 2. `aiwp-gate.sh release --tag`, `guard-bash` message, scenario tests | high | Gate script and a hook |
| 3. Product skills and rules (`/merge`, `/prompt`, `/commit`, implementer, `git.md`, `docs.md`, `AGENTS.md`), `docs/usage.md` and translations | high | Mandatory core |
| 4. Maintenance copy: `.claude/skills/merge`, `/prompt`, remove `/release`, `CLAUDE.md`, `git.md`, `process.md` | medium | Text over decided behavior |
| 5. Suite, `/test-install`, independent review, commits, first `/merge` writing `## [0.2.0] - Unreleased` | high | Proof of a core change |

The agents of each stage run with the stage's effort, passed in the call.
