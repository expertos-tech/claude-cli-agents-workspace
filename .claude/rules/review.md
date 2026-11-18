# review.md

## When

- **Merge into `developer`** (`/caw-merge`): only the difference that enters, `origin/developer..<sha>`; what is already
  on `developer` was reviewed by the merge that brought it.
- **Merge into `main`** (`/caw-merge --main`, the release, and `--hotfix`): everything since the last tag, widened to
  what the reviewer judges necessary (callers, dependents, the docs of what changed).
- The independent review of a stage (hooks, the installer, security, `process.md` step 4), and when the owner asks.

## Effort, by content

- Code and configuration: scripts, hooks, tests, settings, `.claude/` (rules, skills, agents), `CLAUDE.md`,
  `AGENTS.md`, `workspace/rules/`, `workspace/templates/`, `install.sh`: effort `xhigh`, the only use of it.
- Documents: every other `*.md` (`docs/`, `workspace/docs/`, `i18n/`, `maintainers/`, READMEs, changelogs): effort
  `high`.
- A merge with both: two `reviewer` subagents (claude-opus-5-5) in parallel, each with its part of the range.

## How

- The `reviewer` subagent with a clean context: it did not write the change. Give it the code and its part of the
  range, the requests the range delivers (`maintainers/requests/qa/`, with their Execution blocks, and at a release
  every one of them) or the owner's words, the changelog sections of the range, and what the suite already proved.
  Never give it your conclusion.
- It asks only three questions, the same at every merge (`workspace/rules/review.md` "How"):
  1. what was asked against what was done: each business rule and acceptance criterion, pending ones included, done
     and proven, done and not proven, or not done; an Execution block the code contradicts; a changelog entry with no
     change behind it, or a change a user would notice with no entry;
  2. what went beyond the request: each change with no request behind it, CONSEQUENCE (of what) or UNEXPLAINED;
  3. what existed and was lost: behavior, a test, a protection (a hook, a deny rule, the gate, a file mode) or a
     documented promise removed or weakened with no request behind it.
- It reports only defects, each with `path:line`, the failure scenario and the fix. UNEXPLAINED changes and losses
  are BLOCKERs; at a hotfix, so is every change beyond the error.
- A security finding counts only when a second clean-context review confirms it from the code.

## Findings

- BLOCKER: fix it, rerun the suite, and review the fix (the same review, only the fix).
- RECOMMENDED: never blocks a merge. At a merge into `developer` each becomes a `ready` request
  (`maintainers/requests/<kebab-title>.md`, adjustment size, source: the review), listed in the summary and fixed
  when the owner asks. At the release the owner chooses per finding: fix now, or a request.
- A finding is not accepted only because it came: check why the code is that way. Still disagree: give the owner both
  positions.

```text
VERDICT: APPROVED | APPROVED_WITH_CHANGES | REJECTED
FINDINGS:
- [BLOCKER|RECOMMENDED] <path>:<line> — <problem> — <failure scenario> — <fix>
```
