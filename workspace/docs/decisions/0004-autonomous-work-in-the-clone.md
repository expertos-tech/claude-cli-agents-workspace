# 0004 Autonomous work in the clone, a Docker copy per task, the merge only by the person

Status: accepted

## Context

The agent asked the person for authorization while it worked on its own branch, and the person could not tell what
each prompt approved: an `ask` rule on `git push` prompted at every commit, and a line of several commands showed the
whole line when one command at its end needed approval. Outside auto mode every command in a clone prompted, because
the product allowed nothing by rule. `/merge` could be invoked by the model, and `rules/git.md` sent a mature part
through the gate at once. `aiwp-cmds.sh up` published a task's stack over the shared one (same compose project, ports
and image tags), and the hook asked before deleting any Docker volume, so a test stack could not be rebuilt freely.

## Options

- **Claude Code's OS sandbox with automatic approval of sandboxed commands.** The only OS-level confinement, but Docker
  cannot run inside it, the network starts closed, and writes cannot be limited to `tmp/work/` in a documented way.
  Rejected: this is the developer's machine, and the scripts' limits stop a hallucination.
- **One allow rule for a script that runs anything in the clone.** Simple, but `run <clone> -- rm -rf ../..` passes.
- **Auto mode alone.** No setup, but a classifier that the project cannot configure, and `ask` rules still prompt.
- **Scripts at the borders plus an approval only for lines that stay in the clone.** Chosen.

## Decision

- **The trail.** In a clone of `tmp/work/` the agent works with no prompt. `guard-bash` approves a Bash line when it
  can tell that every command of it runs in one clone, every path it names stays in that clone, and no command acts on
  a remote system (a push, a publish, a deploy, a cloud CLI, `ssh`, `docker push`; downloading dependencies is not
  one). Anything it cannot tell stays silent, and the permission mode decides. Its refusals and questions keep their
  precedence. The settings allow edits of `tmp/work/` and the border commands of `aiwp-cmds.sh` (`open`, `status`,
  `push`, `up`, `down`, `close` without `--discard`).
- **A prompt shows one thing.** What needs authorization runs alone, in its own call, after one line saying what it
  asks; `guard-bash` refuses with "run it alone" a line it would ask about that holds other commands.
- **A Docker copy per task.** `aiwp-cmds.sh up <work>/<clone>` publishes the task's stack in its own compose project,
  `agent_<MMDD>-<slug>` (`--<clone>` added for a second clone of the same work: a double dash, which no work slug holds, so two works never share a name), with its own images, networks and
  volumes, on random free host ports in 61000-65535 set in an override file; the project's compose files do not
  change. Only `aiwp-cmds.sh up` starts a copy: it refuses a service that could reach the host (host networking, privileges, capabilities, devices, unsafe security options, host namespaces, a runtime socket, a bind outside the clone), and puts every network of the copy on an internal network with an isolated gateway (Docker Engine 28 or later); a service that publishes a port also joins the group's edge network. The task's own group is then approved with no prompt, volumes included, for `down [-v]`, `logs`, `ps`, `stop`, `restart` and the like, and for `exec` into a container whose networks are all internal to the group, which `guard-bash` confirms by `docker inspect`; `up`, `build`, `start`, `run`, `create` and `cp` follow the permission mode. A group is destroyed only by
  its compose label and only when its name matches `^agent_[0-9]{4}-[a-z0-9][a-z0-9-]*$`: at `/merge` into
  `developer` once phase 2 passed, and at `close --discard`.
- **The final stack** changes only by `/docker-deploy [developer|main]`, which only the person runs: the replaced
  images keep a `rollback` tag, and no volume is deleted. Grafana's data (`tools/observability/.data`) is never
  deleted, moved or emptied without a question.
- **The merge only by the person.** `/merge` cannot be invoked by the model; the `UserPromptSubmit` hook records each
  `/merge` the person types, with its target and an expiry, and `gate --merge` refuses with no record from the same session; `guard-bash` refuses a line that changes the session variables, writes the records or runs the hook's script, and the settings deny edits of `.history/merge-orders/`. A task ends with its
  tests passing, its copy published, and a closing board with the copy's addresses, one test item per acceptance
  criterion and the two ways out: `/merge` when approved, `close --discard` when not.
- **The merge review** asks the same three questions at every merge: what was asked against what was done; what went
  beyond the request; what existed and was lost. Into `developer`, only the difference that enters; into `main`
  (release, hotfix), since the last tag, widened as the reviewer judges necessary. Effort by content: code and
  configuration `xhigh`, documents `high`, two reviews in parallel for a mixed merge. The release's general round is
  dropped.

## Reason

- The prompts that remain are the ones that matter: leaving the trail, a destructive step outside the task's group,
  the person's own merge. Each shows only what it approves.
- A task's copy never touches the stack the person uses, so it can be built, broken and thrown away freely, and the
  person tests the delivery on it before ordering the merge.
- A hook's record of what the person typed keeps the merge in the person's hands without an extra prompt.

## Consequences

- Neither the hook nor the scripts see what an interpreter builds at run time, inside a container or on another host:
  the goal is to stop a hallucination visible on the command line, not to sandbox the agent.
- The same holds for project files: a compose file written on purpose to escape the copy's checks (for example a path
  that interpolates differently when `up` runs) is out of scope. The local Docker is the developer's own machine; the
  checks stop a mistake, not a deliberate escape (the owner's decision after the third return review).
- A project with a database is strongly recommended a test seed, so a copy starts with its database rebuilt
  (`rules/quality.md` "Test seed").
- `aiwp-cmds.sh up <repo>` for the final stack gives way to `/docker-deploy`.

## Change history
