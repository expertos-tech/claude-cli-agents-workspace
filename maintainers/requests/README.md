# Requests

English · [Português (Brasil)](../../i18n/pt-BR/maintainers/requests/README.md) · [Español](../../i18n/es/maintainers/requests/README.md)

Functional requests for the workspace itself, run at the repository root, where the project is maintained
(`/caw-request <name>`). Each one has the objective, the business rules (BR-n), the acceptance criteria (AC-n), what
is out of scope, and the stages with the effort of each; an adjustment has only What, Where, Done when and Effort.
The design behind a large one is in `maintainers/plans/`.

## Lifecycle

| Folder | State | Moved by |
| --- | --- | --- |
| `requests/` | Pending: `idea` (decisions open) or `ready` | An approved plan, an idea, or a finding of a review |
| `requests/qa/` | On `developer`, not released; an "Execution" block records each merge | `/caw-merge` |
| `requests/done/` | Released; "Released in vX.Y.Z" added | `/caw-merge --main` |

A request never moves while its stages run. There is no backlog: an idea is a pending request in state `idea`.

## Pending

Each runs in its own session and clone under `tmp/work/` (`/caw-request <name>`), and enters `developer` through
`/caw-merge`, one at a time; a request starts only after the ones it depends on are on `developer`.

### Recommended order

0. First, before round 2: `autonomous-work` (work in the branch with no prompt, a Docker copy per task, the merge
   only by the person); it delivers `work-branch-push-before-scan`, `review-docs-only-scope`, `review-effort-wording`
   and `work-status-docker-stacks`, and removes `os-sandbox-trial`.
1. Round 1: `rules` and `run-tools` are in qa; the ideas of round 1 once the owner answers their decisions
   (except `measure-quality-indicators`, which waits for `import-from-fork`).
2. Round 2: `normalize-rules` first (the owner needs it to migrate the final project), then `fork-my-rules`,
   `tools-hub`, `onboard`.
3. `import-from-fork`: the first release after the publication, right after `normalize-rules`; then
   `measure-quality-indicators` (both change `measure.py`).
4. Before that first release: the findings of the merge and release flow (the small ready requests below), above all
   `release-developer-moved` and `release-main-sha-check`, and `release-per-project-proof`, which proves the qa
   lifecycle and the release per project in a real run. The small ones mostly touch `/caw-merge` and the rules and can
   run together in one session.

### Ready: the plan

| Round | Request | Notes |
| --- | --- | --- |
| 0 | `autonomous-work.md` | Design: `plans/autonomous-work.md`; before round 2 |
| 2 | `normalize-rules.md` | Needs `rules`; design: `plans/normalize-rules.md`; the owner needs it to migrate the final project |
| 2 | `import-from-fork.md` | After `normalize-rules`: the first release after the publication, the first real test of `aiwp update` |
| 2 | `fork-my-rules.md` | Needs `rules`; design: `plans/fork-my-rules.md` |
| 2 | `tools-hub.md` | Needs `run-tools`; design: `plans/tools-hub.md` |
| 3 | `final-review.md` | A whole-product review in a new session; every release now also ends with a final review |

### Ready: findings of the reviews

Small adjustments, effort low unless noted.

| Request | What it fixes |
| --- | --- |
| `release-developer-moved.md` | `/caw-merge --main` when `developer` moves during the release |
| `release-main-sha-check.md` | The push of `main` and the tag tied to the sha the suite judged |
| `work-branch-push-before-scan.md` | Work and release branches pushed before the company-terms scan |
| `execution-block-after-fixes.md` | The Execution block written before the results it records |
| `clone-path-findings-loop.md` | Requests made of findings loop the clone path of `/caw-merge` |
| `caw-layers-missing-target.md` | The `caw-layers` check passes a layer whose product skill is missing |
| `merge-project-name.md` | `<project>` for a plain folder of repos with no root repo |
| `old-names-leftovers.md` | Old names in a decision record and in pending requests |
| `review-effort-wording.md` | Texts still say every review is effort high |
| `review-docs-only-scope.md` | `CLAUDE.md`, `AGENTS.md` and templates count as documentation and skip the review |
| `release-per-project-proof.md` | Prove AC-1 to AC-4 of `request-lifecycle` in a real run (effort medium) |

### Ideas

| Round | Request | What is missing |
| --- | --- | --- |
| 1 | `prompt-log-results.md` | Two decisions |
| 1 | `gate-audit-gaps.md` | Three decisions |
| 1 | `work-status-docker-stacks.md` | Two decisions |
| 1 | `aiwp-remove.md` | Whether to build it |
| 2 | `onboard.md` | Four decisions; needs `rules`; design: `plans/distribution.md` |
| 2 | `measure-quality-indicators.md` | Three decisions; after `import-from-fork` (both change `measure.py`) |
| 3 | `rules-size-budget.md` | Two decisions; folded into `final-review` or right before it |
| 4 | `os-sandbox-trial.md` | Three decisions; after round 3 |
| — | `qa-validation-on-developer.md` | The owner completes the design of `--qa` |
| — | `release-tag-after-pull-request.md` | The design of the tag after a pull request into a protected `main` |
| — | `repo-terms-skip-stops-merge.md` | Today no terms list exists here |
| — | `workflow-agent-session-name.md` | The parent session name in the labels of Workflow agents |
| — | `colima-console-test-on-linux.md` | Three decisions; a real Colima next to docker-ce on Linux to test the Colima console |

## QA

| Request | Merged into `developer` | Acceptance criteria |
| --- | --- | --- |
| `qa/merge-versioned-changelog.md` | 8e01d75 | AC-1 to AC-3 pending (end-to-end run) |
| `qa/caw-merge-two-changelogs.md` | d4c22bd | AC-3 and AC-4 pending (first release) |
| `qa/project-docs.md` | f9ba9cf | All proven |
| `qa/readme-get-involved-first.md` | f9ba9cf | All proven |
| `qa/review-and-translation-cadence.md` | fb442c1 | All proven |
| `qa/request-lifecycle.md` | this merge | AC-1, AC-2, AC-4 and part of AC-3 pending; AC-5, AC-6 failed in part (requests) |
| `qa/merge-release-step-reference.md` | this merge | Met |
| `qa/review-final-brief-unreleased.md` | this merge | Met |
| `qa/run-tools.md` | this merge | AC-2, AC-3, AC-5, AC-6 proven; AC-1 by a real run; AC-4 and RN-8 in a session pending |
| `qa/accordion-motion.md` | this merge | AC-2, AC-5, AC-7, AC-8 proven; AC-1 measured; AC-3, AC-4 in part; AC-6 and the owner's visual run pending |
| `qa/rules.md` | this merge | AC-2 to AC-4, AC-6, AC-8 proven; AC-1, AC-1a, AC-5, AC-7 at script level, their session part pending |
| `qa/hotfix-from-main.md` | this merge | AC-1, AC-6, AC-8 proven; AC-4, AC-7 at script level; AC-2, AC-3, AC-5, AC-9 and the session run of AC-10 pending |
| `qa/process-merge-check-command.md` | this merge | Met |
| `qa/2026-11-18-maintenance-closing-board.md` | this merge | Met |

## Done

| Request | Released in |
| --- | --- |
| `done/normalize-projects.md` | v0.1.0; a second test on unseen projects is still worth doing |
