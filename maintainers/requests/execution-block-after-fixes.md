# Functional request: The Execution block is written before the results it records

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Source: the review of the caw-merge push fix (2026-11-17), a RECOMMENDED finding.

## What

In `/caw-merge` the Execution block is committed before phase 1 and the review, so it states results nobody has seen yet, and nothing says to update it after a failed run, a fix or a BLOCKER.

## Where

`.claude/skills/caw-merge/SKILL.md`, and the product's step 8 if the same order applies.

## Done when

After any fix the block is updated before phase 1 runs again; its checks name the commands, confirmed by the passing run.

## Effort

low
