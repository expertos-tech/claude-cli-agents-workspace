---
name: caw-commit
description: "Create one Conventional Commit per logical change of this session in the repository, by path, per .claude/rules/git.md. Use only when the owner asks to commit."
argument-hint: "[--all]"
disable-model-invocation: true
model: claude-opus-5-5
effort: medium
---

@workspace/rules/skills/commit/SKILL.md

Read that file in full and follow it as the procedure, with the sections below over it: they win where they differ.

---

## Ignore from the product skill

- `--repo`, the clones of `tmp/work/` as separate repos and `custom/`: here there is one repository, the root (or the
  clone of `tmp/work/` the session works in, the same repository).
- The step that checks a project's `CHANGELOG.md`: `/caw-merge` writes both changelogs.
- The pre-push scan of a clone: this repository has no hooks.

## Mapping

| Product | Here |
| --- | --- |
| `rules/git.md` "Commits" | `.claude/rules/git.md` |
| keys, tokens, credentials, `.env` | also company terms, personal paths, e-mail addresses, internal URLs (`.claude/rules/security.md`) |
| the checkout of a clone | the repository root, or this session's clone in `tmp/work/` |

## CAW rules

- `--all`: every pending change of the repository, not only this session's.
- This request authorizes commits only: no push, no branch, no tag, no merge.
- `/caw-check` passed on these changes in this session; if not, run it first.
- A finding of company data: stop and report it without printing the term.
- Write the message of `.claude/rules/git.md` to a file in the scratchpad and commit by path:
  `git commit -F <file> -- <paths>`.
