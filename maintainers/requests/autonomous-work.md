# Functional request: autonomous work in the work branch, a Docker copy per task, the merge only by the person

**Project:** claude-cli-agents-workspace

This is a development environment; the only concern is data security.

**State:** ready. **Where it runs:** at the repository root, where the project is maintained, with the product in
`workspace/`. Design: `maintainers/plans/autonomous-work.md` (decisions D-1 to D-6 answered). It runs before round 2 of
`maintainers/requests/README.md`. It changes the mandatory core (`guard-bash`, `/merge`, `aiwp-cmds.sh`,
`session-title`): the plan is the owner's decision (`.claude/rules/product.md`).

## 1. Objective

In its branch (a clone in `tmp/work/`) the agent works with no prompt to the person: edits, commands, commits, the push
of its own branch and a Docker copy of what it needs. When it finishes it publishes that copy and asks the person to
validate it; the person then orders the merge, which never happens on its own. Leaving the trail falls back to the
active permission mode. A prompt shows only the command it approves. The same behavior in the product and in the
maintenance of this repository.

## 3. Business rules

- BR-1: in the product, `guard-bash` approves a Bash line, with no prompt, when it can tell that every command of it
  runs in one clone of `tmp/work/`, every path it names (arguments and redirections) stays in that clone, and no
  command acts on a remote system (a push, a publish, a deploy, a cloud CLI, `ssh`, `docker push`). Downloading
  dependencies is not acting on a remote system (assumed decision). Anything it cannot tell: silent, the normal flow
  decides. Its current refusals and questions keep their precedence over the approval.
- BR-2: the product settings allow `Edit(/tmp/work/**)` and the border commands of `aiwp-cmds.sh`: `open`, `status`,
  `push`, `up`, `down`, `close` without `--discard`. The maintenance settings allow `Edit(/tmp/work/**)` and
  `bash tests/caw-work.sh`.
- BR-3: `tests/caw-work.sh` (maintenance) has `open <type>/<slug>` (the clone in
  `tmp/work/<yyyy-mm-dd>-<slug>/claude-cli-agents-workspace`, its branch from `origin/developer`, pushed), `run <work>
  -- <command>` (refuses an argument with a path outside the clone: `..` that leaves it, an absolute path elsewhere),
  `status`, `publish <work>` and `close <work> [--discard]` (refuses, without `--discard`, a clone with work not
  pushed or not in `developer`). It writes only in `tmp/work/` and refuses `developer`, `main` and tags.
- BR-4: a maintenance clone gets git hooks that push its branch after each commit, amend, rebase or merge, only after
  the company-terms scan of the files that leave passes (the scan of `tests/check.sh`); they refuse a push of
  `developer`, `main`, a tag or a force push. `/caw-request` and `/caw-merge` stop pushing the work branch by hand.
- BR-5: the root keeps `ask: Bash(git push *)`; with BR-3 and BR-4 the only prompt left in a maintenance task is the
  push of `developer` by `/caw-merge` (D-1).
- BR-6: what needs authorization runs alone, in its own call, after everything allowed ran, with one line before it
  saying what it asks. In the product, `guard-bash` refuses with "run it alone" a line it would ask about that holds
  other commands. Written in the product's `AGENTS.md` and in the root `CLAUDE.md`.
- BR-7: `aiwp-cmds.sh up <work>/<clone>` publishes the task's copy in its own compose project,
  `agent_<MMDD>-<slug>` (the date and slug of the work folder; a second clone of the same work that publishes adds
  `-<clone>`), with its own images, networks and volumes, never replacing a tag the final stack uses. Its host ports
  are random free ports in 61000-65535 (assumed decision: above the Linux ephemeral range 32768-60999, which the product
  forbids; on macOS only checked free), set in an override file of the copy; the project's compose files do not
  change. The chosen ports are printed and reach the stack as variables. `aiwp-cmds.sh down <work>/<clone>` stops it.
- BR-8: anything in the task's own group is approved with no prompt, volumes and data included. The questions of
  `guard-bash` about deleting a database stay for every other group and for SQL clients run on the host (assumed
  decision: they may reach a remote database).
