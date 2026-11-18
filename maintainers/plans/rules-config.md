# Configurable rules in the custom layer

Status: built on the branch `feat/rules-config` (request `maintainers/requests/rules.md`), waiting for `/caw-merge`. Built with: `/request` in place of `/prompt` (renamed), `reviewer` and `verifier` added to the mandatory core, and own skills and agents limited to a closed list of front matter keys (decision record 0003).

## 1. Goal

- An installed work workspace is never edited while it is used: its core is read-only (555/444). The core changes only
  in this repository, which produces a new release.
- The custom layer (`custom/`) holds two things:
  - a **rules configuration**: which core rules, skills and agents load, and which core rule is replaced by an own one;
  - the **own rules**, in `custom/my-rules/`.
- The session setup builds the effective rules of the workspace: the core, as installed from the data folder, combined
  with the configuration and the own rules.
- The maintainers use the same installation and the same configuration as everyone else. The repository that receives
  commits for the workspace is this one, never the installed copy that is running.

## 2. How the session is assembled today

`scripts/setup-claude.sh` runs at every session start and builds `.claude/`, which is generated and git-ignored:

| Source | Target |
| --- | --- |
| `rules/agents/*.md` | `.claude/agents/` |
| `rules/agents/settings.json` | `.claude/settings.json` |
| `rules/skills/<name>/` | `.claude/skills/<name>/` |
| `rules/*.md` with a `paths:` front matter | `.claude/rules/` |
| `custom/rules/*.md` | `.claude/rules/custom-*.md` |

The other rules (`git.md`, `rules.md`, `models.md`, `review.md`...) are not copied: `AGENTS.md` tells the model to read
them when the subject comes up.

Half of the goal exists: the company's own rules enter through `custom/rules/`. Missing: choosing what of the core
loads, replacing a core rule with an own one, own skills and agents, and a safe way to change all this.

## 3. The configuration: `custom/rules-config.json`

```json
{
  "core": {
    "rules":  { "exclude": ["frontend.md", "infra.md"] },
    "skills": { "exclude": ["pilot"] },
    "agents": { "exclude": ["infra-engineer"] }
  },
  "replace": { "review.md": "review.md" }
}
```

| Field | What it does |
| --- | --- |
| `core.rules.exclude` | Core rules that do not load. An excluded rule leaves `.claude/rules/`, and the generated `AGENTS.md` no longer tells the model to read it |
| `core.skills.exclude`, `core.agents.exclude` | Core skills and agents that do not load |
| `replace` | Replaces a core rule with an own rule on the same subject, kept in `custom/my-rules/`. A replacement is always declared: an own rule with the name of a core rule and no `replace` is refused, so no rule is ever replaced by accident |

The configuration is JSON, read by Python with no dependency. There is no language setting: Claude answers in the
language the person writes in.

**The mandatory core cannot be turned off.** The core declares in a manifest (`rules/manifest.json`) the pieces the
workspace needs to work and stay safe:

- `AGENTS.md` and `rules.md`;
- `git.md` (the gate and the branch always on the remote) and `security.md`;
- the hooks `guard-bash`, `guard-subagent-model`, `Stop`, `session-title` and `prompt-log`;
- the `deny` rules;
- the skills and scripts the flow depends on: `/merge`, `/commit`, `/prompt`, `aiwp-cmds.sh`, `aiwp-gate.sh`,
  `setup-claude.sh`.

The configuration can neither remove nor replace these pieces: the generation keeps the core piece and says why at the
session start. Without this, a configuration file could switch off the protection that the read-only core and the gate
give. Everything else (rules, skills and agents that are not crucial) can be turned off.

## 4. The own rules: `custom/my-rules/`

```text
custom/my-rules/
  *.md                 own rules; with paths:, loaded by path; without, in every session
  skills/<name>/       own skills
  agents/*.md          own agents
```

- `custom/my-rules/` replaces `custom/rules/`: the same role, plus skills and agents. The migration moves the existing
  files (`cloud.md`, `company.md`, `identity.md`) and updates every reference to them.
- Nothing in `custom/my-rules/` may have the name of a core item, except through `replace`. In `.claude/`, own items
  keep the `custom-` prefix, so the origin of each rule is clear.
- **`custom/` is not read-only.** The 555 protection covers the core files only. `custom/` belongs to the person,
  writable and versioned in its own repository. The `deny Edit` rules on `custom/rules/**` and `custom/brand/**` are
  removed: the person and the session edit `custom/my-rules/` and `custom/rules-config.json` like any own file. The
  skill (section 5) is the guided path, not the only one.

## 5. The `/rules` skill

The generator is `setup-claude.sh`, which already runs at every session start and starts reading the configuration.
The skill is the safe way to see and change the configuration:

| Command | Does |
| --- | --- |
| `/rules` | Shows the effective rules: from the core (loaded and excluded), replaced and own, with the origin of each, and the warnings (an own rule nothing loads, an `exclude` that names something no longer in the core) |
| `/rules exclude <rule>`, `/rules include <rule>` | Changes the configuration |
| `/rules add <subject>` | Writes a new own rule in `custom/my-rules/` from what the person describes, in the format of the core rules |
| `/rules replace <core rule>` | Copies the core rule to `custom/my-rules/` as a starting point and declares the `replace` |

- **Script with tests:** validation and generation live in `scripts/rules-config.py`, used by the skill and by
  `setup-claude.sh`.
- **Validation on every path:** a change can come from the skill or from a direct edit in `custom/`. Either way, the
  next generation checks the configuration. If it tries to remove a mandatory piece or names something that does not
  exist, the generation keeps the core piece and warns at the session start. A bad configuration never stops a session
  from opening.
- **After a change:** the skill regenerates `.claude/` (`setup-claude.sh`), commits in `custom/` and says that open
  sessions pick the change up only when reopened.
- **Nothing in the core:** the effective `AGENTS.md` is generated in `.claude/`, because the original is read-only. The
  root `CLAUDE.md` of the product imports the generated one.

## 6. Where this applies

- The configuration and `custom/my-rules/` of each work workspace apply on top of the core installed from the data
  folder.
- The maintenance rules live at the root of this repository, apart from the product rules, and never go
  through this configuration.

## 7. Decisions

- The mandatory core of section 3 is fixed; the configuration cannot turn it off.
- The configuration is JSON, in `custom/rules-config.json`.
- `custom/rules/` becomes `custom/my-rules/`, with own rules, skills and agents.
- The skill is named `/rules`.
- `custom/` is free to edit: the `deny Edit` rules on `custom/rules/**` and `custom/brand/**` are removed.
