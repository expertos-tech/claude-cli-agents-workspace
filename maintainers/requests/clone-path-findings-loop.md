# Functional request: requests made of review findings loop the clone path of /caw-merge

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Source: the review of the push gate (2026-11-17), a RECOMMENDED finding.

## What

In the clone path, a RECOMMENDED finding of the review becomes a request committed in the clone after phase 1; phase 2
sees that HEAD moved and sends the work back to step 1, which runs the review again: it may report the same finding
and write a duplicate request, or never reach phase 2. No `/caw-merge` step says when the work branch is pushed,
though phase 2 checks it with `ls-remote`.

## Where

`.claude/skills/caw-merge/SKILL.md` ("Where the session is", the mapping of phases 1 and 2).

## Done when

A commit that only adds requests made of findings reruns phase 1 (the suite) and not the review; the work branch is
pushed right after the passing phase 1.

## Effort

low
