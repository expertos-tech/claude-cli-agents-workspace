# Functional request

**Project:** the repository folder name in `projects/` (for example `billing-api`), or the POC name. It names the session that runs the request: `<name>-<n>`.

This prompt is a development environment; our only concern is the security of the data.

Keep the headings and the bold labels of this template in English: the workspace reads them. Write everything else in your own language.

The request is as large as what you want. Use only the sections your request needs:

| Size | When | What to write |
| --- | --- | --- |
| Adjustment | changes a behavior of something that exists | a few lines: **What**, **Where**, **Done when**, **Effort**; none of the sections below |
| Feature | a new capability in a system that exists | sections 1, 3, 4, 7 and 11; the others only if you have something to say |
| System | a new system, architecture, new infra, a new external integration, a new flow of personal data | every section |

A section you did not use does not apply: it does not become a question. Claude asks only what keeps it from starting. In **Destination**, **Visual identity** and **Language**, empty means the default or Claude's decision (the folder of a new project in `projects/` is the human's decision, and without it Claude asks). The data you send for testing is used as sent; a secret, token or password never goes in here.

## 1. Objective

What the system must do and which problem it solves, in 2 to 5 lines.

## 2. Users

Who uses it (people, systems, roles) and what each one needs to do.

| User or system | What it does |
| --- | --- |
| | |

## 3. Business rules

One rule per line, numbered. Include exceptions, limits and what happens when the rule is not met.

- BR-1:
- BR-2:

## 4. Acceptance criteria

Verifiable: given a context, when something happens, then the expected result. Each criterion becomes at least one test: automated in a project; in a POC or a tool, a check made by Claude or by you, depending on the verification mode (`/pilot`).

- AC-1: Given ..., when ..., then ...
- AC-2:

## 5. Non-functional requirements (optional)

You do not need to size the infrastructure. Without a number from you, it starts at the smallest size that runs the delivery and ready to grow: scaling is changing a value, not rebuilding. Fill in only what is a real requirement.

| Item | Value |
| --- | --- |
| Volume, deadline or availability requirement, if any | |
| Monthly budget ceiling, if any | |
| Data retention (by type of data) | |
| Personal data: "open" (in full where the delivery shows it: screen, report, API response), "masked" or "Not applicable" (the delivery shows none) | |

## 6. Integrations

External systems, direction (inbound or outbound), format, frequency, who owns it and whether a test environment exists.

| System | Direction | Format and frequency | Test environment |
| --- | --- | --- | --- |
| | | | |

## 7. Out of scope

What must not be done in this delivery.

-

## 8. Destination (optional)

A new project (with its folder in `projects/`, at any level), an evolution of an existing project in `projects/` (which one), a POC to validate a hypothesis, or a local tool. If empty, Claude decides from the objective, except the folder of a new project, which it asks. Grouping one client's repositories in a folder is a recommendation, not a requirement.

## 9. Visual identity (optional)

Only for deliveries with a user interface. Empty: the default identity of the custom layer (`custom/rules/identity.md`); a product with an identity of its own there uses it. Another brand: give its colors, fonts and logo files.

## 10. Language (optional)

A programming language preference, if any, and the reason.

## 11. Steps and effort

The functional slices of the delivery, in order, each one usable or checkable on its own, with the effort it asks for. `low`: a mechanical change; `medium`: a clear scope, the default; `high`: where verification matters (security, personal data, money, permissions, migration, a destructive step, a bug in code that exists). You set the session's effort with `/effort` before each step.

| Step | Effort | Why |
| --- | --- | --- |
| | | |

The subagents of each step run with the step's effort, passed in the call.
