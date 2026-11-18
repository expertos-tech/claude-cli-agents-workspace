# Functional request: the caw-layers check passes a layer whose product skill is missing

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Source: the review of `request-lifecycle.md` (2026-11-17), a RECOMMENDED finding.

## What

`tests/check.sh` `check_caw_layers` skips a `caw-<name>` whose `workspace/rules/skills/<name>/` does not exist, so a layer left pointing at a renamed or deleted product skill passes, and a layer under another name is never checked (BR-11, AC-6 of `request-lifecycle.md`).

## Where

`tests/check.sh`, `check_caw_layers`.

## Done when

Every `.claude/skills/caw-*/SKILL.md` whose body starts with `@` is checked: the target exists and the three sections are there; a same-named product skill with no `@` line in its `caw-` twin fails; the failure is shown on a broken layer.

## Effort

low

## Execution — 2026-11-18, merged into developer

- **Done:** `tests/check.sh` `check_caw_layers` treats as a layer every `.claude/skills/caw-*/SKILL.md` whose body
  starts with `@`, whatever its name: the target must exist and the three sections must be there; a `caw-<name>`
  with no `@` line next to a product skill `<name>` still fails; the FAIL line names the new rule (4f2e372). The
  root `CHANGELOG.md` entry of the check, still unreleased, now describes it; AC-6 of `qa/request-lifecycle.md` is met.
- **Decisions:** the `@` target is a path relative to the repository root, as the current layers write it. A
  `caw-*` skill with no `@` line and no product twin (`caw-check`, `caw-test-install`) is not a layer and is not
  checked.
- **Deviations:** none.
- **Done when:** met. Scenarios on fixtures (the function run against a scratch root): the real tree, a valid layer
  and a valid layer under another name pass; a target removed by a rename, a layer under another name with a missing
  target, a same-named twin with no `@` line, a missing section and an empty `@` line each fail with their line. A
  broken `caw-commit` in the clone made `tests/check.sh` print the problem, `FAIL caw-layers`, and exit 1.
- **Checks:** `bash -n` and shellcheck (container) on `tests/check.sh`; `bash tests/check.sh --base origin/developer
  --i18n-pending` passed (50 translations pending; script suites and repo-terms skipped: no script changed, no terms
  list).
- **Left:** nothing.
