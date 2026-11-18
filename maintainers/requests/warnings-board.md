# Functional request: the warnings board before the closing board

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**State:** ready. **Where it runs:** a work clone of this repository; it changes the product's rules and skills
(`workspace/rules/security.md`, `workspace/rules/git.md`, `workspace/rules/skills/merge/SKILL.md` and the skills that
close a wave) and the maintenance (`.claude/rules/process.md`, `.claude/skills/caw-merge/SKILL.md`). Source: the
owner, 2026-11-18: warnings get lost in one line of the closing board, and whoever passes by the session does not see
that a decision is waiting.

## 1. Objective

Before a session closes, its warnings come first, in a board of their own, numbered, each with what it is, why, its
level of risk and impact, and a suggestion. The person decides each one; only then the closing board appears. The same
in the product and in the maintenance, and in the summary of `/merge` and `/caw-merge`.

## 3. Business rules

- BR-1: the warning format (`workspace/rules/security.md` "Warnings", the one source; the maintenance inherits it
  through its layer) gains a risk level: what was seen, why it may be a problem, the risk (`HIGH`, `MEDIUM`, `LOW`)
  with its impact, and the suggestion, with the recommended option.
- BR-2: risk levels: `HIGH` can reach the public or production, or lose data; `MEDIUM` means rework or a broken flow
  later; `LOW` is hygiene or quality.
- BR-3: a wave or stage that gathered warnings ends with the warnings board, and stops there: no closing board until
  the person has decided every warning. The board stays on screen until the person answers; there is no fallback for a
  run with no person (the person runs the merge afterwards in any case). No warnings: the closing board comes straight,
  with `Warnings: none`.
- BR-4: the board looks like the closing board, so it stands out. Its labels stay in English; its values are in the
  language of the conversation:

  ```text
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ⚠ WARNINGS: <n> — decide each one before the closing
  W-1  <what was seen>
       Why:      <why it may be a problem>
       Risk:     <HIGH | MEDIUM | LOW> — <impact>
       Suggest:  <what the person can do> (recommended: fix | request | accept)
  W-2  ...
  ➜ Answer: W-1 fix|request|accept, W-2 fix|request|accept
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ```

- BR-5: the answers: `fix` (done now, then verified again), `request` (a `ready` request with the warning as its
  source), `accept` (the risk kept). After them, the closing board's `Warnings:` line lists the decision of each one
  (`W-1 accept, W-2 fix in <sha>, W-3 request <file>`), and `/merge` (`/caw-merge`) carries them into the Execution
  block and gives them to the reviewer as authorizations.
- BR-6: the summary of warnings of `/merge` and `/caw-merge` (the review's warnings, the gate's) uses the same board,
  numbered, and the merge goes on only after every decision. A wave closed with warnings still open: the merge shows
  them first, in the same board.

## 4. Acceptance criteria

- AC-1: Given the product rules, then `workspace/rules/security.md` "Warnings" holds the format with the risk level
  and its three levels, and `workspace/rules/git.md` "Waves" holds the warnings board before the closing board, with
  the stop until every decision (BR-1 to BR-5).
- AC-2: Given the maintenance rules, then `.claude/rules/process.md` step 6 follows the same order, by pointing at the
  product rule, with no copy of the board (the layering of `rules-as-product-layers`).
- AC-3: Given the merge skills, then `/merge` and `/caw-merge` show their warnings in the board and wait for every
  decision before going on (BR-6).
- AC-4: Given a headless run of a stage closing with two warnings, then the output is the warnings board, numbered,
  with a risk level per warning, and no closing board; given the answers, the closing board lists each decision.
- AC-5: `bash tests/check.sh --base origin/developer --i18n-pending` passes.

## 7. Out of scope

- What counts as a warning or a hard rule (`workspace/rules/security.md` "Hard rules" stays as it is).
- The labels and lines of the closing board other than `Warnings:`.

## 11. Steps and effort

| Step | Effort | Why |
| --- | --- | --- |
| 1. Product: `security.md` "Warnings" (BR-1, BR-2), `git.md` "Waves" (BR-3 to BR-5), `/merge` and the skills that close a wave (BR-6) | medium | Rules and skills |
| 2. Maintenance: `.claude/rules/process.md` step 6 and `/caw-merge` (AC-2, AC-3) | medium | Layers |
| 3. Proof: AC-4 headless, the suite | medium | The end-to-end check |

The subagents of each step run with the step's effort, passed in the call.

## Assumed decisions

- Decided by the owner (2026-11-18): the board stays until the person decides, with no fallback for a run with no
  person ("o quadro fica parado na tela até o humano resolver, afinal ele vai rodar o merge depois de qualquer
  forma"); `/merge` and `/caw-merge` use the same board ("sim, pode seguir o mesmo padrão").
- Assumed: the three levels and their meaning (BR-2); the three answers, the same the merge review already offers.
