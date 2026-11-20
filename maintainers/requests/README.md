# Requests

English · [Português (Brasil)](../../i18n/pt-BR/maintainers/requests/README.md) · [Español](../../i18n/es/maintainers/requests/README.md)

Functional requests for the workspace itself, run at the repository root, where the project is maintained
(`/caw-request <name>`). Each one has the objective, the business rules (BR-n), the acceptance criteria (AC-n), what
is out of scope, and the stages with the effort of each; an adjustment has only What, Where, Done when and Effort.
The design behind a large one is in `maintainers/plans/`.

## Lifecycle

| Folder | State | Moved by |
| --- | --- | --- |
| `requests/` | Pending: `idea` (decisions open) or `ready`; Status `pending` | An approved plan, an idea, or a finding of a review; `bash tests/caw-work.sh close <work> --discard` puts one back |
| `requests/doing/` | In progress: its work is open in a clone of `tmp/work/`, from its start until `/caw-merge`; Status `doing` | `/caw-request`, through `bash tests/caw-work.sh start <name>`, before its clone opens |
| `requests/qa/` | On `developer`, not released; an "Execution" block records each merge | `/caw-merge`, from `doing/` (or from `requests/`, for one that never went through `doing/`) |
| `requests/done/` | Released; "Released in vX.Y.Z" added | `/caw-merge --main` |

A request moves once, to `doing/`, before its clone opens, and never again while its stages run:
`bash tests/caw-work.sh start <name>` moves it and sets the Status of its row below to `doing`, in one commit pushed
to `developer` (the one exception to `/caw-merge` moving it, `.claude/rules/security.md`); a stage that stops leaves
it there, and `/caw-merge` takes it to `qa/`. A request with the Status `doing` is never offered to run: a closing
board or a summary names it `in progress: <work>`. There is no backlog: an idea is a pending request in state `idea`.

## Pending

Each runs in its own session and clone under `tmp/work/` (`/caw-request <name>`), and enters `developer` through
`/caw-merge`, one at a time; a request starts only after the ones it depends on are on `developer`.

### Recommended order

Nothing runs now: `request-in-progress` and `assisted-mode` are in qa. A running request has the Status `doing`.

0. **Round 0, before the first installation and the first release** (`/caw-merge --main`):
   1. Two sessions at once, on disjoint paths: `draft-prompt`; and the three findings of `/caw-merge` left in one
      session, all in `.claude/skills/caw-merge/SKILL.md`: `release-main-sha-check` first (without it the first
      `--main` runs with a known defect), then `execution-block-after-fixes` and `clone-path-findings-loop`
      (`release-developer-moved` is in qa).
   2. `session-names` after `draft-prompt` (same files).
   3. `final-review` last, once everything above is on `developer`, with `rules-size-budget` folded in when the owner
      has answered its decisions.
   4. The first installation, then `/caw-merge --main`.
1. **Round 1, the next release:** `import-workspace-code-folders` (the owner needs it to migrate a whole older
   workspace; its paths are disjoint from round 0, so it may also run now, in parallel); `import-from-fork`, the
   first real test of `aiwp update` from the first release, then `measure-quality-indicators` (both change
   `measure.py`); `merge-project-name` and `release-per-project-proof` (both prove or change `/merge`); `merge-queue`
   (it also changes `/caw-merge`: never with the four findings of round 0).
2. **Round 2:** `fork-my-rules` (needs `rules`), `tools-hub` (needs `run-tools`), `onboard`, and the ideas
   `prompt-log-results`, `gate-audit-gaps` and `aiwp-remove` once the owner answers their decisions.

The ideas with no round wait for their design. `rules`, `run-tools`, `import-workspace` and
`validators-warn-not-block` are in qa.

### Ready: the plan

