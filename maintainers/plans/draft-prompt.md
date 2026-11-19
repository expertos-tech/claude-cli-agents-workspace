# Draft a prompt, then a request

Status: approved (2026-11-19). Request: `maintainers/requests/draft-prompt.md`.

## 1. Goal

Two steps that are one today. First, a loose text (a dictated message, an audio transcript, notes typed in a hurry)
becomes an organized plan, saved and placed in a priority order. Then, when the person wants, that plan becomes a
request, after an agent evaluates it, researches it and proposes improvements. `/draft-prompt` does the first step;
the command that does the second today, `/draft-request`, is renamed `/new-request`. Both show a short summary on
screen instead of the whole text.

## 2. Today

- `/draft-request` (`workspace/rules/skills/draft-request/SKILL.md`, procedure in `workspace/rules/request-writing.md`)
  turns ideas into a request: it sizes it (`adjustment`, `feature`, `system`), writes BR-n and AC-n, decides the gaps
  as "assumed decisions", asks the blocking doubts, gives the effort of each step, saves to `custom/requests/` and
  commits and pushes it. `/caw-draft-request` is its layer at the root (plans and requests in `maintainers/`).
- It was `/draft-prompt` until 0.2.0, still unreleased; no workspace is installed yet.
- Nothing organizes a loose text without turning it into a request at once. A dictated idea is full of false starts,
  self-corrections ("no, sorry, I mean..."), repetitions and points out of order.
- `/draft-request` prints the whole request on screen at its first delivery (`request-writing.md` "Delivery"). In
  daily use that block is long and not read: what the person needs is what will be built, what was decided for them
  and what is left to answer.
- The product has no plans folder; only the maintenance has one (`maintainers/plans/`).

## 3. Design

### 3.1 `/draft-prompt` (new)

- Input: the loose text, or the path of a file holding it. Empty: ask for it in one line and stop.
- `screen` first (`/draft-prompt screen <text>`): no file, no README row, no commit; the whole plan is printed on
  screen in one fenced `markdown` block ready to copy, then `➜ Next: /new-request <paste it>`. It pairs with
  `/new-request` taking a text: organize, read, copy, request. Owner: asked for it (2026-11-19).
- A text that is one clear request in a line or two: say in one line that it can go straight to `/new-request`, with
  the command ready to copy, and stop; nothing is saved.
- It organizes and improves the writing, by the section "Organize" of `request-writing.md`, which `/new-request`
  follows too: removes fillers and repetitions; resolves self-corrections by keeping the
  last version ("rename A, no, sorry, rename B" keeps "rename B"); joins what was said twice; orders by subject;
  keeps names, commands, paths and numbers verbatim. It finds the gaps and lists them. It never adds a requirement of
  its own: evolving the idea is the job of the agent that reads the plan (the "Final guidance" below).
- It asks only when what is being asked is too vague to organize (no goal can be read, or two readings would be two
  different things): one message, few questions, each with a suggested answer. Every other gap goes to the plan,
  unanswered.
- The plan, in the language of the input text (section 3.5), with these three sections, headings in that language:
  - **Context**: what exists today and why the idea came up.
  - **Instructions**: what is wanted, grouped by subject, one bullet per point; constraints and preferences as said.
  - **Final guidance**: always the same order to the agent that will read it, then the gaps found:
    1. Evaluate the proposal before acting on it.
    2. Ask when in doubt.
    3. Research the best practices on the web, with generic terms only: never a company, customer or project name,
       a path or an internal URL in a search.
    4. Do not hold only to this text: evolve the idea and propose improvements.
    5. The gaps found, one per line, as questions.
- It saves the plan with a status line `Status: draft (<date>). Criticality: <level>.` and a row in the plans
  README, in the place of the priority order it suggests (section 3.4).
- It ends with the screen summary (section 3.6), never the whole plan, and the line to continue:
  `/new-request <plan path>`.

### 3.2 `/new-request` (renamed `/draft-request`, two changes)

