---
name: caw-request
description: "Run the request written in a Markdown file as if the owner had typed it: a bare file name is looked up in maintainers/requests/, then tmp/requests/, then tmp/; a path reads only that file; no argument reads tmp/request.md. Use only when the owner asks."
argument-hint: "[file name | path]"
disable-model-invocation: true
model: claude-opus-5-5
effort: high
---

@workspace/rules/skills/request/SKILL.md

Read that file in full and follow it as the procedure, with the sections below over it: they win where they differ.

---

## Ignore from the product skill

- The session name from the `**Project:**` line (the `session-title.py` hook does not run here).
- Resolving a bare name only in `custom/requests/`: here the lookup is the one of "CAW rules".
- `custom/` and its commit and push.

## Mapping

| Product | Here |
| --- | --- |
| `custom/requests/<name>` | `maintainers/requests/<name>`, then `tmp/requests/<name>`, then `tmp/<name>` |
| `custom/requests/qa/<project>/`, `done/<project>/` | `maintainers/requests/qa/`, `maintainers/requests/done/` |
| `bash scripts/aiwp-cmds.sh open <work> <repo>` | `git clone -q --local . tmp/work/<yyyy-mm-dd>-<slug>/claude-cli-agents-workspace`, then in it `git remote set-url origin "$(git remote get-url origin)"`, `git fetch -q origin`, `git switch -c <type>/<slug> origin/developer`, `git push -u origin HEAD` |
| the clone's hooks push each commit | push the branch after each commit, by hand |
| `/merge` | `/caw-merge` |
| `rules/models.md`, `rules/git.md` | `.claude/rules/models.md`, `.claude/rules/git.md`, `.claude/rules/process.md` step 4 |

## CAW rules

- Arguments, from the repository root: none → `tmp/request.md`; a name with no `/` → the first that exists of
  `maintainers/requests/<name>`, `tmp/requests/<name>`, `tmp/<name>`, exactly as given (never add `.md`, complete a
  prefix or pick a similar name; never `maintainers/requests/qa/` or `done/`, which are not run again); a path → only
  that file, relative to the root or absolute. Not found: list every exact path tried and stop.
- Read the plan the request names too.
- Prove each step: `/caw-check`; `/caw-test-install` when the installer, a hook or `setup-claude.sh` changed.
- The request never moves here: `/caw-merge` moves it to `qa/` with its Execution block.
- End with the report of `.claude/rules/process.md` step 6.
