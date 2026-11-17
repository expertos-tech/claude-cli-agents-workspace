---
name: merge
description: "Take the work of a clone in tmp/work/ into the base of its project (developer) through the gate, writing the versioned CHANGELOG; with --main, publish that version into main with a tag. No argument: the clone of this session. Use when a delivery is ready, or when the user asks to merge or release."
argument-hint: "[<work>/<clone> [request file] | --main <repo>]"
model: claude-opus-5-5
effort: high
---

Arguments: `$ARGUMENTS`. Reply in the language of the conversation. This is the only way into `projects/` (`rules/git.md` "Gate").

## Which work

- No argument: the clones this session opened (their paths are in the conversation). None named: `bash scripts/aiwp-cmds.sh status`; exactly one clone with commits ahead of its base → that one; several → ask which, in one question; none → say there is nothing to merge and stop. A session with no clone worked on no project: nothing to merge.
- `<work>/<clone>`: a clone made by `bash scripts/aiwp-cmds.sh open`. Request file: the prompt of `custom/prompts/` the work came from; none given: the one the session ran, else the request as the human typed it in this conversation. No request at all: every item of the audit becomes a question in step 6.
- `--main <repo>`: the release of `developer` into `main`, always a new version: "Release" below.

## Merge into developer

1. Bring the base in: `bash scripts/aiwp-cmds.sh run <work>/<clone> -- git fetch -q origin`, then `... -- git merge --no-edit origin/<base>`. A conflict: resolve it in the clone and commit; a conflict that changes a business rule goes to step 6.
2. CHANGELOG (`rules/docs.md` "CHANGELOG.md"): write the section of what enters, from `git log` and `git diff` of `origin/<base>..HEAD` in the clone, for each component whose `CHANGELOG.md` covers a changed file, and in the root `CHANGELOG.md` (created when missing) for the files no other one covers. Commit it alone (`docs(changelog): <version> unreleased`). Only documentation of form changed (spelling, formatting, a link): no entry.
3. The full test command of the project: its README "How to test", else the test script of its manifest. Only documentation changed (`*.md`, `*.mmd`, `docs/`): `--docs-only` instead. A normalization (`feat/ai-workspace-migration`, from `/normalize-projects`) the human chose to go on untested: `--untested` instead; the gate judges it on what it adds (`rules/git.md` "Gate").
4. Phase 1: `bash scripts/aiwp-cmds.sh gate <work>/<clone> --test "<command>"`. A failure: fix in the clone (commit; the push is automatic) and run phase 1 again. A conflict with the updated base: resolve it in the clone, fix the CHANGELOG section if the conflict was there, commit, run phase 1 again.
5. Review against the request: one `reviewer` subagent, clean context, effort `high`, read-only. Brief: the request, the audit file phase 1 printed (`tmp/work/<work>/gate-<clone>.md`), the range it printed (`origin/<base>..<sha>`, to read with `git -C <clone> diff`), and what phase 1 already verified (do not re-run it). Ask for this only:

   ```text
   For each item of the audit and each acceptance criterion of the request, classify: REQUESTED (the request asks for
   it), CONSEQUENCE (needed by something the request asks, say which), or UNEXPLAINED. Then report only: a correctness
   defect; a security or data-loss problem; an acceptance criterion not met or that no test proves; a removed or
   weakened test with no reason in the request; a CHANGELOG entry that misdescribes the change. For each: path:line,
   a concrete failure scenario, the fix.
   ```

   A defect (BLOCKER, `rules/review.md`): fix it in the clone and go back to step 4. A RECOMMENDED finding never blocks: fix it when cheap, else list it in the summary.
6. Ask the human, in one round, only when there is at least one of: an UNEXPLAINED item; a destruction outside this machine (cloud resource, data that is not local); a base that publishes to production. Each question names the item and what it removes or changes. Nothing of that: no question.
7. Phase 2, with the sha phase 1 printed: `bash scripts/aiwp-cmds.sh gate --merge <work>/<clone> <sha>`. "moved after phase 1": go back to step 4.
8. `bash scripts/aiwp-cmds.sh close <work>` when the work folder has nothing else open.
9. Summary: what entered `developer` (sha), the version and the CHANGELOG entries, the tests and checks with their results, the audit items with their classification, the human's answers, and the RECOMMENDED left.

