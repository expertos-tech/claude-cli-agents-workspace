# Requests

English · [Português (Brasil)](../../i18n/pt-BR/maintainers/requests/README.md) · [Español](../../i18n/es/maintainers/requests/README.md)

Functional requests for the workspace itself, ready to run at the repository root, where the project is maintained. Each one
has the objective, the business rules (BR-n), the acceptance criteria (AC-n), what is out of scope, and the stages with
the effort of each. The design behind each request is in `maintainers/plans/`.

Run them in this order; each one depends on the ones before it:

| # | Request | Design | State |
| --- | --- | --- | --- |
| 0a | `done/merge-versioned-changelog.md` | — | In progress; plan approved 2026-11-17, recorded at approval |
| 0b | `done/caw-merge-two-changelogs.md` | — | Built 2026-11-17: two changelogs, only the product is released |
| 0c | `done/project-docs.md` | — | Built 2026-11-17: `docs/`, a short README, translations of every README |
| 0d | `done/review-and-translation-cadence.md` | — | Built 2026-11-17: reviews by risk, translations at the release, final review |
| 0 | `import-from-fork.md` | — | Pending; first after the publication, with its own release |
| 1 | `done/normalize-projects.md` | `plans/normalize-projects.md` | Built in 0.1.0; end-to-end test passed on six projects; a second test on unseen projects pending |
| 2 | `rules.md` | `plans/rules-config.md` | Pending |
| 3 | `normalize-rules.md` | `plans/normalize-rules.md` | Pending; needs `rules` |
| 4 | `run-tools.md` | `plans/run-tools.md` | Pending |
| 5 | `tools-hub.md` | `plans/tools-hub.md` | Pending; needs `run-tools` |
| 6 | `fork-my-rules.md` | `plans/fork-my-rules.md` | Pending; needs `rules` |
| 7 | `final-review.md` | — | Pending; runs last, in a new session |
| 8 | `done/readme-get-involved-first.md` | — | Built 2026-11-17 inside `done/project-docs.md` |
| 9 | `prompt-log-results.md` | — | Pending; round 1 |
| 10 | `gate-audit-gaps.md` | — | Pending; round 1 |
| 11 | `work-status-docker-stacks.md` | — | Pending; round 1 |
| 12 | `aiwp-remove.md` | — | Pending; round 1; its first decision is whether to build it |
| 13 | `measure-quality-indicators.md` | — | Pending; round 1, after `import-from-fork` (both change `measure.py`) |
| 14 | `onboard.md` | `plans/distribution.md` | Pending; round 2; needs `rules` |
| 15 | `rules-size-budget.md` | — | Pending; round 3, or folded into `final-review` |
| 16 | `os-sandbox-trial.md` | — | Pending; after round 3 |

Requests in the same round run in parallel sessions, each in its own worktree (`claude --worktree <request>` from the
repository root), merged into `main` one at a time:

| Round | Requests |
| --- | --- |
| 0a | `merge-versioned-changelog`, alone: `developer` as the base, the versioned changelog and `/merge --main` |
| 0 | `import-from-fork`, alone, with its own minor release: the first real test of `aiwp update` |
| 1 | `rules`, `run-tools`, `prompt-log-results`, `gate-audit-gaps`, `work-status-docker-stacks`, `aiwp-remove`, `measure-quality-indicators` |
| 2 | `normalize-rules`, `fork-my-rules`, `tools-hub`, `onboard` |
| 3 | `final-review` (with `rules-size-budget` folded in or right before it), which releases the next version once, and tests the update of a real installed workspace dedicated to it |
| 4 | `os-sandbox-trial` |

Run a request in a new session opened at the repository root, one stage per session when a stage is large. A plan the owner
approves in a session is recorded at once, in English and in this format, in `done/`, with its row here. A delivered
request moves to `done/` (`git mv`, in the commit that closes it); its row stays here with the new path
and its State.
