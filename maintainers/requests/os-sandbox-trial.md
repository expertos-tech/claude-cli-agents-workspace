# Functional request: trial of the Claude Code OS sandbox as a second layer for `tmp/work/`

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained, with the product in `workspace/`
(`rules/agents/settings.json`, `scripts/aiwp-cmds.sh`, docs). It depends on the 0.1.0 publication only, but it changes
how every Bash command runs, so it fits **after round 3** of `maintainers/requests/README.md` (after `final-review`),
as its own round with its own release, once the rest has been used for real. Stage 1 is a trial that may end with
"do not adopt".

## 1. Objective

When the work area in `tmp/work/` was designed, the owner's rule was "in `tmp/` everything is allowed; the big guard
rail is the merge into the base". The design kept the Claude Code OS sandbox "for later, as a reinforcement: worth
testing once the rest is up", and the owner accepted that recommendation. The gain is a write barrier at the operating
system level outside `tmp/work/` (and `custom/`); the costs found then are: Docker cannot run inside the sandbox, git
over SSH fails inside it (and the automatic push of the work branch is SSH), and the network allow list starts empty.
This request runs that trial and adopts the sandbox only if it adds protection without adding questions or steps.

## 3. Business rules

- BR-1: the trial runs in a test installation (`/caw-test-install`) with a real session doing a normal request end to end:
  open a clone, edit, test, `up` to the local Docker, automatic push, `/merge`, `close`.
- BR-2: the sandbox configuration under test: writes allowed in `tmp/work/`, `custom/`, `.history/`, `.claude/` and
  the user's temporary folder; Docker, `aiwp-cmds.sh push`, the git hooks that push, `aiwp-gate.sh` and `release` run
  outside the sandbox (`excludedCommands` or the documented equivalent); a network allow list with the package
  registries the projects use.
- BR-3: adoption criteria, all required: no new question to the person during work (the owner's rule: questions only at
  the gate); the automatic push of the work branch still works; Docker publishing still works; a write outside the
  writable folders is blocked at the OS level in a test.
- BR-4: if adopted, the setting ships off by default or on by default (decision 1), documented in the README "Hooks
  that run on your machine" with what it blocks and what runs outside it; who maintains the domain allow list is
  stated (decision 2).
- BR-5: if not adopted, the trial's findings are written in `maintainers/reviews/<date>-os-sandbox-trial.md` and
  nothing in the product changes.

## 4. Acceptance criteria

- AC-1: Given the trial, then a report in `maintainers/reviews/` lists each step of BR-1 with "works", "asks" or
  "breaks", and the adoption decision against BR-3.
- AC-2: If adopted: given a session in an installed workspace, when a command tries to write in `rules/` or in
  `projects/`, then the OS sandbox refuses it, besides the 555 modes and `guard-bash`.
- AC-3: If adopted: given a normal request run end to end, then the number of questions to the person is the same as
  without the sandbox.
- AC-4: `bash tests/check.sh --all` and `/caw-test-install` pass.

## 7. Out of scope

- Native Windows (no sandbox there; Windows is WSL2 only).
- Changing remotes from SSH to HTTPS in the person's projects.

## Decisions for the owner

1. **Default.** If the trial passes: on by default, or an opt-in in the custom layer? Recommended: opt-in first, on by
   default after a release of real use.
2. **Network allow list.** Kept in the core (common registries) plus `custom/` (company registries), or only in
   `custom/`? Recommended: core list plus `custom/` additions.
3. **Is the trial still wanted?** The 555 core, `deny Edit` on `projects/` and `guard-bash` already cover most writes.
   Recommended: yes, but only after round 3.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Trial in a test installation, with the report | high | Changes how every command runs; security layer |
| 2. If adopted: settings, docs and translations, release | high | Touches permissions of every session |

The agents of each stage run with the stage's effort, passed in the call.
