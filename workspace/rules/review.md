# review.md

## Two roles

- During a request the agent is its developer: it implements, tests what it did, makes sure it works, fixes and tests again. No independent review runs during the waves, hooks and security included: the agent's own tests close each wave.
- The review runs once per merge, as the tech lead: it validates what the agent did against the request and the standards already defined, before it enters the base. It stops only a real BLOCKER ("Findings"); the rest reaches the human once, as warnings, in the summary of the merge.

## When

Once per merge, between the two phases of the gate (`rules/git.md` "Gate", `/merge`), on every change to a project. A further round only when the human asks, or after the fixes of its findings ("The return review").

| Merge | Scope | Effort |
| --- | --- | --- |
| Into `developer` | Only the difference that enters: the range phase 1 printed | `medium` |
| Into `main` (release, hotfix) | Everything since the last tag, widened to what the reviewer judges necessary: callers, dependents, the docs of what changed | `high` |

- One `reviewer` subagent per merge, with the effort of its base. A range too large for one context is split in parts, each to its own `reviewer` with the same effort, in parallel.
- A change to an existing script (an installer, a hook): the review covers only its difference. The reviewer reads the rest of the file to understand the difference, never to review the whole script again.

## How

- The reviewer has a clean context and did not write the code: the `reviewer` subagent (`rules/models.md`), read-only. For a project diff, `/code-review` is an equivalent.
- Its brief gives: the clone path, the range (its part of it), the audit file phase 1 printed, the request (or requests: at a release every one of `custom/requests/qa/<project>/` with its Execution blocks; at a hotfix the error as the human described it), what phase 1 already verified, and the authorizations: each decision of the human in the request, its plan or the conversation that allows something a validator would flag (an allow rule, an accepted risk, a public push after the warning), quoted with where it came from. It asks only these three questions:

  ```text
  1. What was asked against what was done: for each business rule and acceptance criterion of the request, done and
     proven by a test, done and not proven, or not done; a change that does not do what was asked or reads it wrong.
  2. What went beyond the request: each change of the range with no request behind it, classified CONSEQUENCE (of
     what) or UNEXPLAINED.
  3. What existed and was lost: behavior, a test, a protection (a hook, a gate, a permission) or a documented promise
     that worked before the range and is removed or weakened with no request behind it.
  Before reporting, check each finding against the authorizations: what the human authorized is not a finding.
  Report each defect as BLOCKER or WARNING ("Findings"), with path:line.
  ```

- The reviewer never edits, and never re-runs a check that passed on the tree it reviews.
- A release also checks the CHANGELOG against question 1 (an entry with no change behind it, a change a user would notice with no entry). A hotfix goes to production: every change beyond the error described is a BLOCKER, even when it is right, and so is a cherry-picked commit that depends on anything not on `main`.

## The return review

After the fixes of a review's BLOCKERs, the same at a merge into `developer` and into `main`: two `reviewer` subagents in parallel, clean context, never the reviewer that found them.

| Part | Scope | Effort | Reports |
| --- | --- | --- | --- |
| Focused | Each BLOCKER of the round before and its fix | `high` | Per finding: fixed or still open; the same class of defect in another spelling or case; a test that proves the fix; what the fix itself broke |
| Light | The whole range again | `medium` | Only a BLOCKER that the fixes caused (a regression); anything else is a warning of the summary |

- Brief of the focused part: each finding as reported, the commits of its fix, what the suite proved, and the authorizations. Brief of the light part: the range, the commits of the fixes and the authorizations, with no finding.
- A finding whose class comes back after a fix: the next fix changes approach (a list of what is allowed instead of what is refused, a narrower scope, a refusal instead of an approval), never one more spelling.
- A third return review with a BLOCKER still open: stop, and give the human the open findings and the options: narrow the change, merge without that part with a `ready` request for it, or keep fixing.

## Findings

- BLOCKER, only one of:
  - it breaks a hard rule (`rules/security.md` "Hard rules");
  - a correctness defect of what was asked: the change does not do what the request says, or breaks something that worked (a failing test included);
  - a change outside the scope of the request, or a loss with no request behind it (question 2 UNEXPLAINED, question 3);
  - a real security risk that a mistake reaches (a person or an agent doing its normal work), not only someone writing code to escape the checks on purpose;
  - an acceptance criterion not proven, only when the request requires that proof in this delivery.
- WARNING: everything else. A best practice, a hardening idea, a deliberate-escape scenario, a proof the request leaves for later, a check that only makes the validation slower (a mandatory review or check that must run is never a defect of the delivery). It never returns the branch and never opens a round: it goes to the summary of the merge, once, and the human decides (`/merge`).
- Not a finding: what the human authorized (the brief's authorizations), and a finding the human already decided in an earlier round (an accepted risk, a warning answered). Never repeat one.
- A finding is not accepted only because it came. Check why the code is that way. Still disagree: give the human both positions and let the human decide.
- Never report style the formatter fixes. Never praise.

## Report format

```text
VERDICT: APPROVED | APPROVED_WITH_WARNINGS | REJECTED
FINDINGS:
- [BLOCKER] <path>:<line> — <problem> — <failure scenario> — <fix>
- [WARNING] <path>:<line> — <what was seen> — <why it may be a problem> — <what the human can do>
```

REJECTED when a BLOCKER exists. APPROVED_WITH_WARNINGS when only warnings exist: the branch still merges. A warning has the format of `rules/security.md` "Warnings", with its place.
