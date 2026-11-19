# `/normalize-rules`: bringing the rules of an older workspace into `custom/my-rules/`

Status: built (`workspace/rules/skills/normalize-rules/`). Request: `maintainers/requests/qa/normalize-rules.md`. Depends on `/rules` (`custom/my-rules/`,
`custom/rules-config.json`) and shares its approach with `/normalize-projects`.

## 1. The idea

A person who installs the workspace fresh often already has an older workspace: their own instructions, skills,
agents, hooks and habits, built over time. `/normalize-projects` brings the projects; `/normalize-rules` brings the
rules. It reads a whole older workspace, ignores its projects, and proposes what is worth keeping as the person's own
rules in `custom/my-rules/`.

```text
/normalize-rules <path-to-older-workspace>
```

Example: the older workspace has a rule that stops heavy commands when the machine is hot, tuned to that machine's
sensors. The core already has a machine-load rule, so the analysis compares both: if the old one only repeats the core,
it is reported as "already in the core"; if it adds the machine's own limits, those limits become an own rule that
complements the core one.

## 2. Stage 1: the analysis

Like `/normalize-projects`, the skill looks for no fixed file or folder names. Parallel subagents, each called with
`model: opus` and `effort: high`, read the older workspace (read-only; `.env` files and secrets are never read or
copied) and compare what they find with the current core and the current `custom/my-rules/`:

| Analyst | Question |
| --- | --- |
| Instructions | Which instructions does the older workspace give the model (any instruction file, rule, prompt, convention)? |
| Skills and agents | Which commands, skills and subagents does it define, and what does each one really do? |
| Automation and protection | Which hooks, permissions, deny rules and scripts shape what the agent may do? Which behaviours do they enforce? |
| Company layer | What is specific to the person or company (names, cloud, identity, remotes, tools)? |

Each finding gets one verdict:

| Verdict | What happens |
| --- | --- |
| **Already in the core** | Nothing; the report says which core piece covers it |
| **Own rule** | Written to `custom/my-rules/` in the format of the core rules (`*.md`, with `paths:` when it only matters for some files) |
| **Own skill or agent** | Written to `custom/my-rules/skills/<name>/` or `custom/my-rules/agents/` |
| **Replaces a core rule** | An own version in `custom/my-rules/` plus a `replace` in `custom/rules-config.json`; never for a piece of the mandatory core |
| **Needs core support** | A behaviour that only a hook, a permission or a script can enforce; `my-rules` cannot hold it. Reported, with the suggestion to propose it to the project (`/fork-my-rules`) |
| **Not worth keeping** | Obsolete, contradicted by the core, or tied to the older layout; reported with the reason |

Company-specific content is welcome here: `custom/` is private. Secrets never are: a rule that held a key keeps a
placeholder and the report says where the value must be set.

### 2.1 Compatibility with the new way of working

This workspace works in a new way: work in clones under `tmp/work/`, the merge gate, the read-only core, the custom
layer, the mandatory core, replies in the person's language. A rule from an older workspace can be good and still
clash with that: "commit directly in the project folder", "record every request in a history file", "always write in
Portuguese", "edit the core rules when needed", "skip the review for small changes". Imported as it is, such a rule
would fight the core in every session or stop the flow.

So no finding is assumed. Before the plan is shown, every candidate for import is checked against the current core,
item by item:

- **Conflict:** does it contradict a core rule, a hook, a deny rule or the flow (clones, gate, custom layer,
  read-only core, mandatory core)? A conflict means "reject", even when the idea is good; when only part of it clashes,
  the assessment proposes an adapted text that keeps the useful part and the status is "import" only for that text.
- **Blocking:** could it stop a session or a step (an order to ask before every command, a mandatory step the core does
  not provide, a path or tool that no longer exists)? Blocking means "reject".
- **Redundancy:** does the core already do it? Then it is not a decision at all: it goes to the "Rules not imported"
  table (section 2.2), naming the core piece, and nobody is asked about it.

