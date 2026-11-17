---
name: push
description: "Push the custom/ repo, or push again a clone of tmp/work/ whose automatic push failed. Use only when the user asks to push."
argument-hint: "[--repo custom | <work>/<clone>]"
disable-model-invocation: true
model: claude-opus-5-5
effort: low
---

Arguments: `$ARGUMENTS`. `--repo custom`: the custom layer repo; `<work>/<clone>`: a clone of `tmp/work/`. Default: the clones and `custom/` this session changed. `projects/` and the core are never pushed here: the gate pushes the base (`rules/git.md` "Gate").

1. A clone: `bash scripts/aiwp-cmds.sh push <work>/<clone>`. It runs the clone's pre-push checks; a refusal (env file, secret, remote unreadable) is reported, never worked around.
2. `custom/`: `git -C custom status --short`; uncommitted changes do not go in a push, list them. Then `git -C custom push origin <branch checked out>`. Never `--force`, never `--no-verify`.
3. Rejected (non fast-forward, protected branch): report the git message and stop.
4. Reply in the language of the conversation: repo, branch, remote and the real result.
