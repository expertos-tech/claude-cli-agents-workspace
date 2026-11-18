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
| `bash scripts/aiwp-cmds.sh open <work> <repo>` | `bash tests/caw-work.sh open <type>/<slug>`: the clone `tmp/work/<yyyy-mm-dd>-<slug>/claude-cli-agents-workspace`, its branch from `origin/developer`, its hooks, pushed |
| `bash scripts/aiwp-cmds.sh run <work>/<clone> -- <command>` | `bash tests/caw-work.sh run <work> -- <command>`, from the root |
| the clone's hooks push each commit | the same: the clone's hooks push after the company-terms scan; never by hand |
| `/merge` | `/caw-merge` |
| `rules/models.md`, `rules/git.md` | `.claude/rules/models.md`, `.claude/rules/git.md`, `.claude/rules/process.md` step 4 |

## CAW rules

- Arguments, from the repository root: none → `tmp/request.md`; a name with no `/` → the first that exists of
  `maintainers/requests/<name>`, `tmp/requests/<name>`, `tmp/<name>`, exactly as given (never add `.md`, complete a
  prefix or pick a similar name; never `maintainers/requests/qa/` or `done/`, which are not run again); a path → only
  that file, relative to the root or absolute. Not found: list every exact path tried and stop.
- Blocked: before anything, `git fetch -q origin` and `git merge-base --is-ancestor origin/main origin/developer`.
  False (a hotfix on `main` not merged into `developer` yet): refuse to start and say that `/caw-merge --hotfix --down`
  comes first (`.claude/skills/caw-merge/SKILL.md` "Blocked").
- Read the plan the request names too.
- The session stays at the root (settings and allow rules are read there): files of the clone by their path,
  commands by `bash tests/caw-work.sh run <work> -- <command>`. A prompt shows one thing (`CLAUDE.md` "The trail and
  the prompts").
- Prove each step: `/caw-check`; `/caw-test-install` when the installer, a hook or `setup-claude.sh` changed.
- The request never moves here: `/caw-merge` moves it to `qa/` with its Execution block.
- End with the report of `.claude/rules/process.md` step 6.
