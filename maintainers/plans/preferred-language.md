# The preferred language of communication

Status: approved, D-1 to D-4 by the owner (2026-11-18). Request: `maintainers/requests/preferred-language.md`.

## 1. Goal

The person chooses once the language Claude talks to them in, and every session of the product and of the
maintenance replies in it, whatever language the text in front of Claude is written in. Files stay in English.

## 2. Today

- The product (`workspace/AGENTS.md` "Role") and the maintenance (`CLAUDE.md` "Language") reply "in the language the
  person writes in". `.claude/rules/product.md` keeps it as an invariant: "no language setting".
- A request run from a file (`/request`, `/caw-request`) is written in English, so the session takes English as the
  person's language and the whole delivery comes back in English, though the person writes in another one.

## 3. Findings

- Claude Code has a native setting, `language` ("Preferred language for Claude responses and voice dictation, e.g.
  "japanese", "spanish""), read from every settings file.
- Proven by a headless run (2026-11-18): with `"language": "spanish"` in a project's `.claude/settings.local.json` and a
  `CLAUDE.md` that says "reply in the language the person writes in", an English prompt got a Spanish answer.
- `.claude/settings.local.json` is git-ignored at the root, and `workspace/scripts/setup-claude.sh` never touches it in
  an installed workspace ("Personal overrides belong in .claude/settings.local.json (never touched)").
- The installer asks its questions on `/dev/tty` (`install.sh`), so it can ask under `curl | bash`.

## 4. Design

- Storage: the native `language` key in `.claude/settings.local.json`, in both places; no file of our own and no text
  injected per turn. Claude Code applies it in every turn, after a compaction too, and it wins over an English
  request file. A `language` in the user's `~/.claude/settings.json` counts the same.
- Maintenance: one more SessionStart hook at the root, `tests/caw-language.py` (its own script, beside the session
  index). With a `language` in `.claude/settings.local.json` or in `~/.claude/settings.json`: it prints nothing.
  Without: it gives the session a context to ask, in the first reply and before anything else, the preferred
  language of communication, then write it as `language` in `.claude/settings.local.json` (other keys kept) and use
  it from then on. It never fails a session start.
- Product: no hook. A new workspace asks the question once, on the terminal, and writes the answer as `language` in
  `<workspace>/.claude/settings.local.json`, keeping any other key. An empty answer, or no terminal, writes nothing:
  the reply rule falls back to the language the person writes in. `aiwp update` never asks again and never touches
  the file.
- The reply rule, in `workspace/AGENTS.md` and the root `CLAUDE.md`: reply in the preferred language (the `language`
  setting); none set, in the language the person writes in. A plan, request or document is saved in English and shown
  in the reply language.

## 5. Decisions

- D-1: the native `language` key in `.claude/settings.local.json`, instead of a file `.claude/user-preferences.json`.
  Owner: yes.
- D-2: a `language` in the user's `~/.claude/settings.json` spares the question. Owner: yes.
- D-3: an install with no interactive terminal does not ask and leaves the language unset. Owner: yes.
- D-4: the invariant of `.claude/rules/product.md` "no language setting" becomes "the preferred language of
  communication is the `language` setting, asked at install". Owner: yes.

Assumed, the owner can overturn:

- A-1: the value is free text, the language's English name as Claude Code's examples (`portuguese`, `spanish`), at
  most 40 characters of letters, spaces, hyphens and parentheses; anything else is asked again.
- A-2: the product asks in `aiwp.sh new` (run by `install.sh` with the terminal), so every way of creating a
  workspace asks the same question.
- A-3: the maintenance hook runs on `startup|resume|clear|compact`, like the session index, so the question survives
  a compaction while unanswered.
