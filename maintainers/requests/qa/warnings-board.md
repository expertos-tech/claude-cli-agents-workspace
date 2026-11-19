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

---

## Execution — 2026-11-18, merged into developer

Done, by step:

- Step 1, the product (medium): `a88825e`. `workspace/rules/security.md` "Warnings": the numbered format with
  "Why", "Risk" (`HIGH`, `MEDIUM`, `LOW`, with their meaning) and "Suggest" with the recommended answer; a validator's
  one-line `WARNING:` stays its raw output, which the session writes in that format. `workspace/rules/git.md` "Waves":
  the warnings board as step 2 of the close, after the checkpoint of the work and before the resume point, the
  `custom/` checkpoint and the closing board; it stops until every warning is decided, and the closing board's
  `Warnings:` line lists the decisions; "Requests": the Execution block carries them. `/merge`: the warnings of the
  waves left open come first; the gate's and the review's warnings in the board as its step 6, before phase 2, with
  the questions of that step after it; the release lists the BLOCKERs as before and the warnings in the board; a
  hotfix's warnings in the board, answered `request` or `accept`. `workspace/rules/review.md`: the risk in each
  `[WARNING]` line, and the answered warnings among the authorizations. `AGENTS.md`, `/request` and
  `docs/usage.md` follow the order.
- Step 2, the maintenance (medium): `6851799`. `.claude/rules/process.md` step 6 points at the product's board with
  no copy, and the closing board's `Warnings:` line lists the decisions; the `git`, `security` and `review` layers
  keep the board where they replace or map the product's close and summary; `/caw-merge` "The warnings board", and
  its release and hotfix steps.
- Step 3, the proof (medium): no code. `596e740` and `f891fc4` bring `developer` in (a conflict in `/caw-merge`
  release step 7 with the review fixtures of `validators-follow-ups`: both kept).
- Changelog: `a589d58`, the 0.2.0 warnings entries adjusted.

Decisions taken while running:

- The board comes after the checkpoint of the work, so the work is on the remote while it waits; a `fix` answer is
  committed and pushed the same way, a `request` answer in the `custom/` checkpoint.
- A hotfix's board offers only `request` or `accept`: that flow already allowed nothing beyond the error.
- The reviewer's `[WARNING]` line gains the risk; `tests/review-fixtures.sh judge` reads only the tag, so it is
  unaffected.

Deviations from the request: none.

Acceptance criteria:

- AC-1: met: `workspace/rules/security.md` "Warnings" and `workspace/rules/git.md` "Waves" (the board, the stop, the
  answers, the decisions in the closing board).
- AC-2: met: `.claude/rules/process.md` step 6 points at the product rule, with no copy of the board.
- AC-3: in the text of `/merge` and `/caw-merge`; the run is evaluated after this merge, in its session, on the
  owner's decision W-1.
- AC-4: proven by two pairs of headless runs: in the clone (a stage of the maintenance) and in a test installation
  of the clone's tree (a wave of the product). Each first run ended with the board, numbered, a risk per warning and
  no closing board; each run resumed with the answers ended with the closing board listing `W-1 accept, W-2 request
  <file>`.
- AC-5: proven: `bash tests/check.sh --base origin/developer --i18n-pending`, rc 0.

Checks: the suite, rc 0 (54 translations pending; repo-terms skipped: no terms list, as accepted at the previous
merge); `bash tests/test-install.sh` PASS.

Warnings of the stage, decided by the owner: W-1 AC-3 proven only by text: accepted, evaluated after this merge; W-2
the product's wave close not run in an installed workspace: fixed (the second pair of AC-4 runs, no commit).

The merge review (medium): APPROVED_WITH_WARNINGS, no BLOCKER. Its warnings, in the warnings board before phase 2,
decided by the owner: W-3 the gate's comment and record 0005 still named the merge summary: fixed (`29baced`); W-4
`docs/releases.md` and `docs/maintenance.md` still said a warning is decided later: fixed (`347f319`). Found while
fixing: `/merge` step 6 sent a fixed warning to the return review, which `rules/review.md` keeps for the fixes of
BLOCKERs: corrected in `29baced`.

Left: AC-3 evaluated after this merge.

## Execution — 2026-11-18, AC-3 after the merge

The first merge entered `developer` at `58ead34`: `developer` had moved during phase 2, so it was merged into the
clone (one conflict, the QA table of `maintainers/requests/README.md`, both sides kept), the suite passed again, rc 0,
and phase 2 ran on that sha.

- AC-3: proven by two pairs of headless runs on that `developer`, each told the review returned two warnings:
  `/caw-merge` at the root, and `/merge` in a test installation of the same tree (`bash tests/test-install.sh` PASS).
  Each first run ended with the warnings board, numbered, a risk per warning, and stopped before phase 2; each run
  resumed with the answers went on to phase 2, the Execution block with the decisions and the summary, whose
  `Warnings:` line listed them (`W-1 accept, W-2 request <file>` for `/caw-merge`, `W-1 request <file>, W-2 accept`
  for `/merge`). The merge of this request had already done the same for real: its review's W-3 and W-4 were shown in
  the board and phase 2 waited for the owner's answers.

Checks: `bash tests/check.sh --base origin/developer --i18n-pending`, rc 0, at the merge.

Warnings: none.

Left: nothing.
