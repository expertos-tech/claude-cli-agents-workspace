# Autonomous work in the work branch

Status: approved design (2026-11-18). Request: `maintainers/requests/autonomous-work.md`.

## 1. Problem

The agent asks the person for authorization while it works on its own branch, and the person cannot tell what each
prompt approves.

- At the repository root, 37 of 809 permission decisions in six recent sessions were prompts, all `git push`: the
  `ask: Bash(git push *)` rule plus `/caw-request` pushing the work branch by hand after each commit. An `ask` rule
  prompts in every mode, auto mode included, and no hook can lift it.
- 10 of those 37 came inside a line of several commands (`git add && git commit && git push`): the prompt showed the
  whole line, and the one command that needed approval was at its end.
- In an installed workspace on an older version, about 590 of 14 324 decisions in three weeks were prompts, mostly
  `git push`, `git commit` and `rm` from `ask` rules the current product no longer has.
- The product today: `/merge` can be invoked by the model, `rules/git.md` "Waves" sends a mature part through the gate
  "at once", and `permissions.allow` is empty, so outside auto mode every command in a clone prompts.
- `aiwp-cmds.sh up` publishes the task's stack over the shared one (same compose project, same ports, same image
  tags), and the hook asks before deleting any Docker volume, so a test stack cannot be freely rebuilt.

## 2. Goal

- In its branch (a clone in `tmp/work/`) the agent works with no prompt: edits, commands, commits, the push of its own
  branch, and a Docker copy of what it needs.
- When it finishes, it publishes its copy and asks the person to validate it.
- The person orders the merge into `developer` (`/merge`, `/caw-merge`); it never happens on its own.
- The same behavior in the product and in the maintenance of this repository.

## 3. Options

| Option | Gain | Cost | Verdict |
| --- | --- | --- | --- |
| Claude Code's OS sandbox with `autoAllowBashIfSandboxed` | The only OS-level confinement of any command | Docker cannot run inside it; the network starts closed; no documented way to limit writes to `tmp/work/` | Rejected by the owner: this is the developer's machine, and the scripts' limits stop a hallucination |
| One allow rule for a script that runs anything in the clone | Simple | `run <clone> -- rm -rf ../..` passes by the rule | Not alone |
| Scripts at the borders (open, push, publish, close) plus an approval only for lines that stay in the clone | No prompt in the trail; leaving it falls back to the normal flow | The hook or script must tell where every command runs and what it touches | Recommended |
| Auto mode alone | No setup | A classifier, not configurable from the project, and the `ask` rules still prompt | Kept as the default mode, not as the guarantee |

## 4. Design

### The trail

