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
