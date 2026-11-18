---
name: docker-deploy
description: "Update the final local Docker stack of a project from developer or main, with the replaced images tagged for rollback and no volume deleted. A task's copy is published by aiwp-cmds.sh up <work>/<clone>, never by this. Use only when the person asks."
argument-hint: "[developer|main] [<repo>]"
disable-model-invocation: true
model: claude-opus-5-5
effort: medium
---

Arguments: `$ARGUMENTS`. The branch: `developer` (default) or `main`. `<repo>`: a repo of `projects/` with a compose
stack, relative to `projects/`; none given: the project of this session, else ask in one question. Reply in the
language of the conversation.

The final stack is the one the person uses every day: its compose project, ports and image tags are those of the
repo's compose files. It changes only here, on the person's order (`AGENTS.md` "Where work happens"). A task's copy
lives in its own `agent_<MMDD>-<slug>` group and never touches it.

1. Say in one line what will be updated: the repo, the branch and its sha (`git -C projects/<repo> rev-parse --short
   <branch>`), the compose project, and that the replaced images keep a `rollback` tag and no volume is deleted.
2. Run alone, in its own call: `bash scripts/aiwp-cmds.sh deploy <repo> <branch>` (`guard-bash` asks; the question is
   the person's confirmation). `developer` builds from `projects/<repo>`, which stays on `developer`; `main` builds
   from a temporary checkout of `main` that the script removes afterwards.
3. A failure: show the output and stop; never retry with other options and never delete a volume or a container to get
   past it. The stack can go back: `bash scripts/aiwp-cmds.sh rollback <repo>`.
4. Reply: the branch and sha now running, each service with its address (`docker compose ps` of the stack, ports), the
   rollback tags written, and the rollback command.
