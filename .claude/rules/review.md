# review.md

The same rules as the product (`workspace/rules/review.md`, `workspace/rules/security.md` "Hard rules" and
"Warnings"), with this repository's hard rules (`security.md`).

## Two roles

- During a request the agent is its developer: it implements, tests what it did, fixes and tests again. No
  independent review runs during the stages, hooks, the installer and security included: the agent's own tests and
  the suite close each stage.
- The review runs once, at `/caw-merge`, as the tech lead: it validates what the agent did against the request and
  the standards already defined. Only a real BLOCKER returns the branch; the rest goes to the merge summary, once, as
  warnings.

## When

- **Merge into `developer`** (`/caw-merge`): only the difference that enters, `origin/developer..<sha>`; what is already
  on `developer` was reviewed by the merge that brought it. Effort `medium`.
- **Merge into `main`** (`/caw-merge --main`, the release, and `--hotfix`): everything since the last tag, widened to
  what the reviewer judges necessary (callers, dependents, the docs of what changed). Effort `high`.
- When the owner asks, with the effort the owner gives.
- One `reviewer` subagent (claude-opus-5-5) per merge, whatever the range holds; a range too large for one context is
  split in parts, each to its own `reviewer` with the same effort, in parallel.
- A change to an existing script (an installer, a hook): only its difference; the rest of the file is read to
  understand it, never reviewed again.

## How

- The `reviewer` subagent with a clean context: it did not write the change. Give it the code and the range, the
  requests the range delivers (`maintainers/requests/qa/`, with their Execution blocks, and at a release every one of
  them) or the owner's words, the changelog sections of the range, what the suite already proved, and the
  authorizations: each decision of the owner in the requests, their plans or the conversation that allows something
  a validator would flag (an allow rule, an accepted risk, a push after the warning), quoted with its source. Never
  give it your conclusion.
- It asks only three questions, the same at every merge (`workspace/rules/review.md` "How"):
  1. what was asked against what was done: each business rule and acceptance criterion, pending ones included, done
     and proven, done and not proven, or not done; an Execution block the code contradicts; a changelog entry with no
     change behind it, or a change a user would notice with no entry;
  2. what went beyond the request: each change with no request behind it, CONSEQUENCE (of what) or UNEXPLAINED;
  3. what existed and was lost: behavior, a test, a protection (a hook, a deny rule, the gate, a file mode) or a
     documented promise removed or weakened with no request behind it.
- Before reporting, it checks each finding against the authorizations: what the owner authorized or already decided
  is not a finding, and is never repeated.
- It reports only defects, each with `path:line`, as BLOCKER or WARNING ("Findings"). At a hotfix, every change
  beyond the error is a BLOCKER.

## The return review

After the fixes of a review's BLOCKERs, at a merge into `developer` or `main`, the same as the product
(`workspace/rules/review.md` "The return review"): two `reviewer` subagents (claude-opus-5-5) in parallel, never the
one that found them.

- **Focused**, effort `high`: each BLOCKER of the round before and its fix: fixed or still open, the same class of
  defect in another spelling or case, a test that proves it, what the fix broke. Brief: the findings as reported, the
  commits of the fixes, what the suite proved, the authorizations.
- **Light**, effort `medium`: the whole range again, only for a BLOCKER the fixes caused; anything else is a warning
  of the summary. Brief: the range, the commits of the fixes and the authorizations, with no finding.
- A class that comes back after a fix: the next fix changes approach (an allowlist instead of a blocklist, a narrower
  scope, a refusal instead of an approval), never one more spelling.
- A third return review with a BLOCKER still open: stop and give the owner the open findings and the options: narrow
  the change, merge without that part with a `ready` request, or keep fixing.

## Findings

- BLOCKER, only one of: a hard rule broken (`security.md` "Hard rules"); a correctness defect of what was asked (it
  does not do what the request says, or breaks something that worked, a failing check included); a change outside
  the scope of the request, or a loss with no request behind it (UNEXPLAINED); a real security risk that a mistake
  reaches, not only a deliberate escape; an acceptance criterion not proven, only when the request requires that
  proof in this delivery. Fix it, rerun the suite, then the return review. A security BLOCKER counts only when a
  second clean-context review confirms it from the code.
- WARNING: everything else (a best practice, a hardening idea, a deliberate-escape scenario, a proof left for later,
  a mandatory check that only makes the validation slower). It never blocks a merge and never opens a round. At a
  merge into `developer` the summary lists each one once, and the owner decides: fix, a `ready` request
  (`maintainers/requests/<kebab-title>.md`, adjustment size, source: the review), or accept. At the release the owner
  chooses per warning: fix now, a request, or accept.
- A finding is not accepted only because it came: check why the code is that way. Still disagree: give the owner both
  positions.

```text
VERDICT: APPROVED | APPROVED_WITH_WARNINGS | REJECTED
FINDINGS:
- [BLOCKER] <path>:<line> — <problem> — <failure scenario> — <fix>
- [WARNING] <path>:<line> — <what was seen> — <why it may be a problem> — <what the owner can do>
```
