# Functional request: import eleven improvements from an older workspace

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained, with the product in `workspace/`. It is the
first change after the 0.1.0 publication and runs on its own, before the other requests: its release is the first real
test of updating an installed workspace.

## 1. Objective

Bring into the product eleven small improvements found in an older, parallel version of the workspace, each one
reviewed for not adding a lock, a mandatory step or a conflict with the current flow; release them as a new version and
use that release to test `aiwp update` on a real installed workspace.

## 3. Business rules

- BR-1 (D1) `rules/frontend.md` "Behavior": replace the motion bullet with: "Motion gives continuity: route changes,
  tabs, panels and dialogs opening and closing, data entering, loading turning into content. 150–300 ms, ease-out,
  interruptible; never delays or blocks input, never the only carrier of information; no infinite loop except a loading
  indicator; `prefers-reduced-motion` and the user's toggle make it instant." Keep the game exception. Add a "usability
  first" line: each screen shows at once what it is about, the state of things and the next step; components grouped by
  task, with tabs instead of one long page; a whole clickable row keeps a real link or button.
- BR-2 (D2) `AGENTS.md` "Safety": "A tool call stopped by a new message of the human is an interruption, not a refusal:
  handle the message, and never say the human refused it."
- BR-3 (D3) `AGENTS.md` "When a rule gets in the way": "Apply a statement of the human at the scope it was said; ask
  before widening it; never record your own extension as the human's decision."
- BR-4 (D4) `rules/quality.md` "Checking a skill": "it ran and worked: it is done; never write a harness, a checker or a
  long scripted run for it."
- BR-5 (D5) `rules/quality.md`: in the container-isolation bullet, "a smoke run of an image that declares `VOLUME`
  mounts it named or as tmpfs"; in the evals bullet, "an eval applies the app's own normalization and validation first;
  a refused output counts as a failure".
- BR-6 (D6) `rules/models.md` "When to delegate": "parallel subagents that need temp files each get their own folder in
  the brief and never delete outside it."
- BR-7 (D7) `rules/skills/prompt/SKILL.md`: "A file the request expects from earlier work, not at the named path: search
  for it by name before reporting it missing." Never used to find the prompt itself.
- BR-8 (D8) the lesson line in `custom/docs/lessons.md` (`AGENTS.md`) gets three tags: weight (`grave`, `attention`,
  `suggestion`; `grave` when a rule let the forbidden through or was bypassed, or there was a security failure, data
  loss, a destructive action without confirmation, or a BLOCKER that reached the base or came back from the same cause),
  scope (`general` or `project <name>`), recurrence (`recurring` or `rare`). Everything is still recorded; the human
  still decides. No new step.
- BR-9 (D10) `scripts/performance/measure.py`: keep the duration of each hook run and show median and p90 per hook
  instead of the mean; add "Hook wait per prompt, p90" (the largest `UserPromptSubmit` of each prompt). Older reports
  stay readable (compatibility or a new `FORMAT`); `tests/test_performance.py` updated.
- BR-10 (D11) `tools/observability/dashboards/workspace/claude-code.json`: two bar-gauge panels in "Where the cost
  goes", `cost_usd` of `api_request` summed by `skill_name` and by `agent_name`; one line in the tool README; the
  existing dashboard query check covers them.
- BR-11 (D12) `tools/container-console-colima/docs/operations.md`: new, mirroring the docker-ce one: logs, investigation
  commands, monitoring (healthz, `launchctl print` with the tool's labels, `colima list --json`), and a table of common
  failures (bind mount outside `~` empty, `credsStore desktop`, missing `/var/run/docker.sock`, missing kube context, a
  disk that only grows, the Dock icon, a broken VM and `colima stop --force`). Derived from the product's code; linked
  from the README.
- BR-12: each change keeps its translations (`i18n/pt-BR`, `i18n/es`) in the same commit when it touches a document.
- BR-13: release through `/merge --main`: the version is a minor (rules change behaviour), `CHANGELOG.md` lists the
  eleven items, written by `/merge` as they enter `developer`; tag, push and GitHub release only with the owner's confirmation at each step.
- BR-14: after the release, the owner runs `aiwp update` in a terminal on a dedicated installed workspace with real
  projects (not the main one); the session records the result.

## 4. Acceptance criteria

- AC-1: Given the eleven changes, then `bash tests/check.sh --all` and `/test-install` pass, and no change adds a hook,
  a gate step or a mandatory step.
- AC-2: Given the release, when the owner runs `aiwp update` on the dedicated workspace, then it lists the installed
  workspaces with "Update all" as the default, the data folder moves to the new tag, only the changed core files are
  swapped, permissions are back to 555/444, `custom/`, `projects/` and `tmp/` are untouched, and a new session there
  loads the new rules.
- AC-3: Given the updated workspace, when the owner runs `aiwp rollback` and then `aiwp update`, then it returns to the
  previous version and back to the new one.
- AC-4: Given a session opened in that workspace before the update, then the SessionStart notice told it to close and
  run `aiwp update`, and the session did not update anything itself.

## 7. Out of scope

- Everything else found in the older workspace (rejected rows of the analysis).
- The `/rules lessons` view of the tagged lessons (it belongs to the `rules` request).

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Rule and skill lines (BR-1 to BR-8) | medium | Small text changes with clear wording |
| 2. `measure.py`, dashboard, Colima operations doc (BR-9 to BR-11) | medium | Code with tests; a doc derived from code |
| 3. Release and the update test with the owner (BR-13, BR-14) | high | Public action and the first real update |

The agents of each stage run with the stage's effort, passed in the call.
