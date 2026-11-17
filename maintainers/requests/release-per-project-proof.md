# Functional request: Prove the release per project end to end

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Source: the review of `request-lifecycle.md` (2026-11-17), a RECOMMENDED finding.

## What

AC-3 of `request-lifecycle.md` (release part) has only skill text behind it: no run shows a `/merge --main <project>` that dates each repo's changelog, writes the root "Components" table and the production versions table. AC-1, AC-2 and AC-4 (the qa move, the findings question, an instruction conflict) are not proven by a run either.

## Where

A test installation with a root repo holding two nested repos and bare remotes.

## Done when

One recorded run proves AC-1 to AC-4; the result goes to the Execution block of `qa/request-lifecycle.md`.

## Effort

medium
