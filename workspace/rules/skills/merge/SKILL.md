---
name: merge
description: "Take the work of a clone in tmp/work/ into the base of its project (developer) through the gate, writing the versioned CHANGELOG and moving its request to qa; with --main, validate everything in qa and release the project (every repo, the root changelog, the tags). No argument: the clone of this session. Use when a delivery is ready, or when the user asks to merge or release."
argument-hint: "[<work>/<clone> [request file] | --main <project> [instructions]]"
model: claude-opus-5-5
effort: high
---

Arguments: `$ARGUMENTS`. Reply in the language of the conversation. This is the only way into `projects/` (`rules/git.md` "Gate"). The request lifecycle is `rules/git.md` "Requests".

## Which work

- No argument: the clones this session opened (their paths are in the conversation). None named: `bash scripts/aiwp-cmds.sh status`; exactly one clone with commits ahead of its base → that one; several → ask which, in one question; none → say there is nothing to merge and stop. A session with no clone worked on no project: nothing to merge.
- `<work>/<clone>`: a clone made by `bash scripts/aiwp-cmds.sh open`. Request file: the request of `custom/requests/` the work came from; none given: the one the session ran, else the request as the human typed it in this conversation. No request at all: every item of the audit becomes a question in step 6.
- `--main <project> [instructions]`: the release of the project: "Release" below.

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

   A defect (BLOCKER, `rules/review.md`): fix it in the clone and go back to step 4. A RECOMMENDED finding never blocks: it becomes a `ready` request in `custom/requests/` (adjustment size), listed in the summary.
6. Ask the human, in one round, only when there is at least one of: an UNEXPLAINED item; a destruction outside this machine (cloud resource, data that is not local); a base that publishes to production. Each question names the item and what it removes or changes. Nothing of that: no question.
7. Phase 2, with the sha phase 1 printed: `bash scripts/aiwp-cmds.sh gate --merge <work>/<clone> <sha>`. "moved after phase 1": go back to step 4.
8. The request to qa (`rules/git.md` "Requests"): append its `## Execution` block (done by step with the commits, decisions taken while running, deviations, each acceptance criterion proven / pending / failed, checks, left), then move it to `custom/requests/qa/<project>/` (`git -C custom mv`; a request with no file: write `qa/<project>/<yyyy-mm-dd>-<kebab-slug>.md` with "Requested" and "Execution"). `<project>` is the project the release will name: the top repo of the clone's source in `projects/`. Commit and push `custom/` by path.
9. `bash scripts/aiwp-cmds.sh close <work>` when the work folder has nothing else open.
10. Summary: what entered `developer` (sha), the version and the CHANGELOG entries, the tests and checks with their results, the audit items with their classification, the human's answers, the qa file, and the requests made of the RECOMMENDED.

## Release

