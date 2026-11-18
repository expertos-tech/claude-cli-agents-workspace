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

## Execution — 2026-11-18, merged into developer (this merge)

- **Done:** stage 1 (effort high), `rules/manifest.json`, `scripts/rules-config.py` with `test_rules_config.py`,
  `setup-claude.sh` reading the configuration with its scenario tests, the effective `.claude/AGENTS.md` imported by
  `CLAUDE.md` (edc9a74); stage 2 (medium), `custom/rules/` to `custom/my-rules/` in the rules, the
  `normalize-projects` skill, the templates, the docs and the skeleton of a new custom layer, decision record 0003
  (34f3ad5); stage 3 (medium), the `/rules` skill, the README and the usage guide (8313fab); the findings of the
  independent reviews (bdb3772, 4956a31, 5dd302d, 62975db); the plan's status line (70a5f2d).
- **Decisions taken while running:** `/request` in place of `/prompt` in the mandatory core (the skill was renamed);
  the agents `reviewer` and `verifier` added to the mandatory core, since the gate depends on them; own skills and
  agents reach `.claude/` as `custom-<name>` with their `name:` rewritten, so none shadows a core one and
  `guard-subagent-model` keeps trusting `.claude/agents/<name>.md`; a replacement of an on-demand core rule is not
  copied to `.claude/rules/` (it would load in every session): the effective `AGENTS.md` points to it, and says that a
  replaced rule is read in its own version wherever another file names it; a replacement of a path-scoped rule is
  copied as `custom-<file>`; `AGENTS.md` names each optional rule only in table rows or parenthesized references, so
  the generation can remove it, and a test runs the real file through every rule that can be turned off;
  `custom/rules/` is read in place of `custom/my-rules/`, with a warning, until it is renamed; when `rules-config.py`
  cannot run, the whole core loads with `AGENTS.md` as it is; `/rules lessons` also proposes an `attention` lesson
  that recurs, and reads the tags as words in square brackets (`[grave] [project <name>] [recurring]`).
- **Deviations:** own skills and agents keep only a closed list of front matter keys (no `hooks`, `allowed-tools`,
  `permissionMode`, `mcpServers`, `context`, nor a model `guard-subagent-model` refuses), and their hidden files, a
  nested `SKILL.md` and a `SKILL.md` not named exactly so are left out: `custom/` is writable by the session, and those
  would have reached `.claude/` around `guard-bash` and the deny rules (a BLOCKER of the review, confirmed by a second
  one). The `deny Edit` rules on `custom/rules/**` and `custom/brand/**` that the plan removes were already gone.
- **Acceptance criteria:**
  - AC-1: proven at `.claude/` level (test-setup-claude `test_config_excluded_rule_leaves_rules_and_agents_md`;
    test_rules_config `AgentsTests`, the real `AGENTS.md` included; the test installation); that a session loads it
    through `CLAUDE.md` (`@.claude/AGENTS.md`) is pending a real session.
  - AC-1a: the candidate table proven (`test_candidates`: the grave general and the suggestion seen twice, not the
    rare one); the approved row becoming an own rule is skill text, pending a real session.
  - AC-2: proven (`test_config_mandatory_rule_stays_with_a_warning`, `MandatoryTests`; the test installation refused
    `exclude git.md`).
  - AC-3: proven (`test_config_replaced_rules`, `ReplaceTests`, `test_show_lists_origins_and_warnings`).
  - AC-4: proven (`test_config_own_rule_with_a_core_name_refused`, `test_core_names_are_refused`).
  - AC-5: proven at `.claude/` level (`test_config_excluded_skill_and_agent`); the session's skill list pending a real
    session.
  - AC-6: proven (`test_config_invalid_json_loads_the_whole_core`; the test installation).
  - AC-7: the file and its title proven (`test_add_writes_an_own_rule`; the test installation); the rule's text, the
    rebuild and the commit in `custom/` are skill text, pending a real session.
  - AC-8: proven: RN-1 to RN-7 and RN-9 have tests in `test_rules_config.py`; RN-8's script commands too, its
    conversation is skill text.
- **Checks:** `tests/check.sh --base origin/developer --i18n-pending` green at each stage and fix (`repo-terms`
  SKIP: no terms list on this machine); test-setup-claude 33 tests; test_rules_config 36 tests (the coverage gate
  passes); `tests/test-install.sh` all PASS, and in that installation exclude, the refused mandatory exclude, replace,
  add, a `hooks:` dropped and invalid JSON, with the installed scripts; independent reviews (effort high): stage 1
  REJECTED (1 BLOCKER, confirmed by a second review; 1 RECOMMENDED), its fix APPROVED_WITH_CHANGES (1 BLOCKER,
  confirmed; 2 RECOMMENDED), that fix APPROVED_WITH_CHANGES (1 BLOCKER, 1 RECOMMENDED), the last fix
  APPROVED_WITH_CHANGES (1 RECOMMENDED); every finding fixed and the fixes reviewed, the last RECOMMENDED fix by its
  tests; the merge review (effort high): APPROVED_WITH_CHANGES, no defect, 1 RECOMMENDED (AC-1 labelled proven while
  its session part was not seen), fixed in this block.
- **Left:** a real session in an installation, to see `CLAUDE.md` load `@.claude/AGENTS.md`, the skill list without a
  turned-off skill, and `/rules` (`add`, `lessons`); an installed workspace renames `custom/rules/` with
  `git -C custom mv rules my-rules`; `import-from-fork` (BR-8) should write the lesson tags in the bracket syntax
  `/rules lessons` reads; translations pending for the release.
