---
name: caw-request
description: "Run the request written in a Markdown file as if the owner had typed it: a bare file name is looked up in maintainers/requests/, then maintainers/requests/doing/ (a request in progress: resume or start over), then tmp/requests/, then tmp/; a path reads only that file; no argument reads tmp/request.md. Use only when the owner asks."
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
- Resolving a bare name only in `custom/requests/` and `custom/requests/doing/`: here the lookup is the one of "CAW
  rules".
- `custom/` and its commit and push; the move to `doing/` after the clones open (here `start` moves it before, "CAW
  rules").
- "A request in progress": the `stale:` line read from the body of the start commit in `custom/`, `projects/<repo>`,
  `guard-bash` asking, and the line `Discarded on <yyyy-mm-dd>: started over.` (here the `## Stopped` section lives on
  the work branch, which a start over deletes): "CAW rules".

## Mapping

| Product | Here |
| --- | --- |
| `custom/requests/<name>` | `maintainers/requests/<name>`, then `maintainers/requests/doing/<name>`, then `tmp/requests/<name>`, then `tmp/<name>` |
| `custom/requests/doing/` | `maintainers/requests/doing/`, its README row with the Status `doing` |
| `custom/requests/qa/<project>/`, `done/<project>/` | `maintainers/requests/qa/`, `maintainers/requests/done/` |
| `bash scripts/aiwp-cmds.sh open <work> <repo>` | `bash tests/caw-work.sh open <type>/<slug>`: the clone `tmp/work/<yyyy-mm-dd>-<slug>/claude-cli-agents-workspace`, its branch from `origin/developer`, its hooks, pushed |
| `open ... --request <name>`, `--resume` | `bash tests/caw-work.sh start <name> --branch <type>/<slug>` first, then `bash tests/caw-work.sh open <type>/<slug> --request <name>` (`--resume` the same) |
| `bash scripts/aiwp-cmds.sh status`: `request=`, `uncommitted=`, `not-pushed=`, `stale:` | `bash tests/caw-work.sh status`: the same lines |
| `bash scripts/aiwp-cmds.sh close <work> --discard [--start-over]` | `bash tests/caw-work.sh close <work> --discard [--start-over]` |
| `bash scripts/aiwp-cmds.sh run <work>/<clone> -- <command>` | `bash tests/caw-work.sh run <work> -- <command>`, from the root |
| the clone's hooks push each commit | the same: the clone's hooks push after the company-terms scan; never by hand |
| `/merge` | `/caw-merge` |
| `rules/models.md`, `rules/git.md` | `.claude/rules/models.md`, `.claude/rules/git.md`, `.claude/rules/process.md` step 4 |

## CAW rules

- Arguments, from the repository root: none → `tmp/request.md`; a name with no `/` → the first that exists of
  `maintainers/requests/<name>`, `maintainers/requests/doing/<name>`, `tmp/requests/<name>`, `tmp/<name>`, exactly as
  given (never add `.md`, complete a prefix or pick a similar name; never `maintainers/requests/qa/` or `done/`, which
  are not run again); a path → only that file, relative to the root or absolute. Not found: list every exact path
  tried and stop.
- Blocked: before anything, `git fetch -q origin` and `git merge-base --is-ancestor origin/main origin/developer`.
  False (a hotfix on `main` not merged into `developer` yet): refuse to start and say that `/caw-merge --hotfix --down`
  comes first (`.claude/skills/caw-merge/SKILL.md` "Blocked").
- Read the plan the request names too.
- The session stays at the root (settings and allow rules are read there): files of the clone by their path,
  commands by `bash tests/caw-work.sh run <work> -- <command>`. A prompt shows one thing (`CLAUDE.md` "The trail and
  the prompts").
- Prove each step: `/caw-check`; `/caw-test-install` when the installer, a hook or `setup-claude.sh` changed.
- A request of `maintainers/requests/` that opens a clone moves to `doing/` before the clone opens, once: first
  `bash tests/caw-work.sh start <name> --branch <type>/<slug>` at the root (it moves the file and sets the Status of
  its README row to `doing` in one commit pushed to `developer`, only within its checks; `.claude/rules/git.md`
  "Remote"), then `bash tests/caw-work.sh open <type>/<slug> --request <name>`, so the branch holds the move. `start`
  refused: report its reasons and stop; never move the file, commit at the root or push by hand. A request of
  `tmp/requests/`, `tmp/`, `tmp/request.md`, a path elsewhere or a request typed in the conversation: no `start`, no
  `--request`. A question or read-only work moves nothing.
- Then the file moves only by `/caw-merge` (to `qa/`, with its Execution block, and its README row to "QA") or back to
  pending by `bash tests/caw-work.sh close <work> --discard` (the reverse commit). A stage that stops writes its
  `## Stopped` section in the clone, in `maintainers/requests/doing/<name>`, committed there; the file stays in
  `doing/`.
- End with the report of `.claude/rules/process.md` step 6.

### A request in progress

The name resolved in `maintainers/requests/doing/`: it was started and not finished, and its work may still be running
in another session. Before any change, say so, with what is known of that work:

- The work folder and its branch: the `tmp/work/<work>  request=maintainers/requests/doing/<name>` line of
  `bash tests/caw-work.sh status`, and the `branch=` of its clone. No work records it (a `stale:` line): the branch
  named in the body of its start commit
  (`git log -1 --format=%B --grep "^chore(requests): start <name>$" origin/developer`), else ask the owner which
  branch.
- The last commit (sha, date, title): `bash tests/caw-work.sh run <work> -- git log -1 --format='%h %cs %s'`; the
  folder gone: `git fetch -q origin <branch>`, then `git log -1 --format='%h %cs %s' FETCH_HEAD`.
- The files not committed (`uncommitted=` of `status`) and the commits not on the remote (`not-pushed=`): the number a
  start over loses.
- Its `## Stopped` section, when there is one: in the clone's `maintainers/requests/doing/<name>`; the folder gone,
  `git show FETCH_HEAD:maintainers/requests/doing/<name>`.

Then one question, two answers. Neither makes a start commit; the file stays in `doing/`.

- **Resume**: `bash tests/caw-work.sh open <branch> --request <name>` reuses the clone of that branch; with the work
  folder gone, add `--resume`: it checks the branch out from the remote. Go on from the `## Stopped` section, else
  from the last commit.
- **Start over**: `bash tests/caw-work.sh close <work> --discard --start-over`: it deletes the work branch on the
  remote (only that branch, never `developer` or `main`, with the lease of the clone's last push: a commit pushed
  there from elsewhere refuses it and keeps everything), then the work folder; no `Discarded on` line, since the
  `## Stopped` section lived on that branch. With the work folder gone and the branch still on the remote, resume it
  first (`open ... --resume`), then this close. Then a new clone of the same branch from `origin/developer`:
  `bash tests/caw-work.sh open <branch> --request <name>`.
