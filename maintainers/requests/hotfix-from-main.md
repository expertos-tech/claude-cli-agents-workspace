# Functional request: hotfix from main

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**State:** ready. Size: feature. Drafted 2026-11-17 from the owner's prompt, adapted to this repository and the
product.

**Where it runs:** at the repository root: the product (`/merge`, `aiwp-cmds.sh`, `aiwp-gate.sh`, `guard-bash`) and
the maintenance (`/caw-merge`). It builds on `request-lifecycle.md` (the lifecycle, the release per project, the push
gate).

## 1. Objective

When the human finds an error in production, a flow fixes it from `main`, passes the approvals, releases it as a
patch version, and then brings the fix down to `developer`. The fix never starts from `developer`, so
nothing not yet released reaches production. Besides the release (`--main`), this flow is the only way `main` receives
a change. It works for the projects of an installed workspace (`/merge --hotfix`) and for this repository
(`/caw-merge --hotfix`).

## 3. Business rules

- BR-1: The human starts the flow with the project and the description of the error (`/merge --hotfix <project>
  <description>`; here `/caw-merge --hotfix <description>`). Product: any repo of the project that has `main`, a
  nested repo included. A repo without `main`: the flow stops and says so.
- BR-2: The fix branch is `fix/<kebab-slug>`, created from the remote `main` (production) in a clone under
  `tmp/work/<yyyy-mm-dd>-hotfix-<slug>/`; never from `developer` or another branch. Product: `aiwp-cmds.sh open`
  creates it from `main` on request (assumed decision). Here: `git clone --local`, `switch -c fix/<slug>
  origin/main`.
- BR-3: The fix holds only what the bug needs: the review classifies every change of `main..fix` against the error
  described; any change with no link to it is a BLOCKER, even when it is right.
- BR-4: When the fix already exists on `developer`, the fix branch may take only that commit (`git cherry-pick`), when
  it depends on nothing not yet released; otherwise the fix is written again from `main`. The review checks that
  dependency.
- BR-5: The hotfix is a patch version: the newest released version with the patch bumped (`vX.Y.Z` → `vX.Y.(Z+1)`),
  written in the fix branch as a dated section of the `CHANGELOG.md` of `main`. Here, only a fix to the product
  (`workspace/`, `install.sh`) is a hotfix: it bumps `workspace/VERSION` and both changelogs (the root one gets a patch
  section that links the release); a maintenance-only fix follows the normal flow through `developer` (assumed
  decision).
- BR-6: Before `main`, two approvals in this order: the gate against `main` (the full tests and `validate.sh` in the
  product; here the strict suite from the last tag and the test installation) with a clean-context review of the fix
  against `main` (effort high: it touches production), with no BLOCKER open; then the explicit OK of the human. With
  either missing, `main` does not change and receives no push. The push gate applies: what is pushed is the sha the
  suite judged.
- BR-7: Into `main` and the publication, by what pushing `main` does in the project (`workspace/rules/git.md`
  "Waves": a base that publishes to production):
  - `main` publishes by itself (a pipeline of the repo deploys from it, or its docs say so): pushing `main` is the
    publication, so the question "publish to production with the fix?" comes before the push. Yes: `main` moves to the
    fix by fast-forward, is pushed (the deploy runs), then the tag. No: `main` does not change, the fix waits on its
    branch, and nothing below starts.
  - `main` does not publish by itself: `main` moves to the fix by fast-forward and is pushed, the flow says it went
    well, then asks "publish to production with the fix?". Yes: the tag and the project's publication (here: the tag
    `vX.Y.(Z+1)` and the GitHub release, which the installers take). No: the tag is not created, and the flow goes on.

  A protected `main`: a pull request, and the known limit of `release-tag-after-pull-request.md`.
- BR-8: Right after the publication (or the answer no, in the second case of BR-7), the flow says it now merges `main`
  into `developer`, and does it. The only option offered is to go on.
- BR-9: The merge into `developer` (never a rebase or a force push; no other branch is touched: every work branch
  reaches `developer` only through `/merge`, whose phase 1 merges the updated `developer` into it):
  - clean (`git merge main` on `developer` with no conflict): a standard merge commit, pushed; no new branch and no
    further tests, since the fix was tested before `main`. In the product it is a command of the gate, because
    `guard-bash` refuses git writes in `projects/`. A break that only shows when the fix meets the unreleased work of
    `developer` is caught by the full tests of the next `/merge` into `developer`, or of the release.
  - with a conflict, or a fix that must be adapted to the code on `developer` (another API, a moved file, a
    refactor): in a clone of `developer`, on `fix/<slug>-developer`, merge `main`, resolve every conflict and adapt the
    fix, so the bug stays fixed on `developer` too; that branch enters `developer` through the normal gate (`/merge`:
    the full tests, `validate.sh`, and a clean-context review of the resolution, effort high). The human is asked only
    when the resolution changes a business rule.

  The expected conflict in `CHANGELOG.md` follows a rule: the `Unreleased` section of `developer` stays on top and the
  dated patch section goes below it. `main` and its tag never change on the way down.
- BR-10: Until `developer` holds `main`, the project's repo is blocked: the merge into `developer` pending is the
  blocker. It is computed from git, with no state file: the repo is blocked while the remote `main` holds a commit the
  remote `developer` does not (`git merge-base --is-ancestor origin/main origin/developer` is false). So it survives a
  cancel, a crash of the session, another machine or another person, and clears by itself when the merge is pushed. A
  release merged into a protected `main` by a pull request with a merge commit is blocked the same way, and the same
  merge into `developer` clears it.
