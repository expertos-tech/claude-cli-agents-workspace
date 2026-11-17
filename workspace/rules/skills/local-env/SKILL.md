---
name: local-env
description: "Create or complete the filled .env of a folder from its .env.example (docker/, docker/sonar/, tools/<name>/ go to custom/env/<name>.env; a project or clone keeps its own .env), never showing values. Use only when the user asks."
argument-hint: "[dir]"
disable-model-invocation: true
model: claude-opus-5-5
effort: low
---

Arguments: `$ARGUMENTS`. Folder holding `.env.example`, relative to the root or absolute; default `docker`.

- A core folder (`docker`, `docker/sonar`, `tools/<name>`): the filled file is `custom/env/<name>.env` (`docker.env`, `docker-sonar.env`, `<name>.env`), git-ignored by the custom layer, mode 600. The core never holds a `.env`; compose reads the file with `--env-file`.
- A project, a clone of `tmp/work/` (`rules/git.md` "Work area": `aiwp-cmds.sh open` copies the `.env` of its source repo) or a POC: its own `<dir>/.env`, which git must ignore.

1. `bash scripts/sync-env.sh --path <dir>`. This request authorizes writing that one file, and the line `env/` in `custom/.gitignore` when the custom layer does not ignore `env/` yet (the script adds it and says so: tell the person to commit it in `custom/`).
2. Reply in the language of the conversation with the script result: the file, created, updated or unchanged; keys added; keys empty (need a value from the user) and keys still equal to `.env.example` (placeholder to replace or default to confirm). The person fills the values in an editor; NEVER read, print, guess or generate a value, and never open the file (the deny rules refuse `custom/env/**` and `.env`).
