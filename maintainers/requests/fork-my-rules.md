# Functional request: `/fork-my-rules`, giving rules back to the project

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained, with the product in `workspace/`.
Prerequisites: the 0.1.0 publication (the public repository exists) and the configurable-rules request delivered
(`custom/rules-config.json`, `custom/my-rules/`, `/rules`). Full design: `maintainers/plans/fork-my-rules.md`.

## 1. Objective

Someone who installed the workspace and turned off bad rules or wrote good ones gives back to the project what serves
everyone: the skill separates what belongs to the installation from what is reusable, shows it for approval, creates
the fork in the person's GitHub account and opens the pull requests, with descriptions written by Claude.

## 3. Business rules

- RN-1: it reads only `custom/my-rules/` (rules, skills, agents), and the `replace` and `exclude` entries of
  `custom/rules-config.json`. It never reads or sends requests, the prompt log, `projects.md`, the visual identity,
  measurements or projects.
- RN-2: three filters, in order: installation terms (`custom/core-terms.txt` and the names in `custom/projects.md`,
  `company.md`, `cloud.md`, `identity.md`); a reviewer agent (effort `high`, clean context) that classifies each item as
  goes up, goes up generalized (with the proposed text without the details), does not go up, or already in the core;
  and, in the fork's clone, gitleaks and the installation-terms check on the diff. Any finding blocks the send.
- RN-3: for each rule turned off, it asks for the reason, in one round; without a reason, the rule does not go up.
- RN-4: before any action on GitHub, it shows the full summary (item, decision, what goes) and the diff, and the person
  approves item by item. `guard-bash` asks before `gh repo fork` and `gh pr create`.
- RN-5: one pull request per approved item, small and focused, as the README's "Get involved" section asks. A rule
  turned off without a new version becomes an issue with the reason; a replaced rule (`replace`) becomes a pull request
  that changes the core rule.
- RN-6: the fork is created in the person's account (`gh repo fork ... --clone=false`), with a repository description
  written by Claude; when it exists, it is updated from the original. The work happens in a clone in
  `tmp/work/<date>-fork-my-rules/`, one branch per item, in the format and language of the core rules, with the
  project suite run before sending.
- RN-7: the pull request description says what changes, why, the reason the person gave, the expected effect on
  sessions, and that the contribution is under the project's MIT license. What did not go up shows only in categories
  ("2 rules specific to the installation were left out"), without names or content; the detailed list stays in the
  local summary.
- RN-8: at the end, it shows the links of the fork, the pull requests and the issues, and records in `custom/` what was
  sent and when, so the next round does not repeat it.
- RN-9: without a GitHub account or an authenticated `gh`, it writes the patch and the pull request text in
  `tmp/work/` for sending by hand.
- RN-10: after the merge, `/rules` recognizes the rule that entered the core and proposes removing the copy from
  `my-rules/`.

## 4. Acceptance criteria

- AC-1: Given an own rule that cites the company's tenant, when the skill runs, then it shows as "does not go up" in
  the local summary and never reaches the fork.
- AC-2: Given a generic own rule, when approved, then it becomes its own pull request on the original repository, with
  the description asked for and the MIT statement.
- AC-3: Given a core rule turned off with a reason, when approved, then it becomes an issue with the reason; with
  `replace`, it becomes a pull request that changes the rule.
- AC-4: Given a secret or an installation term in the diff, then nothing is sent and the skill says where it is.
- AC-5: Given the summary shown, when the person drops an item, then it is not sent.
- AC-6: The public text (fork description, pull requests, issues) contains no installation term; tested with a
  fictitious installation.
- AC-7: Given `gh` without authentication, then the skill writes the patch and the text and does not try to send.

## 7. Out of scope

- Sending requests, logs, measurements or any project data.
- Accepting or merging pull requests on the original repository.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Reading and the three filters, with the local summary | high | Separates what is private from what becomes public |
| 2. Fork, clone, one pull request or issue per item, scan before sending, `guard-bash` questions | high | A public, irreversible action on GitHub |
| 3. Record of what was sent, the path without GitHub, `/rules` integration after the merge | medium | Clear scope over what exists |

The agents of each stage run with the stage's effort, passed in the call.
