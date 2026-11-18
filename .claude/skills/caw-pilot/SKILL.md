---
name: caw-pilot
description: "Set or show this session's verification mode in the maintenance of this repository: auto (the agent runs every check of the delivery, the test installation and a tool's copy included) or manual (the owner gets a checklist and the agent waits). Use only when the owner asks."
argument-hint: "[auto|manual]"
disable-model-invocation: true
model: claude-opus-5-5
effort: low
---

@workspace/rules/skills/pilot/SKILL.md

Read that file in full and follow it as the procedure, with the sections below over it: they win where they differ.

---

## Ignore from the product skill

- The product's checks of a project (`scripts/validate.sh`, coverage, a browser on the app): here the checks of this
  repository, below.

## Mapping

| Product | Here |
| --- | --- |
| `rules/quality.md` "Verification mode" | the same rules, with the checks of "CAW rules" |
| the task's Docker copy (`aiwp-cmds.sh up <work>/<clone>`) | `bash tests/caw-work.sh publish <work>`: by what changed |

## CAW rules

- The checks of a maintenance delivery, in both modes run by the agent: the suite (`/caw-check`).
- The detailed check, which the mode gives to the agent (`auto`) or to the owner (`manual`), runs on what
  `bash tests/caw-work.sh publish <work>` published: a test installation for the installer, a hook, a script or a rule
  (`/caw-test-install`); a tool of `workspace/tools/` as a copy in its own `agent_` group; documentation alone, the
  rendered pages.
- `manual`: one item per acceptance criterion of the request, with the command ready to copy and the expected result.