- The rename: `workspace/rules/skills/draft-request/` becomes `workspace/rules/skills/new-request/`; at the root,
  `.claude/skills/caw-draft-request/` becomes `.claude/skills/caw-new-request/`. Every current reference follows
  (`workspace/README.md`, `workspace/docs/usage.md`, `workspace/rules/rules.md`, `rules/git.md`, `rules/security.md`,
  `templates/request.md`, `AGENTS.md`, the docstring and test of `scripts/session-title.py`, the root `CLAUDE.md`,
  `.claude/rules/process.md` and `security.md`, `docs/`, the pending plans and requests). History stays as written:
  past changelog entries, `requests/qa/`, `requests/done/`.
- Input: ideas, a file, or a plan of `/draft-prompt`; a plan is never required. Ideas or a file: it works as today,
  and organizes them first by the same rules as `/draft-prompt` (one source, a section "Organize" of
  `request-writing.md`), with no plan saved. With a plan, it follows its "Final guidance": it evaluates,
  researches, and proposes improvements, numbered, in the same message as the blocking doubts; each one enters the
  request only if the person accepts it (D-8), so no rule the person did not choose is written. The plan's row in the
  README then names the request, and its status line says `request: <file>`.
- Delivery: the screen summary (section 3.6) instead of the full text. The whole request only when the person asks
  for it, or when there is no write access (the separate Claude project of `request-writing.md`), because then no file
  holds it.

### 3.4 The plans README and the priority order

- Product: `custom/plans/<yyyy-mm-dd>-<kebab-slug>.md` and `custom/plans/README.md` (D-7), committed and pushed in the
  custom layer like a request of `/new-request` today. Root: `maintainers/plans/<kebab-name>.md` and
  `maintainers/plans/README.md`, committed only when the owner asks.
- The README gets a section "Pending, by priority" at the top: `| # | Plan | Criticality | Summary |`, in the order
  suggested; the current table stays below as the plans already requested or built.
- Criticality, three levels:

  | Level | When |
  | --- | --- |
  | `high` | a security or data hole, a broken flow that blocks daily use, or something another pending item waits on |
  | `medium` | a real improvement of a flow used often; it costs rework if it waits |
  | `low` | hygiene, convenience, naming |

- The new plan is placed by its criticality, then by what it depends on; the rows already there keep their level and
  relative order. The summary says where it went and why, so the person can move it.

### 3.5 The language of plans and requests

A rule, the same in the product and at the root: a plan or a request is saved in the language of the input text it
came from (the ideas, the dictated text, the plan it is built from); a text in two languages takes the one most of it
is written in. It is shown on screen in the reply language (the `language` setting). Not translated: the headings and
bold labels of `templates/request.md` and the label of a status line (`**Project:**`, `**State:**`, `Status:`,
"Execution"), because scripts and skills read them; technical terms of the market (commit, deploy, smoke test).
Everything else stays as it is today: code, rules, skills, docs, commits and changelogs in English, translations of
documents in `i18n/`. Plans and requests written before the build stay in English.

It replaces "saved in English" where it is written today:

- the root `CLAUDE.md` "Language" ("A plan, request or document is shown in the reply language and saved in English")
  and `.claude/rules/process.md` step 2 (a plan approved in plan mode recorded "in English");
- `workspace/AGENTS.md` (a plan, request or document written to a file "is in English");
- `workspace/rules/request-writing.md` "Role" ("write the saved file in English");
- `workspace/templates/request.md` (a request Claude writes "is saved in English");
- the product skill `/new-request` step 6 and the root layer `/caw-new-request`.

A document (a README, a page of `docs/`) stays in English with its translations in `i18n/`: the rule covers plans and
requests only.

### 3.6 The screen summaries

Both are short, in the reply language, formatted for a person to read, with the saved file named once.

`/draft-prompt`:

