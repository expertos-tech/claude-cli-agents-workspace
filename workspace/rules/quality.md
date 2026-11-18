---
paths:
  - "**/*.{go,py,ts,tsx,js,jsx,mjs,cjs,sh,bash,java,kt,cs,rs,rb,php,swift,sql}"
---

# quality.md

## Design

- MUST NOT duplicate logic. Second occurrence: extract and reuse.
- MUST separate domains: business rules NEVER depend on transport, persistence, UI or vendor SDK types.
- One responsibility per module, class and function. Name by responsibility, not by layer jargon.
- Integrate each external system through one owner module with explicit inputs, outputs, errors and deadlines.
- Introduce an interface/port only when a second implementation exists or is required now (including a test double that cannot be built otherwise).
- PREFER composition over inheritance.
- Configuration via environment or service settings; NEVER as constants in code. Fail fast on invalid config at startup.
- Use explicit time zone for "today" and deadlines; inject the clock.
- Changing a contract others consume (port, endpoint, network, path): MUST update every consumer in the same change, including those outside the repo, or not change it.
- Before recreating a running service: MUST compare its config file with what is running. Another session may have changed the file.

## Functional quality patterns (apply when the trigger exists)

- Decision, validation or scoring output: MUST be explainable (what was compared, outcome, reason).
- Replacing a behavior that writes to external systems: MUST support shadow mode (external writes disabled, results compared).
- Event, message, webhook or retried operation: MUST be idempotent.
- Every external call: MUST have an explicit timeout. Retry only transient failures (timeout, 5xx), with backoff, inside the overall deadline. NEVER retry business errors.
- AI output: MUST be structured and schema-validated; NEVER parse JSON from free text. Use AI only where deterministic code cannot solve it.
- Projects: changing a model, provider or prompt: MUST run evals on a reference set first: the data the human sent, or one the session builds (`rules/security.md` "Test and example data").
- Development and staging MUST call simulators or test environments, NEVER production.
- Moving data: MUST copy, compare files and a fixed-time baseline before and after, check the destination's retention, and keep the original until the user confirms deletion.
- Projects: a total shown to the user: MUST be reconciled with its raw source for the selected period and filter before delivery.

## Input validation

- MUST validate at every boundary: API, CLI, events, files, environment, AI output.
- Validate type, format, range, size and batch limits before use. Reject unknown fields where the format allows.
- NEVER build queries or commands by string concatenation with external values.

## Tests

