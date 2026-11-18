---
name: merge
description: "Take the work of a clone in tmp/work/ into the base of its project (developer) through the gate, writing the versioned CHANGELOG and moving its request to qa; with --main, validate everything in qa and release the project (every repo, the root changelog, the tags); with --hotfix, fix an error of production from main as a patch version, then merge main down into developer. No argument: the clone of this session. Only the person runs it: the model never invokes it, and the gate refuses its phase 2 unless the person typed /merge in this session."
argument-hint: "[<work>/<clone> [request file] | --main <project> [instructions] | --hotfix <project> <description>]"
disable-model-invocation: true
model: claude-opus-5-5
effort: high
---

Arguments: `$ARGUMENTS`. Reply in the language of the conversation. This is the only way into `projects/` (`rules/git.md` "Gate"), and it runs only on the person's order: the `UserPromptSubmit` hook records each `/merge` the person types, and `gate --merge` refuses with no record from this session. Never ask the person to let you run it; at the end of a task, offer it as a way out (`rules/git.md` "Waves"). The request lifecycle is `rules/git.md` "Requests".

## Which work

- No argument: the clones this session opened (their paths are in the conversation). None named: `bash scripts/aiwp-cmds.sh status`; exactly one clone with commits ahead of its base → that one; several → ask which, in one question; none → say there is nothing to merge and stop. A session with no clone worked on no project: nothing to merge.
- `<work>/<clone>`: a clone made by `bash scripts/aiwp-cmds.sh open`. Request file: the request of `custom/requests/` the work came from; none given: the one the session ran, else the request as the human typed it in this conversation. No request at all: every item of the audit becomes a question in step 6.
- `--main <project> [instructions]`: the release of the project: "Release" below.
- `--hotfix <project> <description>`: an error in production, fixed from `main`: "Hotfix" below.

A repo whose remote `main` holds a commit its remote `developer` does not (a hotfix not merged down yet, after a cancel or a crash, or a release merged by a pull request with a merge commit) is blocked: the gate refuses every merge into its `developer` and `release` refuses its release, with the reason. Clear it first: "Hotfix" step 12, then go on.

## Merge into developer

1. Bring the base in: `bash scripts/aiwp-cmds.sh run <work>/<clone> -- git fetch -q origin`, then `... -- git merge --no-edit origin/<base>`. A conflict: resolve it in the clone and commit; a conflict that changes a business rule goes to step 6.
2. CHANGELOG (`rules/docs.md` "CHANGELOG.md"): write the section of what enters, from `git log` and `git diff` of `origin/<base>..HEAD` in the clone, for each component whose `CHANGELOG.md` covers a changed file, and in the root `CHANGELOG.md` (created when missing) for the files no other one covers. Commit it alone (`docs(changelog): <version> unreleased`). Only documentation of form changed (spelling, formatting, a link): no entry.
3. The full test command of the project: its README "How to test", else the test script of its manifest. Only documentation changed (`*.md`, `*.mmd`, `docs/`): `--docs-only` instead. A normalization (`feat/ai-workspace-migration`, from `/normalize-projects`) the human chose to go on untested: `--untested` instead; the gate judges it on what it adds (`rules/git.md` "Gate").
4. Phase 1: `bash scripts/aiwp-cmds.sh gate <work>/<clone> --test "<command>"`. A failure: fix in the clone (commit; the push is automatic) and run phase 1 again. A conflict with the updated base: resolve it in the clone, fix the CHANGELOG section if the conflict was there, commit, run phase 1 again.
5. Review against the request (`rules/review.md`): only the difference that enters, the range phase 1 printed (`origin/<base>..<sha>`, to read with `git -C <clone> diff`). Its code and configuration go to one `reviewer` subagent with effort `xhigh`, its documents to another with effort `high`, in parallel (one of them when the range holds only one kind); clean context, read-only. Brief of each: its part of the range, the request, the audit file phase 1 printed (`tmp/work/<work>/gate-<clone>.md`), and what phase 1 already verified (do not re-run it); the three questions of `rules/review.md` "How", plus a CHANGELOG entry that misdescribes the change.

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
4. **Final review** (`rules/review.md`), one review of the project, on everything since the last tag of each repo (`v<last>..HEAD` of each clone; no tag yet: `origin/main..HEAD`), widened to what the reviewer judges necessary. Code and configuration to one `reviewer` subagent with effort `xhigh`, documents to another with effort `high`, in parallel, clean context. Brief of each: its part of the ranges, every request of `custom/requests/qa/<project>/` with its Execution blocks, the `Unreleased` sections, and the results of step 3. The three questions of `rules/review.md` "How", against every qa request (every acceptance criterion, pending ones included; every Execution block the code contradicts; every qa request with no change behind it), plus the compatibility between the repos released together and those that stay, and the CHANGELOG.

   UNEXPLAINED changes and losses, failed acceptance criteria and failing checks are BLOCKERs.
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

