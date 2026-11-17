---
name: caw-check
description: "Run the repository suite (tests/check.sh) with the right flags for the change and explain each failure: what failed, where, and the likely fix. Use after every change and before a commit."
argument-hint: "[--base <ref>] [--floor] [extra check.sh options]"
model: claude-opus-5-5
effort: medium
---

Arguments: `$ARGUMENTS`, passed to `tests/check.sh` after the defaults below.

1. Pick the flags:
   - `--base <ref>`: the base of the change. Default: `origin/developer`, so only what changed is judged and only the
     suites it touches run;
   - `--i18n-pending`: translations wait for the release and are reported as `pending:` lines;
   - `--all` (every suite, whatever changed) and no `--i18n-pending` only for the release (`--base <last tag>`) or
     when the owner asks;
   - anything the owner gave in the arguments (`bash tests/check.sh --help` lists them).
2. Run `bash tests/check.sh <flags>` from the repository root, in the background when it may pass 3 minutes. A long
   noisy run may go through the `verifier` agent (model claude-haiku-5-5, effort low) with the exact command.
3. Report the `PASS`, `CACHED`, `SKIP` and `FAIL` lines. For each `FAIL`: the file and line, the cause in one sentence,
   and the fix. A `CACHED` line is a result: never rerun to confirm it.
4. Typical fixes:
   - `validate` python format: run ruff format through the product container with `workspace/docker/config/ruff.toml`;
   - `validate` markdown: fix the rule markdownlint names, with `workspace/.markdownlint-cli2.jsonc`;
   - `i18n` outdated or missing in a strict run: translate the change, then set the source line hash
     (`.claude/rules/docs.md`); between releases, run with `--i18n-pending` instead;
   - `repo-terms` or `custom-terms`: reword without the company term; never print the term in the report.
5. Never weaken a check, skip it or add an exemption to make it pass. A fix goes back through `/caw-check`.

The suite does not lint Markdown outside `workspace/` (the root, `.claude/`, `maintainers/`): when those changed, also run
markdownlint-cli2 from the pinned image of `workspace/docker/compose.yaml` with `workspace/.markdownlint-cli2.jsonc`.
