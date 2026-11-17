---
name: caw-merge
description: "Take the work of this session into developer through the gates, writing the versioned workspace/CHANGELOG.md; with --main, publish that version (main, tag and GitHub release, each public step confirmed). No argument: the clone of this session in tmp/work/, else the session on developer. Use only when the owner asks."
argument-hint: "[<work>/<clone> | --main]"
disable-model-invocation: true
model: claude-opus-5-5
effort: high
---

Arguments: `$ARGUMENTS`. A copy of the product's `/merge` (`workspace/rules/skills/merge/SKILL.md`) with this
repository's mechanics: no hooks here, so the steps run plain git. Running `/caw-merge` is the owner's order for the pushes
it makes: the work branch and `developer`. `main`, the tag and the GitHub release are each confirmed (`--main`).

The CHANGELOG is `workspace/CHANGELOG.md`, the product's, with the rules of `workspace/rules/docs.md` "CHANGELOG.md":
`## [X.Y.Z] - Unreleased`, the bump by the Conventional Commit types, and a fix of something that entered the same
`Unreleased` version is not a fix (no `### Fixed` entry, no bump; adjust the original entry only when the behavior it
describes changed). Write for someone who uses the workspace, and what they must do after updating, if anything.
Changes only to the maintenance (`CLAUDE.md`, `.claude/`, `tests/`, `maintainers/`, `i18n/` alone) get no entry.

## Where the session is

- `<work>/<clone>`, or no argument and this session opened a clone (`tmp/work/<work>/<clone>`, named in the
  conversation): "From a clone".
- No argument and no clone: the session worked at the root, on `developer`: "On developer". The root on another
  branch: say so and stop.
- `--main`: "Release".

## From a clone

1. In the clone: commit what is pending (`/caw-commit` rules), `git -C <clone> fetch -q origin`, then
   `git -C <clone> merge --no-edit origin/developer`. A conflict: resolve it in the clone and commit.
2. CHANGELOG: write the section of what enters, from `git -C <clone> log` and `diff` of `origin/developer..HEAD`;
   commit it alone (`docs(changelog): X.Y.Z unreleased`). Push the branch.
3. Phase 1, in the clone: `bash <clone>/tests/check.sh --all --base origin/developer`, with `AIWP_TERMS_FILE` set to
   the root's `workspace/custom/core-terms.txt` when it exists (that file is git-ignored, so the clone lacks it); and, when the range changes
   `install.sh`, `tests/test-install.sh`, a hook or `workspace/scripts/setup-claude.sh`, `/caw-test-install` from the
   clone. A failure: fix in the clone, commit, push, run phase 1 again. Record the sha: `git -C <clone> rev-parse HEAD`.
4. Review: one `reviewer` subagent (claude-opus-5-5), clean context, effort `high`. Brief: the request the session ran
   (file or the owner's words), the range `origin/developer..<sha>` to read with `git -C <clone> diff`, and what
   phase 1 verified (do not re-run it). Ask only for: a correctness defect; a security or data-loss problem; an
   acceptance criterion not met or not proven; a removed or weakened test or protection; a CHANGELOG entry that
   misdescribes the change. Each with path:line, the failure scenario and the fix. A BLOCKER: fix it in the clone, go
   back to step 3. A security finding counts only after a second clean review confirms it (`.claude/rules/review.md`).
5. Phase 2, at the root: on `developer`, with no change (`git status --short` empty; else stop and say so),
   `git fetch -q origin` and `git merge --ff-only origin/developer`. The clone's sha must still be its HEAD and the
   remote branch (`git ls-remote origin <branch>`); `origin/developer` moved since phase 1: back to step 1. Then
   `git fetch -q <clone> <branch>`, `git merge --ff-only <sha>`, `git push origin developer`, and
   `git push origin --delete <branch>`.
6. Delete the clone (`rm -rf tmp/work/<work>/<clone>`, and the work folder when empty) once `developer` holds the sha.
7. Summary: what entered `developer` (sha), the version and the CHANGELOG entries, the checks and their results, the
   review findings and the RECOMMENDED left.

## On developer

1. Commit what is pending (`/caw-commit` rules). The range is the commits since the last change of `workspace/CHANGELOG.md`
   (`git log --format=%H -1 -- workspace/CHANGELOG.md`) up to `HEAD`.
2. Steps 2 to 4 of "From a clone" with the root as the clone and `origin/developer` as the base: CHANGELOG commit,
   `bash tests/check.sh --all --base origin/developer` (and `/caw-test-install` as there), the clean-context review.
   Fixes are commits on `developer`.
3. `git push origin developer`. Summary as in step 7 above.

## Release

`/caw-merge --main` publishes the version of the `Unreleased` header of `workspace/CHANGELOG.md` on `developer` (none: say
there is nothing to release and stop). `vX.Y.Z` is that version; `X-Y-Z` the same with hyphens. The tag must be free
(`git tag -l vX.Y.Z` and `git ls-remote --tags origin vX.Y.Z` both empty); else stop before step 1 and tell the owner.

1. Open the release clone: `git clone -q --local . tmp/work/<yyyy-mm-dd>-release-vX-Y-Z/claude-cli-agents-workspace`,
   origin set to the root's origin URL (`git -C <clone> remote set-url origin "$(git remote get-url origin)"`),
   `git -C <clone> fetch -q origin`, `git -C <clone> switch -c fix/release-vX-Y-Z origin/developer`, push it with
   upstream.
2. Full check: one `reviewer` subagent (claude-opus-5-5), clean context, effort `high`. Brief: the clone's path, the
   range `<last tag>..origin/developer`, the `Unreleased` section. Ask it to run
   `bash <clone>/tests/check.sh --all --base <last tag>` and `bash <clone>/tests/test-install.sh`, and to report: a
   failing check; a correctness, security or data-loss defect in the range; a protection that got weaker; a change the
   CHANGELOG does not describe for the user, or an entry with no change behind it. Each with path:line, the failure
   scenario and the fix.
3. Fix every BLOCKER in the clone, commit by commit, push. A fix of something of this version adds no entry.
4. In the clone: `workspace/VERSION` to `X.Y.Z`; `## [X.Y.Z] - Unreleased` becomes `## [X.Y.Z] - YYYY-MM-DD`; the
   translations of the English documents the release changed (`.claude/rules/docs.md`); commit
   (`chore(release): X.Y.Z`) and push.
5. Into `developer`: steps 3 to 6 of "From a clone" with this clone (phase 1 with `--base <last tag>`).
6. Then, **asking the owner before each one** (each answer covers that step only):
   1. `main`: `git push origin developer:main` (a fast-forward; refused: a pull request `developer` → `main` with
      `gh pr create`, and stop until it is merged);
   2. the tag: `git tag -a vX.Y.Z -m "vX.Y.Z" <sha of main>` and `git push origin vX.Y.Z`; a tag is never moved or
      deleted;
   3. the GitHub release of the tag, with the CHANGELOG section as its notes (`gh release create`).
7. Check that a fresh installation (`install.sh`) picks up the new tag.
8. Summary: the version, `main` (sha), the tag, the release URL, the fixes made, the checks and their results.

A refused or failed public step stops the release there: report where it stopped, never force it. Never merge with a
failing check or an open BLOCKER. Never move `developer` or `main` by any other command, and never rewrite either.
