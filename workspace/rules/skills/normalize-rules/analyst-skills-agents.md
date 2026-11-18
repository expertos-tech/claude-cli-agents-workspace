# Analyst: skills and agents

Brief of one of the four analysts of `/normalize-rules`; read `analyst-common.md` first.

## Question

Which commands, skills and subagents does the older workspace define, and what does each one really do? Read the
whole of each (its steps, the scripts it calls, the files it writes), not its description. For each, compare with the
current `rules/skills/`, `rules/agents/` and `custom/my-rules/`.

- A skill or agent the core has under another name, or that the current flow makes unneeded: `already in the core`
  or `not worth keeping`, naming the core piece.
- A skill whose value is a fragment (one step, one check): the fragment is the candidate, as an own rule, or as an
  adapted text for the core skill that would hold it (`needs core support`, since a core skill is not replaced).
- An own skill or agent kept: its front matter only with the keys an own item may have (no `hooks`, permission mode
  or tool grant), a model of `rules/models.md`, never Fable; one that needs a hook or a grant is
  `needs core support`.
