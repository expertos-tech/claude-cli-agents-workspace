# Analyst: automation and protection

Brief of one of the four analysts of `/normalize-rules`; read `analyst-common.md` first.

## Question

Which hooks, permissions, deny and allow rules, git hooks and scripts shape what the agent may do, and which
behaviour does each enforce? Read the configuration that wires them (settings files, hook registrations, git hooks)
and the code of each, never by running it. For each, compare with the current `rules/agents/settings.json`, the hooks
and scripts of `scripts/` and `rules/manifest.json`.

- What the current hooks, `deny` rules, `guard-bash`, the gate or a script already enforce: `already in the core`,
  naming it.
- A behaviour that only a hook, a permission or a script can enforce: `needs core support`, with one line on what the
  core change would be. Never propose a rule that asks the model to emulate it.
- A protection that slows every command or prompt, or locks sessions against each other: `not worth keeping`, unless
  the core lacks what it protects; then `needs core support`.
- A script's knowledge that is not code (a limit, a host, a convention): the knowledge may be an own rule.
