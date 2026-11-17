# Functional request: `aiwp remove`, deleting an installed workspace safely

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained, with the product in `workspace/`
(`scripts/aiwp.sh`, `scripts/guard-bash.py`, their suites, README and `docs/usage.md`). Prerequisite: the 0.1.0
publication (registry `workspaces.json`, manifest, read-only core). It depends on no other request; it fits **round 1**
of `maintainers/requests/README.md`, beside `rules` and `run-tools`, which do not touch `aiwp.sh`. `tools-hub` (round
2) may later offer the same action in its Workspace area, by calling this command.

## 1. Objective

An installed workspace has its core in 555/444, so a plain `rm -rf` fails; today the README and `docs/usage.md` tell
the person to run `chmod -R u+w <folder> && rm -rf <folder>` and to push `custom/` and the projects first. That is a
manual, unchecked step that can delete unpushed work. The owner asked that, with everything in 555, the tooling "needs
to know how to deal with it" (the hub and the skill). This request adds `aiwp remove <folder>`: it checks what would be
lost, asks, opens the permissions only of that workspace, deletes it and takes it out of the registry.

## 3. Business rules

- BR-1: `aiwp remove <folder>` only acts on a folder that is a work workspace (it has `.aiwp/manifest.json`) or a
  registered one. Anything else is refused with the reason; it never opens permissions or deletes outside that folder,
  and it resolves links before deciding (the same care as `forget`).
- BR-2: never inside a Claude Code session, like `update`, `rollback`, `repair` and `forget`: `aiwp` refuses it and
  `guard-bash` denies it with the message "close the session and run `aiwp remove` in a terminal".
- BR-3: before deleting, it lists what would be lost, read-only:
  - `custom/`: uncommitted changes, commits not on its remote, no remote at all;
  - each repository in `projects/` and each clone in `tmp/work/`: uncommitted changes, branches or commits not on
    the remote;
  - a `claude` process running in the folder (named by pid, as `update` does).
- BR-4: with nothing at risk, it asks once "Delete <folder>? [y/N]". With something at risk, it shows the list and
  asks the person to type the folder name to confirm. With no terminal, it refuses unless `--yes` is given, and even
  then it refuses when something is at risk unless `--force` is also given.
- BR-5: deletion: give write permission back only inside that folder, delete it, then remove its entry from the
  registry. A failure halfway leaves a clear message with what is left and never a partly writable core of another
  workspace.
- BR-6: the data folder, the `aiwp` command and other workspaces are never touched.
- BR-7: README, `docs/usage.md` and their translations replace the manual `chmod -R u+w ... && rm -rf ...` line with
  the command, in the same commit.

## 4. Acceptance criteria

- AC-1: Given a registered workspace with everything pushed, when `aiwp remove <folder>` runs in a terminal and the
  person answers `y`, then the folder is gone and `aiwp list` no longer shows it.
- AC-2: Given a workspace whose `custom/` has a commit not on the remote, then the list shows it and the folder is
  deleted only after the folder name is typed.
- AC-3: Given a folder without `.aiwp/manifest.json` and not in the registry, then nothing is changed and the exit
  code is not 0.
- AC-4: Given a Claude Code session, when it runs `aiwp remove`, then `aiwp` refuses and `guard-bash` denies it.
- AC-5: Given no terminal and no `--yes`, then nothing is deleted.
- AC-6: Given a link to a workspace, when removed through the link, then the real workspace is the one checked and
  deleted, and the permissions of any other path are unchanged (tested).
- AC-7: The `aiwp` suite covers every rule above; `bash tests/check.sh --all` and `/caw-test-install` pass.

## 7. Out of scope

- Removing the whole installation (data folder, `~/.local/bin/aiwp`, menu items): see decision 1.
- Pushing anything on the person's behalf before deleting.
- The hub's button (it belongs to `tools-hub`, which can call this command).

## Decisions for the owner

The owner did not discuss this command directly; it came from the open points of the installer stage ("There is no
`aiwp remove`, and no doc says so yet") and from the owner's wish that the tooling handle the 555 core.

1. **Build it, or keep the documented `chmod -R u+w && rm -rf`?** Recommended: build it, because the manual line skips
   the check of unpushed work.
2. **Also `aiwp uninstall`** (data folder, the `aiwp` link, menu items, after every workspace is removed or forgotten)?
   Recommended: not now; add it with `tools-hub`, which creates the menu items.
3. **Keep `custom/` on request** (`aiwp remove <folder> --keep-custom`, moving it next to the folder)? Recommended: no;
   `custom/` is a git repository and the at-risk list already covers it.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. The at-risk check and the confirmation, read-only, with the suite | medium | Reads git state; changes nothing |
| 2. Deletion, registry, refusal inside a session, `guard-bash` rule, with the suite | high | A destructive step that opens permissions |
| 3. README, guide and translations | low | Text only |

The agents of each stage run with the stage's effort, passed in the call.
