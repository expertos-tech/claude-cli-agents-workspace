# Functional request: Parent session name in the labels of Workflow agents

**Project:** claude-cli-agents-workspace

**State:** idea. Size: adjustment. Created 2026-11-16 as a backlog item (improvement, priority low, target workspace); source: Subagent naming in the product rules.

## What

The agents a `Workflow` script creates do not go through the `PreToolUse` hooks on `Agent`, so no hook checks that
their label starts with the name of the parent session. A workflow runs only when the person asks for one, and a wrong
label breaks nothing, but the sessions list loses the link between the agent and the session that started it.

## Done when

An agent created by a `Workflow` also carries the parent session name in its label.

## Acceptance criteria

- AC-1: Given a workflow the person asked for, when it creates agents, then the label of each one starts with the
  session name.

## Out of scope

- Changing the model hook `guard-subagent-model.sh`.

## Notes

Check whether `Workflow` now fires `PreToolUse` on `Agent`, or whether the label can be required in the workflow
authoring rule.

## Effort

low
