---
name: merge
description: "Take the work of a clone in tmp/work/ into the base of its project (developer) through the gate: updated base, full tests, validate, secrets, the audit of what leaves the base, a clean-context review against the request, the human's answers when needed, and the fast-forward. Use when a delivery is ready, or when the user asks to merge."
argument-hint: "<work>/<clone> [request file]"
model: claude-opus-5-5
effort: high
---

Arguments: `$ARGUMENTS`. `<work>/<clone>`: a clone made by `bash scripts/aiwp-cmds.sh open`. Request file: the prompt of `custom/prompts/` the work came from; none given: the one the session ran, else the request as the human typed it in this conversation. No request at all: every item of the audit becomes a question in step 5.

This is the only way into `projects/` (`rules/git.md` "Gate"). Reply in the language of the conversation.

1. The full test command of the project: its README "How to test", else the test script of its manifest. Only documentation changed (`*.md`, `*.mmd`, `docs/`): `--docs-only` instead. A normalization (`feat/ai-workspace-migration`, from `/normalize-projects`) the human chose to go on untested: `--untested` instead; the gate judges it on what it adds (`rules/git.md` "Gate").
2. Phase 1: `bash scripts/aiwp-cmds.sh gate <work>/<clone> --test "<command>"`. A failure: fix in the clone (commit; the push is automatic) and run phase 1 again. A conflict with the updated base: resolve it in the clone, commit, run phase 1 again; a conflict that changes a business rule goes to step 5.
3. Review against the request: one `reviewer` subagent, clean context, effort `high`, read-only. Brief: the request, the audit file phase 1 printed (`tmp/work/<work>/gate-<clone>.md`), the range it printed (`origin/<base>..<sha>`, to read with `git -C <clone> diff`), and what phase 1 already verified (do not re-run it). Ask for this only:

   ```text
   For each item of the audit and each acceptance criterion of the request, classify: REQUESTED (the request asks for
   it), CONSEQUENCE (needed by something the request asks, say which), or UNEXPLAINED. Then report only: a correctness
   defect; a security or data-loss problem; an acceptance criterion not met or that no test proves; a removed or
   weakened test with no reason in the request. For each: path:line, a concrete failure scenario, the fix.
   ```

4. A defect (BLOCKER, `rules/review.md`): fix it in the clone and go back to step 2. A RECOMMENDED finding never blocks: fix it when cheap, else list it in the summary.
5. Ask the human, in one round, only when there is at least one of: an UNEXPLAINED item; a destruction outside this machine (cloud resource, data that is not local); a base that publishes to production. Each question names the item and what it removes or changes. Nothing of that: no question.
6. Phase 2, with the sha phase 1 printed: `bash scripts/aiwp-cmds.sh gate --merge <work>/<clone> <sha>`. "moved after phase 1": go back to step 2.
7. `bash scripts/aiwp-cmds.sh close <work>` when the work folder has nothing else open.
8. Summary: what entered `developer` (sha), the tests and checks with their results, the audit items with their classification, the human's answers, and the RECOMMENDED left.

Never merge with a failing check or an open BLOCKER. Never move `developer` or `main` by any other command. `main` moves only by `bash scripts/aiwp-cmds.sh release <repo>`, and Terraform applies only by `bash scripts/aiwp-cmds.sh apply`, both on the human's explicit request.
