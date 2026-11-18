# Functional request: a closing board for maintenance work

**Project:** claude-cli-agents-workspace

**State:** done in a session. Size: adjustment. Created 2026-11-18 from the owner's words, in the session of
`process-merge-check-command`.

## Requested

The owner asked why a maintenance session no longer ends with the closing board of the product
(`workspace/rules/git.md` "Waves" step 4), and asked for the same board in maintenance, on the open work branch.

## Execution — 2026-11-18, merged into developer

- **Done:** `.claude/rules/process.md` step 6 ends with a closing board instead of a free short report (4a5e5be):
  fixed English labels, values in the language of the conversation, the last thing of the reply. Adapted from the
  product's: `STAGE CLOSED: <request> — <stage>`, `Request:` instead of `Prompt:`, and `➜ Next:` with the command to
  run and where. `/caw-request` already ends with "the report of `.claude/rules/process.md` step 6", so it needs no
  change.
- **Decisions:** the product's board was never part of maintenance (0.1.0 included): the root session does not load
  `workspace/AGENTS.md` or `workspace/rules/git.md` (`claudeMdExcludes`).
- **Done when:** the next `/caw-request` closes with the board; proven in this session's reply, by hand.
- **Checks:** `bash tests/check.sh --base origin/developer --i18n-pending` passed; markdownlint-cli2 on a copy of
  `process.md`: 0 issues.
- **Left:** nothing.
