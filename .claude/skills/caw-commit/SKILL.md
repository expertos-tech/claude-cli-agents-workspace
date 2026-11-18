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
- The product's pre-push secret scan of a clone: here the clone's hooks run the company-terms scan
  (`tests/caw-work.sh`).

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
- Stage, then commit by the same paths, written out in the command (never in a shell variable: zsh passes an unquoted
  variable as one word): at the root, the message of `.claude/rules/git.md` in a file of the scratchpad,
  `git add -- <paths>`, then `git commit -F <file> -- <paths>`. In a work clone, the message in the clone's
  `.git/CAW_COMMIT_MSG` (inside the clone, never committed), then
  `bash tests/caw-work.sh run <work> -- git add -- <paths>` and
  `bash tests/caw-work.sh run <work> -- git commit -F .git/CAW_COMMIT_MSG -- <paths>`. The clone's hooks push it; a
  refused push (a company term) is reported, never worked around.
