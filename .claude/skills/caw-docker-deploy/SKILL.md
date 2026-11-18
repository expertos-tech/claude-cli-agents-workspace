---
name: caw-docker-deploy
description: "Update the local tools group (claude-cli-agents-tools) from developer or main of this repository, with the replaced images tagged for rollback and no volume deleted; the tools' configuration comes from the installed workspace. Use only when the owner asks."
argument-hint: "[developer|main]"
disable-model-invocation: true
model: claude-opus-5-5
effort: medium
---

@workspace/rules/skills/docker-deploy/SKILL.md

Read that file in full and follow it as the procedure, with the sections below over it: they win where they differ.

---

## Ignore from the product skill

- `<repo>` and `projects/`: here the final stack is the tools group, `claude-cli-agents-tools`, of `workspace/tools/`.
- `bash scripts/aiwp-cmds.sh deploy` and `rollback`: here `run-tools.sh`, below.

## Mapping

| Product | Here |
| --- | --- |
| `projects/<repo>` on `developer` | the root of this repository, on `developer` with no change (`git status` clean) |
| a temporary checkout of `main` | `git worktree add --detach tmp/deploy-main origin/main` after `git fetch -q origin`, removed afterwards (`git worktree remove tmp/deploy-main`) |
| `bash scripts/aiwp-cmds.sh deploy <repo> <branch>` | `bash workspace/scripts/run-tools.sh up <tool>...` from that tree, with `AIWP_CUSTOM_DIR` set to the `custom/` of the installed workspace that holds the tools' configuration (default `$HOME/Development/ai-workspace/custom`) |
| `bash scripts/aiwp-cmds.sh rollback <repo>` | the `rollback-latest` tags `run-tools.sh up` wrote, as its `--help` says |

## CAW rules

- The tools to update: the ones `run-tools.sh status` shows `up`; the owner may name others.
- `run-tools.sh up` tags the replaced images for rollback and never removes a volume; never run `docker compose` on
  the tools by hand and never delete a volume here.
- The configuration is read, never copied into this repository: no file of the installed workspace's `custom/` is
  printed or committed (`.claude/rules/security.md`).
