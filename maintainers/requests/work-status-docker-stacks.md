# Functional request: `aiwp-cmds.sh status` shows the Docker stacks running for each clone

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained, with the product in `workspace/`
(`scripts/aiwp-cmds.sh` and its suite, `docs/usage.md`). It depends on no other request and fits **round 1** of
`maintainers/requests/README.md`. Size: an adjustment.

## 1. Objective

The approved design of the work area (work in `tmp/work/<date>-<slug>/<repo>`, the `aiwp-cmds.sh` command) gave
`status` three things per clone: branches, commits ahead of `developer`, and "the Docker stacks up for each clone". The
0.1.0 `status` prints branch, base, commits ahead, commits not on the remote and uncommitted files, but nothing about
Docker. Since the owner decided that publishing to the local Docker is free (only deleting a database asks) and that
every publish keeps a rollback tag, knowing which stacks of which clone are up, and their rollback tag, is what closes
the picture before `close`.

## 3. Business rules

- BR-1: for each clone, `status` adds the compose projects started from that clone (by the compose working-directory
  label of the containers, or by the project name `aiwp-cmds.sh up` uses), with the service count, the state and the
  `rollback-latest` tag of the images when present.
- BR-2: read-only: `docker ps`/`docker compose ls` only; nothing is started, stopped or removed.
- BR-3: without Docker, or with the daemon down, `status` prints one line "Docker: not reachable" and the rest of the
  output is unchanged; the exit code does not change because of Docker.
- BR-4: `close` keeps its current checks; this request does not make a running stack block `close` (decision 1).

## 4. Acceptance criteria

- AC-1: Given a clone with a stack started by `aiwp-cmds.sh up`, when `status` runs, then the stack shows under that
  clone with its state and rollback tag.
- AC-2: Given no Docker, then `status` prints the git part as today plus one "not reachable" line, exit code as before.
- AC-3: The suite covers both cases with a fake `docker`.

## 7. Out of scope

- Stopping or removing stacks from `status`.
- Stacks of `projects/<repo>` started outside `aiwp-cmds.sh up` (listed only if decision 2 says so).

## Decisions for the owner

1. **Should `close` warn about a stack still up from that clone?** Recommended: warn in one line, never block.
2. **Also list stacks started from `projects/<repo>` (`aiwp-cmds.sh up <repo>`)?** Recommended: yes, under a "base"
   heading, since they are the local environment of the project.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Docker section of `status`, with the suite and the guide | low | Read-only output over existing labels |

The agents of each stage run with the stage's effort, passed in the call.