- Mandatory floor, every change, deterministic and with no model in the loop: the `secrets` check, and format and integrity of the changed files (lint or parse per file type, through `scripts/validate.sh`; in a project, the gate of `/merge` runs it). `scripts/check-workspace.sh` is the gate of the product repository, a maintenance tool: in an installed workspace it checks nothing and says so.
- Strategy: the session chooses how to test the change: reuse a script or test that exists, or write a check for this change. Never a test out of proportion to the risk.
- Checking a skill (`rules/skills/`): run its possible scenarios and a few error scenarios by following its steps. A scenario that acts outside its own temp files (a remote, a merge, a deletion) stays a human test.
- Shared library: a new test or script joins `scripts/` or `scripts/tests/` only with a concrete second use; a check for one task stays in that task (`rules/scripts.md`). NEVER a second mechanism for what an existing one already does.
- Everywhere: a check a human could do by hand (manual run of the app or a script, browser, visual, manual end-to-end, exploratory, manual acceptance, a screenshot, a console log) follows the session's mode ("Verification mode").
- `tools/` and `custom/pocs/`: only the floor and what `rules/rules.md` "Workspace layout" requires. The rest of this section applies to projects, unless a line says otherwise.
- `scripts/` and `docker/`: scenarios only: the possible paths, a few error paths, one regression test per defect found. No coverage gate, except Python under `scripts/`, whose tests run through `scripts/.coveragerc`.
- Projects: unit tests mandatory for every module whose kind of code has a unit-test convention in its ecosystem (application and library code, yes; a skill, a prompt or a Markdown file, no). They favor the changed behavior and the relevant regressions.
- Test of a rule that reads shipped data (world, catalog, parameters): MUST include a case on the real data file. Test of a parser of a message from an external system (webhook, connector, queue): MUST include a case on a real captured message: the tests run on it as sent, outside the repo, and the versioned fixture keeps its structure, types and formats, nulls, empty lists and fixed protocol values, with every personal or identifying value replaced by an invented one of the same type and format; the raw capture never enters a repo, a log or a report and is deleted once the fixture is written and the tests ran on it (`rules/security.md` "Test and example data"). NEVER only invented fixtures, because they hide values and types the real data has: a hand-made DocuSign Connect fixture hid that `pages` is a list or null, and the generic-docusign agent rejected every real envelope.
- Coverage MUST be >= 85% lines AND >= 85% branches per module, generated code excluded, measured once, at the gate. In Go, a module is a `go.mod`. Measure with the language's standard coverage tool.
- Exception for Go and bash, whose standard tools do not measure branches: the automatic gate is 85% lines. In Go, `test-engineer` also lists every decision and error path with its test, and `reviewer` checks the list.
- Everywhere: during the work, run only the tests of what changed. After a failure: find the exact test and step, say whether it is code, environment, infrastructure or an unstable test, fix it, and run that test alone (`--only`, `pytest --lf`, `go test -run`, `vitest --changed`). The full run happens once, at the gate, and the check ledger reuses what still holds (`rules/scripts.md`); it runs again only when a fix invalidates earlier results or the state prevents a safe resume. NEVER run a whole suite after any change.
- Everywhere: a failure of environment, infrastructure or an unstable test is not a code defect: report its class and evidence, and NEVER change the code under test to get around it; an unstable test is fixed in the test itself.
- Everywhere: NEVER a test of a test, unless a concrete reliability reason of the test infrastructure is written in the delivery summary.
- Everywhere: extreme cases (concurrency, `kill -9`, many writers) run only when the request names them, after a real defect, or on a change to that module's lock code. They stay out of the default run.
- Script suite: at most 60 s. Full gate: at most 3 min. A changed gate script or shared library runs only the suites that depend on it (`scripts/check-workspace.sh` `suite_inputs`), NEVER every suite. `scripts/check-workspace.sh` prints the time of each check.
- Every acceptance criterion MUST have at least one automated test that proves it; when only the running system can show it: one check under "Verification mode". Reference the criterion id (`AC-n`) in the test name or doc comment.
- Each rule gets passing and failing cases.
- Tests MUST be deterministic and isolated: injected clock, seeded randomness, no shared mutable state, no network to real services.
- Choose test doubles (fake, stub, mock, contract test) per risk and dependency; record the strategy in `docs/` when non-obvious.
- Integration tests use controlled dependencies, isolated data and cleanup.
- Test data: the data the human sends, as sent; none sent: the session builds its own (`rules/security.md` "Test and example data").
- Tests that start containers or bind ports MUST isolate each run: unique project name, free ports, own network; cleanup removes only its own resources. NEVER a fixed shared name: simultaneous sessions destroy each other's run.
- A check that passes on empty results proves nothing: assert behavior with fixtures and confirm it fails when the bug is restored.
- Intermittent failure: MUST find the cause and keep its logs. NEVER rerun until green.

## Test seed

- A project with a database SHOULD, strongly recommended, have a test seed: one command that rebuilds the database from nothing with invented data (`rules/security.md` "Test and example data"), named in the README "How to test". Each task's Docker copy (`aiwp-cmds.sh up <work>/<clone>`) then starts with its database rebuilt, and its volumes can be thrown away freely. `/normalize-projects` reports a project without one as a gap.

## Verification mode

Who runs a check a human could do by hand (running the app, a browser, a screenshot): the agent (`auto`) or the human (`manual`). `/pilot` sets it for the session.

- Every session starts in `auto`. A skill or rule that routes a test to the human by name (e.g. `/normalize-projects`, which tests the branch with the human) wins over `auto`.
- Both modes: the agent runs unit tests, coverage, lint, format, `secrets` and `scripts/validate.sh`. Never hand them to the human.
- `auto`: the agent runs every check the delivery needs, visual ones included, with the browser tool the session has, and asks the human nothing. Before the first visual check, open the app's local address and confirm the page loads.
- `auto`, exception: what the agent must not or cannot do alone goes to the human as a `manual` item, with the reason: a login with a real credential, a physical device, a remote, a deletion, a tool that is not available.
- `auto`, a failing check: at most 2 fix attempts. After them, stop and tell the human the failure and the options.
- `manual`: once the automatic checks pass, give the human a numbered list, one item per change: what changed, where to see it, short steps with the command ready to copy, the expected result and what to send back. Then wait.
- `manual`, a return that asks for a change: change only what it asks. The delivery closes when every item is ok, when the human asks to finish (switch to `auto` for the rest), or when the human waives an item (list it as not verified).
- The delivery summary names the mode and, per check, who ran it and the result.
- The checks of a delivery run on the task's Docker copy (`bash scripts/aiwp-cmds.sh up <work>/<clone>`, its own group and ports), never on the final stack; the closing board gives its addresses and one test item per acceptance criterion (`rules/git.md` "Waves").

## Readability

- Short functions, low nesting, low cognitive complexity. Extract a named function instead of adding a comment.
- One way to do the same thing inside a project; follow the existing pattern before introducing a new one.
- Linter and formatter configured per project, run in CI and locally; zero errors to finish.
