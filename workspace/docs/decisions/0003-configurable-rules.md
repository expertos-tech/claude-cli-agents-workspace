# 0003 Configurable rules in the custom layer

Status: accepted

## Context

An installed workspace has a read-only core: a person could add rules in `custom/rules/`, but could not choose which
core rules, skills and agents a workspace loads, replace a core rule with one of their own, or add their own skills
and agents. Editing the core was the only way, and an update overwrites it.

## Options

- **Edit the installed core.** Lost at every update, and it breaks the read-only core (0001).
- **A fork of the product per company.** Every release becomes a merge; the custom layer already exists for this.
- **A configuration in the custom layer, applied when `.claude/` is generated.** The core stays as installed; the
  session setup builds the effective rules from it, the configuration and the own items.

## Decision

- `custom/rules-config.json` turns core rules, skills and agents off (`core.<kind>.exclude`) and replaces a core rule
  with an own one (`replace`). There is no language setting.
- `custom/my-rules/` holds the own rules (`*.md`; with `paths:` by path, without in every session), skills
  (`skills/<name>/`) and agents (`agents/<name>.md`). It replaces `custom/rules/`, which is read in its place, with a
  warning, until it is renamed. In `.claude/` every own item carries the `custom-` prefix (an agent's `name:` too), so
  none can shadow a core one; an own item with a core name is refused unless a `replace` declares it (rules only).
- The mandatory core is declared in `rules/manifest.json`: `AGENTS.md`, `rules.md`, `git.md`, `security.md`, the
  hooks, the `deny` rules, `/merge`, `/commit`, `/request`, the agents `reviewer` and `verifier` the gate depends on,
  `aiwp-cmds.sh`, `aiwp-gate.sh` and `setup-claude.sh`. The configuration can neither turn these off nor replace them:
  the core piece stays and the session start warns.
- `scripts/setup-claude.sh` applies the configuration through `scripts/rules-config.py` at every session start. A
  configuration that cannot be used never stops a session: what is wrong is ignored with a warning, the rest loads.
- A rule turned off leaves the instructions too: the effective `AGENTS.md` is generated as `.claude/AGENTS.md` (the
  original is read-only), without the rule's rows and references, and with a replaced rule pointing to its own file.
  The product's `CLAUDE.md` imports the generated one.
- A replacement takes the place of the core rule: copied to `.claude/rules/` when the core rule loads by path, else
  named by the effective `AGENTS.md` where the core rule was.
- The `/rules` skill shows the effective rules with the origin of each and changes the configuration; `custom/` stays
  free to edit by hand, and validation runs on either path.

## Reason

- The core stays one release for everyone, and what a workspace changes lives with its other private files.
- A manifest keeps the protections out of reach of a configuration file that a session can write.
- Generating `AGENTS.md` is the only way a turned-off rule also leaves the instructions, with the core read-only.

## Consequences

- A rule mentioned in another core file (a rule, a skill) is not rewritten there; the effective `AGENTS.md` says that
  a turned-off rule does not apply and that a replaced one is read in its own version wherever it is named.
- `AGENTS.md` names each rule that can be turned off only in a table row or a parenthesized reference, so the
  generation can remove it; `scripts/tests/test_rules_config.py` checks it against the real file.
- A workspace with `custom/rules/` renames it to `custom/my-rules/` (`git -C custom mv rules my-rules`).

## Change history