## Hotfix

`/merge --hotfix <project> <description>`: the human found an error in production. The fix starts from the remote `main`, never from `developer`, so nothing not yet released reaches production; it is released as a patch version, then `main` is merged down into `developer`. Besides the release, this is the only way `main` receives a change. The request is the file of `custom/requests/` the human names, else the description, written as `custom/requests/<yyyy-mm-dd>-hotfix-<slug>.md` with a "Requested" section before step 3.

1. **The repo.** The repo of `projects/<project>` the error is in (the project's root repo, a repo inside it at any depth, or the one repo it is); unclear from the description and the code: ask, in one question. A repo without `main`: stop, say so, create nothing. A repo already blocked (above): clear it first (step 12).
2. **The version:** the newest released version of the repo (its newest `vX.Y.Z` tag, or the newest dated section of the `CHANGELOG.md` of `main`) with the patch bumped: `vX.Y.(Z+1)`. Its tag must be free (`git -C <repo> tag -l` and `ls-remote --tags origin`), else stop and tell the human.
3. **The clone:** `bash scripts/aiwp-cmds.sh open <yyyy-mm-dd>-hotfix-<slug> <repo> --from-main --branch fix/<slug>`. It starts from the remote `main` and its base is `main`.
4. **The fix**, only what the error needs, with a test that fails without it. The fix already exists on `developer`: take only that commit (`git cherry-pick -x <sha>`) when it depends on nothing not yet released; otherwise write it again from `main`. Nothing else, even when it is right: it waits for the next release.
5. **CHANGELOG** of `main` (`rules/docs.md` "CHANGELOG.md"): a dated section `## [X.Y.(Z+1)] - YYYY-MM-DD` (today) above the newest dated one, with `### Fixed`; commit it alone (`docs(changelog): release X.Y.Z`). A project with nested repos: the hotfix is per repo, and the project's root repo then gets its own patch version, in its own hotfix clone (steps 3 to 11), with the "Components" table.
6. **Phase 1 against `main`:** `bash scripts/aiwp-cmds.sh gate <work>/<clone> --test "<full test command>"` (the full tests, `validate.sh`, the scan and the audit, as in "Merge into developer" step 4). The gate refuses a branch that holds a commit of `developer` not on `main`.
7. **Review of the fix against `main`** (`rules/review.md`): everything since the last tag of the repo, widened to what the reviewer judges necessary; code and configuration with effort `xhigh`, documents with effort `high`, as in "Merge into developer" step 5. Brief: the error as the human described it (the request), the audit, the range phase 1 printed, and what phase 1 verified. The three questions of `rules/review.md` "How"; for question 2 every change beyond the error is a BLOCKER, even when it is right, and so is a cherry-picked commit (cherry picked from ...) that depends on anything not on `main` (a function, a schema, a configuration, an API).

   A BLOCKER: fix it in the clone (a cherry-pick that depends on unreleased work: write the fix again from `main`) and go back to step 6. A RECOMMENDED: a `ready` request in `custom/requests/`, as in "Merge into developer" step 5.
8. **The human's OK**, in one round, with no BLOCKER open: what goes into `main` (sha, version, the fix). And how `main` publishes (`rules/git.md` "Waves"): a pipeline of the repo deploys from it, or its docs say so → `main` publishes by itself, and the same round asks "publish to production with the fix?". No OK, or no to publishing: `main` does not change and receives no push; the fix waits on its branch (on the remote), the request stays pending with where it stopped (`rules/git.md` "Waves" step 2), and the flow stops here.
9. **Into `main`:** `bash scripts/aiwp-cmds.sh hotfix <work>/<clone> <sha>` with the sha phase 1 printed (`guard-bash` asks): the fast-forward of the remote `main`, then the local one. "moved after phase 1": back to step 6. A protected `main` refuses the push: `--pr-if-refused` opens a pull request `fix/<slug>` → `main`, and the tag waits for its merge (no command does it yet: never `hotfix-tag`). After the merge, go on from step 10 without `hotfix-tag` (the human tags the commit of `main` by hand, if publishing), then steps 11 and 12.
10. **The publication:**
    - `main` publishes by itself (the human said yes in step 8): the push was the publication; now `bash scripts/aiwp-cmds.sh hotfix-tag <repo> vX.Y.Z` (`guard-bash` asks).
    - It does not: say `main` received the fix, then ask "publish to production with the fix?". Yes: `hotfix-tag <repo> vX.Y.Z`, then the project's own publication step, as its docs say, on the human's order. No: no tag; go on.
11. **The request to qa:** its `## Execution` block (as in "Merge into developer" step 8), with the line `Merge into developer pending.`, then moved to `custom/requests/qa/<project>/`; commit and push `custom/`.
12. **Down into `developer`.** Say that `main` is now merged into `developer`, and do it; the only option offered is to go on. `bash scripts/aiwp-cmds.sh hotfix-down <repo>` (`guard-bash` asks):
    - clean: a standard merge commit on `developer`, pushed; no new branch and no tests (the fix was tested before `main`; a break that only shows with the unreleased work is caught by the full tests of the next `/merge` into `developer` or of the release).
    - a conflict, or a fix that must be adapted to the code on `developer` (another API, a moved file, a refactor): `bash scripts/aiwp-cmds.sh open <work> <repo> --branch fix/<slug>-developer` (from `developer`), `git fetch origin main` and `git merge origin/main` in it, resolve every conflict and adapt the fix so the error stays fixed on `developer` too, then "Merge into developer" steps 3 to 7, with the review of the resolution (step 5) and no CHANGELOG step: in `CHANGELOG.md` the `Unreleased` section of `developer` stays on top and the dated patch section goes below it; an `Unreleased` version not above the patch takes the next one (`rules/docs.md`). Ask the human only when the resolution changes a business rule.

    Never a rebase or a force push; `main` and its tag never change on the way down, and no other branch is touched: every work branch gets the fix through its own `/merge`, whose step 1 merges the updated `developer`.
13. **The request to done:** once `developer` holds `main` (the merge pushed), move it to `custom/requests/done/<project>/` with `Released in <project> vX.Y.(Z+1)` (or `Not published: vX.Y.(Z+1) on main without a tag`), replacing `Merge into developer pending.`; commit and push `custom/`. `bash scripts/aiwp-cmds.sh close <work>`.
14. Summary: the version, what entered `main` (sha) and `developer` (sha, clean or resolved), the tag and the publication, the review with its classification, the checks with their results, the request file.

A cancel, a crash or another session between steps 9 and 12 leaves the repo blocked, computed from git: every `/merge` into its `developer` and its release are refused until step 12 is done.

Never merge with a failing check or an open BLOCKER. Never move `developer` or `main` by any other command. `main` moves only by `bash scripts/aiwp-cmds.sh release <repo>` and `hotfix`, `developer` is written outside the gate only by `hotfix-down`, and Terraform applies only by `bash scripts/aiwp-cmds.sh apply`, each on the human's explicit request.