## Release

`/merge --main <repo>` publishes the version of the `Unreleased` header of the root `CHANGELOG.md` of `projects/<repo>` on `developer` (no such header: say there is nothing to release and stop; component sections are dated with it, and only the root version is tagged). `vX.Y.Z` is that version; `X-Y-Z` the same with hyphens. The tag must be free: `git -C projects/<repo> tag -l vX.Y.Z` and `git -C projects/<repo> ls-remote --tags origin vX.Y.Z` both empty; else stop before step 1 and tell the human (the version is renumbered by the rules of `rules/docs.md`).

1. Open the release clone, always: `bash scripts/aiwp-cmds.sh open <yyyy-mm-dd>-release-vX-Y-Z <repo> --branch fix/release-vX-Y-Z`.
2. Full check, in the clone: the project's full test command and `bash scripts/validate.sh --path <clone>` (a `verifier` subagent may run them). A failure is a BLOCKER of step 4.
3. Final review (`rules/review.md` "Release"), on `origin/main..HEAD` of the clone, in this order, each a `reviewer` subagent with a clean context:
   1. **What enters and what leaves**, effort `high`. Brief: the range, the requests the version delivers (the prompts of `custom/prompts/archive/` and the requests named in the commits since the last tag, else the human's words), the `Unreleased` sections, and the result of step 2. It answers: the inventory of the range (added, changed, removed: files, endpoints, commands, options, functions, tests, migrations, configuration, documented behavior), each REQUESTED (which request), CONSEQUENCE (of what) or UNEXPLAINED; every regression (something that worked on `main` and is removed or changed with no request behind it; a test removed, skipped or weakened; a protection weaker); every change that does not do what its request asked, does more, or reads it wrong; every CHANGELOG entry with no change behind it, and every change a user would notice with no entry.
   2. **General**, effort `medium`. Brief: the whole tree of the clone and the range. It reads everything once for contradictions between docs and code, references to what no longer exists, configuration that disagrees, leftovers (TODO, debug output, temporary files).

   UNEXPLAINED removals and regressions are BLOCKERs. Fix every BLOCKER in the release clone, commit by commit, rerun step 2 and review the fix. A fix of something that entered this same version adds no CHANGELOG entry; it adjusts the original entry only when the described behavior changed (`rules/docs.md`). A RECOMMENDED never blocks: list it in the summary.
4. Date the version: `## [X.Y.Z] - Unreleased` becomes `## [X.Y.Z] - YYYY-MM-DD` (today) in each CHANGELOG that has it; commit (`docs(changelog): release X.Y.Z`).
5. Into `developer`: steps 3, 4, 6 and 7 of "Merge into developer" with this clone (step 2 there is replaced by step 4 here; the review there by step 3 here).
6. Into `main`, the human having asked by running `--main`: `bash scripts/aiwp-cmds.sh release <repo> --tag vX.Y.Z` (`guard-bash` asks). The remote refuses the push of `main` (a protected branch): `--pr-if-refused`, and say that the tag `vX.Y.Z` is not created: after that pull request is merged, the human tags its merge commit on `main` (no command does it yet).
7. `bash scripts/aiwp-cmds.sh close <yyyy-mm-dd>-release-vX-Y-Z`.
8. Summary: the version, what entered `main` (sha), the tag, the inventory of the final review with its classification, the regressions found and fixed, the checks with their results, and the RECOMMENDED left.

Never merge with a failing check or an open BLOCKER. Never move `developer` or `main` by any other command. `main` moves only by `bash scripts/aiwp-cmds.sh release <repo>`, and Terraform applies only by `bash scripts/aiwp-cmds.sh apply`, both on the human's explicit request.
