# models.md

## Models

- Allowed: `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-haiku-5-5`. The main session and `CLAUDE_CODE_SUBAGENT_MODEL` follow the `opus` alias. Agent files use the full ids; a call that accepts only aliases uses `opus`, `sonnet`, `haiku`.
- Fable: only the human activates it, in the main session, through `/model`. Never select or start it on your own, never as a fallback, never in a skill or agent file. A subagent runs on it only when the human expressly asks for one with Fable and an effort; the hook then asks the human to confirm.
- `rules/agents/settings.json` starts every session on `opus` with effort `medium`. The `PreToolUse` hook `scripts/guard-subagent-model.sh` denies a fork and a model outside the list, asks on Fable, and sets `opus` on a call that would inherit.
- The goal is the correct result at the lowest cost that keeps it. A model or an effort above the default of the table needs the human's approval; `xhigh` exists only for the merge review.
- Model unavailable: fall back only inside the allowed list, and say so in the delivery summary.

## Skills

- Every `rules/skills/*/SKILL.md` sets `model: claude-opus-5-5`, the main session's model, and an `effort`. Another model would re-read the whole session with no prompt cache.

## Subagents

| Task | Agent | Model | Effort |
| --- | --- | --- | --- |
| Functional gaps of a request | `requirements-analyst` | claude-opus-5-5 | high |
| A hard-to-reverse architecture decision | `architect` | claude-opus-5-5 | high |
| Implementation and refactoring | `implementer` | claude-opus-5-5 | high |
| Tests for acceptance criteria with none | `test-engineer` | claude-opus-5-5 | medium |
| Merge review (`rules/review.md`) | `reviewer` | claude-opus-5-5 | `xhigh` for code and configuration, `high` for documents |
| Return review after fixes (`rules/review.md`) | `reviewer`, two in parallel | claude-opus-5-5 | `high` focused on the findings, `medium` light on the whole range |
| Code search, locating reuse | `code-explorer` | claude-sonnet-5-5 | medium |
| Web research: docs, versions, prices | `web-researcher` | claude-sonnet-5-5 | high |
| Documentation | `docs-writer` | claude-sonnet-5-5 | medium |
| Terraform and cost estimates | `infra-engineer` | claude-opus-5-5 | high |
| Reusable scripts in `scripts/` | `script-engineer` | claude-sonnet-5-5 | medium |
| Running checks and returning only the result lines | `verifier` | claude-haiku-5-5 | low |
| The four analysts of `/normalize-projects` (read only) | `code-explorer` | claude-opus-5-5 (`model: opus` in the call) | high |
| The four analysts and the conflict check of `/normalize-rules` (read only) | `code-explorer` | claude-opus-5-5 (`model: opus` in the call) | high |

## Effort of a step

- A request that gives an effort per step ("Steps and effort", or an `**Effort:**` line): at the start of each step, say in one line the effort it asks for. The human sets the session's level with `/effort`; do not wait for it.
- Pass the effort of the step in every subagent call of that step. It replaces the default of the table above for that call. Two roles keep their own: `verifier` at `low`, with the exact command in its brief, and `reviewer` by `rules/review.md` ("Effort, by content" and "The return review"). `xhigh` is allowed only for that review.
- No effort given: the defaults of the table.

## When to delegate

- Default: one agent, no subagent. A role existing in the table is no reason to use it: a subagent starts with no context and must gather what the session already knows.
- Delegate for: independent work that runs in parallel on disjoint files; a search whose output would flood the context; a review, which needs a context that did not write the code.
- A long, noisy check (a full suite, `scripts/validate.sh`) may run through `verifier`, which returns only the result lines.
- At most 4 subagents at once. Two writers on overlapping files run one after the other, or each in its own clone (`rules/git.md` "Work area").
- The `reviewer` runs after the implementation is complete, never beside the writer it reviews.
- Subagents never commit, merge or push: the main session does.

## Brief

A subagent does not see the conversation. Its brief states:

```text
GOAL: <one sentence: the outcome, not the steps>
CONTEXT: <request summary, acceptance criteria, decisions already taken>
FILES: read=<paths> change=<paths> do-not-touch=<paths>
CLONE: <absolute path of the clone in tmp/work/, when it changes files of a repo>
DONE WHEN: <checks that can be verified>
VERIFY: <the exact commands to run>
VERIFICATION: <auto|manual: the session's mode (`rules/quality.md` "Verification mode"); left out of a `reviewer` brief>
RETURN: <the format below, at most 30 lines>
```

- Point to files by path; never paste content the subagent can read.
- A subagent that runs a task heavy on CPU or GPU (graphics, 3D rendering) follows `rules/machine-load.md`: say so in the brief.

## Return format

```text
STATUS: done | partial | blocked
CHANGED: <path> — <one line>
CHECKS: <command> → pass|fail
OPEN: <gaps, risks, questions for the human>
```

- Never raw logs, whole files or diffs: cite `path:line`. A large artifact goes to a file, and the return gives its path.
- A number or a claim from a subagent that will go into a plan or a decision record: confirm it against the code or the log first.
