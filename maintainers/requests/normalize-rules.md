# Functional request: `/normalize-rules`

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained, with the product in `workspace/`. After
`rules.md` (it needs `custom/my-rules/` and `custom/rules-config.json`). Full design: `maintainers/plans/normalize-rules.md`.

## 1. Objective

Read a whole older workspace, ignore its projects, and bring what is worth keeping into the person's own rules in
`custom/my-rules/`, after the person approves each item; list the projects and POCs found with the command to migrate
each one.

## 3. Business rules

- BR-1: `/normalize-rules <path>`; the path is an older workspace folder. Read-only on it.
- BR-2: no fixed file or folder names. Stage 1 is a deep analysis by parallel subagents, each called with
  `model: opus` and `effort: high`: instructions, skills and agents, automation and protection (hooks, permissions,
  scripts), company layer. Each compares its findings with the current core and `custom/my-rules/`.
- BR-3: each finding gets a verdict: already in the core, own rule, own skill or agent, replaces a core rule (never a
  piece of the mandatory core), needs core support (reported, with the suggestion of `/fork-my-rules`), not worth
  keeping (with the reason).
- BR-4: nothing is assumed. Every import candidate is checked against the new way of working (clones in `tmp/work/`,
  the gate, the read-only core, the custom layer, the mandatory core, replies in the person's language): a conflict, a
  rule that could block a session or a step is rejected; a partial conflict gets an adapted
  text. A second subagent (`model: opus`, `effort: high`, clean context, given the candidates and the core, not the
  first conclusions) looks only for conflicts and blocking. When in doubt, reject.
- BR-4a: what the core already covers is not a decision: it is listed first, in a "Rules not imported" table (`#`,
  item, the core piece that covers it), and the person is not asked about it.
- BR-4b: the person decides on a numbered table of the remaining findings: `#`, item (origin), assessment, status (`import` or `reject`, filled with
  the recommendation), and why (one or two sentences, naming the core piece involved). The person changes rows by
  number or edits a proposed text, then confirms; nothing is written before. The plan with the table goes to
  `custom/migrations/rules-<date>.md`.
- BR-5: `.env` files are never read; a secret is never copied (a placeholder and a note on where to set the value).
- BR-6: stage 2 writes the `import` rows to `custom/my-rules/` (and `replace` entries to `custom/rules-config.json`),
  one commit per item; validates and generates through `/rules`; checks that `setup-claude.sh` runs clean, undoing an
  item that breaks it; never pushes; says that open sessions need reopening.
- BR-7: projects and POCs found in the older workspace are not analysed; at the end the skill lists them under
  "Projects found in the workspace given, in case you want to migrate them:", one
  `/normalize-projects --from <path>` per line.
- BR-8: the listed command relies on `/normalize-projects --from <path>` (built with `/normalize-projects`): it clones the folder (keeping local branches never pushed),
  points `origin` to the original remote, and reports uncommitted changes in the source.

## 4. Acceptance criteria

- AC-1: Given an older workspace with a machine-load rule equal to the core's, then it appears only in the "Rules not
  imported" table with the core rule named, the decision table does not list it, and nothing is written for it.
- AC-1a: Given an older rule that tells the agent to commit straight to the project folder, then its row says `reject`
  with the conflict with the clones and the gate as the reason; when the person keeps it rejected, it is not written.
- AC-1b: Given the table, when the person answers "4 reject" and confirms, then row 4 is not written and every other
  `import` row is, one commit each.
- AC-2: Given an older rule with machine-specific limits, when approved, then an own rule in `custom/my-rules/`
  complements the core one, and `/rules` shows it as own.
- AC-3: Given an older hook that blocks a command, then the plan marks it "needs core support" and suggests
  `/fork-my-rules`; nothing emulates it.
- AC-4: Given an older workspace with two projects and a POC, then nothing inside them is analysed, and the end of the
  skill lists three `/normalize-projects --from <path>` lines.
- AC-5: Given a rule in the older workspace that holds a token, then the written rule has a placeholder, and the token
  appears in no file of `custom/`.
- AC-6: Given `/normalize-projects --from <local path>` of a repository with a local branch never pushed, then the
  branch exists in the clone in `projects/`, `origin` is the original remote, and nothing was pushed.

- AC-7: Given the older workspace the owner keeps for this test and the manual analysis of it kept as a private
  baseline (`tmp/baselines/older-workspace-analysis.md`, git-ignored; made before `import-from-fork`), when
  `/normalize-rules` runs on it, then its findings match the baseline item by item, the same in substance even when
  worded differently, after accounting for two designed differences: items the baseline marked "import" are in the
  core by then, so they must come out as "already in the core"; and items the baseline rejected only because they are
  company-specific may come out as `import` here, since `custom/my-rules/` is private. Every other divergence (an item
  found by one and not the other, or an opposite verdict) is listed with its reason in the test report and is either
  fixed in the skill or justified.

## 7. Out of scope

- Migrating projects (that is `/normalize-projects`).
- Changing the core; behaviours that need core support go through `/fork-my-rules`.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Skill: analysts, verdicts, plan, approval | high | Judgement over a whole older workspace |
| 2. Writing through `/rules`, commit, the projects list | medium | Clear rules over an approved plan |

The agents of each stage run with the stage's effort, passed in the call.