| Round | Request | Status | Notes |
| --- | --- | --- | --- |
| 0 | `draft-prompt.md` | doing | `/draft-prompt` (a loose text to a plan in a priority order), `/draft-request` renamed `/new-request` with a summary on screen, plans in the person's language and requests in English, the screen in the person's language; design: `plans/draft-prompt.md` |
| 0 | `session-names.md` | pending | Session names that follow the life of a request (`ai-workspace-NN`, `rq-`, `rq-done-`, `rq-closed-`, the release session), `/rename-workspace`; after `draft-prompt` (same files); design: `plans/session-names.md` |
| 0 | `final-review.md` | pending | Last of round 0, before the first release, with `rules-size-budget` folded in; a whole-product review in a new session; every release now also ends with a final review |
| 1 | `import-workspace-code-folders.md` | pending | After `import-workspace`; may run now, in parallel with round 0: every code folder found by extension, POC, tool or project in rounds of checkboxes, a local repository with its history; source: its warning W-1; design: `plans/import-workspace-code-folders.md` |
| 1 | `import-from-fork.md` | pending | After the first release: the first real test of `aiwp update` |
| 2 | `fork-my-rules.md` | pending | Needs `rules`; design: `plans/fork-my-rules.md` |
| 2 | `tools-hub.md` | pending | Needs `run-tools`; design: `plans/tools-hub.md` |

### Ready: findings of the reviews

Small adjustments, effort low unless noted. Round 0: the first three, in one session; round 1: the other three.

| Request | Status | What it fixes |
| --- | --- | --- |
| `release-main-sha-check.md` | pending | The push of `main` and the tag tied to the sha the suite judged |
| `execution-block-after-fixes.md` | pending | The Execution block written before the results it records |
| `clone-path-findings-loop.md` | pending | Requests made of findings loop the clone path of `/caw-merge` |
| `merge-project-name.md` | pending | `<project>` for a plain folder of repos with no root repo |
| `release-per-project-proof.md` | pending | Prove AC-1 to AC-4 of `request-lifecycle` in a real run (effort medium) |
| `merge-queue.md` | pending | One merge at a time per git repository (developer and main): a new hard rule, a BLOCKER with no override, the queue file, a log per merge, the unfinished merge, the check at each merge and `--sweep`, product and `caw-` (effort high) |

### Ideas

| Round | Request | Status | What is missing |
| --- | --- | --- | --- |
| 0 | `rules-size-budget.md` | pending | Two decisions; folded into `final-review` or right before it |
| 1 | `measure-quality-indicators.md` | pending | Three decisions; after `import-from-fork` (both change `measure.py`) |
| 2 | `prompt-log-results.md` | pending | Two decisions |
| 2 | `gate-audit-gaps.md` | pending | Three decisions |
| 2 | `aiwp-remove.md` | pending | Whether to build it |
| 2 | `onboard.md` | pending | Four decisions; needs `rules`; design: `plans/distribution.md` |
| — | `qa-validation-on-developer.md` | pending | The owner completes the design of `--qa` |
| — | `release-tag-after-pull-request.md` | pending | The design of the tag after a pull request into a protected `main` |
| — | `repo-terms-skip-stops-merge.md` | pending | Today no terms list exists here |
| — | `workflow-agent-session-name.md` | pending | The parent session name in the labels of Workflow agents |
| — | `colima-console-test-on-linux.md` | pending | Three decisions; a real Colima next to docker-ce on Linux to test the Colima console |

## QA