| Where | Behavior |
| --- | --- |
| Edits and commands in a clone of `tmp/work/` | No prompt |
| Opening the clone, pushing its branch, publishing its Docker copy, closing it | No prompt, by the scripts |
| Anything in the Docker group of the task (`agent_...`) | No prompt |
| Another Docker group, outside the clone, or remote | Nothing automatic: the active permission mode decides |
| Deleting, moving or emptying `tools/observability/.data` (Grafana's data) | Asks, always |
| A git write in `projects/` or the core, Terraform outside `apply` | Refused, as today |

- Product: `guard-bash` approves a line (`permissionDecision: allow`) when it can tell that every command of it runs in
  one clone of `tmp/work/`, every path it names (arguments and redirections) stays in that clone, and no command acts
  on a remote system (a push other than the clone's own hook, a publish, a deploy, a cloud CLI, `ssh`, `docker push`);
  anything it cannot tell stays silent, and the normal flow decides. Allow rules for the border commands of
  `aiwp-cmds.sh` (`open`, `status`, `push`, `up`, `down`, `close` without `--discard`) and `Edit(/tmp/work/**)`.
- Maintenance (no hooks at the root): `tests/caw-work.sh` with `open`, `run`, `status`, `publish` and `close`, allowed
  by rule. `run` refuses an argument with a path outside the clone (`..`, an absolute path elsewhere). The clone gets
  git hooks that push its branch after each commit, after the company-terms scan of what leaves; they refuse
  `developer`, `main`, tags and force. The root keeps `ask: Bash(git push *)`: the only prompt left is the push of
  `developer` by `/caw-merge`.
- Accepted limit: neither the hook nor the script sees what an interpreter builds at run time. The goal is to stop a
  hallucination visible on the command line; the developer keeps the autonomy they had before the AI.

### A prompt shows one thing

The agent first runs everything it may; what needs authorization runs alone, in its own call, with one line before it
saying what is asked. In the product, `guard-bash` refuses with "run it alone" when a line that would prompt holds
other commands too. In the maintenance, each sensitive step is one script command. Outside auto mode the trail stays
approved and the rest follows what Claude Code asks; the separation is the same.

### The Docker copy of a task

- The group (compose project) is `agent_<MMDD>-<slug>`: the month and day and the slug of the work folder
  (`2026-11-18-add-export` → `agent_1118-add-export`); a second clone of the same work that publishes adds
  `-<clone>`. The branch name holds a `/`, which compose refuses. In the container console, the group tells whose
  instance it is.
- Ports: random free ports in 61000-65535 (above the Linux ephemeral range, 32768-60999, which the product already
  forbids for publishing; on macOS the script only checks they are free), in an override file of the copy; the
  project's compose files never change. The chosen ports are in the closing report and reach the stack as variables,
  for a project whose own address is fixed in its configuration.
- Images, networks and volumes are the group's own: the task's build never replaces a tag the final stack uses.
- Destruction only by label and only of a group whose name matches `^agent_[0-9]{4}-[a-z0-9][a-z0-9-]*$`: at
  `/merge` into `developer` once the branch is in, and at `close --discard`.
- A project with a database keeps a test seed (strong recommendation in the project contract), so a copy starts with
  its database rebuilt.
- `status` shows the groups of each clone.

### The final stack

- `/docker-deploy [developer|main]`, product, only by the person: updates the project's stack from that branch (`main`
  from a temporary checkout), tags the replaced images for `rollback`, never deletes a volume.
- `/caw-docker-deploy [developer|main]`, maintenance, a layer over it: the tools group (`claude-cli-agents-tools`),
  through `run-tools.sh`, with the tools' configuration read from the installed workspace (the repository has no
  `custom/`).

### End of a task

1. The tests of what changed pass.
2. The agent publishes its copy.
3. The closing report: the addresses of the copy, what to test (one item per acceptance criterion), and the two ways
   out, `/merge` when approved, `close --discard` when not.

`/pilot` (and `/caw-pilot`, its layer here) decides who runs the detailed check: the agent, with evidence, or the
person, with the list. The merge never happens on its own: in the product `/merge` cannot be invoked by the model and
`gate --merge` runs only after the `UserPromptSubmit` hook recorded that the person typed `/merge`.

### The merge review

The same three questions at every merge: what was asked against what was done; what went beyond the request; what
existed and was lost.

| Merge | Scope | Effort |
| --- | --- | --- |
| Into `developer` | Only the difference that enters | Code and configuration `xhigh`; documents `high` |
| Into `main` (release, hotfix) | Since the last tag, widened to what the reviewer judges necessary (callers, dependents, the docs of what changed) | The same |

A mixed merge is two reviews in parallel, each with its part. Rules, skills, agents, `AGENTS.md`, `CLAUDE.md` and
settings count as configuration. The release's "general" round, which reads the whole tree, is dropped.

## 5. Decisions

- D-1: the maintenance keeps one prompt, the push of `developer` by `/caw-merge`. Answer: keep.
- D-2: in the product, "never automatic" by the hook's record of a typed `/merge` (no extra prompt). Answer: ok.
- D-3: the review effort is by content, not by risk: code and configuration `xhigh`, documents `high`; the same three
  questions at `developer` (the difference) and `main` (widened as needed). Answer: as written.
- D-4: no OS sandbox; the scripts' limits are enough. Answer: as written; `os-sandbox-trial` is removed.
- D-5: Docker is free inside the task's own group; the final stack changes only by `/docker-deploy` and
  `/caw-docker-deploy`, which only the person runs; Grafana's data stays protected. Answer: as written.
- D-6: task copies in `agent_<MMDD>-<slug>` groups with random free ports above 50000, destroyed by the script at the
  merge into `developer`. Answer: as written; the range is 61000-65535 to stay above the Linux ephemeral range.

## 6. What it changes in pending requests

- Delivers `work-branch-push-before-scan`, `review-docs-only-scope`, `review-effort-wording` and
  `work-status-docker-stacks`.
- Removes `os-sandbox-trial`.
