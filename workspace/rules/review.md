# review.md

## When

Once per gate, between its two phases (`rules/git.md` "Gate", `/merge`), on every change to a project. A further round only when the human asks, or on the fix of a BLOCKER that touched a hook, a permission or a secret.

## How

- The reviewer has a clean context and did not write the code: the `reviewer` subagent (`rules/models.md`), read-only. For a project diff, `/code-review` is an equivalent.
- Run it after phase 1 of the gate passed, on the diff of the branch against its updated base (the range phase 1 printed) and on the audit of what leaves the base.
- Its brief gives: the clone path, the range, the audit file, the acceptance criteria (or the request text), and what phase 1 already verified. It asks only for this:

  ```text
  For each item of the audit and each acceptance criterion, classify: REQUESTED, CONSEQUENCE (of what), or UNEXPLAINED.
  Then report only: a correctness defect; a security or data-loss problem; an acceptance criterion that is not met, or
  that no test proves; a removed or weakened test with no reason in the request; a protection that got weaker (a hook,
  a gate, a permission). For each: path:line, a concrete failure scenario, the fix.
  ```

- The reviewer never edits, and never re-runs a check that passed on the tree it reviews.

## Release

`/merge --main` ends with a stronger final review (`rules/skills/merge/SKILL.md` "Release" step 3), on everything since the last release, in two rounds: **what enters and what leaves** (effort `high`: the inventory of what was added, changed and removed, each traced to its request; regressions, so nothing that works is removed without a request; intent, so each change does what was asked and no more; the CHANGELOG) and a **general** reading of the whole tree (effort `medium`: contradictions, dead references, leftovers). UNEXPLAINED removals and regressions are BLOCKERs.

## Findings

- BLOCKER: correctness, security, data loss, a broken or unproven acceptance criterion, a failing test, a weaker gate or hook. Fix it in the clone and run the gate again from phase 1.
- RECOMMENDED: everything else. It never returns the branch and never opens a round: fix it in the same pass when it is cheap, else list it in the delivery summary.
- A finding is not accepted only because it came. Check why the code is that way. Still disagree: give the human both positions and let the human decide.
- Never report style the formatter fixes. Never praise.

## Report format

```text
VERDICT: APPROVED | APPROVED_WITH_CHANGES | REJECTED
FINDINGS:
- [BLOCKER|RECOMMENDED] <path>:<line> — <problem> — <failure scenario> — <fix>
```

REJECTED when a BLOCKER exists. APPROVED_WITH_CHANGES when only RECOMMENDED exist: the branch still merges.
