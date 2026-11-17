# Functional request: final review of Claude CLI Agents Workspace

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** in a new session at the repository root, where the project is maintained. It runs after `fork-my-rules`,
once the 0.1.0 publication, `/rules`, `/run-tools`, the hub and `/fork-my-rules` are in the repository.

## 1. Objective

Review the whole product with fresh eyes and fix what is found: duplicated rules, conflicting rules and real security
problems at run time. Close with a new version, minor or patch, by the size of the fixes.

## 2. What the project is

Claude CLI Agents Workspace is a working folder for the Claude Code CLI. It gives sessions ready rules, skills, agents
and hooks to work safely across several projects.

**The three folders:**

1. **This repository:**
   - the root is the maintenance of the project (`CLAUDE.md`, `.claude/`, `tests/` and `maintainers/`), used to
     maintain the product;
   - the product lives in `workspace/`;
   - document translations live in `i18n/`.
2. **The local data folder**, where `install.sh` clones the full repository and installs the `aiwp` command. It is the
   source of updates.
3. **The work workspaces**, created by `aiwp new`:
   - a copy of `workspace/` only, without `.git`, with the core in 555/444;
   - writable only in `custom/`, `projects/`, `tmp/`, `.claude/`, `.history/` and a closed list of tool outputs.

**How it works:**

- **Opening:** `aiwp` opens the workspace. Before starting `claude`, it checks the release, updates the data folder
  and copies what changed, through the manifest, with backup and journal.
- **Assembling the session:** `setup-claude.sh` builds `.claude/` at every session start, joining the core with the
  custom layer's configuration (`custom/rules-config.json` and `custom/my-rules/`).
- **Custom:** the custom layer is the installer's private repository. It keeps the own rules, the identity, the env
  files (`custom/env/`), the requests and the prompt log.
- **Projects:** each project in `projects/` is its own repository. Work happens in clones in `tmp/work/` and enters
  through the gate (`/merge`), on the `developer` branch.
- **Hooks:**
  - `guard-bash`: guards commands;
  - `guard-subagent-model`: requires model and effort on agents;
  - `session-title`: names the session;
  - `prompt-log`: keeps the prompt log;
  - new-version notice;
  - not-normalized-project notice.
- **Contributing:** `/fork-my-rules` gives back to the project, by pull request, the own rules that serve everyone.

## 3. Business rules

- RN-1: before reviewing, read and record in a short map the rules that exist, where each comes from and when it
  loads:
  - `AGENTS.md` and `workspace/rules/`;
  - skills, agents and hooks;
  - `settings.json`, with the `deny` rules;
  - the mandatory core;
  - the maintenance of the repository, at its root.

  The map is the base of the three findings below and goes into the report.
- RN-2: **Duplicated rules:** the same instruction written in more than one place, with the same effect. The fix keeps
  one place and replaces the others with a reference.
- RN-3: **Rule conflicts:**
  - two rules that say different things for the same situation;
  - a rule that a hook or `settings.json` contradicts;
  - a rule the custom configuration can turn off although it belongs to the mandatory core;
  - text that cites a file, command or skill that no longer exists.

  The fix picks the rule that applies and says why.
- RN-4: **Run-time security:**
  - only what can really happen counts, with a concrete path:
    - a destructive command that gets through `guard-bash`;
    - a secret that reaches a commit, a record or a log;
    - a write in the installed core outside `aiwp`;
    - an update that swaps files without the manifest or without a way back;
    - a public send (push, fork, pull request, release) without confirmation;
    - a script that runs untrusted input;
  - each finding states the path: what the person or the agent does, and what happens;
  - rare hypotheses, which need several unlikely failures at once, are not findings. At most, they get one line in an
    "observations" section.
- RN-5: each security finding is confirmed by a second reviewer agent, with effort `high` and a clean context. That
  reviewer gets the code, not the conclusion. An unconfirmed finding is dropped.
- RN-6: fix the findings in the repository. Each fix comes with the test that proves it, when there is a suite, and
  with the `i18n/` translations updated in the same commit, when it touches a document.
- RN-7: version, by the size of the change:
  - **patch** (`0.x.Y`): only fixes that do not change what users see, such as duplicated text, a broken reference or a
    test;
  - **minor** (`0.X.0`): any behavior change, such as a rule that applies differently, a hook that blocks or asks
    something new, a new command or a security fix.

  The release process is `/merge --main` (`.claude/skills/merge/SKILL.md`): `VERSION`, `CHANGELOG.md` in English, the suite and the test
  installation. If a fix asks something of the projects, it also goes into `migrations/`.
- RN-8: the push, the tag and the GitHub release are public actions. They happen only with the owner's explicit
  confirmation, at each step.

## 4. Acceptance criteria

- AC-1: Given the repository, when the review ends, then a report in English exists in
  `maintainers/reviews/<date>-final-review.md`, with the rules map and the findings. Each finding has the category,
  the file, the concrete path (for security), the fix and the commit.
- AC-2: Given a security finding in the report, then the second reviewer confirmed it and its concrete path is
  described.
- AC-3: Given the fixes, then the suite (`tests/check.sh`) and the test installation pass, and `VERSION` and
  `CHANGELOG.md` show the new version, patch or minor, per RN-7.
- AC-4: Given the new version, when the owner confirms the publication, then the `vX.Y.Z` tag and the release exist on
  GitHub, and a test workspace updates to it through `aiwp`.
- AC-5: Given a real installed workspace on the previous version, with real projects in it (a dedicated one, not the
  owner's main workspace and not a test fixture), when the owner opens it with `aiwp` after the release, then the data folder moves to the new tag, only the changed core files are swapped, permissions are back
  to 555/444, `custom/`, `projects/` and `tmp/` are untouched, and `aiwp rollback` followed by `aiwp update` returns to
  the new version. This is the first update between two real releases; any failure is a finding of this review.

## 7. Out of scope

- New features that are not the fix of a finding. Ideas go to `maintainers/backlog/`.
- Old lint of the tools in `tools/`, which does not go through the gate.
- Changes to the user's projects.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Rules map | medium | Broad reading, no decision |
| 2. Duplicates and conflicts | high | Requires judging which rule applies |
| 3. Security, with the second reviewer | high | Risky actions and hooks |
| 4. Fixes, tests, translations | high | Touches hooks and mandatory rules |
| 5. Version, release and publication, each step confirmed | high | A public action |

The agents of each stage run with the stage's effort, passed in the call.
