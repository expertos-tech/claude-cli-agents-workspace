# Functional request: tie the push of main and the tag to the sha the suite judged

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Source: the review of the release push fix (2026-11-17), a RECOMMENDED finding.

## What

`/caw-merge --main` step 9 pushes `developer:main` and tags `<sha of main>` without checking that either equals the
sha step 5 recorded: a commit added to the local `developer` after step 8, or a pull request merged with a merge or
squash commit, would reach `main` or get the tag untested.

## Where

`.claude/skills/caw-merge/SKILL.md` "Release" step 9.

## Done when

`main` is pushed as `<sha>:main` only when `git ls-remote origin developer` equals `<sha>`; the tag goes on `<sha>`
only after `main` resolves to it; on the pull-request path, step 5 reruns on the merge commit (or its tree equals the
tree of `<sha>`) before the tag.

## Effort

low
