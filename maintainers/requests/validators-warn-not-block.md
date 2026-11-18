# Functional request: validators block only real errors; the rest is a warning and the person decides

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**State:** ready. **Where it runs:** at the repository root, where the project is maintained, with the product in
`workspace/`. It changes the product (reviews, hooks, the gate) and the maintenance (`.claude/rules/`, `/caw-merge`,
`tests/`). Source: the owner, after `autonomous-work` (2026-11-18), where reviews and hooks kept returning BLOCKERs
for things the owner had asked for or authorized, and the work went in circles on cases the owner did not know were
blocking.

## 1. Objective

The validators (the hooks, the gate, the reviews of a merge and of a stage, the scripts' checks) stop an error that
really happens: something nobody asked for, a hallucination, a change outside the request's scope, and a few real
security risks. Everything else is a warning: "this looks like a problem", and the person who asked decides. What
the person asked for or authorized is never blocked again. A review never turns a decision of the person into a
BLOCKER, and the work never loops on hypothetical attacks. The same rules in the product and in the maintenance of
this repository.

## 3. Business rules

- BR-1: what the person asks for, in the request or in the conversation, is the decision; a validator may warn about
  it once ("public repository with company terms: confirm?"), never refuse it and never reopen it later.
- BR-2: a hard refusal (deny, or a BLOCKER that stops a merge) only for the mandatory rules, a closed list in one
  place of the product and mirrored in the maintenance (assumed list, the owner adjusts it in the run):
  - a secret in clear (key, token, password, private key, `.env` with values) committed or pushed;
  - deleting a remote repository, or rewriting or deleting published history (`push --force` to a shared branch,
    deleting `developer`, `main` or a tag on the remote);
  - a git write in `projects/` or in the read-only core outside the gate; Terraform changing the cloud outside
    `apply`;
  - the merge into a base without the person's order (`/merge` typed, the push of `developer` by `/caw-merge`);
  - deleting a database or Grafana's data without the person's confirmation;
  - a change that does something nobody asked for and that cannot be undone (data deleted, a remote changed).
  Each item of the list says why it is a hard rule.
- BR-3: everything else a validator finds is a WARNING with a suggestion: best practices, a hardening idea, a public
  IP in an `.env`, a company term in a public repository, an attack that needs someone writing code to escape the
  checks on purpose. The person decides; the work goes on.
- BR-4: a review classifies each finding as BLOCKER only when it breaks a rule of BR-2, is a correctness defect of
  what was asked (it does not do what the request says, or breaks something that worked), is a change outside the
  scope of the request, or is a real security risk reachable by a mistake (not only by a deliberate escape). An
  acceptance criterion not proven is a BLOCKER only when the request requires the proof in this delivery. Everything
  else is a WARNING.
- BR-5: a finding about a permission, an access or a behavior the person authorized (in the request, its plan, or the
  conversation) is not a finding. The review brief carries those authorizations, and the reviewer checks against
  them before reporting.
- BR-6: the developer owns the machine: a destructive program, a security test, a tool that does what the person
  asked is not policed. The validators protect against mistakes, not against the person.
- BR-7: what would interrupt the work over and over during an implementation (a question per command, a refusal per
  spelling, a review round per fix) is not done during the implementation: it is gathered and shown once, at the
  merge into `developer` (the review's summary) or when the request is written (`/draft-request`, `/caw-draft-request`),
  as warnings for the person to decide.
- BR-8: the return review after fixes keeps the rule the owner set: focused on the findings with effort `high`, light
  on the whole range with effort `medium`, and it reports only regressions the fixes caused and findings still open;
  a third round with a BLOCKER open stops and asks the person.
- BR-9: a mandatory rule that only makes validation slower (a check that must run, a review that must happen) is not
  an error: it is never reported as a BLOCKER of the delivery.
- BR-10: the review of a change to an existing script (an installer, a hook) covers only the difference, not the whole
  script again.
- BR-12: the effort of the merge review goes by the base, not by content: a merge into `developer` effort `medium`, a
  merge into `main` (release, hotfix) effort `high`. It replaces the split by content of `autonomous-work` (BR-15:
  `xhigh` for code and configuration, `high` for documents), and `xhigh` leaves the rules. The return review after
  fixes (BR-8) keeps its focused part at `high` and its light part at `medium`.
- BR-13: a review already run during the request counts at the merge. The independent reviews of stages (and their
  return reviews) are recorded with the commits they covered and their verdict (in the request's resume point or the
  merge's Execution block); the merge review then reads only the commits no review saw, plus the three questions on
  the whole request in one light pass (effort `medium` into `developer`, BR-12), and never repeats a finding the
  person already decided (an accepted risk, an authorization). Only a real BLOCKER returns the branch; the rest goes
  to the merge summary as warnings.
- BR-11: the warnings have one format in the product and in the maintenance, short, each with what was seen, why it
  may be a problem, and what the person can do; the closing board and the merge summary list them under
  "Warnings".

## 4. Acceptance criteria

- AC-1: Given a request that asks for something a hook or review would have refused before (e.g. an allow rule for
  the agent, a push of a public repository with a company term after the warning), when it runs, then the work does
  it after at most one warning, and no review reports it as a BLOCKER.
- AC-2: Given each item of BR-2, then a test proves the hard refusal still happens (hooks) or the review reports it
  as BLOCKER (a fixture diff for each).
- AC-3: Given a finding of a best practice, a hardening idea or a deliberate-escape scenario, then the review reports
  it as WARNING and the merge goes on.
- AC-4: Given a review brief, then it carries the authorizations of the request, its plan and the conversation, and a
  finding against an authorization is not reported.
- AC-5: Given a merge into `developer`, then its summary lists every warning of the delivery once, for the person to
  decide; the implementation itself did not stop for any of them.
- AC-6: Given the change of an existing installer or hook, then its review covers only the difference.
- AC-8: Given a merge into `developer`, then its review runs with effort `medium`; given a merge into `main` (release or
  hotfix), with effort `high`; no rule or skill of the product or the maintenance names `xhigh`.
- AC-9: Given a request whose stages were reviewed during the work, when it merges into `developer`, then the merge
  review covers only the commits no review saw plus the three questions in one pass, and repeats no decided finding.
- AC-7: Given `tests/check.sh --all`, then the hooks' suites prove BR-2 refusals still hold, and the texts of
  `rules/review.md`, `.claude/rules/review.md`, `/merge`, `/caw-merge`, the `reviewer` agents and `AGENTS.md` /
  `CLAUDE.md` say the same rules.

## 7. Out of scope

- Removing the protections of BR-2, or the merge only by the person.
- Changing what `autonomous-work` delivered beyond reclassifying its refusals and findings into BR-2 or warnings.

## 11. Steps and effort

| Step | Effort | Why |
| --- | --- | --- |
| 1. The rule: BR-2's closed list, the BLOCKER/WARNING criteria, the authorizations in the brief, the warning format, the review effort by base (BR-12; also `rules/models.md`, `.claude/rules/models.md`, `/merge`, `/caw-merge`) (product `rules/review.md`, `rules/security.md`, `AGENTS.md`; maintenance `.claude/rules/review.md`, `security.md`, `CLAUDE.md`; the `reviewer` agents) | high | It decides what stops a delivery |
| 2. The hooks and scripts: each deny or ask of `guard-bash`, the gate, `caw-work.sh` and the copy's checks classified as BR-2 (kept) or warning (an ask becomes a printed warning, or nothing), with tests | high | Hooks of the mandatory core |
| 3. The merge skills and `/draft-request`: warnings gathered once at the merge summary and at the writing of the request (BR-7, BR-11) | medium | Rules and skills with a clear scope |
| 4. Docs and the decision record that changes (0004, or a new one) | medium | Documentation |

## Assumed decisions

- Open: the exact list of BR-2. Decided: the list above. Reason: the owner named secrets, deleting repositories and
  force pushes on the remote "and so on"; the rest are the protections `autonomous-work` kept on purpose.
- Open: a company term in a public repository. Decided: a warning with confirmation, never a refusal. Reason: the
  owner's words.
- Open: an ask of `guard-bash` that is not in BR-2 (for example `docker volume rm` of another group). Decided: it
  becomes a warning in the output, not a question, unless the owner keeps it in BR-2 in the run.
