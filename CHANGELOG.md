# Changelog

The history of this repository: the maintenance of the project (`CLAUDE.md`, `.claude/`, `tests/`, `maintainers/`,
`i18n/`, `docs/`, `README.md`) in detail, and each product change as a summary under "Product". The product's own
changelog, with the detail, is [`workspace/CHANGELOG.md`](workspace/CHANGELOG.md).

Only the product is released (tags `vX.Y.Z` and GitHub releases). The versions here are never released on their own:
a section is dated by the product release that ships it, and points to it.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the versions
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - Unreleased

### Product

- `/merge` writes a versioned changelog at every merge, and `/merge --main` releases that version with a tag
  ([product changelog](workspace/CHANGELOG.md)).
- Plans and requests are shown in the person's language and saved in English.
- The i18n check of the product gate also requires the translations of every README and of the root `docs/`, and can
  report them as pending (`--i18n-pending`).
- `/merge --main` ends with a final review of everything since the last tag, by the three questions of every merge
  review.
- A request lifecycle (pending, `qa/`, `done/`) with an Execution block at each merge; the release per project with
  the project's own changelog in its root repo; any project layout, nested repos included; `/prompt` becomes
  `/request`; the prompt log moves to `logs/`; no backlog.
- `/merge --hotfix`: an error in production fixed from `main` as a patch version, then merged down into `developer`;
  the repo is blocked until it is.
- `/run-tools` and `tools/compose.yaml`: the local tools started by checkbox, the container ones in one compose group,
  their configuration from `custom/`.
- The container consoles animate opening and closing a Compose group, and the chevron of the jobs panel rotates; the
  menu switch is now "Animations".
- `make check` of the container consoles fails on a high `npm audit` finding instead of ignoring it.
- Configurable rules: the custom layer turns optional core rules, skills and agents off, replaces a core rule, and
  keeps its own in `custom/my-rules/` (was `custom/rules/`); the mandatory core in `rules/manifest.json`; `/rules`.
- Work in a clone with no question (`guard-bash` approves lines that stay in it, allow rules from `setup-claude.sh`,
  "Run it alone"), a Docker copy per task in its own `agent_` group on internal networks, `/docker-deploy` for the
  final stack, the merge only on the person's order, and the merge review by three questions with a return review
  after fixes (decision record 0004).
- Validators refuse only a closed list of hard rules; the rest is a warning shown once (a numbered warnings board
  with a risk level per warning, before the closing board of a wave and before the merge, waiting for a decision on
  each; `/draft-request` with "Authorizations"); one review per merge, effort `medium` into `developer` and
  `high` into `main`; the gate's non-secret checks, four asks of `guard-bash` and the copy's unsafe services become
  warnings (decision record 0005).
- `guard-bash`: a line refused with "Run it alone" shows the warnings of its other commands, as a question does.
- The preferred language of communication: asked by `aiwp new` and kept as the Claude Code setting `language`, which
  wins over the language of a request file; the single-agent mode is removed.

### Added

- This changelog of the repository, next to the product's.
- `/caw-merge`: the work of a session into `developer` through the suite and a clean-context review, writing both
  changelogs; `/caw-merge --main` releases the product version. Every push it makes comes right after a passing suite
  on that same commit, so nothing reaches this public repository without the company-terms scan.
- Requests in `maintainers/requests/` for the features discussed and not built yet (among them a hotfix flow from
  `main`, and the findings of the reviews), in the order they run, and the
  `/rules` lessons and the local delivery of `/fork-my-rules` in the `rules` and `fork-my-rules` requests.
- `maintainers/requests/done/`: delivered requests, and every plan the owner approves, recorded at approval.
- `maintainers/requests/qa/`: the requests on `developer` not released yet, each with what each merge did; the
  backlog becomes pending requests (`idea` or `ready`).
- `tests/check.sh` checks every `caw-*` layer, whatever its name: its `@` line names an existing product skill (the
  same-named one when there is one) and its three sections are there; a `caw-<name>` with no `@` line next to a
  product skill `<name>` fails.
- `/caw-merge --hotfix <description>`: a fix of the released product from `main`, as a patch version with its tag
  and GitHub release when the owner says to publish, then `main` merged into `developer` (`--down` resumes it); a
  maintenance-only fix is not a hotfix. `/caw-merge` and `/caw-request` refuse to start while `main` is not in
  `developer`.
- `docs/`: the documentation of the project: getting started, features, commands and updates, hooks, the repository,
  contributing, maintenance, releases and translations.
- `pt-BR` and `es` translations of `docs/` and of every README outside the product, each with a language links line.
- `tests/caw-work.sh`: opens a work clone (`open <type>/<slug>`), runs a closed list of commands in it (`run`),
  publishes what changed (`publish`: a tool as a Docker copy, the installer, a hook, a script or a rule as a test
  installation), pushes and closes it (the work folder first, a read-only test installation in it included, then
  the remote branch, so a failed delete never leaves a clone without its branch); the clone's hooks push its branch
  after each commit only after the company-terms scan of what leaves, and refuse `developer`, `main`, tags and
  force. `.claude/settings.json` allows
  it and edits of `tmp/work/` with no prompt, so the one prompt of a task is the push of `developer`.
