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

Run them in this order; a request starts only after the ones it depends on are on `developer`. Each runs in its own
session and clone under `tmp/work/` (`/caw-request`), and enters `developer` through `/caw-merge`, one at a time.

| Round | Request | State | Notes |
| --- | --- | --- | --- |
| 0 | `request-lifecycle.md` | ready | The lifecycle, the release per project, a free layout, `caw-*` layers; in progress |
| 0 | `import-from-fork.md` | ready | The first release after the publication: the first real test of `aiwp update` |
| 1 | `rules.md` | ready | Design: `plans/rules-config.md` |
| 1 | `run-tools.md` | ready | Design: `plans/run-tools.md` |
| 1 | `prompt-log-results.md` | idea | Two decisions open |
| 1 | `gate-audit-gaps.md` | idea | Three decisions open |
| 1 | `work-status-docker-stacks.md` | idea | Two decisions open |
| 1 | `aiwp-remove.md` | idea | Its first decision is whether to build it |
| 1 | `measure-quality-indicators.md` | idea | After `import-from-fork` (both change `measure.py`) |
| 2 | `normalize-rules.md` | ready | Needs `rules`; design: `plans/normalize-rules.md` |
| 2 | `fork-my-rules.md` | ready | Needs `rules`; design: `plans/fork-my-rules.md` |
| 2 | `tools-hub.md` | ready | Needs `run-tools`; design: `plans/tools-hub.md` |
| 2 | `onboard.md` | idea | Needs `rules`; four decisions open; design: `plans/distribution.md` |
| 3 | `final-review.md` | ready | A whole-product review in a new session; every release now also ends with a final review |
| 3 | `rules-size-budget.md` | idea | Folded into `final-review` or right before it |
| 4 | `os-sandbox-trial.md` | idea | After round 3; three decisions open |
| — | `qa-validation-on-developer.md` | idea | The `--qa` validation; the owner completes the design |
| — | `release-developer-moved.md` | ready | `/caw-merge --main` when `developer` moves during the release |
| — | `release-tag-after-pull-request.md` | idea | The tag after a pull request into a protected `main` |
| — | `process-merge-check-command.md` | ready | A review finding |
| — | `review-effort-wording.md` | ready | A review finding |
| — | `review-docs-only-scope.md` | ready | A review finding |
| — | `merge-release-step-reference.md` | ready | A review finding |
| — | `review-final-brief-unreleased.md` | ready | A review finding |
| — | `workflow-agent-session-name.md` | idea | Parent session name in the labels of Workflow agents |

## QA

| Request | Merged into `developer` | Acceptance criteria |
| --- | --- | --- |
| `qa/merge-versioned-changelog.md` | 8e01d75 | AC-1 to AC-3 pending (end-to-end run) |
| `qa/caw-merge-two-changelogs.md` | d4c22bd | AC-3 and AC-4 pending (first release) |
| `qa/project-docs.md` | f9ba9cf | All proven |
| `qa/readme-get-involved-first.md` | f9ba9cf | All proven |
| `qa/review-and-translation-cadence.md` | fb442c1 | All proven |

## Done

| Request | Released in |
| --- | --- |
| `done/normalize-projects.md` | v0.1.0; a second test on unseen projects is still worth doing |
