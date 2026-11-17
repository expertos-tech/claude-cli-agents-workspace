# Functional request: a size budget for what every session loads

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained, with the product in `workspace/`
(`AGENTS.md`, `rules/`, `tests/check.sh`). It changes the same texts as `final-review` (round 3 of
`maintainers/requests/README.md`), so it fits **round 3, merged into `final-review`** as an extra rule and criterion,
or right after it (decision 1). Running it earlier would be undone by `rules`, `import-from-fork` and the other
requests, which all add text.

## 1. Objective

The simplification plan the owner approved set two targets for the text loaded in every session: `AGENTS.md` "up to
about 700 words" (it was 3,462 words loaded per session then) and imperatives (MUST/NEVER) cut "from 523 to a few
dozen". The execution recorded both as not met, and they were never revisited. Today `workspace/AGENTS.md` has about
1,300 words and `AGENTS.md` plus `rules/` hold about 84 MUST/NEVER. The product also grew (gate, clones, `aiwp`, the
custom layer), so the target must be set again before it is enforced. This request sets the budget and keeps it with a
check in the suite.

## 3. Business rules

- BR-1: the budget covers what loads in every session: `AGENTS.md` and the rules without `paths:` (after the `rules`
  request, the effective `AGENTS.md` generated in `.claude/`). The numbers are decision 2.
- BR-2: reaching the budget moves text, never drops protection: a rule that a hook or script already enforces keeps
  one short line pointing to it ("prefer a hook or a tested script to more text", README "Get involved"); a topic rule
  moves to a `paths:` rule; examples and reasons move to `docs/`.
- BR-3: a check in `tests/check.sh` counts words and MUST/NEVER of the always-loaded set and fails above the budget,
  printing the numbers; a change that must exceed it updates the budget in the same commit, with the reason in the
  commit body.
- BR-4: the measurement report's "context of the first call" indicator is the way to confirm the effect; no new
  measurement is added.
- BR-5: translations are not affected (rules and `AGENTS.md` are English only).

## 4. Acceptance criteria

- AC-1: Given the repository after the change, then the check reports the always-loaded words and MUST/NEVER, both
  within the budget, and the suite passes.
- AC-2: Given a commit that adds 200 words to `AGENTS.md` without raising the budget, then `tests/check.sh` fails with
  the numbers.
- AC-3: Given every rule removed from the always-loaded set, then it is still enforced by a hook or script, or present
  in a `paths:` rule (listed in the report of the change).

## 7. Out of scope

- Changing what the hooks enforce.
- Rules loaded by `paths:` (no budget for them).

## Decisions for the owner

1. **Still wanted, and where.** Recommended: yes, as one more rule of `final-review` (it already removes duplicates
   and conflicts), not a separate run.
2. **The budget.** Recommended: `AGENTS.md` at most 1,000 words and at most 30 MUST/NEVER in the always-loaded set;
   the old 700 words was set before the gate, the clones and the installer existed.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Measure, move text to `paths:` rules, hooks or `docs/` | high | Touches the mandatory rules every session obeys |
| 2. The budget check in the suite | low | A small counting script |

The agents of each stage run with the stage's effort, passed in the call.
