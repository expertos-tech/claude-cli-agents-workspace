# Functional request: draft a prompt, then a request

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**State:** ready. **Where it runs:** a work clone of this repository; it changes the product (`workspace/rules/skills/`,
`workspace/rules/request-writing.md`, `workspace/templates/request.md`, `workspace/AGENTS.md`, `workspace/rules/`,
`workspace/scripts/session-title.py` and its test, `workspace/README.md`, `workspace/docs/usage.md`,
`workspace/CHANGELOG.md`) and the maintenance (`CLAUDE.md`, `.claude/skills/`, `.claude/rules/process.md`,
`.claude/rules/security.md`, `docs/`, `maintainers/plans/README.md`, the pending plans and requests). Design:
`maintainers/plans/draft-prompt.md`. Source: the owner, 2026-11-19: the step that only organizes an idea is missing,
`/draft-request` no longer says what it does, and printing the whole request on screen is not read.

## 1. Objective

A loose text (a dictated message, a transcript, hurried notes) becomes an organized plan, saved and placed in a
priority order, with `/draft-prompt`; a plan or a text becomes a request with `/new-request`, the current
`/draft-request` renamed. Both show a short summary on screen, not the whole file. A plan is saved in the person's
language and a request in English; whatever is shown on screen is in the person's language, but code and
configuration. The same in the product and at the root (`/caw-draft-prompt`, `/caw-new-request`).

## 3. Business rules

