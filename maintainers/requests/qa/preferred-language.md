# Functional request: the preferred language of communication

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**State:** ready. **Where it runs:** a work clone of this repository; it changes the product (`workspace/AGENTS.md`,
`workspace/scripts/aiwp.sh`, its tests and docs) and the maintenance (`CLAUDE.md`, `.claude/`, `tests/`). Design:
`maintainers/plans/preferred-language.md`. Runs after `rules-as-product-layers` is merged (both change `CLAUDE.md` and
the root `.claude/settings.json`).

## 1. Objective

The person chooses once the language Claude talks to them in; every session, of the product and of the maintenance,
replies in it, even when it runs a request file written in English. Files stay in English.

## 3. Business rules

- BR-1: the preferred language is the native Claude Code setting `language`, in `.claude/settings.local.json` of the
  workspace or of this repository; a `language` in the user's `~/.claude/settings.json` counts the same.
- BR-2: the reply rule, in `workspace/AGENTS.md` and the root `CLAUDE.md`: reply in the preferred language; none set,
  in the language the person writes in. A plan, request or document is saved in English and shown in the reply
  language.
- BR-3: maintenance: a SessionStart hook at the root (`tests/caw-language.py`, matcher `startup|resume|clear|compact`)
  prints nothing when a `language` is set (BR-1); otherwise it tells the session to ask, in its first reply and before
  anything else, the preferred language of communication, write the answer as `language` in
  `.claude/settings.local.json` keeping the other keys, and use it from then on. It never fails a session start.
- BR-4: product: no hook. Creating a workspace (`aiwp.sh new`, which `install.sh` runs with the terminal) asks once,
  on the terminal, the preferred language of communication, and writes it as `language` in
  `<workspace>/.claude/settings.local.json`, keeping any other key. An empty answer or no terminal writes nothing.
- BR-5: the value is the language's English name (`portuguese`, `spanish`): at most 40 characters of letters, spaces,
  hyphens and parentheses; anything else is asked again.
- BR-6: `aiwp update` and `setup-claude.sh` never ask and never change `.claude/settings.local.json`.
- BR-7: `.claude/rules/product.md`: the invariant "no language setting" becomes "the preferred language of
  communication is the `language` setting, asked at install" (the owner's D-4 of the plan).

## 4. Acceptance criteria

- AC-1: Given `"language": "portuguese"` in `.claude/settings.local.json`, when a session runs a request file written
  in English, then it replies in Portuguese (a headless run, at the root and in a test installation).
- AC-2: Given no `language` in the local nor the user settings, when a maintenance session starts, then the hook's
  context asks for it; given either, the hook prints nothing; a malformed settings file still exits 0 (scenario tests).
- AC-3: Given `aiwp.sh new` with a terminal, an answer `portuguese` writes `"language": "portuguese"` and keeps the
  other keys of an existing `.claude/settings.local.json`; an invalid answer is asked again; an empty answer and no
  terminal write nothing (scenario tests and `/caw-test-install`).
- AC-4: Given an installed workspace with a `language`, when `aiwp update` and `setup-claude.sh` run, then
  `.claude/settings.local.json` is byte for byte the same (test).
- AC-5: `bash tests/check.sh --base origin/developer --i18n-pending` passes, with the new hook's tests in it.

## 7. Out of scope

- Translating any file, or a language per project.
- Voice dictation, which the same setting also drives.
- Asking again in an existing workspace: the person adds the key, or the maintenance hook asks at the root.

## 11. Steps and effort

| Step | Effort | Why |
| --- | --- | --- |
| 1. Product: the question in `aiwp.sh new`, BR-4 to BR-6, its scenario tests | high | The installer |
| 2. Product rules: `workspace/AGENTS.md` (BR-2), `.claude/rules/product.md` (BR-7), `workspace/docs/` and `docs/getting-started.md` | medium | Rules and docs |
| 3. Maintenance: `tests/caw-language.py`, its entry in `.claude/settings.json`, scenario tests in `tests/check.sh`, `CLAUDE.md` "Language" | high | A hook |
| 4. Proof: AC-1 headless at the root and in `/caw-test-install` | medium | The end-to-end check |

The subagents of each step run with the step's effort, passed in the call.

