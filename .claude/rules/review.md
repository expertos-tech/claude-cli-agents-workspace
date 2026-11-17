# review.md

## When

- Before a stage closes, when it changed a hook, the installer, `setup-claude.sh`, a permission or deny rule, the gate,
  or anything that handles secrets or file modes.
- Before a release, on the whole diff since the last tag.
- When the owner asks.

## How

- The `reviewer` subagent, effort high, with a clean context: it did not write the change. Give it the code and the
  range (`git diff <base>..HEAD -- <paths>`), the acceptance criteria, and what the suite already proved. Never give it
  your conclusion.
- It reports only: a correctness defect; a security or data-loss problem with a concrete path; an acceptance criterion
  not met or not proven by a test; a protection that got weaker. Each with `path:line`, the failure scenario and the fix.
- A security finding counts only when a second clean-context review confirms it from the code.

## Findings

- BLOCKER: fix it, rerun `bash tests/check.sh --all`, and review the fix. RECOMMENDED: fix it when cheap, else list it in
  the report or the backlog.
- A finding is not accepted only because it came: check why the code is that way. Still disagree: give the owner both
  positions.

```text
VERDICT: APPROVED | APPROVED_WITH_CHANGES | REJECTED
FINDINGS:
- [BLOCKER|RECOMMENDED] <path>:<line> — <problem> — <failure scenario> — <fix>
```
