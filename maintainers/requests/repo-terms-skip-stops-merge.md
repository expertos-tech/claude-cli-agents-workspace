# Functional request: A missing terms list lets the company-terms scan skip silently

**Project:** claude-cli-agents-workspace

**State:** idea. Size: adjustment. Source: the review of the caw-merge push fix (2026-11-17), a RECOMMENDED finding.

## What

With no terms list found (`AIWP_TERMS_FILE`, the workspace's `custom/core-terms.txt`, `workspace/custom/core-terms.txt`), `tests/check.sh` prints `SKIP repo-terms` and passes, so the push gate of `/caw-merge` does not scan for company terms.

## Where

`.claude/skills/caw-merge/SKILL.md` (push gate), `tests/check.sh`.

## Done when

`/caw-merge` stops on `SKIP repo-terms` and asks the owner for the terms list, or the owner decides it may go on without one.

## Effort

low
