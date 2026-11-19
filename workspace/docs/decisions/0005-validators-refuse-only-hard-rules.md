# 0005 Validators refuse only hard rules; the rest is a warning

Status: accepted

## Context

Every validator of the workspace could stop the work: the gate refused any failing check of `validate.sh` (a lint
rule, a vulnerability, a coverage floor), `guard-bash` asked before `deploy`, `checkpoint`, `developer --create` and
`gate --untested`, the task's Docker copy refused any service with a privileged key, and the review classed a finding as
BLOCKER or RECOMMENDED, with the highest effort for code. The person saw a prompt or a refusal for things that were
theirs to decide, could not tell a real error from a preference, and paid for reviews that stopped nothing more than a
warning would. The agent works for the person, who knows their machine and their project better than a validator.

## Options

- **Keep every validator as a gate.** Predictable, but a refusal that is not a real error trains the person to
  approve without reading, which weakens the refusals that matter.
- **Turn the validators off.** Nothing blocks, but a secret or a destroyed database would pass as well.
- **Refuse only a hard rule, warn about the rest.** Chosen.

## Decision

- **A hard rule refuses.** It is a secret or an env file in the commits, a failing test command, a check that changes
  tracked files, the normalization and hotfix scope rules, a git write outside the gate, a database or Grafana's data
  deleted, and what the Docker copy's isolation needs (Docker 28 or later, no external network or volume, no bind
  outside the clone, no host networking, no `volumes_from` outside the compose files). `release`, `hotfix`,
  `hotfix-tag`, `hotfix-down`, `apply --apply` and `close --discard` keep asking.
- **Everything else is a warning** in one format, `WARNING: <what> — <why> — <what the person can do>`, gathered and
  shown once. The work goes on and the person decides.
  - The gate: only the `secrets` check of `validate.sh` refuses; every other failing check is a warning under
    "Warnings" of the audit file, which `/merge` shows in its warnings board (see the change history).
  - `guard-bash`: `deploy`, `checkpoint`, `developer --create` and `gate --untested` print a warning and the
    permission mode decides.
  - The Docker copy: a service with a key off the safe list (privileged, `cap_add`, devices, `sysctls`...) starts with
    a warning and gets no auto-allow of `exec`, which falls back to the permission mode.
  - The maintenance: a company term in what a work clone pushes is a warning; the push waits for
    `tests/caw-work.sh push <work> --accept-terms`, the owner's confirmation.
- **Reviews.** One per merge, effort `medium` into `developer` and `high` into `main`; no effort above `high`, and no independent
  review of a stage. A BLOCKER is only a hard rule, a correctness defect, a change outside the request's scope, a risk
  a mistake reaches or a proof the request requires now; every other finding is a WARNING. The brief carries what the
  person authorized, and that is never a finding.

## Reason

- A refusal means something only when it is rare: it keeps the hard rules visible.
- The person decides what is theirs: a deploy, a lint rule or a privileged container on their own machine.
- A warning costs one line in the summary; a refusal costs a round trip.

## Consequences

- A merge can enter `developer` with failing lint, vulnerability or coverage checks; the warnings are in the audit and
  the summary, and the person sees them before the merge.
- Where a mistake cannot be undone, the protection stays: the hard rules are code, and weakening one needs a plan with
  the owner's decision.
- A privileged service in a copy no longer gets `exec` approved by the hook; the person's permission mode judges it.
- Supersedes the effort by content and the review of a stage in 0004; it adjusts the asks of 0002 (`checkpoint`,
  `developer --create`).

## Change history

2026-11-18 — record created — validators refuse only hard rules — the owner
2026-11-18 — the one-line format stays the validators' output; the session shows each warning numbered, with its risk
(`HIGH`, `MEDIUM`, `LOW`) and a suggestion, in a warnings board before the closing board of a wave and before `/merge`
merges, and both wait for a decision on each (`rules/security.md` "Warnings", `rules/git.md` "Waves") — the owner
