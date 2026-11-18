@workspace/rules/review.md

The sections below win where they differ; its `paths:` do not limit it here.

---

## Ignore from the product rule

- How, "For a project diff, `/code-review` is an equivalent": the review here is the `reviewer` subagent.
- How, the audit file phase 1 printed: this repository's gate prints none.

## Mapping

| Product | Here |
| --- | --- |
| the human | the owner |
| waves | stages |
| the gate (`rules/git.md` "Gate", `/merge`), its two phases | `/caw-merge`: `bash tests/check.sh --base origin/developer --i18n-pending`, then the review, then the push of `developer` |
| the range phase 1 printed | `origin/developer..<sha>` |
| what phase 1 already verified; a failing test | what the suite already proved; a failing check |
| the requests of `custom/requests/qa/<project>/` | the requests of `maintainers/requests/qa/`, with their Execution blocks; at a release every one of them |
| `rules/security.md` "Hard rules", `rules/models.md` | `.claude/rules/security.md` (the product's list with this repository's rows), `.claude/rules/models.md` |
| a protection (a hook, a gate, a permission) | a hook, a deny rule, the gate, a file mode |
| a warning the human chooses in the summary of `/merge` | `maintainers/requests/<kebab-title>.md`, `**State:** ready`, adjustment size, source: the review |

## CAW rules

- The agent's own tests and the suite close each stage.
- Into `developer`: what is already on `developer` was reviewed by the merge that brought it; never again.
- A review the owner asks for runs with the effort the owner gives.
- The brief also gives the changelog sections of the range: the root `CHANGELOG.md`, and `workspace/CHANGELOG.md` for
  a product change.
- Question 1, at every merge, not only at the release: also an Execution block the code contradicts, and a changelog
  entry with no change behind it, or a change a user would notice with no entry.
- A security BLOCKER counts only when a second clean-context review confirms it from the code.
- The warnings: at a merge into `developer` the summary lists each one once, and the owner decides: fix, a `ready`
  request, or accept. At the release the owner chooses per warning: fix now, a request, or accept.