| Request | Merged into `developer` | Acceptance criteria |
| --- | --- | --- |
| `qa/custom-skeleton-requests-folder.md` | this merge | Met: by the scenarios of the `aiwp` suite and the test installation |
| `qa/release-developer-moved.md` | this merge | Met: by the text of "Release" step 8; its first real run is a release where `developer` moves |
| `qa/2026-11-19-requests-priorities.md` | this merge | Met |
| `qa/2026-11-20-install-developer.md` | this merge | Met: by the scenarios of the `aiwp` suite and a run on the test installation's repository |
| `qa/request-in-progress.md` | this merge | AC-1 to AC-3, AC-7, AC-8 proven by scenario tests; AC-4 to AC-6 by headless rehearsals |
| `qa/assisted-mode.md` | this merge | All proven: AC-1, AC-5, AC-6 in interactive and headless sessions of a test installation, AC-2 and AC-9 headless (AC-9 at the root and in a work clone), AC-8 headless, AC-3, AC-4, AC-7, AC-10 by scenario tests |
| `qa/import-workspace.md` | this merge | All proven: AC-1 to AC-9 by scenario tests, AC-10 by a headless run on a copy of a real older workspace |
| `qa/warnings-board.md` | 58ead34 | All proven: AC-3 and AC-4 by headless runs, in a clone or at the root and in a test installation |
| `qa/2026-11-18-caw-work-close-readonly.md` | this merge | Met: by the scenarios of `test-caw-work.sh` |
| `qa/preferred-language.md` | this merge | All proven: AC-1 and AC-2 by headless runs, AC-3 on a pty of the test installation |
| `qa/validators-follow-ups.md` | this merge | AC-1, AC-3, AC-4 proven (AC-4 by scenarios and a run from a clone); AC-2 at the first release |
| `qa/rules-as-product-layers.md` | this merge | All proven: AC-2 and AC-5 by headless runs, AC-4 by the table of its Execution block |
| `qa/validators-warn-not-block.md` | this merge | AC-8, AC-9 proven; AC-1, AC-2 at script level; AC-3 to AC-6 by this merge's review and summary; AC-7 in part |
| `qa/merge-versioned-changelog.md` | 8e01d75 | AC-1 to AC-3 pending (end-to-end run) |
| `qa/autonomous-work.md` | this merge | AC-2, AC-4, AC-6 to AC-9, AC-14 proven; AC-1, AC-3, AC-5, AC-10 at script level, their session part pending; AC-11 to AC-13, AC-15 in part |
| `qa/caw-merge-two-changelogs.md` | d4c22bd | AC-3 and AC-4 pending (first release) |
| `qa/project-docs.md` | f9ba9cf | All proven |
| `qa/readme-get-involved-first.md` | f9ba9cf | All proven |
| `qa/review-and-translation-cadence.md` | fb442c1 | All proven |
| `qa/request-lifecycle.md` | this merge | AC-1, AC-2, AC-4 and part of AC-3 pending; AC-5 met by `qa/old-names-leftovers.md`; AC-6 met by `qa/caw-layers-missing-target.md` |
| `qa/merge-release-step-reference.md` | this merge | Met |
| `qa/review-final-brief-unreleased.md` | this merge | Met |
| `qa/run-tools.md` | this merge | AC-2, AC-3, AC-5, AC-6 proven; AC-1 by a real run; AC-4 and RN-8 in a session pending |
| `qa/accordion-motion.md` | this merge | AC-2, AC-5, AC-7, AC-8 proven; AC-1 measured; AC-3, AC-4 in part; AC-6 and the owner's visual run pending |
| `qa/rules.md` | this merge | AC-2 to AC-4, AC-6, AC-8 proven; AC-1, AC-1a, AC-5, AC-7 at script level, their session part pending |
| `qa/hotfix-from-main.md` | this merge | AC-1, AC-6, AC-8 proven; AC-4, AC-7 at script level; AC-2, AC-3, AC-5, AC-9 and the session run of AC-10 pending |
| `qa/process-merge-check-command.md` | this merge | Met |
| `qa/2026-11-18-maintenance-closing-board.md` | this merge | Met |
| `qa/old-names-leftovers.md` | this merge | Met |
| `qa/caw-layers-missing-target.md` | this merge | Met |
| `qa/console-npm-audit.md` | this merge | Met |

## Done

| Request | Released in |
| --- | --- |
| `done/normalize-projects.md` | v0.1.0; a second test on unseen projects is still worth doing |
