# Analyst: company layer

Brief of one of the four analysts of `/normalize-rules`; read `analyst-common.md` first.

## Question

What in the older workspace is specific to the person or the company: names, cloud accounts and tenants, identity
and visual identity, remotes and hosts, internal tools, customers, machines and their paths? Company content is
welcome as an own rule: `custom/` is private. Compare with the current `custom/` (`custom/my-rules/`, the
`custom/projects.md` index, the own tools) so nothing is proposed twice.

- Knowledge a session needs to work for that company (where things are deployed, which cloud and tenant, the team's
  conventions): an own rule, scoped by `paths:` when it only matters for some files.
- A value tied to one machine (an absolute path, a user name): adapt it to this workspace or leave it out, saying so.
- Tools of the company or a customer kept in the older workspace (simulators, consoles, scripts): the knowledge may be
  an own rule; the code is a codebase ("Codebases"), never copied by this skill.
- Every secret or secret-shaped value (token, key, password, connection string): a separate table, `#`, `path:line`,
  type, still used; the candidate that needs it gets a placeholder and says where the person sets the value (an
  environment variable, `custom/env/<tool>.env`, the person's secret store), never in a rule.