`/merge --main <project> [instructions]` releases the project `projects/<project>`: every repo in it (the project's root repo and each repo inside it, at any depth; or the one repo it is) that has an `Unreleased` section on `developer`, then the project version in its root repo. No such section anywhere: say there is nothing to release and stop. For each repo, `vX.Y.Z` is its version and `X-Y-Z` the same with hyphens; its tag must be free (`git -C <repo> tag -l vX.Y.Z` and `ls-remote --tags origin vX.Y.Z` both empty), else stop before step 1 and tell the human.

1. **The plan.** State what will be released (each repo and version, the project version) and what stays on `developer`. With instructions (free text after the arguments): what they change in that default. Then every conflict: anything that leaves `main` or production in a state that matches no version, or breaks a dependency between the repos (an API, a contract, a migration, a shared configuration one side needs and the other does not ship). For each conflict, its concrete effect and the options, for example:

   ```text
   Instruction understood: release billing-api only; billing-web stays on developer.

   Conflict: billing-web on developer calls GET /invoices/{id}/pdf, which billing-api adds in this release.
   Releasing only the back is safe for production (the current front does not call it); releasing the front
   alone later is safe only after this API is in production.
     (1) Go on with billing-api only   (2) Release both   (3) Cancel
   ```

   Ask once and wait. No conflict: one confirmation of the plan.
2. **Release clones.** For each repo of the plan: `bash scripts/aiwp-cmds.sh open <yyyy-mm-dd>-release-<project> <repo> --branch fix/release-vX-Y-Z`.
3. **Full check**, in each clone: the full test command of the repo and `bash scripts/validate.sh --path <clone>` (a `verifier` subagent may run them).
4. **Final review** (`rules/review.md` "Release"), on `origin/main..HEAD` of each clone, as one review of the project, in this order, each a `reviewer` subagent with a clean context:
   1. **What enters and what leaves**, effort `high`. Brief: the ranges, every request of `custom/requests/qa/<project>/` with its Execution blocks, the `Unreleased` sections, and the results of step 3. It answers: the inventory of the ranges (added, changed, removed: files, endpoints, commands, options, functions, tests, migrations, configuration, documented behavior), each REQUESTED (which qa request), CONSEQUENCE (of what) or UNEXPLAINED; every qa request with no change behind it; every Execution block the code contradicts; every acceptance criterion of every qa request, pending ones included: proven or not; every regression (something that worked on `main` and is removed or changed with no request behind it; a test removed, skipped or weakened; a protection weaker); every change that does not do what its request asked, does more, or reads it wrong; the compatibility between the repos released together and those that stay; every CHANGELOG entry with no change behind it, and every change a user would notice with no entry.
   2. **General**, effort `medium`. Brief: the whole tree of each clone and the ranges. It reads everything once for contradictions between docs and code, references to what no longer exists, configuration that disagrees, leftovers (TODO, debug output, temporary files).

   UNEXPLAINED removals and regressions, failed acceptance criteria and failing checks are BLOCKERs.
5. **The findings, once.** Gather every finding of steps 3 and 4, of every qa request, in one list, and ask per finding:

   ```text
   qa/billing/2026-11-18-add-login.md
     [BLOCKER] AC-3 not proven: no test covers the expired token
       (1) Fix now, in the release clone   ← strongly recommended
       (2) Create a request with the fix   (the release stops: a BLOCKER cannot ship)
     [RECOMMENDED] the README still names the old endpoint
       (1) Fix now, in the release clone
       (2) Create a request with the fix   (custom/requests/, ready; the release goes on)
   ```

   (1): fix in the release clone, commit by commit; a fix of something of this version adds no CHANGELOG entry and adjusts the original entry only when the described behavior changed (`rules/docs.md`); then rerun step 3 and review the fixes (the same rounds, only the fixes). (2): write the request; a BLOCKER sent to a request stops the release here.
6. **Versions.** In each clone, `## [X.Y.Z] - Unreleased` becomes `## [X.Y.Z] - YYYY-MM-DD` (today) in each CHANGELOG that has it; commit (`docs(changelog): release X.Y.Z`). The project's root repo: its own version (`rules/docs.md`: the largest bump of the release), the dated section with the "Components" table, and the production versions table of its `README.md`; commit. A project with no root repo (a plain folder of repos): no project version; say so in the summary.
7. **Into `developer`**, each clone: steps 3, 4, 6 and 7 of "Merge into developer" (the review there is step 4 here).
8. **Into `main`**, the human having asked by running `--main`: for each repo, the internal ones first and the root repo last, `bash scripts/aiwp-cmds.sh release <repo> --tag vX.Y.Z` (`guard-bash` asks). The remote refuses the push of `main` (a protected branch): `--pr-if-refused`, and say that the tag is not created: after that pull request is merged, the human tags its merge commit on `main` (no command does it yet).
9. **Requests to done:** each file of `custom/requests/qa/<project>/` the release covers moves to `custom/requests/done/<project>/`, with the line `Released in <project> vX.Y.Z (<repo> vA.B.C, ...)`; commit and push `custom/`.
10. `bash scripts/aiwp-cmds.sh close <yyyy-mm-dd>-release-<project>`.
11. Summary: the project version and each repo's, what entered `main` (sha), the tags, the inventory of the final review with its classification, the findings and what was done with each, the requests created, the checks with their results.

Never merge with a failing check or an open BLOCKER. Never move `developer` or `main` by any other command. `main` moves only by `bash scripts/aiwp-cmds.sh release <repo>`, and Terraform applies only by `bash scripts/aiwp-cmds.sh apply`, both on the human's explicit request.
