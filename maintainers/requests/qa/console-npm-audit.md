# Functional request: the container consoles fail their check on a high npm vulnerability

**Project:** claude-cli-agents-workspace

**State:** ready. Size: adjustment. Source: found while running `accordion-motion` (2026-11-18).

## What

`make check` of both container consoles passes while `npm audit --audit-level=high` reports 4 high vulnerabilities
(picomatch, through `fdir`, `tinyglobby` and `vite`, build-time only): the Makefile runs the audit and the type check
in one `if` block joined by `;`, so only the last command's exit code counts. The check must fail on a high finding,
and the dependencies must be brought to versions with none, keeping vite on its current major (8): `npm audit fix
--force` proposes vite 6.2.7, a downgrade, which is not acceptable (assumed decision).

## Where

`workspace/tools/container-console-docker-ce/` and `workspace/tools/container-console-colima/`: `Makefile` ("check")
and `web/package.json` with `web/package-lock.json`.

## Done when

In both tools, `make check` exits non-zero when `npm audit --audit-level=high` fails (shown once with the current
lockfile), then passes with the updated dependencies; `make build` still builds and the screen still loads.

## Effort

medium

## Assumed decisions

- Open: how to clear picomatch. Decided: newer versions or an npm `overrides` entry, on vite 8; never a downgrade.
  Reason: the fix npm proposes goes back two majors of the build tool.
- Open: the other tools with a lockfile (`azurite-console`). Decided: out of this request; its Makefile runs no audit.
  Reason: the finding is about the consoles' check.

## Where it stopped (2026-11-18)

- Done on `fix/console-npm-audit` (clone `tmp/work/2026-11-18-console-npm-audit/`), commit `b3510f1`: in both
  Makefiles the audit and the type check are joined by `&&`. With the current lockfile `make check` now exits 2 in
  both tools on the 4 high findings; `make build` still builds both.
- Not done, by the owner's decision: the dependency update. No version clears the finding: the advisory
  (GHSA-fc5q-39xc-vjpf) covers `picomatch <=4.0.7`, 4.0.7 is the latest release with no patched version, and every
  vite 8 (8.3.8, 8.4.0-beta.1) requires `picomatch ^4.0.7`, so neither an update nor an `overrides` entry helps.
  GitHub withdrew the advisory on 2026-11-18 at 15:38 UTC; at 16:49 UTC npm audit still reported it.
- Next: rerun `npm --prefix web audit --audit-level=high` in both tools. Once npm drops the withdrawn advisory,
  `make check` passes with the lockfiles unchanged: prove it there (the "then passes" part of "Done when") and
  `/caw-merge`. If npm still reports it after a few days, the owner decides again (an update that clears it, or
  filtering this one advisory, which weakens the check and needs a review).

## Execution — 2026-11-18, merged into developer

- **Done:** in the `check` target of both consoles' `Makefile`, `npm audit --audit-level=high` and the type check are
  joined by `&&`, so a high finding fails `make check` (b3510f1). Changelogs: a Fixed entry in
  `workspace/CHANGELOG.md` (the audit line was already in v0.1.0) and a Product line in the root one.
- **Decisions:** the owner chose to change only the Makefiles and leave the lockfiles, after the finding proved to
  have no fix (see "Where it stopped"). `&&` stops before the type check when the audit fails; the check fails either
  way.
- **Deviations:** no dependency was updated. The second half of "Done when" ("then passes with the updated
  dependencies") is met with the lockfiles unchanged: npm stopped reporting the withdrawn advisory
  (GHSA-fc5q-39xc-vjpf) between 16:49 and 19:31 UTC.
- **Done when:** met. With the lockfile of the time, `make check` exited 2 in both tools on the 4 high findings
  (16:4x UTC); at 19:31 UTC `npm audit` reported 0 vulnerabilities and `make check` exited 0 in both tools.
  `make build` built both tools and changed no tracked file. The screen was not loaded: the front-end did not change.
- **Checks:** `bash tests/check.sh --base origin/developer --i18n-pending` passed (translations pending, as before;
  repo-terms skipped: no terms list).
- **Left:** the `web` target joins `npm ci`, the cleanup and the build with `;` too, so a failed `npm ci` does not stop
  it; not in this request.
