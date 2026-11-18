---
name: rules
description: "Show the rules, skills and agents this workspace loads, with where each comes from, and change them in the custom layer: turn a core one off or on, replace a core rule, add an own rule, or turn the tagged lessons into own rules. Use only when the user asks."
argument-hint: "[exclude <name> | include <name> | add <subject> | replace <rule> | lessons]"
disable-model-invocation: true
model: claude-opus-5-5
effort: medium
---

Arguments: `$ARGUMENTS`. The configuration is `custom/rules-config.json` and the own items are in `custom/my-rules/`
(`*.md` rules, `skills/<name>/`, `agents/<name>.md`); `scripts/rules-config.py` reads, validates and edits them, and
`scripts/setup-claude.sh` builds `.claude/` from them at every session start (`rules/rules.md` "Custom layer"). The
mandatory core (`rules/manifest.json`) never turns off: the script refuses it, say so with its reason. Run every
command from the workspace root as `python3 -I -B scripts/rules-config.py <command>`. Show tables in the human's
language; files stay in English.

## No argument

Run `show` and print its tables: the core rules, skills and agents with their state (core, mandatory, turned off,
replaced) and how each loads, the own items, then the warnings, each with what fixes it (an own rule with a core name:
rename it or declare a `replace`; an `exclude` that names nothing in the core: remove it). Nothing changes.

## exclude, include

`exclude <name>` or `include <name>`: a rule is named with `.md` (`frontend.md`); a skill or agent by its name. A name
that is both a skill and an agent: add `--kind skills` or `--kind agents`. `include` of a replaced rule brings the core
one back; the own file stays, and the script says to delete or rename it. Then "After a change".

## add

`add <subject>`: first read the own rules (`custom/my-rules/*.md`) and the core rules on the same subject. One that
already covers it: adjust it instead, and say so. Otherwise run `add "<subject>"`, which creates
`custom/my-rules/<slug>.md` with its title and prints the path, and write the rule there in the format of the core
rules: the title line, then short, direct bullets, one instruction each, no `MUST` or `NEVER`, no generic intro, only
what the model would not do right without it. A rule for some files only opens with a `paths:` front matter (the
format of `rules/docs.md`), so it loads only when those files are touched; without it, it loads in every session.
No secret, credential or personal data (`rules/security.md`). Show the rule, then "After a change".

An own skill or agent is written by hand in `custom/my-rules/skills/<name>/SKILL.md` or
`custom/my-rules/agents/<name>.md`, in the format of the core ones; its front matter keeps only the keys
`rules-config.py` allows (no `hooks`, permission mode or tool grant), and the session sees it as `custom-<name>`.

## replace

`replace <rule>` (with `--as <file>` for another own file name): copies the core rule to `custom/my-rules/` as a
starting point, unless that file exists, and declares the `replace`. Apply what the human asked to change in the copy;
nothing asked: say the copy is ready to edit. Then "After a change".

## lessons

1. Run `lessons`: the candidates of `custom/docs/lessons.md`, the lines tagged `grave`, or recurring (tagged
   `recurring`, or written more than once), never the ones tagged `rare`. The tags are words in square brackets on
   the line: the weight (`[grave]`, `[attention]`, `[suggestion]`), the scope (`[general]`, `[project <name>]`) and
   the recurrence (`[recurring]`, `[rare]`); a line without a weight is not read. None: say so and stop.
2. Read the core rules and `custom/my-rules/` once, then show two tables:
   - **Already covered**: the candidates a core or own rule already covers, with the rule (and section) that does.
     No question.
   - **Decision**: the others, numbered: `#`, the lesson, the assessment (what the rule would change in later
     sessions, and whether a hook would hold it better), the status (`import` or `reject`) and why. Reject what is a
     one-off, what a rule cannot hold, and what would add text the model already follows.
3. Ask which rows to apply (default: the ones marked `import`), then stop for the answer.
4. Each approved row becomes an own rule, as in "add": covering only the kind of case that caused it, adjusting an
   existing own rule when one is on the subject. A lesson of `project <name>` gets a `paths:` front matter with
   `projects/<repo>/**` and `tmp/work/*/<repo>/**`. Then "After a change". The lines of `lessons.md` stay as they are.

## After a change

1. Run `bash scripts/setup-claude.sh` and show its `warning:` lines.
2. Commit in `custom/` by path only the files this command wrote (`rules-config.json`, the files of `my-rules/`), scope
   `rules` (`rules/git.md` "Commits"), and push `custom/`.
3. Say that this session keeps the rules it opened with: the change reaches the sessions opened from now on, and an
   open one only when it is closed and opened again.
