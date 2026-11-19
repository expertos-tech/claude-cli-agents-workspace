# Functional request: prompt log, the results of the custom layer and of other sources, and readable session titles

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained, with the product in `workspace/`
(`scripts/prompt-log.py` and `scripts/tests/test_prompt_log.py`, the scripts README, `docs/usage.md`). It depends on
no other request and touches only the prompt log; it fits **round 2** of `maintainers/requests/README.md`, after the
first release.

## 1. Objective

The owner decided that the prompt log keeps "prompt and result" per project and per week, with the day and week
summaries built from the commits. Two gaps were found when it was built and never closed:

- prompts that touch no project go to the `workspace` bucket, and prompts of the folders listed in
  `custom/config/prompt-log/sources.json` go to their named project, but both never show a result: commits are only looked
  up in the repositories of `projects/`, so the commits of `custom/` and of a maintenance clone are missing;
- most older sessions have no `custom-title`, so the log shows the short session id instead of a readable title.

## 3. Business rules

- BR-1: prompts of the `workspace` bucket get as result the agent commits of `custom/` in their window (the same window
  rule as projects: from the prompt to the last response or tool result before the next one, at most 4 h). An
  installed workspace has no `.git` at its root, so `custom/` is the only repository of that bucket.
- BR-2: `sources.json` accepts, for each folder, either the project name (today's form, still valid) or an object
  `{"project": "<name>", "repo": "<path of the git repository>"}`; with `repo`, the prompts of that source get the
  agent commits of that repository as result. The path is expanded (`~`) and must be a git work tree; otherwise the
  sync prints a clear error for that source and goes on with the others.
- BR-3: an agent commit is still recognized only by the `[#automatic-agent-commit]` mark; the window and the
  deduplication rules of today do not change.
- BR-4: session title: the last `custom-title` record; else the last `ai-title` record (the title Claude Code generates
  itself, an undocumented record: a reader that does not find it falls back silently); else the short id, as today.
- BR-5: records already written are completed on the next sync while their transcript still exists (results and
  titles that were missing are filled), and a sync still never deletes a record nor rewrites a prompt text.
- BR-6: no new secret path: commit subjects already pass through the redaction and the gitleaks scan of `--commit`.

## 4. Acceptance criteria

- AC-1: Given a prompt that touched no project and a commit with the agent mark in `custom/` inside its window, when
  `prompt-log.py sync` runs, then the prompt's result lists that commit.
- AC-2: Given `sources.json` with `{"project": "claude-cli-agents-workspace", "repo": "<clone>"}` and an agent commit
  in that clone during a prompt of that source, then the prompt's result lists it; given the old string form, the sync
  behaves as today.
- AC-3: Given a `repo` that is not a git work tree, then the sync names the source in an error line and the other
  sources are still written.
- AC-4: Given a transcript with only an `ai-title` record, then the log shows that title; with neither record, the
  short id.
- AC-5: Given a week file written before this change whose transcripts still exist, when the next sync runs, then the missing results and titles are
  filled and no record is lost.
- AC-6: The suite covers each rule; `--context` stays within its time and line limits.

## 7. Out of scope

- A commit attributed to two sessions that worked on the same project at the same time (a known limit, kept).
- Changing the weekly file layout or the summaries.

## Decisions for the owner

1. **The maintenance clone as a source.** The owner rejected the source repository as a project inside `projects/`;
   BR-2 is the alternative (a repository path in `sources.json`). Accept it, or leave adjustment sessions without
   results? Recommended: accept.
2. **`ai-title` fallback.** It reads an undocumented record of the transcript. Accept it with the silent fallback, or
   keep the short id? Recommended: accept; the log already reads other undocumented records with the same care.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Results for `custom/` and for `sources.json` repositories, with the suite | medium | Clear rules over the existing window logic |
| 2. Titles from `ai-title`, filling older records, docs | low | A fallback and text |

The agents of each stage run with the stage's effort, passed in the call.
