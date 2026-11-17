# Functional request: the gate audit lists coverage drops, destroyed infrastructure and removed routes or config

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**Where it runs:** at the repository root, where the project is maintained, with the product in `workspace/`
(`scripts/aiwp-gate.sh` and its suite, `rules/skills/merge/SKILL.md`, `rules/git.md` "Gate", `docs/usage.md`). It
depends on no other request; it fits **round 1** of `maintainers/requests/README.md`, beside `rules` and `run-tools`
(neither touches the gate). The `final-review` request (round 3) then reviews it with the rest.

## 1. Objective

The owner asked for "a heavier test only for the merge, that analyses what there was and what is coming in, based on
the requirements of what was done": the gate is the one place where destructive changes are caught, and the questions
to the human concentrate there. The approved gate design (step 3, "audit of what leaves") listed: deleted files;
removed or disabled tests; a migration that drops a column or table; **a removed route, contract or configuration**;
a changed dependency; **a coverage drop against the base**; **Terraform that destroys a resource (`plan`)**. The gate
in 0.1.0 (`write_audit` in `aiwp-gate.sh`) has the others, but the three in bold are missing or partial: infrastructure
is only a list of file names, configuration only the sample env and appsettings lines, and there is no coverage
comparison. This request adds them to the audit report, which the clean reviewer of `/merge` already judges against
the request.

## 3. Business rules

- BR-1: the audit stays a report: it never fails the gate by itself. Each new section lists findings for the reviewer
  of `/merge` step 3, who classifies them as requested, a consequence of the request, or unexplained; only unexplained
  findings reach the human, as today.
- BR-2: **Removed routes and contracts:** lines removed from route declarations, OpenAPI/AsyncAPI/proto/GraphQL schema
  files and public API surface files, found by what they do (a route registration, a schema path or message), never by
  a fixed list of project names. A rename that keeps the route is not a removal.
- BR-3: **Removed configuration:** keys removed from configuration files the project ships (not only samples): env
  examples, `appsettings*.json`, `application*.yml|properties`, Helm values, compose environment entries. Values are
  never printed, only the key and the file.
- BR-4: **Coverage drop:** when the project's test run already produces a coverage report (the suite of gate step 2),
  compare the total line coverage of the branch with the base and list a drop above a threshold (decision 1). When the
  project produces no coverage, the section says "not measured" and nothing else; the gate never adds a coverage tool
  to a project.
- BR-5: **Destroyed infrastructure:** when the diff touches Terraform/OpenTofu files, the audit lists the resources
  removed in the code (resource and module blocks that disappear or change `count`/`for_each` to fewer). Running
  `terraform plan` in the gate is decision 2.
- BR-6: nothing in the audit reads a `.env` or a secret value; the audit runs in the same place as today.
- BR-7: the suite of `aiwp-gate.sh` gets a fixture per new section (found, not found, not measured); the docs of the
  gate and their translations say what the audit lists.

## 4. Acceptance criteria

- AC-1: Given a branch that removes an HTTP route registration, when the gate runs, then the audit lists it under
  "Removed routes and contracts" with the file and line.
- AC-2: Given a branch that removes a key from `appsettings.json`, then the audit lists the key and file, never the
  value.
- AC-3: Given a project whose suite writes a coverage report and a branch that lowers coverage above the threshold,
  then the audit lists base and branch coverage; given a project without coverage, then the section says "not
  measured" and the gate result is unchanged.
- AC-4: Given a branch that deletes a Terraform resource block, then the audit lists the resource address.
- AC-5: Given any of these findings explained by the request, then `/merge` does not ask the human about it.
- AC-6: `bash tests/check.sh --all` passes with the new fixtures.

## 7. Out of scope

- Making any audit section block the gate.
- Installing coverage tools in projects.
- `terraform apply` (still only by `aiwp-gate.sh apply`, from `main`, confirmed).

## Decisions for the owner

1. **Coverage threshold.** Recommended: list a drop of more than 1 percentage point of total line coverage; any drop
   in a file the branch touched is listed only when that file lost more than 5 points.
2. **`terraform plan` in the gate.** It needs cloud credentials and reaches the cloud read-only. Options: never (only
   the code reading of BR-5, recommended), or run `plan` when the clone has credentials configured, with the plan's
   destroy count in the report.
3. **Contract files.** Should a removed field inside a schema (not only a whole path or message) count? Recommended:
   yes for OpenAPI paths and proto/GraphQL fields, since a removed field breaks a client.

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Routes, contracts and configuration sections, with fixtures | high | The gate is the main guard against destructive changes |
| 2. Coverage comparison and Terraform resources, with fixtures | high | Reads test and infra output; must never block wrongly |
| 3. `/merge` skill text, gate docs and translations | low | Text only |

The agents of each stage run with the stage's effort, passed in the call.
