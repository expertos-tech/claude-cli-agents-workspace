---
name: caw-merge
description: "Take the work of this session into developer through the gates, writing the two changelogs (CHANGELOG.md of the repository, workspace/CHANGELOG.md of the product); with --main, release the product version (main, tag and GitHub release, each public step confirmed). No argument: the clone of this session in tmp/work/, else the session on developer. Use only when the owner asks."
argument-hint: "[<work>/<clone> | --main]"
disable-model-invocation: true
model: claude-opus-5-5
effort: high
---

Arguments: `$ARGUMENTS`. A copy of the product's `/merge` (`workspace/rules/skills/merge/SKILL.md`) with this
repository's mechanics: no hooks here, so the steps run plain git. Running `/caw-merge` is the owner's order for the
pushes it makes: the work branch and `developer`. `main`, the tag and the GitHub release are each confirmed (`--main`).

## The two changelogs

Both follow `workspace/rules/docs.md` "CHANGELOG.md": `## [X.Y.Z] - Unreleased`, the bump by the Conventional Commit
types of what enters each one, and a fix of something that entered the same `Unreleased` version is not a fix (no
`### Fixed` entry, no bump; adjust the original entry only when the behavior it describes changed).

- **Product**, `workspace/CHANGELOG.md`: only a change to `workspace/` or `install.sh`, in detail, for someone who uses
  the workspace, with what they must do after updating, if anything. Only the product is released.
- **Repository**, `CHANGELOG.md` at the root: every change. A change of the maintenance (`CLAUDE.md`, `.claude/`,
  `tests/`, `maintainers/`, `i18n/`, `docs/`, the root `README.md`) in detail, under its type; a product change as
  one summary line of the feature under `### Product`, pointing to the product changelog. Its versions are never
  released on their own: a section is dated by the product release that ships it ("Release" step 5).

## Where the session is

- `<work>/<clone>`, or no argument and this session opened a clone (`tmp/work/<work>/<clone>`, named in the
  conversation): "From a clone".
- No argument and no clone: the session worked at the root, on `developer`: "On developer". The root on another
  branch: say so and stop.
- `--main`: "Release".

## From a clone

1. In the clone: commit what is pending (`/caw-commit` rules), `git -C <clone> fetch -q origin`, then
   `git -C <clone> merge --no-edit origin/developer`. A conflict: resolve it in the clone and commit.
2. Changelogs: write what enters, from `git -C <clone> log` and `diff` of `origin/developer..HEAD`, in the
   repository's and, when the range changes `workspace/` or `install.sh`, in the product's ("The two changelogs");
   commit them alone (`docs(changelog): <version> unreleased`). Push the branch.
3. Phase 1, in the clone, only what changed: `bash <clone>/tests/check.sh --base origin/developer --i18n-pending`
   (no `--all`: the suites run only for what the range touches; the translations wait for the release), with
   `AIWP_TERMS_FILE` set to the root's `workspace/custom/core-terms.txt` when it exists (that file is git-ignored, so
   the clone lacks it); and, when the range changes `install.sh`, `tests/test-install.sh`, a hook or
   `workspace/scripts/setup-claude.sh`, `/caw-test-install` from the clone. A failure: fix in the clone, commit, push,
   run phase 1 again. Record the sha: `git -C <clone> rev-parse HEAD`.