- BR-9: deleting, moving or emptying `tools/observability/.data` (Grafana's data) asks, whatever runs it (D-5).
- BR-10: a group is destroyed (containers, networks, volumes, images) only by its compose label and only when its
  name matches `^agent_[0-9]{4}-[a-z0-9][a-z0-9-]*$`: by `/merge` into `developer` once phase 2 passed, by
  `close --discard`, and in the maintenance by `caw-work.sh close`. `aiwp-cmds.sh status` lists the groups of each
  clone, with their ports.
- BR-11: the end of a task: the tests of what changed pass, the agent publishes its copy (a project with no compose
  stack: nothing to publish), and the closing board gains the addresses of the copy, what to test (one item per
  acceptance criterion) and the two ways out, `/merge` when approved, `close --discard` when not. `rules/git.md`
  "Waves" no longer sends a part through the gate on its own.
- BR-12: in the maintenance, `caw-work.sh publish` publishes by what changed: a tool of `workspace/tools/` as a copy
  in its own `agent_` group (from the clone, with the tools' configuration read from the installed workspace), the
  installer, a hook, a script or a rule as a test installation, documentation alone nothing.
- BR-13: the merge happens only when the person orders it. Product: `/merge` gets `disable-model-invocation: true`;
  the `UserPromptSubmit` hook records each `/merge` the person types (under `.history/`), and `aiwp-gate.sh` refuses
  `gate --merge` with no record from the same session since phase 1 (D-2). Maintenance: `/caw-merge` already cannot
  be invoked by the model, and the push of `developer` asks (BR-5).
- BR-14: `/pilot` keeps deciding who runs the detailed check of the copy; `/caw-pilot` is its layer here (the three
  sections of a `caw-` layer), with the maintenance's checks (the suite, the test installation, a tool copy).
- BR-15: the merge review asks only three questions: what was asked against what was done; what went beyond the
  request; what existed and was lost. Into `developer`: only the difference that enters. Into `main` (release and
  hotfix, assumed decision for the hotfix): since the last tag, widened to what the reviewer judges necessary. Effort
  by content: code and configuration (rules, skills, agents, `AGENTS.md`, `CLAUDE.md`, settings, scripts, hooks)
  `xhigh`, documents `high`; a mixed merge runs both reviews in parallel, each on its part. The release's "general"
  round is dropped (assumed decision). The product's rules allow `xhigh` for this review only.
- BR-16: `/docker-deploy [developer|main]` (product, `disable-model-invocation: true`) updates the final stack of a
  project from that branch (`main` from a temporary checkout) through a new `aiwp-cmds.sh deploy` that `guard-bash`
  asks about, tags the replaced images for `rollback`, and never deletes a volume. `aiwp-cmds.sh up <repo>` (from
  `projects/`) gives way to it. `/caw-docker-deploy [developer|main]` is its layer here, on the tools group
  (`claude-cli-agents-tools`) through `run-tools.sh`.
- BR-17: the project contract strongly recommends a test seed to a project with a database, so a copy starts with its
  database rebuilt (`rules/quality.md`, the normalization analysis of `/normalize-projects`).
- BR-18: a decision record of the product (`0004`) records the trail, the Docker copy and the merge only by the
  person. The docs and READMEs that describe permissions, `up`, `/merge` and the reviews say the new behavior. The
  pending requests `work-branch-push-before-scan`, `review-docs-only-scope`, `review-effort-wording` and
  `work-status-docker-stacks` are delivered by this one and leave `maintainers/requests/`; `os-sandbox-trial` is
  removed (D-4).
- BR-19: `/caw-commit` stages before it commits by path: `git add -- <paths>`, then `git commit -F <file> -- <paths>`.
  Today its text gives only the commit form, which fails for a file git does not track yet; the product's `/commit`
  already stages first. And the rule that keeps the second failure from coming back, in "Commits" of
  `.claude/rules/git.md` and of the product's `rules/git.md`: the paths of a command are written out in it, never held
  in a shell variable, because the session's shell may be zsh, which passes an unquoted variable as one word.

## 4. Acceptance criteria

- AC-1: Given a session in a clone of `tmp/work/` (product, a test installation, default permission mode), when the
  agent edits files, runs the project's tests, commits and its branch is pushed, then the person gets no prompt.
- AC-2: Given the same session, when a line runs a command whose path leaves the clone (`rm -rf ../../projects/x`,
  `cp f /etc/x`) or acts on a remote system, then `guard-bash` does not approve it and the normal flow decides; a
  command `guard-bash` refuses today is still refused.
- AC-3: Given a line `git add -A && git commit -m x && <a command guard-bash asks about>`, when it runs, then it is
  refused with "run it alone", and the same command alone gets the question.
- AC-4: Given a maintenance task opened by `caw-work.sh open`, when the agent commits, then the branch is pushed
  only after the terms scan passed, and `caw-work.sh run <work> -- <command with ../..>` is refused; a push of
  `developer` from the clone's hook is refused.
- AC-5: Given a full maintenance task from `/caw-request` to `/caw-merge`, when it runs, then the only prompt is the
  push of `developer`.
- AC-6: Given `up` of a clone of work `2026-11-18-add-export`, then its group is `agent_1118-add-export`, its ports
  are free and in 61000-65535, a stack already running with the same compose file keeps its containers, ports and
  image tags, and `status` lists the group.
- AC-7: Given that group, when the agent runs `docker compose down -v` on it, then no prompt; when it runs
  `docker volume rm` on a volume of another group, then `guard-bash` asks.
- AC-8: Given any command that deletes, moves or empties `tools/observability/.data`, then `guard-bash` asks.
- AC-9: Given `/merge` into `developer` passed phase 2, then the task's group and its images are gone, and a group
  whose name does not match the expression is never removed by the script, even when passed by name.
- AC-10: Given a session where the person did not type `/merge`, when the agent runs `aiwp-gate.sh gate --merge`,
  then it is refused; after the person types `/merge`, it runs.
- AC-11: Given a task that ends, then its closing board lists the copy's addresses, one test item per acceptance
  criterion and the two ways out.
- AC-12: Given a merge into `developer` that changes a script and a doc, then two reviews run, `xhigh` on the script
  and `high` on the doc, each answering the three questions; a merge into `main` reviews since the last tag.
- AC-13: Given `/docker-deploy developer` and `/caw-docker-deploy developer`, then the final stack (the tools group
  here) is updated with its rollback tags and no volume is deleted; the model cannot invoke either skill.
- AC-14: Given `tests/check.sh --all`, then the suites of `guard-bash`, `aiwp-cmds.sh`, `aiwp-gate.sh`,
  `session-title.py` and `caw-work.sh` cover BR-1 to BR-13 with passing and failing cases, and the `caw-layers` check
  passes `/caw-pilot` and `/caw-docker-deploy`.
- AC-15: Given a new file and a changed file pending at the root, when `/caw-commit` runs, then both enter one commit
  at the first attempt, with no pathspec error; both `git.md` files carry the rule about paths in a variable.

## 7. Out of scope

- Claude Code's OS sandbox (D-4).
- What an interpreter builds at run time, inside a container, or on another host beyond the command line.
- Remote and cloud deployments: they keep their current flow (`release`, `apply`, `hotfix`).

## 11. Stages and effort

| Stage | Effort | Why |
| --- | --- | --- |
| 1. Maintenance trail: `caw-work.sh`, the clone's git hooks with the terms scan, the allow rules, `/caw-request` and `/caw-merge` without hand pushes, a prompt shows one thing, the `/caw-commit` staging (BR-2 to BR-6, BR-19) | high | Pushes to a public repository |
| 2. Product trail: `guard-bash` approval of lines in a clone and the "run it alone" refusal, the allow rules (BR-1, BR-2, BR-6) | high | A hook of the mandatory core; weakens nothing it guards today |
| 3. The Docker copy: `agent_` groups, ports, destruction by label, Grafana, `status`, `publish` (BR-7 to BR-10, BR-12) | high | Destructive steps on the machine's Docker |
| 4. End of task and merge only by the person: the closing board, `/merge` record and gate, `/caw-pilot` (BR-11, BR-13, BR-14) | high | Changes the gate |
| 5. The merge review (BR-15) | medium | Rules and skills with a clear scope |
| 6. `/docker-deploy` and `/caw-docker-deploy`, the seed recommendation (BR-16, BR-17) | high | Replaces the final stack |
| 7. Decision record, docs, pending requests (BR-18) | medium | Documentation |

The subagents of each stage run with the stage's effort, passed in the call. Stages 1 to 4 and 6 get an independent
review (effort high) before they close (`.claude/rules/review.md`), and AC-1, AC-3, AC-5 and AC-10 are proven in a
real session of a test installation (`/caw-test-install`): one of them also proves that a question from the hook
prevails over an allow rule, which the Claude Code documentation does not state.

## Assumed decisions

- Open: what counts as acting on a remote system. Decided: a push, a publish, a deploy, a cloud CLI, `ssh`,
  `docker push`; downloading dependencies does not. Reason: installs are part of normal local work.
- Open: SQL clients run on the host. Decided: the current question stays. Reason: they may reach a remote database.
- Open: the port range "above 50000". Decided: 61000-65535. Reason: 50000-60999 is inside the Linux ephemeral range,
  which the product forbids for publishing.
- Open: the hotfix review and the release's general round. Decided: the hotfix follows the `main` rule; the general
  round is dropped. Reason: the new `main` review widens as needed.
- Open: a second clone of the same work. Decided: its group adds `-<clone>`. Reason: two stacks in one compose project
  collide.