## Assumed decisions

- The owner decided D-1 to D-4 of the plan (2026-11-18). A-1 to A-3 of the plan are assumed: the value format, the
  question in `aiwp.sh new`, the hook's matcher.

---

## Execution — 2026-11-18, merged into developer

Done, by step:

- Step 1, product (high): `6f271d6` `aiwp new` asks the language on a terminal right after the custom layer and
  writes `language` in `.claude/settings.local.json` keeping the other keys, atomically; scenarios for the question,
  the merge of keys, and `aiwp update`, the opening and `setup-claude.sh` leaving the file byte for byte the same.
- Step 2, rules and docs (medium): `42e08df` `workspace/AGENTS.md` "Role", `rules/rules.md`, `README.md`,
  `docs/usage.md`; `d536a61` `.claude/rules/product.md` (BR-7); `docs/getting-started.md` in `6f271d6`.
- Step 3, maintenance (high): `dd6059b` `tests/caw-language.py`, its entry in `.claude/settings.json`,
  `tests/test-caw-language.sh` (14 scenarios) in `tests/check.sh`, `CLAUDE.md` "Language"; `d0febb6` the stub of the
  new suite in the repo-terms scenario of `tests/test-caw-work.sh`.
- Step 4, proof (medium): the headless runs and `/caw-test-install` below.
- The owner's answers to the closing board's warnings: `4c2d4c8` (W-2), `30ca933` (W-4), `aa20086` (W-3),
  `3600cf3` (W-6), `1725015` (W-5); W-1 became `maintainers/requests/merge-queue.md`.
- Changelog: `b014468`.

Decisions taken while running (the owner, 2026-11-18):

- W-1: a merge queue, written as the request `merge-queue.md` (`ready`), instead of only merging one branch first.
- W-2: the language answer follows BR-5 exactly: the extra "at least one letter" check is gone.
- W-3: the single-agent mode is removed from the product (`single-claude`, `single-agent.sh`, the plugin and its
  `/single-agent` skill, the template, `docs/single-agent.md` with its translations, its suite and harness, the deny
  `Read(**/SINGLE-AGENT.md)`): working alone with one agent is now the default. The reply-language rule stays.
- W-4: the lint debt is fixed: the Python embedded in `aiwp.sh` passes ruff check and format; `tests/check.sh`
  declares `shellcheck source-path=SCRIPTDIR`.
- W-5: the 8 translations that kept the single-agent mode are translated again in full now, not at the release.
- W-6: `aiwp update` removes a dangling `~/.local/bin/single-claude` link to the updated workspace's script.

Deviations from the request:

- Beyond the listed files, the language rule was also aligned in `workspace/README.md`, `rules/rules.md`, and the
  statements "the one hook of the root" of `CLAUDE.md` and `docs/maintenance.md` (now two hooks).
- W-3 to W-6 go beyond the request, each by the owner's answer above.

Acceptance criteria:

- AC-1: proven by headless runs: with `"language": "portuguese"` an English request file got a Portuguese reply at a
  root copy of the branch (its `CLAUDE.md` loaded) and in a workspace installed from the branch.
- AC-2: proven by `tests/test-caw-language.sh` (unset, local, user through `CLAUDE_CONFIG_DIR` and `HOME`, malformed
  files, non-string values, no `CLAUDE_PROJECT_DIR`, the registration) and by a headless run with no setting whose
  first line asked the language.
- AC-3: proven by the aiwp scenarios and by `aiwp new` on a pty of the test installation: an invalid answer asked
  again, `portuguese` (padded) written trimmed; no terminal writes nothing.
- AC-4: proven by the aiwp and setup-claude scenarios (update, opening, rollback, repair, setup-claude: byte for byte
  the same) and by `setup-claude.sh` in the installed workspace.
- AC-5: proven: the suite below.

Checks: `bash tests/check.sh --base origin/developer --i18n-pending` rc 0 (repo-terms skipped: no terms list found);
aiwp 64, setup-claude 37, caw-language 14 scenarios; `/caw-test-install` PASS; ruff and shellcheck (the gate's pinned
images) clean on the changed scripts.

Left: nothing of this request. `merge-queue.md` is pending.
