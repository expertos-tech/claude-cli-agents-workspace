---
name: release
description: "Cut a release of the product: version, changelog, suite, test installation, translations, then tag and GitHub release, each public step confirmed by the owner. Use only when the owner asks."
argument-hint: "[X.Y.Z]"
disable-model-invocation: true
model: claude-opus-5-5
effort: high
---

Arguments: `$ARGUMENTS`, the version to release. Empty: propose one from the changes since the last tag and ask.

A release is a git tag `vX.Y.Z` on `main` with a GitHub release. Installers and `aiwp` fetch the tags and move to the
newest release, so a tag is what users get: never move or delete a published tag.

## Steps

1. Pick the version (semantic versioning) from `git log <last tag>..HEAD`: patch for fixes, minor for new behavior,
   major for a change that needs action in an installed workspace or its custom layer. Say why.
2. On a branch `chore/release-X.Y.Z`, set `workspace/VERSION` to `X.Y.Z`.
3. Add the `## [X.Y.Z] - YYYY-MM-DD` section at the top of `workspace/CHANGELOG.md`: what changed for someone using the
   workspace, and what they must do after updating, if anything. Tools with their own `CHANGELOG.md` get their entry.
4. Run `bash tests/check.sh --all --base <last tag>`. Every check passes.
5. Run `/test-install` from this tree. It passes, and nothing from outside `workspace/` appears in the installation.
6. Update the translations of every English document the release changed (`.claude/rules/docs.md`).
7. Independent review of the diff since the last tag (`.claude/rules/review.md`). No BLOCKER open.
8. Commit per `.claude/rules/git.md`. Then, **asking the owner before each one** (each answer covers that step only):
   1. push the branch and open the pull request;
   2. merge it to `main`;
   3. tag the merge commit, `git tag -a vX.Y.Z -m "vX.Y.Z"`, and push the tag;
   4. publish the GitHub release for the tag, with the `CHANGELOG.md` section as its notes.
9. Check that a fresh installation (`install.sh`) picks up the new tag.

A refused or failed public step stops the release there: report where it stopped, never force it.

## Checklist

Copy into the release pull request and tick each box.

- [ ] Version chosen: `X.Y.Z`, semantic versioning
- [ ] `workspace/VERSION` holds `X.Y.Z`
- [ ] `workspace/CHANGELOG.md` has the `## [X.Y.Z] - YYYY-MM-DD` section, with the actions an update needs
- [ ] Tool changelogs updated for the tools that changed
- [ ] `bash tests/check.sh --all --base <last tag>` passes
- [ ] `/test-install` passes, with no file from outside `workspace/` in the installed workspace
- [ ] Translations of the changed English documents updated in `i18n/<locale>/`
- [ ] Independent review: no BLOCKER open
- [ ] No company term, personal path, e-mail address, internal URL or secret in the diff
- [ ] Pull request merged to `main` (owner confirmed)
- [ ] Tag `vX.Y.Z` created on the merge commit and pushed (owner confirmed)
- [ ] GitHub release published, notes taken from the changelog section (owner confirmed)
- [ ] A fresh installation picks up the new tag
