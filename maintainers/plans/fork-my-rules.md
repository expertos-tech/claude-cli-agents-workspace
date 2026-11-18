# `/fork-my-rules`: give back to the project the rules that serve everyone

Status: approved design. Depends on `rules-config.md` (`custom/rules-config.json` and `custom/my-rules/`). Request:
`maintainers/requests/fork-my-rules.md`.

## 1. Goal

Someone who installed the workspace may find core rules bad and turn them off, or write good own rules. The
`/fork-my-rules` skill:

1. Reads the rules turned off and the rules written.
2. Separates what is specific to that installation from what the workspace can use.
3. Shows a summary for approval.
4. Creates a fork of the project in the person's GitHub account, with a detailed description written by Claude.
5. Opens the pull requests, saying what goes up and what does not.

## 2. What it reads

| Source | What it can become |
| --- | --- |
| `custom/my-rules/*.md` | A new core rule, or an addition to an existing one |
| `custom/my-rules/skills/`, `custom/my-rules/agents/` | A new skill or agent |
| `replace` in `rules-config.json` | A better version of a core rule: a change to that rule |
| `core.*.exclude` in `rules-config.json` | A core rule the person found bad: a proposal to change or remove it, with the reason |

It never reads, and never sends, anything else: requests (`custom/requests/`), the prompt log, `custom/projects.md`,
the visual identity, measurements, projects.

## 3. Specific or reusable

Each item goes through three filters, in order:

1. **Installation terms.** `custom/core-terms.txt` (names of the company, customers and projects), plus the names in
   `custom/projects.md`, `company.md`, `cloud.md` and `identity.md`: tenant, subscription, domain, internal URL. An item
   that cites any of them is specific.
2. **The content, judged by a reviewer agent** with effort `high` and a clean context. It gets the item and the current
   core, and classifies:
   - **goes up**: the rule serves anyone;
   - **goes up generalized**: the idea serves, but the text cites something of the installation. The reviewer proposes
     a version without the details. Example: "use tenant X of the cloud" does not go up; "prefer managed identity to an
     access key" does;
   - **does not go up**: only makes sense for this installation;
   - **already exists**: the newest core has the same rule. The skill says so and proposes removing the copy from
     `my-rules/`.
3. **Scan before any send.** In the fork's clone, gitleaks and the installation-terms check (the core's terms check,
   with the installer's own terms list) run on the diff. Any finding blocks the send.

For rules turned off, the skill asks for the reason in one round, one question per rule. The reason goes into the
contribution. A rule turned off with no reason does not go up: without the why, there is nothing to propose.

## 4. Approval

Before creating anything on GitHub, the skill shows the full summary, which only the person sees:

| Item | Decision | What goes |
| --- | --- | --- |
| `my-rules/sql-review.md` | goes up generalized | the proposed text, in full |
| `my-rules/tenant.md` | does not go up | reason: cites the company's tenant and subscription |
| `frontend.md` (turned off) | change proposal | the reason given, and what would change |

It also shows the full diff of what goes to the fork. The person approves item by item: drop one, edit a text, approve
all. **Nothing leaves the machine without this approval.** Creating a fork and opening a pull request are public
actions, and `guard-bash` asks before `gh repo fork` and `gh pr create`, even in auto mode.

## 5. The fork and the pull requests

1. Creates the fork in the person's account: `gh repo fork expertos-tech/claude-cli-agents-workspace --clone=false`.
   - The repository description, written by Claude, says what the fork brings.
   - If the fork exists, the skill updates it from the original repository.
2. Clones the fork into `tmp/work/<date>-fork-my-rules/`, on a `rules/<subject>` branch per item.
3. Writes the changes in `workspace/rules/` (and `workspace/rules/skills/` or `workspace/rules/agents/`), in the format
   and language of the core rules: English. The source folder, `my-rules/`, is never copied.
4. Runs the project suite (`tests/check.sh`), commits and pushes to the fork.
5. Opens the pull request on the original repository (`gh pr create`). Claude writes the description:
   - what the contribution changes and why;
   - for a rule turned off, the reason the person gave;
   - the expected effect on sessions: a step, a question, loaded text;
   - that the contribution is under the project's MIT license;
   - **what did not go up, in categories only**: "2 rules specific to the installation were left out". No names, no
     content.
6. Ends with the links of the fork and the pull requests, and records in `custom/` what was sent and when, so the next
   round does not repeat it.

**About "what does not go up":** the detailed list stays in the summary of section 4, on the person's machine. In the
pull request, which is public, it shows only in categories, because the name of an excluded rule can already reveal the
company or a customer.

## 6. After the merge

When the pull request enters a release, the next update brings the rule in the core. `/rules` notices that a rule of
`my-rules/` now exists in the core and proposes removing the own copy, so the person does not keep two versions of the
same rule.

## 7. Without GitHub

The person may have no GitHub account or no authenticated `gh` (for example, someone on another git server). Then the
skill writes the patch and the pull request text in `tmp/work/`, ready to send by hand, and says how.

## 8. Decisions

- "What does not go up" shows in the pull request in categories only, without names or content.
- One pull request per item: a small pull request is reviewed and accepted faster, and a refused item does not hold the
  others.
- A rule only turned off becomes an issue with the reason; a rule with a better version (`replace`) becomes a pull
  request that changes the core rule.
- The pull request states that the contribution is under the project's MIT license.
- The skill is named `/fork-my-rules`.
