# Functional request: Work and release branches are pushed before the company-terms scan

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Source: the review of the caw-merge push fix (2026-11-17), a RECOMMENDED finding.

## What

`.claude/rules/git.md` pushes the work branch after each commit, and the release steps 3 and 4 of `/caw-merge` push before the strict suite: text reaches a public branch of the remote before any terms scan.

## Where

`.claude/rules/git.md` "Remote", `.claude/skills/caw-request/SKILL.md`, `.claude/skills/caw-merge/SKILL.md" "Release".

## Done when

A branch of this public repository is pushed only after a passing `tests/check.sh` on that commit, as the push gate of `/caw-merge` says.

## Effort

low
