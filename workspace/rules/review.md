# review.md

## When

Once per merge, between the two phases of the gate (`rules/git.md` "Gate", `/merge`), on every change to a project. A further round only when the human asks, or on the fix of a BLOCKER (the same review, only the fix).

| Merge | Scope |
| --- | --- |
| Into `developer` | Only the difference that enters: the range phase 1 printed |
| Into `main` (release, hotfix) | Everything since the last tag, widened to what the reviewer judges necessary: callers, dependents, the docs of what changed |

## Effort, by content

- Code and configuration (code, scripts, hooks, settings, rules, skills, agents, `AGENTS.md`, `CLAUDE.md`, templates): effort `xhigh`. This review is the only use of `xhigh` (`rules/models.md`).
- Documents (`*.md` and `docs/` that are none of the above): effort `high`.
- A merge with both: two `reviewer` subagents in parallel, each with its part of the range.

## How

- The reviewer has a clean context and did not write the code: the `reviewer` subagent (`rules/models.md`), read-only. For a project diff, `/code-review` is an equivalent.
- Its brief gives: the clone path, the range (its part of it), the audit file phase 1 printed, the request (or requests: at a release every one of `custom/requests/qa/<project>/` with its Execution blocks; at a hotfix the error as the human described it), and what phase 1 already verified. It asks only these three questions:

  ```text
  1. What was asked against what was done: for each business rule and acceptance criterion of the request, done and
     proven by a test, done and not proven, or not done; a change that does not do what was asked or reads it wrong.
  2. What went beyond the request: each change of the range with no request behind it, classified CONSEQUENCE (of
     what) or UNEXPLAINED.
  3. What existed and was lost: behavior, a test, a protection (a hook, a gate, a permission) or a documented promise
     that worked before the range and is removed or weakened with no request behind it.
  Report only defects, each with path:line, a concrete failure scenario and the fix.
  ```

- The reviewer never edits, and never re-runs a check that passed on the tree it reviews.
- A release also checks the CHANGELOG against question 1 (an entry with no change behind it, a change a user would notice with no entry). A hotfix goes to production: every change beyond the error described is a BLOCKER, even when it is right, and so is a cherry-picked commit that depends on anything not on `main`.

## Findings

- BLOCKER: correctness, security, data loss, a broken or unproven acceptance criterion, an UNEXPLAINED change or loss, a failing test, a weaker gate or hook. Fix it in the clone and run the gate again from phase 1.
- RECOMMENDED: everything else. It never returns the branch and never opens a round. At a merge into `developer` it becomes a `ready` request in `custom/requests/`; at a release the human chooses per finding: fix now, or a request (`rules/skills/merge/SKILL.md` "Release" step 5).
- A finding is not accepted only because it came. Check why the code is that way. Still disagree: give the human both positions and let the human decide.
- Never report style the formatter fixes. Never praise.

## Report format

```text
VERDICT: APPROVED | APPROVED_WITH_CHANGES | REJECTED
FINDINGS:
- [BLOCKER|RECOMMENDED] <path>:<line> — <problem> — <failure scenario> — <fix>
```

REJECTED when a BLOCKER exists. APPROVED_WITH_CHANGES when only RECOMMENDED exist: the branch still merges.
