# 0001 Base design

Status: partly superseded by 0003

## Context

Claude CLI Agents Workspace is a folder where Claude Code works on a person's projects: the person says what they want, and Claude decides how. It must stay easy to maintain for whoever uses it, keep what belongs to one company out of the shared product, never let an agent damage a project's base branch, a database or the cloud without the person, and receive improvements without overwriting the person's own files.

## Decision

- **The core and the custom layer.** The core is the product: `AGENTS.md`, `rules/`, `scripts/`, `docker/`, `docs/`, `tools/`, `assets/` and `templates/`, in English. What belongs to one company or person lives in the custom layer, `custom/`, a git repository of its own at the workspace root: company, cloud and tenant, visual identity, the project index and its ports, written requests, lessons, the backlog, performance reports and extra rules (`custom/rules/*.md`, loaded like the core rules). `scripts/check-workspace.sh` fails when a term of `custom/core-terms.txt` appears in the core.
- **Projects.** Each project is an independent git repository under `projects/`, at any depth, never part of the core. Its checkout stays on its base branch (`developer`, else `main`) and is never edited there.
- **Work in clones.** A change to a project or a POC happens in a clone under `tmp/work/<date>-<slug>/`, opened by `scripts/aiwp-cmds.sh open`. Inside a clone everything is allowed; each commit is pushed by the clone's own hooks after a secret scan of what leaves.
- **The merge gate.** A base branch receives only what the gate checked (`/merge`): phase 1 updates the base, runs the full tests, `validate.sh` and the secret scan, and audits what leaves the base; a clean-context review compares the change with the request; phase 2 fast-forwards the base to exactly the checked commit. `main` moves only by `aiwp-cmds.sh release`, and Terraform applies only by `aiwp-cmds.sh apply`, both on the person's explicit request.
- **Hooks over text.** What must never happen is enforced by hooks and permissions, not by rules to read: `guard-bash` (git writes in `projects/` and the core, Terraform, deleting databases, secrets in commits), `guard-subagent-model` (the model of each subagent), the `Stop` hook (no reply ends with a commit that is not on the remote), `session-title` and `prompt-log`, plus `deny` rules on the core. Everything else follows Claude Code's permission mode.
- **A mandatory core.** `AGENTS.md`, `rules/rules.md`, `rules/git.md` and `rules/security.md`; the hooks `guard-bash`, `guard-subagent-model`, `Stop`, `session-title` and `prompt-log`; the `deny` rules; `/merge`, `/commit`, `/prompt`, `aiwp-cmds.sh`, `aiwp-gate.sh` and `setup-claude.sh`. No configuration can turn them off.
- **A read-only installed core.** An installed workspace has no `.git` in its root. Core folders and executables are mode 555 and other core files 444; only `custom/`, `projects/`, `tmp/`, `.claude/`, `.history/` and a closed list of generated tool outputs are writable. The core changes only by `aiwp`, which brings a new release from the local copy of the product repository, replaces the files that changed and keeps the previous version for a rollback.
- **The repository root is the maintenance of the project.** The product is maintained in its own repository, where it sits in `workspace/`. The repository root holds the maintenance: its `CLAUDE.md` and `.claude/` (process, rules, skills and agents), the suite (`tests/`), the maintainers' backlog, plans and requests (`maintainers/`), the translations (`i18n/`) and the installer. A session opened there maintains the product and never loads the product's rules. An installation copies only `workspace/`.
- **Language.** The core is in English. Claude replies in the language the person writes in. Translations of the documents live in `i18n/<locale>/` of the product repository and are not installed. In the person's own projects and POCs, English code is recommended, not required.

## Reason

- One place for the heavy checks and the questions (the gate) keeps the work fast and the base safe.
- A guarantee held by a hook cannot be skipped by a model that misread a rule, and it costs no context.
- A read-only core and a separate custom layer let a release replace the core without touching the person's files, and keep company data out of the shared product.
- Developing the product in a mode of its own keeps its rules, which are the code being edited, from steering the session that edits them.

## Consequences

- A session in an installed workspace never edits the core; a rule that gets in the way becomes a proposal in `custom/docs/lessons.md` or a pull request to the product repository.
- Every change to the product goes through the product repository's suite (`check-workspace.sh`), including the translations of the documents it changes.
- A person who wants other rules adds them to `custom/rules/`; the mandatory core still applies.

## Change history

- 2026-11-17 — the own rules move from `custom/rules/` to `custom/my-rules/`, the custom layer can turn optional core rules, skills and agents off, and the mandatory core is declared in `rules/manifest.json` (`/request` in place of `/prompt`, plus the agents `reviewer` and `verifier`) — configurable rules — the owner (0003)