- BR-1: `/draft-request` is renamed `/new-request` (folder, `name:` and every current reference), and
  `/caw-draft-request` is renamed `/caw-new-request`, with no alias. History stays as written: past changelog
  entries, `maintainers/requests/qa/`, `maintainers/requests/done/`, the plan and this request. The 0.2.0 sections of
  `workspace/CHANGELOG.md` and of the root `CHANGELOG.md` are not released, so they are no history: every mention of
  `/draft-request` or `/caw-draft-request` there names the new command, but an entry that records this rename (in
  the product's, the rename line becomes
  "`/prompt` and `/draft-prompt` are renamed `/request` and `/new-request`", and the line on the warnings, "Also when
  `/draft-request` writes a request", names `/new-request`), and a new line says what `/draft-prompt` does now.
- BR-2: The files. A plan is saved in the person's language: the Claude Code setting `language`, else the language
  the person writes in. A request is saved in English, as today, its template headings and bold labels included.
  Not translated in a plan: the labels of its status line (`Status:`, `Criticality:`). Code, rules, skills, documents,
  commits and changelogs stay in English, translations of documents in `i18n/`; the product's `custom/plans/README.md`
  is in the person's language, the root's `maintainers/plans/README.md` in English (a translated document). It
  replaces "plans ... saved in English" in the root `CLAUDE.md` "Language", `.claude/rules/process.md` step 2,
  `.claude/rules/product.md` (its "English" bullet), `workspace/AGENTS.md` "Role" and `docs/maintenance.md` (the line
  "**Plans and requests** are shown to the owner ... and saved in English"); `request-writing.md` "Role" and
  `templates/request.md` keep "saved in English", which speaks of requests. Plans written before stay as they are.
- BR-3: One source of the organizing rules, a section "Organize" of `workspace/rules/request-writing.md`, below its
  paste marker: remove fillers and repetitions; on a self-correction keep the last version; join what was said twice;
  order by subject; keep names, commands, paths and numbers verbatim; list the gaps; add no requirement of its own.
  `/draft-prompt` and `/new-request` both follow it.
- BR-4: `/draft-prompt [screen] [text | path]`: empty, it asks for the text in one line and stops. With `screen`, it
  writes no file, touches no README and commits nothing: it prints the whole plan on screen, in one fenced `markdown`
  block ready to copy, then `➜ Next: /new-request <paste it>`; everything else of BR-3 to BR-5 holds. One clear request in a line
  or two: it says in one line that it can go straight to `/new-request`, with the command ready to copy, and saves
  nothing. It asks only when the text is too vague to organize (no goal can be read, or two readings would be two
  different things): one message, each question with a suggested answer. It never runs anything else.
- BR-5: The plan of `/draft-prompt`: a title, the line `Status: draft (<yyyy-mm-dd>). Criticality: <high | medium |
  low>.`, and three sections with headings in the person's language: Context, Instructions, Final guidance. Final
  guidance always holds, in this order: evaluate the proposal before acting; ask when in doubt; research the best
  practices on the web with generic terms only, never a company, customer or project name, a path or an internal URL;
  do not hold only to this text, evolve the idea and propose improvements; then the gaps found, one per line, as
  questions.
- BR-6: Where the plan goes, without `screen`. Product: `custom/plans/<yyyy-mm-dd>-<kebab-slug>.md` and `custom/plans/README.md`,
  committed and pushed by path in `custom/` as `/new-request` does with a request. Root:
  `maintainers/plans/<kebab-name>.md` and `maintainers/plans/README.md`, committed only when the owner asks. Never
  overwrite another plan (`-2`, `-3`).
- BR-7: The plans README gets, at the top, a section "Pending, by priority", `| # | Plan | Criticality | Summary |`.
  The new plan goes in by its criticality, then by what it depends on; the rows already there keep their level and
  relative order. Criticality: `high`, a security or data hole, a broken flow that blocks daily use, or something
  another pending item waits on; `medium`, a real improvement of a flow used often; `low`, hygiene, convenience,
  naming. The other plans stay in the table below it.
- BR-8: `/new-request` never requires a plan. Given ideas or a file, it does what it does today, organizing them first
  by BR-3, with no plan saved. Given a plan of `/draft-prompt`, it follows its Final guidance: it evaluates and
  researches, and proposes improvements, numbered, in the same message as the blocking doubts; each one enters the
  request only if the person accepts it. Then the plan's README row leaves "Pending, by priority" and names the
  request, and its status line says `request: <file>`. At the root, `/caw-new-request` with a plan also writes the
  options, the recommendation and the decisions into it before the request (`process.md` step 2).
- BR-9: Screen summaries, in the reply language, never the whole file (but `/draft-prompt screen`, BR-4), the saved file named once with the language
  it was saved in. `/draft-prompt`: plan title, file, a one-line summary, criticality with its reason, its place in the
  priority order, the gaps, and `➜ Next: /new-request <file>`. `/new-request`: title, file, size, project, objective,
  what will be built (one line per business rule), how many acceptance criteria and what they cover, every assumed
  decision, improvements accepted and declined, open questions, authorizations, the steps with their effort, and
  `➜ Run: /request <file>`. The whole request is shown only when the person asks for it, or when there is no write
  access (the separate Claude project of `request-writing.md`).
- BR-10: The screen, a rule of every reply, apart from BR-2. Whatever is shown to the person is in the person's
  language (BR-2), whatever the language of its source: a plan, a request, a document, a rule, a summary, a board.
  Source code and configuration are shown exactly as they are. Documentation in code (docstrings) and comments, shown
  for reading, are in the person's language; a block meant to be copied into a file, a diff or a patch is shown
  verbatim, because it must match the file, and is explained around it. Literal output (an error message, a log
  line, a command's output) is quoted verbatim and explained in the person's language. Where: the reply-language
  bullet of `workspace/AGENTS.md` "Role" and of the root `CLAUDE.md` "Language", `workspace/docs/usage.md`
  "Language", and `.claude/rules/product.md` ("Claude answers in the person's language").

## 4. Acceptance criteria

- AC-1: Given the build, when `/draft-request` and `caw-draft-request` are searched in the repository, then they
  appear only in what BR-1 keeps as history; `workspace/rules/skills/new-request/`, `.claude/skills/caw-new-request/`,
  `workspace/rules/skills/draft-prompt/` and `.claude/skills/caw-draft-prompt/` exist, and
  `bash tests/check.sh --base origin/developer --i18n-pending` passes, the `caw-layers` check included.
- AC-2: Given the test of `session-title.py`, when it runs, then `/new-request ideas` and `/draft-prompt ideas` leave
  the title alone, and `/request <file>` still names the session from the `**Project:**` line.
- AC-3: Given a test installation with `language` portuguese and a dictated text in English with a self-correction
  and a repeated point, when
  `/draft-prompt` runs on it, then `custom/plans/<date>-<slug>.md` is in Portuguese with the status line and the three
  headings, holds only the corrected version and the point once, carries the five items of Final guidance in order,
  and is committed in `custom/` with its README row in "Pending, by priority"; the screen shows the summary of BR-9 and
  not the plan.
- AC-4: Given a one-line clear request, when `/draft-prompt` runs, then no file is written and the reply gives the
  `/new-request` command. Given a text with no goal that can be read, then it asks in one message with suggested
  answers and writes nothing before the answer.
- AC-5: Given `language` portuguese and a loose text in Portuguese with a self-correction, when `/new-request` runs on
  it, then the request is in English, holds only the corrected version, no plan is written, and the screen shows the
  summary of BR-9 in Portuguese, every assumed decision included, and not the request.
- AC-6: Given a plan of `/draft-prompt`, when `/new-request` runs on it and the person accepts one proposed
  improvement and declines another, then only the accepted one is in the request, the plan's status line names the
  request and its README row left "Pending, by priority".
- AC-7: Given the root, when `/caw-draft-prompt` runs on a text, then `maintainers/plans/<name>.md` and its README row
  are written, the plan in the owner's language and the row in English, and nothing is committed; the root
  `CLAUDE.md` "Language", `process.md` and `docs/maintenance.md` state BR-2, and no file of BR-2 still says a plan is
  saved in English.
- AC-8: Given a dictated text, when `/draft-prompt screen` runs on it, then the whole plan of BR-5 is on screen in one
  `markdown` block, and no file, README row or commit is made, in the product and at the root.
- AC-9: Given `language` portuguese and an English script with comments and a docstring, when the session is asked
  to show one of its functions for reading, then the code lines are shown exactly as in the file and the comments and
  the docstring in Portuguese; asked for a diff of that file, the diff is verbatim.

## 7. Out of scope

- Translating the plans and requests that exist, and giving a criticality to the plans already in the README.
- A criticality field in requests, and any change to the order of `maintainers/requests/README.md`.
- Documents saved in the person's language: READMEs, `docs/` and their `i18n/` stay as they are.
- `/request` reading a plan directly: a plan becomes a request only through `/new-request`.

## Steps and effort

| Step | Effort | Why |
| --- | --- | --- |
| 1. The rename (BR-1) and the language rules (BR-2, BR-10), product and root | high | It touches a hook (`session-title.py`, docstring and test): `/caw-test-install` too |
| 2. "Organize" and `/draft-prompt` with `/caw-draft-prompt`: the plan, `screen`, the plans README with priority and criticality, the summary, the docs (BR-3 to BR-7, BR-9) | medium | A new skill with a clear scope |
| 3. `/new-request`: a text organized by BR-3, a plan with its Final guidance and the accepted improvements, the summary instead of the full text (BR-8, BR-9) | medium | A change of a procedure used every day, with a clear scope |

The subagents of each step run with the step's effort, passed in the call.

## Assumed decisions

- Open: the model of `/draft-prompt`. Decided: `claude-opus-5-5`, effort `medium`; `/new-request` keeps
  `claude-opus-5-5`, effort `high`. Reason: it judges gaps and priority but writes no rules.
- Open: the mandatory core. Decided: neither command joins it (`.claude/rules/product.md`). Reason: `/draft-request`
  is not in it today.
- Open: the word "prompt" in `request-writing.md`. Decided: it says "request" where it means the request, so "prompt"
  names only what `/draft-prompt` writes. Reason: two meanings of one word.
- Open: the order with `request-in-progress`. Decided: it runs after `request-in-progress` is on `developer`.
  Reason: both change `rules/git.md`, `.claude/rules/process.md` and `.claude/rules/security.md`.
- Open: acceptance criteria. Decided: AC-1 to AC-9, derived from the rules; AC-3 to AC-9 by headless runs, in a test
  installation for the product. Reason: they prove the behavior of skills.

---

## Stopped — 2026-11-20

- Where: `tmp/work/2026-11-20-draft-prompt/claude-cli-agents-workspace`, branch `feat/draft-prompt`, stages 1 and 2
  done and pushed: `4698af1` the rename, `7b2771b` the language rules, `da6d784` `/draft-prompt`, `0ab13fe`
  `/caw-draft-prompt`.
- Stage 1 (BR-1, BR-2, BR-10): `/draft-request` is `/new-request` and `/caw-draft-request` is `/caw-new-request`, every
  current reference with them, the session-title docstring and test included; the language of files and of the screen
  written in `workspace/AGENTS.md` "Role", `workspace/docs/usage.md` "Language", the root `CLAUDE.md` "Language",
  `.claude/rules/process.md` step 2, `.claude/rules/product.md`, `docs/maintenance.md`, `/caw-new-request` and the
  0.2.0 changelog entries that said a plan is saved in English.
- Stage 2 (BR-3 to BR-7, BR-9 for `/draft-prompt`): the section "Organize" of `workspace/rules/request-writing.md`;
  `workspace/rules/skills/draft-prompt/` (`claude-opus-5-5`, effort `medium`) and its layer
  `.claude/skills/caw-draft-prompt/`; "Pending, by priority" at the top of `maintainers/plans/README.md` (empty: the
  plans there get no criticality, out of scope), the other plans under "Other plans"; the custom-layer commit scope
  `plans` in `workspace/rules/git.md`; `workspace/README.md`, `workspace/docs/usage.md`, `workspace/rules/rules.md`,
  box 5 of `workspace/rules/assisted.md`, `docs/features.md`, `docs/maintenance.md`, `process.md` step 2 and the
  product changelog line of `/draft-prompt`.
- Decisions taken: those of stage 1 (the plans of requests already built and the rows that record the rename keep
  `/draft-request` as history; `i18n/` follows at the release); `➜ Next` of `/draft-prompt` gives the plan's path
  (`/new-request custom/plans/<file>`, `/caw-new-request maintainers/plans/<name>.md`), not a bare name, so it is never
  read as a request name. A-3 ("prompt" to "request" in `request-writing.md`) goes with stage 3.
- Proven: `bash tests/check.sh --base origin/developer --i18n-pending` green; `test_session_title.py` 37 tests OK
  (AC-2); `bash tests/test-install.sh` all PASS. Headless runs of `/draft-prompt` in a test installation with
  `language` portuguese: AC-3 (a dictated English text: the plan in Portuguese with the status line, the three headings,
  PDF kept over the corrected CSV, the finance team once, the five items of Final guidance in order, committed in
  `custom/` with its README row in "Pending, by priority"; the screen showed the summary, not the plan), AC-4 (a
  one-line request: no file, the `/new-request` command; a text with no goal: one message of questions with
  suggestions, nothing written), AC-8 (`screen`: the whole plan in one `markdown` block, no file, no commit). The first
  AC-8 run said a plan would be saved in English: step 4 of the skill now says the "saved in English" of
  `request-writing.md` speaks of requests, and the rerun no longer says it.
- Next steps: stage 3, `/new-request` with a text organized by "Organize" or a plan with its Final guidance, the
  accepted improvements, the plan's README row and status line, the summary instead of the full text (BR-8, BR-9),
  `/caw-new-request` with a plan (A-4, `process.md` step 3) and A-3, effort medium. Then AC-5, AC-6, AC-7 and AC-9 by
  headless runs (AC-7 at the root, in a throwaway copy, nothing committed).

## Execution — 2026-11-20, merged into developer

- **Done:** stage 1 (BR-1, BR-2, BR-10): `/draft-request` renamed `/new-request` and `/caw-draft-request`
  `/caw-new-request`, every current reference with them (4698af1); the rule of the files (a plan in the person's
  language, a request in English) and the rule of the screen (7b2771b). Stage 2 (BR-3 to BR-7, BR-9): the section
  "Organize" of `request-writing.md` and `/draft-prompt` (da6d784); `/caw-draft-prompt` and "Pending, by priority" of
  `maintainers/plans/README.md` (0ab13fe). Stage 3 (BR-8, BR-9, A-3, A-4): `/new-request` with a text organized first
  or a plan with its final guidance, improvements `I-n` accepted by number, the plan's status line and README row at
  delivery, the summary instead of the whole request, "prompt" no longer naming the request in
  `request-writing.md` (98ad4a8); `/caw-new-request` from a draft plan, `process.md` step 3 (3c4b409). Resume points
  7987c10 and a960c94; the changelog entries with each stage and 3e12091.
- **Decisions:** the plans of requests already built and the rows that record the rename keep `/draft-request` as
  history; `i18n/` follows at the release; `➜ Next` of `/draft-prompt` gives the plan's path, never a bare name.
  Stage 3: "ok" alone accepts the suggested answers of the questions and no improvement; the plan's status line
  becomes `Status: request: custom/requests/<file> (<date>). Criticality: <level>.`; a plan whose status line already
  names a request is asked about before a second one; at the root a draft plan given to `/caw-new-request` defaults
  to `request`, and `plan` writes only the design into it, its row still pending.
- **Deviations:** `/caw-new-request` in `plan` mode shows a summary too (title, file, recommendation, every open
  decision), beyond BR-9, which names only `/draft-prompt` and `/new-request`.
- **Done when:** AC-1 by the suite (`caw-layers` included) and a search of the names; AC-2 by
  `test_session_title.py` (37 tests OK); AC-3, AC-4 and AC-8 by headless runs of stage 2 in a test installation;
  AC-5 and AC-6 by headless runs in a test installation with `language` portuguese (the request in English with only
  the corrected version and no plan, the summary in Portuguese with every assumed decision; only the accepted
  improvement in the request, the plan's status line and README row in the same commit); AC-7 by a headless run in a
  throwaway copy of the root (the plan in Portuguese, its row in English, nothing committed) and a search of the
  files of BR-2; AC-9 by a headless run with the installation's `.claude/AGENTS.md` given to the session (the code
  lines as in the file, the comments and docstring in Portuguese; the diff verbatim). A headless session in an
  installation under this repository's `tmp/` loads the root `CLAUDE.md` instead of the installation's (the pattern
  `**/claude-cli-agents-workspace/tmp/**` of `claudeMdExcludes`), and one outside it, in a folder not trusted, loads
  no project memory: a criterion that depends on `AGENTS.md` is proven with it given to the session.
- **Checks:** `bash tests/check.sh --base origin/developer --i18n-pending` passed (repo-terms skipped: no terms list);
  `bash tests/test-install.sh` every check PASS, in stages 1 and 3.
- **Warnings:** W-1 (AC-9 not reached) fix: no change needed; the failure came from the test setup, and the rule of
  stage 1 passes AC-9.
- **Left:** nothing.
