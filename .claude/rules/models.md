# models.md

- Every subagent call states its model and its effort. A call that would inherit them is a mistake.
- Models: `claude-opus-5-5`, `claude-sonnet-5-5`, `claude-haiku-5-5` (the agent files use the full ids; a call that
  accepts only aliases uses `opus`, `sonnet`, `haiku`). Fable only when the owner asks for it by name.
- Effort `high` for hooks, the installer, security, risky actions and every review; the effort of the stage otherwise.

| Task | Agent | Model | Effort |
| --- | --- | --- | --- |
| Gaps of a plan or request | `requirements-analyst` | claude-opus-5-5 | high |
| Independent review | `reviewer` | claude-opus-5-5 | high |
| Scripts, hooks and their tests | `script-engineer` | claude-opus-5-5 | high for hooks and the installer, else medium |
| Docs and their pt-BR and es translations | `docs-writer` | claude-sonnet-5-5 | medium |
| Running the suite, returning only result lines | `verifier` | claude-haiku-5-5 | low |
| Official docs, versions, prices | `web-researcher` | claude-sonnet-5-5 | high |

- Default: no subagent. Delegate independent work on disjoint paths, a search that would flood the context, a long
  noisy check, and every review. At most 4 subagents at once.
- A subagent does not see the conversation: its brief gives the goal, the context and decisions, the files to read,
  change and not touch, the done-when checks, and the return format (status, changed paths, checks, open points; at
  most 30 lines).
- Subagents never commit or push: the main session does.
