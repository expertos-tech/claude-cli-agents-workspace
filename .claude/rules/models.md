@workspace/rules/models.md

Read that file in full before the first action it governs, and follow it with the sections below over it: they win
where they differ. Its `paths:` do not limit it here: it applies wherever this file applies.

---

## Ignore from the product rule

- Models, the bullet on `rules/agents/settings.json` and `scripts/guard-subagent-model.sh`, and the hook that asks on
  Fable: no product hook runs here, so nothing sets a model for a call (CAW rules).
- Subagents, the rows of agents this repository does not have: `architect`, `implementer`, `test-engineer`,
  `code-explorer`, `infra-engineer` and the analysts of `/normalize-projects`. The agents here are `.claude/agents/`.
- Brief, the `VERIFICATION:` line: this repository has no verification mode.

## Mapping

| Product | Here |
| --- | --- |
| the human | the owner |
| `rules/skills/*/SKILL.md` | `.claude/skills/caw-*/SKILL.md` |
| `rules/review.md`, `rules/git.md` "Work area" | `.claude/rules/review.md`, a clone of `bash tests/caw-work.sh open` |
| step, wave | stage (`process.md` step 4) |
| Functional gaps of a request | Gaps of a plan or request |
| Documentation | Docs in English |

## CAW rules

- Every subagent call states its model and its effort. A call that would inherit them is a mistake.
- Effort `high` for hooks, the installer, security and risky actions; the effort of the stage otherwise.
- The rows of this repository, over the product's rows of the same agent:

| Task | Agent | Model | Effort |
| --- | --- | --- | --- |
| Scripts, hooks and their tests | `script-engineer` | claude-opus-5-5 | high for hooks and the installer, else medium |
| The pt-BR and es translations, once per release | `docs-writer`, one call | claude-sonnet-5-5 | medium |
