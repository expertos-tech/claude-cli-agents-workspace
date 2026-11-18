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
