# Functional request: configurable rules in `custom/` and the `/rules` skill

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained, with the product in `workspace/`. Full design:
`maintainers/plans/rules-config.md`.

## 1. Objective

Each work workspace chooses, in `custom/`, which core rules, skills and agents it uses, replaces a core rule with its
own and keeps its own ones, without editing the core (which is read-only). What is crucial for the workspace to work
cannot be turned off.

## 3. Business rules

- RN-1: `custom/rules-config.json` has `core.rules.exclude`, `core.skills.exclude`, `core.agents.exclude`, and
  `replace` (core rule → file in `custom/my-rules/`). There is no language setting: Claude answers in the language the
  person writes in.
- RN-2: `custom/my-rules/` holds the own rules (`*.md`; with `paths:` loaded by path, without in every session),
  `skills/<name>/` and `agents/*.md`. It replaces `custom/rules/`; the existing files (`cloud.md`, `company.md`,
  `identity.md`) move, and whatever cites them cites the new path.
- RN-3: the core declares its mandatory pieces in a manifest (`rules/manifest.json`): `AGENTS.md`, `rules.md`,
  `git.md`, `security.md`, the protection hooks (`guard-bash`, `guard-subagent-model`, `Stop`, `session-title`,
  `prompt-log`), the `deny` rules, and the skills and scripts the flow depends on (`/merge`, `/commit`, `/prompt`,
  `aiwp-cmds.sh`, `aiwp-gate.sh`, `setup-claude.sh`). The configuration neither removes nor replaces them: the
  generation keeps the piece and warns at the session start.
- RN-4: an item of `my-rules/` with the name of a core item and no `replace` is refused (the core one stays, with a
  warning). In `.claude/`, own items carry the `custom-` prefix.
- RN-5: the generator is `setup-claude.sh`, which already builds `.claude/` at every session start: it starts reading
  the configuration. Validation and assembly live in `scripts/rules-config.py`, with tests, used by `setup-claude.sh`
  and by the skill.
- RN-6: a core rule turned off also leaves the instructions that tell the model to read it: the effective `AGENTS.md`
  is generated in `.claude/` (the original is read-only), and the product's root `CLAUDE.md` imports the generated one.
- RN-7: `custom/` is free to edit: the configuration and `my-rules/` can be edited by hand; validation runs on every
  path, and an invalid configuration never stops a session from opening.
- RN-8: the `/rules` skill: without arguments, shows the effective rules with the origin of each (core, replaced, own,
  turned off) and the warnings; `exclude`, `include`, `add <subject>` (writes an own rule in the format of the core
  rules), `replace <rule>` (copies the core rule to `my-rules/` as a starting point). After a change, it builds
  `.claude/`, commits in `custom/` and says that open sessions pick the change up only when reopened.
- RN-9: `/rules lessons`: reads the tagged lines of `custom/docs/lessons.md` (weight `grave`/`attention`/`suggestion`,
  scope `general`/`project <name>`, recurrence `recurring`/`rare`, added by `import-from-fork`) and shows only the
  candidates: `grave` ones and suggestions that recur. Same two tables as `/normalize-rules`: what the core or
  `my-rules` already covers (no question), then a numbered decision table with assessment, status (`import` or
  `reject`) and why; `rare` lines are never proposed. An approved row becomes an own rule through `/rules add`
  (scoped with `paths:` for a project lesson), covering only the kind of case that caused it; the skill prefers
  adjusting an existing own rule over adding a new one. No chain of reviewers, no new step in the sessions.

## 4. Acceptance criteria

- AC-1: Given `"exclude": ["frontend.md"]`, when the session opens, then `frontend.md` is not in `.claude/rules/` and
  the effective `AGENTS.md` does not tell the model to read it.
- AC-1a: Given three lessons (one `grave general`, one `suggestion` seen twice, one `rare`), when `/rules lessons`
  runs, then the table lists the first two only, and the approved row becomes an own rule in `custom/my-rules/`.
- AC-2: Given `"exclude": ["git.md"]`, when the session opens, then `git.md` still applies and the session start warns
  that it is mandatory.
- AC-3: Given `"replace": {"review.md": "review.md"}` with the file in `my-rules/`, then the own version applies
  instead of the core one, marked as replaced in `/rules`.
- AC-4: Given `my-rules/git.md` without `replace`, then the core one applies and there is a warning.
- AC-5: Given `"exclude": ["pilot"]` in skills, then the skill does not show in the session; given
  `"exclude": ["merge"]`, then it stays (mandatory) and there is a warning.
- AC-6: Given a `rules-config.json` with invalid JSON, when the session opens, then it opens with the whole core and a
  warning, without an error.
- AC-7: Given `/rules add "SQL review"`, then `custom/my-rules/sql-review.md` is created in the format of the core
  rules, `.claude/` is built and the commit is in `custom/`.
- AC-8: The `rules-config.py` suite covers each business rule above.

## 7. Out of scope

- Turning off mandatory pieces (decided: the mandatory core is fixed).
- `/fork-my-rules` (its own request, which depends on this one).

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Mandatory-core manifest, `rules-config.py` with its suite, `setup-claude.sh` reading the configuration, effective `AGENTS.md` | high | Changes what every session loads and touches protection |
| 2. `custom/rules/` → `custom/my-rules/`, with own skills and agents | medium | Mechanical migration, with the references |
| 3. `/rules` skill, README and guide | medium | A conversation over a script already tested |

The agents of each stage run with the stage's effort, passed in the call.