A second subagent, `model: opus`, `effort: high`, with a clean context, receives the "import" candidates and the core
(not the first analysts' conclusions) and looks only for conflicts and blocking. An item it flags becomes "reject",
with its reason, unless the person decides otherwise. When in doubt, the recommendation is "reject".

### 2.2 The table the person decides on

The skill shows two tables, in this order.

**First, "Rules not imported"**: what the core already covers. It is information, not a question: there is nothing to
authorize when the rule already exists.

| # | Item (origin) | Covered by |
| --- | --- | --- |
| 1 | Machine-load rule (`rules/machine-load.md`) | The core rule `rules/machine-load.md`, same thresholds and steps |
| 2 | "Answer in the person's language" | `AGENTS.md`, language section |

**Then the decision table**, numbered, one row per remaining finding. The skill never writes from its own
recommendation:

| # | Item (origin) | Assessment | Status | Why |
| --- | --- | --- | --- | --- |
| 1 | GPU temperature limit of this machine (same file, last section) | Machine-specific limit the core does not have; adapted as a complement to the core rule | import | Adds a limit without contradicting the core's steps |
| 2 | "Commit straight to the project folder" | Contradicts work in clones and the merge gate | reject | Would bypass the gate and fight the core in every session |
| 3 | Heavy-command blocking hook | A behaviour only a hook can enforce | reject | `my-rules` cannot hold a hook; propose it with `/fork-my-rules` |
| 4 | SQL review checklist skill | Useful, no conflict found by either reviewer | import | New capability; no core piece covers it |

- **Status** is only `import` or `reject`. The recommendation comes filled in; the person changes any row by its number
  ("2 import", "4 reject"), or edits the proposed text of a row, before confirming.
- **Why** always explains the decision in one or two sentences, naming the core piece involved when there is one.
- Nothing is written until the person confirms the final decision table.

The consolidated plan, with both tables and the proposed texts, goes to `custom/migrations/rules-<date>.md`.

## 3. Stage 2: writing the rules

1. Writes the items marked `import` into `custom/my-rules/` and, for replacements, `custom/rules-config.json`, one
   commit per item, so any single import can be undone with `git revert`.
2. Runs the generation (`setup-claude.sh`, through the `/rules` validation): an item that clashes with a core name
   without `replace`, or touches the mandatory core, is refused and reported.
3. Checks that the workspace still opens and works with the imported rules: `setup-claude.sh` runs clean and the
   generated `.claude/` has no clash; a failure undoes that item's commit and reports it.
4. Push only when the person asks.
5. Says that open sessions pick the new rules up only when reopened.

## 4. The projects found

The analysis ignores the projects of the older workspace, but it notices them: any independent repository or POC
folder it meets. At the end the skill lists them, with the command to bring each one in:

```text
Projects found in the workspace given, in case you want to migrate them:
* /normalize-projects --from /path/to/older/projects/billing-api
* /normalize-projects --from /path/to/older/projects/landing-page
* /normalize-projects --from /path/to/older/custom/pocs/new-checkout
```

`/normalize-projects --from` accepts a local path as well as a remote URL. From a local path it clones the folder,
which keeps every local branch, including the ones never pushed, then points `origin` to the original remote and
reports uncommitted changes in the source, which a clone does not carry.

## 5. Relation with the other skills

- `/normalize-projects`: same two stages and the same analysts' standard (Opus, high effort, no fixed names, approval
  before change). It brings projects; this one brings rules.
- `/rules`: owns `custom/my-rules/` and `custom/rules-config.json`; this skill writes through its validation.
- `/fork-my-rules`: the way back. An own rule that turns out useful for everyone can be proposed to the project.

## 6. Decisions

- Name `/normalize-rules`; argument: the path of the older workspace.
- Read-only on the older workspace; never reads `.env` files nor copies a secret.
- Projects and POCs are only listed, with the `/normalize-projects --from <path>` command for each.
- Behaviours that need a hook, permission or script are reported, not emulated in a rule.
- Nothing is assumed: what the core already covers is listed in a "Rules not imported" table, without asking;
  the rest goes to a numbered table with assessment, status (`import` or `reject`) and the reason for each row;
  conflicts with the new way of working and anything that could block the workspace are rejected; a second, clean
  reviewer checks the `import` rows; the person confirms the final table; one commit per imported item.
