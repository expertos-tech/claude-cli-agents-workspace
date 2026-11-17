---
name: caw-commit
description: "Create one Conventional Commit per logical change of this session in the repository, by path, per .claude/rules/git.md. Use only when the owner asks to commit."
argument-hint: "[--all]"
disable-model-invocation: true
model: claude-opus-5-5
effort: medium
---

Arguments: `$ARGUMENTS`. `--all`: every pending change of the repository, not only this session's.

This request authorizes commits only: no push, no branch, no tag, no merge.

1. `git status --short`, `git diff` and `git diff --cached`. No changes: say so and stop. Staged paths that are not
   this session's changes (or any, with `--all`): list them and stop; never commit or unstage them on your own.
2. Group the selected changes into logical changes; one commit each. A changed English document goes with its
   translations (`.claude/rules/docs.md`); both paths of a move go together.
3. Read the selected diff for company terms, personal paths, e-mail addresses, internal URLs, keys, tokens and `.env`
   (`.claude/rules/security.md`). A finding: stop and report it without printing the term.
4. `/caw-check` passed on these changes in this session; if not, run it first.
5. Write the message of `.claude/rules/git.md` to a file in the scratchpad and commit by path:
   `git commit -F <file> -- <paths>` (or `git add -- <paths>` then `git commit -F <file>`).
6. Report `<hash> <title>` per commit, and what was left out and why.
