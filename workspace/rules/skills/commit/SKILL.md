---
name: commit
description: "Create one Conventional Commit per logical change in the checkout that holds the changes. Use only when the user asks to commit."
argument-hint: "[--all] [--repo <dir>]"
disable-model-invocation: true
model: claude-opus-5-5
effort: medium
---

Arguments: `$ARGUMENTS`. `--repo <dir>`: a clone of `tmp/work/` (`tmp/work/<work>/<clone>`), or `custom`; default: the clones and the custom files changed in this session. `projects/` and the core take no commit here (`rules/git.md` "Authorization"). `--all`: every pending change of that checkout, not only this session's.

Follow `rules/git.md`. This request authorizes commits only: no new branch, no merge. In a clone, the commit is pushed by the clone's own hooks.

1. Per repo, the checkout is the clone itself (or `custom/`).
2. `git -C <checkout> status --short`, `git -C <checkout> diff` and `git -C <checkout> diff --cached`. No changes: say so and stop for that repo. Staged paths that are not this session's changes (any pending change, with `--all`): list them and stop; never commit or unstage them on your own.
3. Select the changes: this session's only, or all with `--all`. Group them into logical changes; one commit each.
4. Never write `CHANGELOG.md`: `/merge` writes it from the commits (`rules/docs.md` "CHANGELOG.md"), so the message must say what changed for the reader.
5. Read the selected diff for keys, tokens, credentials and `.env`. A finding: stop and report.
6. Write the message of `rules/git.md` "Commits" to a temporary file. Stage by path and commit by the same paths, written out (never in a shell variable): `git -C <checkout> add -- <paths>`, then `git -C <checkout> commit -F <file> -- <paths>`. A refusal (the clone's pre-push scan, or the `guard-bash` hook in `custom/`) is reported, never worked around.
7. Reply in the language of the conversation: per repo, `<hash> <title>`, what was left and why.
