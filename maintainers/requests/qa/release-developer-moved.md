# Functional request: /caw-merge --main does not say what to do when developer moves

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Created 2026-11-17 as a backlog item (defect, priority medium, target maintenance); source: the review of the fix eb40e43 (release commit checked before it merges).

## What

During the strict suite or the final review of a release, another session merges into `developer`. "From a clone" step 5 then says "back to step 1", which reopens a clone that exists and runs the non-strict phase 1 and the diff-only review: the new commits would reach `main` without the strict suite or the final review.

## Done when

Release step 6: `origin/developer` moved: merge it in the clone, put its entries into the dated `X.Y.Z` sections, and go back to step 4.

## Where

`.claude/skills/caw-merge/SKILL.md`, "Release" step 6.

## Effort

low

---

## Execution — 2026-11-20, merged into developer

- **Done:** `.claude/skills/caw-merge/SKILL.md` "Release" step 8 (1cbb560): `origin/developer` moved since the release
  clone was made (`merge-base --is-ancestor origin/developer <sha>` false) is no longer sent to the mapping's "back
  to step 1": the release clone merges it, puts its entries into the dated `X.Y.Z` sections of both changelogs and
  goes back to step 4 (its requests of `qa/` move to `done/` there), then steps 5 to 7 again, with the final review
  on what the merge brought and the review fixtures not rerun (step 5 says so too). The root changelog entry of
  `/caw-merge` adjusted (71f277f): it entered in the same unreleased version, so no `Fixed` entry.
- **Deviations:** the request names "Release" step 6; the steps were renumbered since it was written, and the merge
  into `developer`, where the move shows, is step 8 today.
- **Done when:** met by the text of step 8; its first real run is a release during which `developer` moves.
- **Checks:** `bash tests/check.sh --base origin/developer --i18n-pending` passed (repo-terms skipped: no terms list);
  no hook, installer or `setup-claude.sh` changed, so no test installation.
- **Warnings:** none in the stage.
- **Left:** nothing.