4. Review of the difference only (`.claude/rules/review.md` "When"): `origin/developer..<sha>`, read with
   `git -C <clone> diff`; what is already on `developer` was reviewed. Documentation only: no review. Otherwise one
   `reviewer` subagent (claude-opus-5-5), clean context, effort `high` for a hook, the installer, `setup-claude.sh`, a
   gate script, a permission or deny rule or secrets, else `medium`. Brief: the request the session ran (file or the
   owner's words), the range, and what phase 1 verified (do not re-run it). Ask only for: a correctness defect; a
   security or data-loss problem; an acceptance criterion not met or not proven; a removed or weakened test or
   protection; a CHANGELOG entry that misdescribes the change. Each with path:line, the failure scenario and the fix.
   A BLOCKER: fix it in the clone, go back to step 3. A RECOMMENDED never blocks: write it as a backlog item and list
   it in the summary. A security finding counts only after a second clean review confirms it.
5. Phase 2, at the root: on `developer`, with no change (`git status --short` empty; else stop and say so),
   `git fetch -q origin` and `git merge --ff-only origin/developer`. The clone's sha must still be its HEAD and the
   remote branch (`git ls-remote origin <branch>`); `origin/developer` moved since phase 1: back to step 1. Then
   `git fetch -q <clone> <branch>`, `git merge --ff-only <sha>`, `git push origin developer`, and
   `git push origin --delete <branch>`.
6. Delete the clone (`rm -rf tmp/work/<work>/<clone>`, and the work folder when empty) once `developer` holds the sha.
7. Summary: what entered `developer` (sha), the version and the CHANGELOG entries, the checks and their results, the
   review findings, the backlog items made of the RECOMMENDED, and the translations left for the release.

## On developer

1. Commit what is pending (`/caw-commit` rules). The range is the commits since the last changelog commit
   (`git log -1 --format=%H --grep='^docs(changelog):' --grep='^chore(release):'`) up to `HEAD`; an edit of a
   changelog's introduction does not end the range.
2. Steps 2 to 4 of "From a clone" with the root as the clone and `origin/developer` as the base: CHANGELOG commit,
   `bash tests/check.sh --base origin/developer --i18n-pending` (and `/caw-test-install` as there), and the review of
   `origin/developer..HEAD` only (the commits not pushed yet). Fixes are commits on `developer`.
3. `git push origin developer`. Summary as in step 7 above.

## Release

`/caw-merge --main` releases the product: the version of the `Unreleased` header of `workspace/CHANGELOG.md` on
`developer`. None: no product change since the last release, so there is nothing to release; say so and stop (the
maintenance changes stay on `developer`, recorded in the root `CHANGELOG.md`). `vX.Y.Z` is that version; `X-Y-Z` the
same with hyphens. The tag must be free
(`git tag -l vX.Y.Z` and `git ls-remote --tags origin vX.Y.Z` both empty); else stop before step 1 and tell the owner.

1. Open the release clone: `git clone -q --local . tmp/work/<yyyy-mm-dd>-release-vX-Y-Z/claude-cli-agents-workspace`,
   origin set to the root's origin URL (`git -C <clone> remote set-url origin "$(git remote get-url origin)"`),
   `git -C <clone> fetch -q origin`, `git -C <clone> switch -c fix/release-vX-Y-Z origin/developer`, push it with
   upstream.
2. Translations, once for the whole release: one `docs-writer` subagent (claude-sonnet-5-5, effort `medium`) brings
   every pending translation up to date (the `pending:` lines of
   `bash <clone>/tests/check.sh --base <last tag> --i18n-pending`), per `.claude/rules/docs.md`; commit
   (`docs(i18n): translations for X.Y.Z`) and push.
3. The full suite, strict: `bash <clone>/tests/check.sh --all --base <last tag>` (translations included) and
   `bash <clone>/tests/test-install.sh`. A failure: fix in the clone, commit, push, run it again.
4. Final review (`.claude/rules/review.md` "Final review"), on `<last tag>..HEAD` of the clone, in this order:
   1. what enters and what leaves: `reviewer`, claude-opus-5-5, effort `high`, with the requests of
      `maintainers/requests/done/` the range delivers and the `Unreleased` sections: the inventory, regressions,
      intent and the changelogs;
   2. general: `reviewer`, claude-opus-5-5, effort `medium`, over the whole tree.

   Fix every BLOCKER in the clone, commit by commit, push, rerun step 3 and review the fix. A fix of something of this
   version adds no entry. Each RECOMMENDED becomes a backlog item.
5. In the clone, with today's date:
   - `workspace/VERSION` to `X.Y.Z`; in `workspace/CHANGELOG.md`, `## [X.Y.Z] - Unreleased` becomes
     `## [X.Y.Z] - YYYY-MM-DD`;
   - in the root `CHANGELOG.md`, the `Unreleased` section is dated the same day; none: add a patch section over the
     newest one. Under its `### Product`, the line `Released [vX.Y.Z](<repo URL>/releases/tag/vX.Y.Z): see its
     [changelog](<repo URL>/blob/vX.Y.Z/workspace/CHANGELOG.md).`, with the repository URL of `README.md`;
   - commit (`chore(release): X.Y.Z`) and push.
6. Into `developer`: step 5 and 6 of "From a clone" with this clone (phases 1 and the review already passed in steps
   3 and 4).
7. Then, **asking the owner before each one** (each answer covers that step only):
   1. `main`: `git push origin developer:main` (a fast-forward; refused: a pull request `developer` → `main` with
      `gh pr create`, and stop until it is merged);
   2. the tag: `git tag -a vX.Y.Z -m "vX.Y.Z" <sha of main>` and `git push origin vX.Y.Z`; a tag is never moved or
      deleted;
   3. the GitHub release of the tag, with the product CHANGELOG section as its notes (`gh release create`).
8. Check that a fresh installation (`install.sh`) picks up the new tag.
9. Summary: the version, `main` (sha), the tag, the release URL, the translations, the final review's inventory and
   findings, the fixes made, the backlog items, the checks and their results.

A refused or failed public step stops the release there: report where it stopped, never force it. Never merge with a
failing check or an open BLOCKER. Never move `developer` or `main` by any other command, and never rewrite either.
