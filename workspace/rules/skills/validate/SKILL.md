---
name: validate
description: "Run the Docker validation checks (scripts/validate.sh) on a folder and, with --sonar, the SonarQube quality gate. Use when the user asks to validate, or to verify the Definition of Done."
argument-hint: "[dir] [--only <checks>] [--sonar]"
model: claude-opus-5-5
effort: medium
---

Arguments: `$ARGUMENTS`. Folder relative to the root. Default: the clone of the request (`tmp/work/<work>/<clone>`), relative to the root, because `sonar.sh` refuses an absolute one; with no clone, `.`. Other flags go to `scripts/validate.sh`.

1. From the root checkout: `bash scripts/validate.sh --path <dir> [--only|--skip ...]`. Docker unavailable: say so and list the checks that did not run.
2. `--sonar` (only when the user wrote it; it starts containers): `bash scripts/sonar.sh status`; down → `bash scripts/sonar.sh up`; then `bash scripts/sonar.sh scan --key <the repo's folder name in lowercase kebab-case, never a clone's> --path <dir>`.
3. Fix nothing. Reply in the language of the conversation: PASS/FAIL and time per check, the failing lines, skipped checks.

A long run may go through the `verifier` (`rules/models.md` "When to delegate"), which returns only the result lines.
