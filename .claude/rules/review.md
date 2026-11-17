# review.md

## When

- **Merge into `developer`** (`/caw-merge`): only the difference that enters, `origin/developer..<sha>`; what is already
  on `developer` was reviewed by the merge that brought it. Effort by risk:
  - `high`: the range changes a hook, the installer, `setup-claude.sh`, a gate script, a permission or deny rule, or
    anything that handles secrets or file modes;
  - `medium`: any other code or rule;
  - none: documentation only (`*.md` outside `.claude/` and `workspace/rules/`, `docs/`, `i18n/`, `maintainers/`);
    the final review covers it.
- **Merge into `main`** (`/caw-merge --main`, the release): the final review, below, on everything since the last tag.
- When the owner asks.

## How

- The `reviewer` subagent with a clean context: it did not write the change. Give it the code and the range, the
  requests the range delivers (`maintainers/requests/done/`) or the owner's words, and what the suite already proved.
  Never give it your conclusion.
- It reports only: a correctness defect; a security or data-loss problem with a concrete path; an acceptance criterion
  not met or not proven by a test; a protection that got weaker. Each with `path:line`, the failure scenario and the
  fix.
- A security finding counts only when a second clean-context review confirms it from the code.

## Final review

Two reviews, in this order, on `<last tag>..<release clone HEAD>`, after the translations are up to date and the suite
passed from the last tag. The same applies to the product's `/merge --main` (`workspace/rules/skills/merge/SKILL.md`).

1. **What enters and what leaves** (`reviewer`, claude-opus-5-5, effort `high`). Brief: the range, the requests and
   plans it delivers, the `Unreleased` sections of the changelogs, the suite's result. It answers, item by item:
   - an inventory of the range: what was added, changed and removed (files, commands, options, functions, tests,
     rules, hooks, deny rules, documented behavior), each with the request or business rule that asked for it, or
     CONSEQUENCE (of what), or UNEXPLAINED;
   - regression: everything removed or changed that worked at the last tag and that no request asks to remove or
     change; a test removed, skipped or weakened; a protection that got weaker;
   - intent: a change that does not do what its request asked, does more than it asked, or reads the request wrong;
     an acceptance criterion not met or not proven;
   - the changelogs: an entry with no change behind it, or a change a user would notice with no entry.

   UNEXPLAINED removals and regressions are BLOCKERs.
2. **General** (`reviewer`, claude-opus-5-5, effort `medium`). Brief: the whole tree at the release clone, and the
   range. It reads everything once for: rules that contradict each other, docs that contradict the code, references to
   things that no longer exist, translations that say something other than the English, leftovers (TODO, debug output,
   temporary files). It reports BLOCKER only for a contradiction that changes behavior; the rest is RECOMMENDED.

## Findings

- BLOCKER: fix it, rerun the suite, and review the fix (the same review, only the fix).
- RECOMMENDED: never blocks a merge. Each becomes a backlog item (`maintainers/backlog/<kebab-title>.md`, source: the
  review) and is listed in the summary; it is fixed only when the owner asks.
- A finding is not accepted only because it came: check why the code is that way. Still disagree: give the owner both
  positions.

```text
VERDICT: APPROVED | APPROVED_WITH_CHANGES | REJECTED
FINDINGS:
- [BLOCKER|RECOMMENDED] <path>:<line> — <problem> — <failure scenario> — <fix>
```