- `/caw-pilot` and `/caw-docker-deploy`, the layers of `/pilot` and `/docker-deploy`.
- The request `validators-warn-not-block`: validators block only real errors, the rest is a warning.
- `.claude/rules/security.md` "Hard rules", the product's closed list with this repository's rows over it, and
  "Warnings": a company term in what a work clone pushes is a warning, the push waits, and
  `bash tests/caw-work.sh push <work> --accept-terms` (an ask prompt: the owner's confirmation) records it in a
  private file next to the terms list and pushes; `check.sh` repo-terms honours it, and a new term warns again.
- The session index, a hook of the root: at the start of a session and after each compaction,
  `tests/caw-session-index.py` tells the session which rule to read before which task, built from the product's own
  index (`workspace/AGENTS.md` "Reference") with `.claude/session-index.md` over it (rules left out, such as
  `quality.md`; words mapped, such as the gate to `/caw-merge`; rows only this repository has). It also defines the
  pointer: a line holding only `@<path>` in the root `CLAUDE.md` or a rule or skill of `.claude/` names a file to read
  in full from the root; any other `@`, in a file of `workspace/` too, is not one.
- `tests/check.sh` checks the rule layers and the index layer in `caw-layers` (a rule with a product counterpart that
  is not a layer, a layer whose product rule is gone, a missing section, the hook missing from the settings), with
  scenario tests (`caw-layers-tests`), and runs the hook's scenario tests (`caw-session-index`).
- The requests `warnings-board` (the numbered warnings board with risk levels before the closing board),
  `preferred-language` with its plan (the reply language as Claude Code's `language` setting) and
  `validators-follow-ups`.
- Review fixtures (`tests/review-fixtures/`): one made-up change per hard rule, expected BLOCKER, and three expected
  WARNING only; `/caw-merge --main` reviews each once per release (`reviewer`, effort `medium`) and judges the reports
  with `tests/review-fixtures.sh`; a failing fixture is a warning of the release, read to tell a fixture's own defect
  from a review rule that drifted. `tests/check.sh` checks the judge and the set (`review-fixtures`), never the model.
- `tests/caw-language.py`, a second SessionStart hook at the root (start, resume, clear, compact): with no `language`
  setting in the root `.claude/settings.local.json` or the user settings, it has the session ask the preferred language
  of communication first and save it there; with one, it prints nothing; it never fails a session start. Its
  scenarios run in `tests/check.sh` (`caw-language`). `bash tests/caw-work.sh open` copies that `language` into the
  clone's own `.claude/settings.local.json`, so a session inside a clone replies in it too.

### Changed

- `CLAUDE.md` "Language": the session replies in the `language` setting, even when a request file is in English; with
  none set, in the language the person writes in. `.claude/rules/product.md`: the invariant "no language setting"
  becomes the preferred language as the `language` setting, asked at install.
- The `pt-BR` and `es` translations of the product's README, `docs/README.md`, `docs/usage.md` and
  `scripts/README.md` are up to date with their sources.
- `developer` is the default branch; `main` moves only by a product release.
- The maintenance rules with a product counterpart (`security`, `review`, `models`, `git`, `docs`, `scripts` of
  `.claude/rules/`) are layers over the product rule of the same name, which stays the one source: each holds only
  what differs here ("Ignore from the product rule", "Mapping", "CAW rules"), so the hard rules no longer live in two
  lists that can drift, and a line the product rule gains reaches the maintenance with no copy to update.
- `/caw-request` works in a clone on a work branch under `tmp/work/`, and finds a bare file name in
  `maintainers/requests/`, then `tmp/requests/`, then `tmp/`.
- The maintenance skills carry the prefix `caw-`, apart from the product's; `/caw-merge`, `/caw-request` (was
  `/caw-prompt`), `/caw-commit` and `/caw-draft-request` are layers over the product skill of the same purpose.
- An approved plan is recorded as a pending request, no longer in `done/`.
- Plans and requests are shown to the owner in their language and saved in English.
- A merge into `developer` checks and reviews only the difference that enters, by the three questions, with effort
  `medium` (`high` into `main`), the owner's authorizations in the brief, and a return review after the fixes of its
  BLOCKERs; a WARNING never blocks and goes to the warnings board, where the owner decides each one before the merge goes on.
  No independent review runs during the stages of a request, hooks and security included; a stage with warnings ends
  with the warnings board, and the closing board lists the owner's decisions.
- Translations are brought up to date once per release, by one agent; between releases they are listed as pending.
- `/caw-merge --main` ends with the same final review as the product's: since the last tag, by the three questions.
- `/caw-request` and `/caw-merge` no longer push the work branch by hand: the clone's hooks do; `/caw-commit` stages
  before it commits by path, with the paths written out.
- `README.md` keeps the intro, "Get involved", a short "Quick start", the index of `docs/` and the license.
- `docs/features.md` lists `/run-tools` and the tools' compose group.
- The `rules-config` plan records that it is built, with what the build decided beyond it.
- Maintenance work ends with a closing board (`.claude/rules/process.md` step 6), like the product's: what was done,
  verified, left and pending, the request, and the next command.
- The test installation runs from a work clone: the clone's pre-push lets its snapshot reach the throwaway repository
  inside the clone's own `tmp/` (an absolute path, no named remote or URL, links resolved), any branch; a tag, a
  non-branch ref and a force push stay refused there, `main` and `developer` to `origin` too, and the company-terms
  scan still runs, counting what `origin` already has as scanned. `/caw-test-install` runs there, never from a copy
  of the branch without hooks.

### Removed

- `/release`: replaced by `/caw-merge --main`.

### Fixed

- `.claude/rules/process.md` step 4 names the suite `/caw-merge` runs into `developer`
  (`--base origin/developer --i18n-pending`), not the strict `--all`, which fails on translations left for the release.

## [0.1.0] - 2026-11-16

### Product

- Released [v0.1.0](https://github.com/expertos-tech/claude-cli-agents-workspace/releases/tag/v0.1.0): see its
  [changelog](https://github.com/expertos-tech/claude-cli-agents-workspace/blob/v0.1.0/workspace/CHANGELOG.md).

### Added

- The maintenance at the repository root: the process, rules, skills and agents for whoever maintains the product,
  the repository suite (`tests/check.sh`) and the test installation (`tests/test-install.sh`).
