---
name: caw-pilot
description: "Set or show the mode of the maintenance of this repository: assisted (auto plus short boxes on the maintenance flow), auto (the agent runs every check of the delivery, the test installation and a tool's copy included) or manual (the owner gets a checklist and the agent waits; this session only). assisted and auto also become the default of this clone. Use only when the owner asks."
argument-hint: "[assisted|auto|manual]"
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
- Its `allowed-tools` and `scripts/pilot-mode.sh`: the root has no such script; the file is read and written as in
  "Mapping".
- The start context line `Pilot mode: ...`: the root learns the mode from `CLAUDE.md` "Pilot mode".

## Mapping

| Product | Here |
| --- | --- |
| `rules/quality.md` "Verification mode" | the same rules, with the checks of "CAW rules" |
| the task's Docker copy (`aiwp-cmds.sh up <work>/<clone>`) | `bash tests/caw-work.sh publish <work>`: by what changed |
| `.claude/pilot-mode` of the installation | `.claude/pilot-mode.local.md` at the root, git-ignored, imported by `CLAUDE.md` "Pilot mode" |
| `bash scripts/pilot-mode.sh show` | read `.claude/pilot-mode.local.md`: its line `` Pilot mode: `<mode>`. ``; missing, or another value: `assisted` |
| `bash scripts/pilot-mode.sh set <mode>` | write `.claude/pilot-mode.local.md` with the Write tool, holding the one line `` Pilot mode: `<mode>`. `` |
| `rules/assisted.md` | `.claude/assisted.md` (a layer over it) |
| `/pilot`, `/pilot assisted`, `/pilot auto`, `/pilot manual` | `/caw-pilot`, `/caw-pilot assisted`, `/caw-pilot auto`, `/caw-pilot manual` |

## CAW rules

- The checks of a maintenance delivery, in every mode run by the agent: the suite (`/caw-check`).
- The detailed check, which the mode gives to the agent (`assisted`, `auto`) or to the owner (`manual`), runs on what
  `bash tests/caw-work.sh publish <work>` published: a test installation for the installer, a hook, a script or a rule
  (`/caw-test-install`); a tool of `workspace/tools/` as a copy in its own `agent_` group; documentation alone, the
  rendered pages.
- `manual`: one item per acceptance criterion of the request, with the command ready to copy and the expected result.
- The file is written at the root the session started in, never in a work clone: a clone's sessions do not start
  there.
