---
name: caw-merge
description: "Take the work of this session into developer through the gates, writing the two changelogs (CHANGELOG.md of the repository, workspace/CHANGELOG.md of the product) and moving the request to qa; with --main, validate everything in qa and release the product (main, tag and GitHub release, each public step confirmed); with --hotfix, fix an error of the released product from main as a patch version, then merge main down into developer. No argument: the clone of this session in tmp/work/, else the session on developer. Use only when the owner asks."
argument-hint: "[<work>/<clone> | --main [instructions] | --hotfix <description> | --hotfix --down]"
disable-model-invocation: true
model: claude-opus-5-5
effort: high
---

@workspace/rules/skills/merge/SKILL.md

Read that file in full and follow it as the procedure, with the sections below over it: they win where they differ.
Running `/caw-merge` is the owner's order for the push of `developer`, the one prompt of a task; the work branch is
pushed by the clone's hooks (`tests/caw-work.sh`). `main`, the tag and the GitHub release are each confirmed
(`--main`).

---

## Ignore from the product skill

- The place of step 8 ("The request to qa") after phase 2: this repository is public, so the Execution block and the
  move to `qa/` are written and committed in the clone (or on `developer`) right after the changelogs, before phase 1,
  where the suite's company-terms scan and the review judge them. Nothing reaches `developer` unscanned.
- "Which work" through `aiwp-cmds.sh status`: here "Where the session is", below.
- The release per project with one clone per repo, the project root version and `aiwp-cmds.sh release`: here one
  repository, and only the product is released ("Release", below).
- Step 6 of "Merge into developer" for a base that publishes to production: `developer` publishes nothing here.
- The review of the product's skill: here `.claude/rules/review.md` (the same three questions, the same effort by
  base: `medium` into `developer`, `high` into `main`, and this repository's hard rules).
- The product's "Hotfix" steps 1, 3, 9, 10, 12 and 13 (`aiwp-cmds.sh open --from-main`, `hotfix`, `hotfix-tag`,
  `hotfix-down`, the project's repos, the request in `qa/` marked pending): here "Hotfix", below, with plain git.

## Mapping