```text
Plan: Monthly billing report by e-mail
File: custom/plans/2026-11-19-monthly-billing-report.md (saved in Portuguese)
Summary: billing-api sends a PDF report to the finance team on the first business day of each month.
Criticality: medium (a manual task done every month) · Priority: 2 of 5, after release-main-sha-check
Gaps: 2 (the period covered; who else receives it)
➜ Next: /new-request 2026-11-19-monthly-billing-report.md
```

`/new-request`, a little more complete:

```text
Request: Monthly billing report by e-mail
File: custom/requests/2026-11-19-monthly-billing-report.md (saved in English)
Size: feature · Project: billing-api
Objective: a PDF of the previous month's billing, e-mailed to the finance team on the first business day.
What will be built:
  - BR-1 sent on the first business day of the month
  - BR-2 covers the month that ended
  - BR-3 recipients kept in a list the finance team edits
Done when: 4 criteria (sending day, period, recipients, PDF content)
Assumed decisions (answer to change one):
  - the time of sending: 08:00, the team's time zone
Improvements accepted: 1 · declined: 1
Open questions: none · Authorizations: none
Steps: 1. report (medium) · 2. sending (medium)
➜ Run: /request 2026-11-19-monthly-billing-report.md
```

## 4. Decisions

- D-1: `/draft-prompt` and `/new-request` in the product, `/caw-draft-prompt` and `/caw-new-request` at the root.
  Owner: yes, the names asked for.
- D-2: `/draft-prompt` organizes, improves, finds the gaps and asks only when the request is too vague; a request of
  a line or two goes straight to `/new-request`; the three sections, the fixed "Final guidance", the plans README with
  the priority order and the criticality, the screen summary. Owner: as above.
- D-3: the draft is a plan, saved in plans; it becomes a request only through `/new-request`. Owner: answered by D-2.
- D-4 and D-6: plans and requests, in the product and at the root, are saved in the language of the input text: a
  rule, not an exception (section 3.5). Owner: yes.
- D-5: no alias and no transition for `/draft-request` or the old `/draft-prompt`: no workspace is installed yet.
  Owner: yes.
- `/new-request` shows a summary instead of the whole request (section 3.6). Owner: asked for it.
- D-7: the product's plans in `custom/plans/`, beside `custom/requests/`. Owner: yes.
- D-8: the improvements `/new-request` proposes enter the request only when the person accepts each one. Owner: yes;
  and `/new-request` never requires a plan: given a text, it does what it does today, organizing it first by the
  rules of `/draft-prompt`.

Assumed, the owner can overturn:

- A-1: `/draft-prompt` runs on `claude-opus-5-5`, effort `medium`: it judges the gaps and the priority order but writes
  no rules. `/new-request` keeps `claude-opus-5-5`, effort `high`.
- A-2: neither command joins the mandatory core (`.claude/rules/product.md`), as `/draft-request` is not in it today.
- A-3: `request-writing.md` keeps its name; where it calls the request a "prompt" it says "request", so "prompt" names
  only what `/draft-prompt` writes.
- A-4: at the root, `/caw-new-request` keeps today's work of `process.md` step 2: with a plan, it writes the options,
  the recommendation and the decisions into the plan before the request; `process.md` steps 2 and 3 say that the plan
  starts as a draft of `/caw-draft-prompt`.
- A-5: the test of `session-title.py` checks that `/new-request` and `/draft-prompt` leave the title alone.
- A-6: the translations in `i18n/` follow at the release (`.claude/rules/docs.md`).

## 5. Stages

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Rename `/draft-request` to `/new-request`, product and root, with every reference and the changelog; the language rule of section 3.5 | high | It touches a hook (`session-title.py`, docstring and test): `/caw-test-install` too |
| 2. `/draft-prompt` and `/caw-draft-prompt`: the plan, its three sections, the plans README with priority and criticality, the summary, their docs | medium | A new skill with a clear scope |
| 3. `/new-request`: a plan as input with its "Final guidance", the accepted improvements, the summary instead of the full text (`request-writing.md` "Flow" and "Delivery") | medium | A change of a procedure people use every day, with a clear scope |
