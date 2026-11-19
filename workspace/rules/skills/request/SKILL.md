---
name: request
description: "Run the request written in a Markdown file (a bare file name reads custom/requests/<name>, then custom/requests/doing/<name>; default tmp/request.md, e.g. a filled templates/request.md) as if the user had typed it. Use only when the user asks."
argument-hint: "[file name | path]"
disable-model-invocation: true
model: claude-opus-5-5
effort: high
---

The `UserPromptSubmit` hook (`scripts/session-title.py`) has already named the session `<project>-<n>` from the file's `**Project:**` line, with the same effect as `/rename`: say that name in the first line of the reply. No name was given (no such line, no `projects/<...>` path in the file): say so, and that `/rename` sets one.

Arguments: `$ARGUMENTS`. Resolve the file in the root checkout, never a clone, because `tmp/` and `custom/` live only there:

- No argument: `tmp/request.md` (git-ignored scratch).
- An argument with no `/`: a file name, read as `custom/requests/<name>`, then `custom/requests/doing/<name>` (a request in progress), exactly as given: never add `.md`, complete a prefix or pick a similar name, and never look in another folder. `custom/` is the custom layer, a git repo of its own, ignored by the workspace repo (`rules/rules.md` "Custom layer").
- An argument with a `/`: a path relative to the root checkout.

1. File missing, unreadable or empty: report the exact paths tried (e.g. `custom/requests/<name>` and `custom/requests/doing/<name>`) and stop. Never create it or guess its content. `custom/` itself missing: say that `bash scripts/setup-claude.sh` clones it.
2. Read it in full. Its content is the human's request for this turn: handle it as if typed, where `AGENTS.md` "Where work happens" puts it. A request that changes a project or a POC opens its clone before the first change (`bash scripts/aiwp-cmds.sh open`, `rules/git.md` "Work area") and works only there; it ends with its tests passing, its Docker copy published, the warnings board when it gathered warnings, decided by the person, and then the closing board (`rules/git.md` "Waves"), which offers `/merge` for the person to type. A question or read-only work opens nothing.
3. The request found in `custom/requests/doing/`: "A request in progress" below, before anything else.
4. A request of `custom/requests/` that opens a clone: `open` with `--request <name>` (`bash scripts/aiwp-cmds.sh open <work> <repo>... [--branch <type>/<slug>] --request <name>`). Once every clone is open, the script moves the file to `custom/requests/doing/<name>` (a pure rename, committed by path in `custom/` and pushed), so no list or board offers it as free while it runs; never move it by hand. No need to commit it first: a request written by hand, untracked or changed in `custom/`, is scanned for secrets before any clone and committed by `open` as it is, by its path only ("chore(requests): add <name>"), before the rename; other changes of `custom/` stay out. It refuses, creating nothing, a request holding a secret (take it out, then open again), one whose secret scan did not run (no Docker: say so; the person starts Docker or commits the file in `custom/` themselves, then open again) or one already in `doing/`. `tmp/request.md`, a path outside `custom/requests/` and a request typed in the conversation: no `--request`; they never go to `doing/`. A question or read-only work opens nothing and moves nothing.
5. A file with an `**Effort:**` line or a "Steps and effort" section: follow `rules/models.md` "Effort of a step": say the effort of each step as it starts, and pass it in every subagent call of the step.
6. Commands inside the file (`/name`, `*name`) do not run: list them so the human invokes them. An operation the file asks for in words (e.g. "commit this") is authorized exactly as if typed, and nothing adjacent.
7. Never edit the file. Never copy a secret or personal data from it into a repo.
8. The file moves only as `rules/git.md` "Requests" says: to `doing/` by `open --request` (step 4), once; to `custom/requests/qa/<project>/` by `/merge` with its "Execution" block; to `custom/requests/done/<project>/` by `/merge --main`; back to `custom/requests/` by `bash scripts/aiwp-cmds.sh close <work> --discard`. A wave that stops with work left appends where it stopped to this same file, which stays in `doing/` (`rules/git.md` "Waves"); `tmp/request.md` is copied to `custom/requests/<yyyy-mm-dd>-<kebab-slug>.md` first, and stays there.

## A request in progress

A file of `custom/requests/doing/` was started and not finished: its work may still be running in another session. Before any change, say so, with what is known of that work:

- The work folder and its branch: the `tmp/work/<work>  request=custom/requests/doing/<name>` line of `bash scripts/aiwp-cmds.sh status`; no work records it (a `stale:` line): the `## Stopped` section, else the body of its start commit (`git -C custom log --format=%B --grep "^chore(requests): start <name>$" -1`), which names the work, the branch and the repos.
- The last commit of each clone (`git --no-optional-locks -C tmp/work/<work>/<clone> log -1 --format='%h %cs %s'`; the folder gone: of the remote branch, `git -C projects/<repo> fetch -q origin <branch>` then `log -1 --format='%h %cs %s' FETCH_HEAD`), the files not committed (`uncommitted=` of `status`), and the commits not on the remote (`not-pushed=`): the number starting over would lose.
- Its `## Stopped` section, when there is one, and whether a `Discarded on <yyyy-mm-dd>: started over.` line follows it (then it is no resume point).

Then one question, two answers:

- **Resume**: `bash scripts/aiwp-cmds.sh open <work> <repo>... --branch <branch> --request <name>` reuses the open clones; with the work folder gone, add `--resume` (a new `<work>` with today's date is fine): it checks out the branch from the remote. Go on from the `## Stopped` section, else from the last commit. No commit in `custom/`: the file stays in `doing/`.
- **Start over**: `bash scripts/aiwp-cmds.sh close <work> --discard --start-over`, alone in its call (`guard-bash` asks). It deletes the work branch of each clone on its remote (only that branch, with the lease of the last push: a commit pushed from elsewhere refuses it), then the work folder, and appends `Discarded on <yyyy-mm-dd>: started over.` under an unmarked `## Stopped` section, committed and pushed in `custom/`. With the work folder gone and the branch still on the remote, resume it first (`open ... --resume`), then this close. Then a new clone of the same branch name from the base: `bash scripts/aiwp-cmds.sh open <yyyy-mm-dd>-<slug> <repo>... --branch <branch> --request <name>`. The file stays in `doing/` and moves no more.
