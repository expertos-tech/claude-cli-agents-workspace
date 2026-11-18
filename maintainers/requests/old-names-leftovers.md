# Functional request: Old names left in a decision record and in pending requests

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Source: the review of `request-lifecycle.md` (2026-11-17), a RECOMMENDED finding.

## What

`workspace/docs/decisions/0001-base-design.md` (lines 11 and 16) still lists `/prompt` in the mandatory core and the backlog in the custom layer; pending requests keep old paths: `final-review.md` (`maintainers/backlog/`), `import-from-fork.md` (`rules/skills/prompt/SKILL.md`), `rules.md` (`/prompt`), `prompt-log-results.md` (`custom/prompts/log/sources.json`). AC-5 of `request-lifecycle.md`.

## Where

Those files.

## Done when

0001 gets a "partly superseded" status line per `workspace/rules/docs.md` "Decision records" (or a new record); the pending requests name the new paths.

## Effort

low