- BR-11: While blocked, the gate refuses `/merge` into that `developer` and `/merge --main` of that repo, and says the
  hotfix merge into `developer` comes first; the product's session gets the same warning as context when the repo is
  named (the `UserPromptSubmit` hook already reports project states). Here, `/caw-merge` and `/caw-request` refuse to
  start and say so; no visual warning (assumed decision).
- BR-12: The request of the hotfix (a file in `custom/requests/`, or written from the human's words) goes to
  `qa/<project>/` with its Execution block, marked "merge into developer pending", once `main` received the fix; it
  moves to `done/<project>/` with `Released in <project> vX.Y.(Z+1)` (or "not published", when the answer was no) when
  the merge into `developer` is pushed.
- BR-13: In a project with nested repos, the hotfix is per repo; the project's root repo then gets its own patch
  version with the "Components" table (`workspace/rules/docs.md`) (assumed decision).
- BR-14: `guard-bash` keeps refusing any other way to move `main` or to write `developer` in `projects/`: only
  `aiwp-cmds.sh release`, the gate, and the new hotfix commands of the gate (into `main`, and the clean merge into
  `developer`), each asked to the human.

## 4. Acceptance criteria

- AC-1: Given a repo with `main` and `developer`, when the flow starts, then the fix branch starts from the remote
  `main` and holds no commit of `developer` that is not on `main`.
- AC-2: Given a fix branch with a change unrelated to the error, then the review reports a BLOCKER and `main` does not
  change.
- AC-3: Given a fix that exists on `developer` in a commit that depends on unreleased work, then the cherry-pick is
  refused by the review and the fix is written from `main`.
- AC-4: Given a fix with a BLOCKER open, or without the human's OK, when the flow reaches the merge, then `main` does
  not change and receives no push.
- AC-5: Given a repo whose `main` publishes by itself, then the question "publish?" comes before the push of `main`;
  given the answer no, `main` does not change. Given a repo whose `main` does not publish by itself, then `main` is
  pushed first and the question comes after; given no, there is no tag and the flow goes on to `developer`.
- AC-6: Given a clean merge of `main` into `developer`, then `developer` gets a merge commit and is pushed, with no new
  branch and no test run; given a conflict or a needed adaptation, then `fix/<slug>-developer` resolves it, the gate
  and the review of the resolution pass, and `developer` receives it; `CHANGELOG.md` keeps `Unreleased` on top.
- AC-7: Given `main` ahead of `developer` on the remote (a hotfix not merged down, after a cancel or a crash), then
  `/merge` into that `developer` and `/merge --main` of that repo are refused with the reason, and the request is in
  `qa/<project>/` marked "merge into developer pending"; once the merge is pushed, both work again and the request is
  in `done/<project>/`.
- AC-8: Given a repo without `main`, when the flow starts, then it stops with a warning and creates no branch.
- AC-9: Here, given a fix that touches only the maintenance, then `/caw-merge --hotfix` says it is not a hotfix and
  points to the normal flow.
- AC-10: The suites of the changed scripts cover AC-1, AC-4 (no push), AC-6 (the clean merge and a conflict), AC-7 and
  AC-8 against bare remotes; a test installation proves the whole flow once, both kinds of `main`.

## 7. Out of scope

- Any branch other than `main` and `developer`: work branches get the fix through `/merge`.
- A visual warning of the blocked repo (a colored band like the Fable alert): the owner will evolve it later.
- Tagging after a pull request into a protected `main` (`release-tag-after-pull-request.md`).
- Releasing what is on `developer` (`/merge --main`).

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Product scripts: `open` from `main`, the gate against `main`, the hotfix commands (into `main`, the clean merge into `developer`), the blocker computed from git in the gate and the `UserPromptSubmit` warning, `guard-bash`, with scenario tests | high | Moves the production branch; a hook |
| 2. Product `/merge --hotfix`, rules, docs | high | Mandatory core |
| 3. Maintenance `/caw-merge --hotfix` (the layer: mapping and CAW rules) | medium | Text over decided behavior |
| 4. Suite, test installation (AC-3), independent review | high | Production branch |

The agents of each stage run with the stage's effort, passed in the call.

## Assumed decisions

- Open: where the flow applies. Decided: every repo of a project with `main`, nested ones included, and this
  repository. Reason: an error in production may be in any of them.
- Open: whether the hotfix is a version. Decided: a patch version in the CHANGELOG of `main`; its tag only when the
  human says to publish. Reason: `main` moves only with a version, and the installers here take only tags.
- Open: a fix to the maintenance only, here. Decided: not a hotfix; the normal flow. Reason: only the product is
  released.
- Open: where the blocker lives. Decided: computed from git (`main` ahead of `developer`), no state file. Reason:
  it survives a cancel or a crash and clears by itself.
- Open: a visual warning here. Decided: none; the skills refuse to start. Reason: the owner's decision; no hook runs
  here.
- Open: a conflict when the fix goes down to `developer`. Decided: resolve it and adapt the fix in a branch that goes
  through the gate and a review of the resolution; ask only when a business rule changes. Reason: the owner's
  decision; the gate and the review keep the shared branch safe.
- Open: how `open` starts from `main`. Decided: an option of `aiwp-cmds.sh open`. Reason: one way to open a clone.
- Open: the acceptance criteria. Decided: AC-1 to AC-10, derived from the rules. Reason: the ideas give only the rules.