| Product | Here |
| --- | --- |
| `bash scripts/aiwp-cmds.sh run <clone> -- git ...` | `bash tests/caw-work.sh run <work> -- git ...`, from the root; a clone with no hooks (release, hotfix): `git -C <clone> ...` |
| the CHANGELOG of the changed component | the two changelogs ("CAW rules") |
| the full test command and gate phase 1 | `bash tests/caw-work.sh run <work> -- bash tests/check.sh --base origin/developer --i18n-pending` (it sets `AIWP_TERMS_FILE` to the root's terms list); a clone with no hooks (release, hotfix, hotfix down): `bash <clone>/tests/check.sh ...` with `AIWP_TERMS_FILE` set to the root's terms list when there is one; `/caw-test-install` from the clone when the range changes `install.sh`, `tests/test-install.sh`, a hook or `workspace/scripts/setup-claude.sh`. Record the sha: `git -C <clone> rev-parse HEAD` |
| gate phase 2 | at the root, on `developer` with no change: `git fetch -q origin`, `git merge --ff-only origin/developer`; the clone's sha still its HEAD and the remote branch (`git ls-remote origin <branch>`), else back to step 1; `git fetch -q <clone> <branch>`, `git merge --ff-only <sha>`, then, alone in its call, `git push origin developer` |
| `aiwp-cmds.sh close <work>` | `bash tests/caw-work.sh close <work>`, once `developer` holds the sha: it deletes the remote work branch and the work folder; a clone with no hooks (release, hotfix, hotfix down): `rm -rf tmp/work/<work>/<clone>`, and the work folder when empty, once `developer` holds the sha |
| `custom/requests/` (and `qa/<project>/`, `done/<project>/`) | `maintainers/requests/` (and `qa/`, `done/`), committed in the clone, or on `developer` when the session has no clone; no `custom/` |
| a `ready` request made of a warning the owner chose to fix later | `maintainers/requests/<kebab-title>.md`, `**State:** ready`, with its row in the README |
| `rules/review.md`, `rules/docs.md` | `.claude/rules/review.md`, `.claude/rules/docs.md` (`workspace/rules/docs.md` "CHANGELOG.md" for the changelog rules) |

## CAW rules

### Push gate

This repository is public. Every push `/caw-merge` makes (a release or hotfix branch, `developer`, `main`) happens
only right after a passing `tests/check.sh` run on that same commit; a work branch is pushed by the clone's hooks,
after the company-terms scan: record `git rev-parse HEAD` after the run, and
push only when HEAD still equals it. Anything written after that run (an Execution block, a request made of a
finding, a fix, a translation) means running the suite again before the push.

### Where the session is

- `<work>/<clone>`, or no argument and this session opened a clone (`tmp/work/<work>/<clone>`, named in the
  conversation): the product's "Merge into developer" with the mapping.
- No argument and no clone: the session worked at the root, on `developer` (another branch: say so and stop). Commit
  what is pending (`/caw-commit` rules); the changelog range is the commits since the last changelog commit
  (`git log -1 --format=%H --grep='^docs(changelog):' --grep='^chore(release):'`) up to `HEAD`; then the changelogs
  and the request to `qa/` with its Execution block (commits), the suite with `--base origin/developer --i18n-pending`
  (it scans them), the review of `origin/developer..HEAD` only, and `git push origin developer`.
- `--main [instructions]`: "Release", below.

### The two changelogs

Both follow `workspace/rules/docs.md` "CHANGELOG.md".

- **Product**, `workspace/CHANGELOG.md`: only a change to `workspace/` or `install.sh`, in detail, for someone who uses
  the workspace, with what they must do after updating, if anything.
- **Repository**, `CHANGELOG.md` at the root: every change. A change of the maintenance (`CLAUDE.md`, `.claude/`,
  `tests/`, `maintainers/`, `i18n/`, `docs/`, the root `README.md`) in detail, under its type; a product change as
  one summary line under `### Product`. Its versions are never released on their own: a section is dated by the
  product release that ships it.

### Release

`/caw-merge --main [instructions]` releases the product: the version of the `Unreleased` header of
`workspace/CHANGELOG.md` on `developer`. None: no product change since the last release; say so and stop (the
maintenance changes stay on `developer`). Its tag `vX.Y.Z` must be free (`git tag -l` and `git ls-remote --tags`).

1. **The plan and its conflicts** (the product's step 1). The default releases the product and moves `main` to
   `developer`. An instruction that releases part of it conflicts with the fast-forward: `main` can only move to
   `developer` as a whole. For example, "only caw, not the product":

   ```text
   Instruction understood: move main to developer without releasing the product (no vX.Y.Z tag, no GitHub release).

   Conflict: main can only move to developer as a whole (a fast-forward, never a partial merge). developer holds
   3 product changes not released yet (workspace/), so they would reach main with no version:
     - installations are not affected: install.sh and aiwp only take vX.Y.Z tags, still v0.2.0;
     - main would show workspace/VERSION 0.2.0 with code that is no released version; a clone of main,
       or AIWP_REF=main, would install a product that matches no tag;
     - /caw-merge and /caw-request on main would use, as their base, product skills that are not released.
     (1) Release the product too (v0.3.0)   (2) Go on without the product release, knowing the above   (3) Cancel
   ```

2. **Release clone:** `git clone -q --local . tmp/work/<yyyy-mm-dd>-release-vX-Y-Z/claude-cli-agents-workspace`,
   origin set to the root's URL, `git -C <clone> fetch -q origin`, `git -C <clone> switch -c fix/release-vX-Y-Z
   origin/developer`; not pushed yet (the push gate: after step 5).
3. **Translations**, once for the release: one `docs-writer` (claude-sonnet-5-5, effort `medium`) brings every pending
   translation up to date (the `pending:` lines of `bash <clone>/tests/check.sh --base <last tag> --i18n-pending`);
   commit (`docs(i18n): translations for X.Y.Z`); no push.
4. **Version and dates**, today, so the checks below judge them: `workspace/VERSION` to `X.Y.Z`; `workspace/CHANGELOG.md`
   dated; in the root `CHANGELOG.md` the `Unreleased` section dated the same day (none: a patch section over the
   newest), with under `### Product` the line `Released [vX.Y.Z](<repo URL>/releases/tag/vX.Y.Z): see its
   [changelog](<repo URL>/blob/vX.Y.Z/workspace/CHANGELOG.md).` (the repository URL of `README.md`); each file of
   `maintainers/requests/qa/` moved to `done/` with `Released in vX.Y.Z`, and its row in the README; commit
   (`chore(release): X.Y.Z`); no push.
5. **Full suite, strict:** `bash <clone>/tests/check.sh --all --base <last tag>` (translations included) and
   `bash <clone>/tests/test-install.sh`. Passed: record `git -C <clone> rev-parse HEAD` and push the release branch
   with upstream.
6. **Final review** (the product's step 4, `.claude/rules/review.md`) on `<last tag>..HEAD` of the
   clone, against every request of `maintainers/requests/qa/`.
7. **The findings, once** (the product's step 5): per finding, (1) fix now in the release clone, (2) a request in
   `maintainers/requests/`, or, for a warning only, (3) accept it; a BLOCKER sent to a request stops the release. Fixes or requests written in the clone: rerun step 5 (which
   records and pushes again) and the return review of the fixes (`.claude/rules/review.md`). The sha is the one step 5 recorded last, equal to the pushed
   `fix/release-vX-Y-Z` and to HEAD.
8. **Into `developer`:** phase 2 of the mapping with that sha (phase 1 and the review are steps 5 and 6). The clone
   moved after the sha was recorded: back to step 5.
9. Then, **asking the owner before each one** (each answer covers that step only): `main` (`git push origin
   developer:main`; refused: a pull request `developer` → `main`, and stop until it is merged); the tag
   (`git tag -a vX.Y.Z -m "vX.Y.Z" <sha of main>`, `git push origin vX.Y.Z`; never moved or deleted); the GitHub
   release, with the product CHANGELOG section as its notes.
10. Check that a fresh installation (`install.sh`) picks up the new tag. Summary as the product's step 11.

### Blocked

Every `/caw-merge` and `/caw-request` starts with `git fetch -q origin` and
`git merge-base --is-ancestor origin/main origin/developer`. False (a hotfix not merged down, after a cancel or a
crash, or a pull request merged into `main` with a merge commit): refuse to start, say that `main` must be merged into
`developer` first, and point to step 9 of "Hotfix" (`/caw-merge --hotfix --down`). Only that step, and a
`/caw-merge` of a `fix/<slug>-developer` clone whose HEAD holds `origin/main`, may run. No visual warning (out of
scope).

### Hotfix

`/caw-merge --hotfix <description>`: an error of the released product, fixed from `main` (the product's "Hotfix",
with this mapping). Only a fix to the product (`workspace/`, `install.sh`) is a hotfix: a fix that touches only the
maintenance (`CLAUDE.md`, `.claude/`, `tests/`, `maintainers/`, `docs/`, `i18n/`, the root `README.md`) is not; say so
and point to the normal flow (`/caw-request`, `/caw-merge` into `developer`), and stop. The request: the file the owner
names in `maintainers/requests/`, else the description.

1. **The version:** the newest `vX.Y.Z` tag with the patch bumped; tag free (`git tag -l`, `git ls-remote --tags`).
2. **Clone from `main`:** `git clone -q --local . tmp/work/<yyyy-mm-dd>-hotfix-<slug>/claude-cli-agents-workspace`,
   origin set to the root's URL, `git -C <clone> fetch -q origin`, `git -C <clone> switch -c fix/<slug> origin/main`;
   not pushed yet (the push gate: after step 5).
3. **The fix** (the product's step 4): only what the error needs, with a test that fails without it; a commit of
   `developer` taken by `git cherry-pick -x` only when it depends on nothing not released. A doc it changes that has a
   translation: the translation in the same fix (the strict suite checks it).
4. **Version and changelogs:** `workspace/VERSION` to `X.Y.(Z+1)`; in `workspace/CHANGELOG.md` a dated section
   `## [X.Y.(Z+1)] - YYYY-MM-DD` above the newest one, with `### Fixed`; in the root `CHANGELOG.md` (created when
   `main` has none) the same dated section with under `### Product` the line `Released [vX.Y.Z](<repo
   URL>/releases/tag/vX.Y.Z): see its [changelog](<repo URL>/blob/vX.Y.Z/workspace/CHANGELOG.md).`; commit
   (`chore(release): X.Y.Z`).
5. **The gate against `main`:** `bash <clone>/tests/check.sh --all --base <last tag>` (with `AIWP_TERMS_FILE` as in
   the mapping) and `bash <clone>/tests/test-install.sh`; and no commit of `origin/main..HEAD` may be one that only
   `developer` has (`comm -12` of the sorted `git -C <clone> rev-list origin/main..HEAD` and
   `git -C <clone> rev-list origin/main..origin/developer` is empty). Passed: record `git -C <clone> rev-parse HEAD`
   and push `fix/<slug>` with upstream.
6. **Review against `main`** (the product's step 7, `.claude/rules/review.md`) on `<last tag>..<sha>`, widened as
   needed, with the error described. A BLOCKER: fix in the clone, back to step 5, then the return review (`.claude/rules/review.md`). A WARNING: listed
   in the owner's OK of step 7; one the owner sends to a request becomes a `ready` request in `maintainers/requests/`,
   written in the down step (step 9), never on `main`.
7. **Into `main`:** `main` here does not publish by itself (the installers take only tags), so: the owner's OK, with no
   BLOCKER open and HEAD still the recorded sha; then `git -C <clone> push origin <sha>:refs/heads/main` (a
   fast-forward; refused: a pull request `fix/<slug>` → `main`, and the tag waits for its merge,
   `release-tag-after-pull-request`). Say `main` received the fix.
8. **The publication:** ask "publish to production with the fix?". Yes, asking before each one (each answer covers
   that step only): the tag (`git tag -a vX.Y.Z -m "vX.Y.Z" <sha>`, `git push origin vX.Y.Z`; never moved or deleted),
   then the GitHub release with the `workspace/CHANGELOG.md` section as its notes; then check that a fresh `install.sh`
   picks up the tag. No: no tag; go on.
9. **Down into `developer`** (`/caw-merge --hotfix --down` resumes here, in the hotfix clone, or in a new clone
   `tmp/work/<yyyy-mm-dd>-hotfix-down/claude-cli-agents-workspace` made as in step 2 when it is gone): say that `main`
   is now merged into `developer`, and do it; the only option offered is to go on. In the clone: `git fetch -q origin`, `git switch -c fix/<slug>-developer
   origin/developer`, `git merge --no-ff origin/main -m "Merge branch 'main' into developer"`.
   - Clean: a standard merge commit, no new branch on the remote. Then the request's `## Execution` block (the
     product's step 11) with `Released in vX.Y.(Z+1)` (or `Not published: vX.Y.(Z+1) on main without a tag`), the
     file moved to `maintainers/requests/done/` and its row in the README, and the requests made of warnings
     the owner chose; commit (`docs(requests): ...`). The suite `--base origin/developer --i18n-pending` (the push gate: the
     request and the merge are scanned; the fix's own tests already passed on `main`), then
     `git -C <clone> push origin HEAD:refs/heads/developer` (a fast-forward of `origin/developer`; refused because it
     moved: back to the start of this step).
   - A conflict, or a fix to adapt: resolve it in this branch and adapt the fix so the error stays fixed on
     `developer`; in the changelogs, the `Unreleased` sections of `developer` stay on top and the dated patch sections
     go below them (an `Unreleased` version not above the patch takes the next one); `workspace/VERSION` keeps the
     version of `developer` when it is above. Then the request as in the clean case, push the branch, and take it into
     `developer` by "Merge into developer" of this skill (the suite, the review of the resolution (`.claude/rules/review.md`),
     phase 2). Ask the owner only when the resolution changes a business rule.

   `main` and its tag never change on the way down; never a rebase or a force push; no other branch is touched.
10. Delete the clone once `developer` holds `origin/main`, and remove the remote `fix/<slug>` (and
    `fix/<slug>-developer`) branch. Summary: the version, `main` and `developer` (shas), the tag and the release,
    the review, the checks with their results, the request.

The request lives only on `developer` (`main` has no `maintainers/requests/` of today), so here it goes straight to
`done/` in step 9, with the merge down; until then it stays pending in `maintainers/requests/`, and a stop between steps
7 and 9 appends where it stopped to it (`.claude/rules/process.md` step 4).

A refused or failed public step stops the release there: report where it stopped, never force it. Never merge with a
failing check or an open BLOCKER. Never move `developer` or `main` by any other command, and never rewrite either.
