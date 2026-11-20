# rules.md

## Index

- `AGENTS.md` holds what applies to every session and the list of these files.
- `rules/agents/`: subagent definitions and the Claude Code settings. `rules/skills/`: commands, one `<name>/SKILL.md` each. Both are the source of `.claude/`.
- `rules/request-writing.md`: instructions of the separate Claude project that only writes requests, and the procedure of `/new-request`; its section "Organize" is also the one of `/draft-prompt`.
- `docs/decisions/`: decision records of the workspace (`rules/docs.md`). Read the ones a rule change touches before proposing it.
- `custom/docs/lessons.md`: lessons, not loaded in sessions (`AGENTS.md` "When a rule gets in the way").
- A change to the workspace updates `docs/` and `README.md` in the same commit, and the translations of the documents it changed (`i18n/` of the product repository).

## Workspace layout

- The workspace root holds the core: workspace files (`AGENTS.md`, `rules/`, `scripts/`, `docker/`, `docs/`, `assets/`, `templates/`, `projects/README.md`) plus `tools/`. Installed, the root is an installation, not a git repository (the repositories are `custom/` and each project), and the core is read only: it changes only by an update the person runs in a terminal, with the session closed (`aiwp update`; `guard-bash` refuses it inside a session). When the session start reports a new workspace version, tell the person to close this session and run `aiwp update` in a terminal; never run the update yourself. NEVER put project code in the core, and never write a file there: what the workspace generates goes to `custom/`, `projects/`, `tmp/` or a tool output folder (`scripts/aiwp.sh _writable`).
- `projects/`: each project is an independent git repo, cloned or created there. Any folder of `projects/`, at any depth, may be a repo, inside another repo too: the structure is the developer's choice, and no tool refuses one. A path belongs to the nearest `.git` above it; whether a repo ignores the repos inside it is its own choice. A project is the folder a release names: one repo, a repo that holds others (its root repo), or a plain folder of repos. Subfolders are git-ignored; `projects/README.md` is part of the core. `scripts/lib/projects.sh` holds the rule of which folder is a repo.
- Folder of a new project in `projects/`: decided by the human, in the request. None given: ask before creating the project, never pick the folder.
- New or cloned project: add a row to the table in `custom/projects.md` (path relative to `projects/`; repo URL; purpose; the language of its documentation, once `/normalize-projects` asked it).
- `tools/`: the product's local support tools, part of the read-only core; one folder per tool: `tools/<name>/`. A tool with a UI shows the project's identity, never the custom layer's: the name Claude CLI Agents Workspace and the logo or icon of `assets/`.
- `custom/tools/`: your own tools, in the custom layer; one folder per tool: `custom/tools/<name>/`, with its `history.txt` when it keeps one. A new tool of yours never goes into `tools/`, which only an update changes.
- `custom/pocs/`: POCs (experiments, hypothesis validation), in the custom layer; one folder per POC: `custom/pocs/<name>/`.
- Names: kebab-case, by business purpose.
- Create a project, POC or tool only with `bash scripts/init-repo.sh` (its `--help`): a new project or POC starts with the marker (below). Bring an existing project in only with `/normalize-projects --from <git-url | folder>`, or, for the work of an older workspace, with `/import-workspace <folder>`, which then sends each project it brought to `/normalize-projects`; a project cloned or moved into `projects/` by hand, or a POC moved into `custom/pocs/`, has no marker and is normalized like any other ("Workspace projects").
- Start sessions from the workspace root so `AGENTS.md`, `rules/` and `.claude/` apply to every repo.
- Destination: new system → the folder of `projects/` the request names (above); change to an existing system → its folder in `projects/`; experiment → `custom/pocs/`; local tool of yours → `custom/tools/`. A change to a tool of `tools/` is a change to the product, made in the product repository.
- POC (validates a hypothesis) in `custom/pocs/`: worked on in a clone of `custom/` and taken in by the gate with its build or parse command as `--test`. A local tool of yours in `custom/tools/`: worked on like a POC. A tool of `tools/`: part of the core, changed only in the product repository. Security rules always apply. Both exempt from unit tests, coverage gate and review: it only has to compile (interpreted code and config: parse) and pass `scripts/validate.sh --only secrets`, with a README. A POC's README also states hypothesis, how to run, result and conclusion.
- Promoting a POC to a project or tool: full Definition of Done for the target.
- Host ports: every port a project, tool, POC or `docker/` stack publishes on the host is unique in the workspace and listed once: a tool or `docker/` stack in the "Host ports" table of `tools/README.md`, a project or POC in the one of `custom/projects.md`. Read both tables before choosing one, and add the row in the same commit that starts using it. Never pick one in 32768-60999, the Linux ephemeral range. By type of stack:
  - POC in `custom/pocs/`: MUST be >= 20000, the conventional port + 20000 when it fits (e.g. 3000 → 23000), so a POC never collides with a tool or a project.
  - Tool in `tools/`: MUST keep its conventional port when it has one (e.g. Grafana 3000, OTLP 4317 and 4318). A tool with no conventional port: >= 20000.
  - Project in `projects/`: the conventional port when no other row uses it; otherwise a free one below 20000.
  - Workspace `docker/` stacks: MUST be >= 20000, the conventional port + 20000 when it fits (e.g. SonarQube 29000).

## Workspace projects

- The marker is line 1 of a project's `README.md` (of a POC's folder `README.md`): `<!-- AI-WORKSPACE-PROJECT x.y.z -->`, the workspace version it was last normalized with. For a project, the one committed on `developer` counts. `bash scripts/aiwp-project-state.sh` reads it against `VERSION` and `migrations/`: no marker, up to date, out of date (a file of `migrations/` newer than the marker), or the workspace's own repository, which is never normalized.
- Warning, never a block: the `UserPromptSubmit` hook adds the state of every project or POC a message names (its folder name, a path, the `**Project:**` line) when it has no marker or is out of date; `aiwp-cmds.sh open` and the gate print it too. Then tell the person and ask for authorization to run `/normalize-projects <project>`. Yes: it runs before the request. No: the request goes on as asked, and the warning comes back at the next message that names the project.
- `/normalize-projects` works in two stages, with the person's approval between them: (1) four analysts read a fresh clone and the plan goes to `custom/migrations/<name>-<date>.md`, with the language of the documentation; (2) `projects/<repo>` on `developer`, the checkpoint tags pushed, a clone on `feat/ai-workspace-migration`, the approved plan in commits (custom layer first, the marker last), the test with the person, `/merge` into `developer` and the release of `main`. A POC gets the same analysis and approval, then commits in `custom/`, with no branch, tag, gate or release. What each version asks of the projects: `migrations/`.
- A normalization never rewrites code, writes tests or fixes a security gap: gaps go to the project's `AI-WORKSPACE-MIGRATION.md`, security alerts (file, line, type, never the value) are shown to the person at the end and counted in that report.

## Custom layer

- `custom/` is the custom layer: a git repo of its own at the workspace root, never part of the core. It holds what belongs to one company and its projects: company, cloud and tenant, visual identity and logos, the project index with the project ports (`custom/projects.md`), the plans of `/draft-prompt` (`custom/plans/`, with their priority order in its README), the requests (`custom/requests/`: pending, in state `idea` or `ready`; `qa/<project>/` once on `developer`; `done/<project>/` once released), the lessons (`custom/docs/lessons.md`), the performance reports (`custom/performance/`, written by `scripts/performance/measure.py`) and the data of workspace tools that are the company's.
- Text that changes with the company, a client or a project goes to `custom/`, never to `AGENTS.md`, `rules/`, `docs/`, `scripts/`, `docker/` or `tools/`. `bash scripts/check-workspace.sh` fails on a term of `custom/core-terms.txt` found here; a new company term (a project, a product) is added there.
- The workspace's own rules, skills and agents live in `custom/my-rules/` (`*.md`, `skills/<name>/`, `agents/<name>.md`), and `custom/rules-config.json` turns core ones off or replaces a core rule with an own one; `scripts/setup-claude.sh` applies both at every session start, each own item as `custom-*` in `.claude/` (an own rule without `paths:` in every session, with it when a matching file is touched). The mandatory core (`rules/manifest.json`) always loads. They change through `/rules`, on the human's request, or by hand; a change reaches the next sessions.
- No `custom/`: what it would name (cloud, identity, project folder) is asked in intake, never invented.

## Project structure

- Applies inside each repo in `projects/`. Tools in `tools/` and POCs in `custom/pocs/` follow it as guidance, not as a delivery gate.

- MUST place reusable, project-agnostic code in `components/<language>/`. NEVER put business rules of a specific project there.
- MUST place libraries for external use or internal consumption with a stable public API in `sdk/<language>/`.
- MUST keep project-specific code outside `components/` and `sdk/`, in the layout the language's modern convention favors.
- Every component and SDK MUST have its own semantic version, `README.md` and `CHANGELOG.md`.
- Breaking change in an SDK public API MUST bump MAJOR and list migration steps in its `CHANGELOG.md`.
- Before creating any module, MUST search `components/` and `sdk/` of the current repo, then of the other repos in `projects/`, of `tools/` and of `custom/pocs/`. If something fits: reuse it or evolve it. NEVER create a second version of it.
- Reuse across repos only through a versioned dependency (published SDK/component). NEVER copy code between repos; if no published version exists, report the options to the user.
- Extract to `components/` only when the logic is project-agnostic AND a second real consumer exists or the extraction simplifies the current code.

## How to decide (technical choices)

- NEVER hard-code an engineering decision in `rules/`. Rules define criteria; decisions go to `docs/` per request. Exception: what the rules fix as user-defined or workspace standard (visual identity, ports, coverage gate, Terraform).
- Hard gates (an option failing any is discarded): correctness, security rules, request NFRs.
- Rank options that pass by: maintainability > evolvability > simplicity > operability > cost. A higher criterion beats any number of lower ones.
- PREFER the language standard library and its idiomatic patterns over third-party code.
- PREFER mature, actively maintained, widely adopted libraries with compatible licenses over new or niche ones.
- PREFER the simplest design that meets the acceptance criteria and NFRs; add structure only when a current requirement needs it.
- Use OO and design patterns where the language paradigm favors them; in non-OO languages use the idiomatic equivalent.
- Check current official docs (web) before choosing a version, library or cloud service. NEVER rely on memory for versions.
- Record a decision in `docs/` when it is hard to reverse, non-obvious, or chooses between viable options, per `rules/docs.md` "Decision records" (a new record, or an adjustment of an existing one).

## Language

- Replies and written requests: in the human's preferred language, else in the language the human writes in; technical terms stay as the market uses them (`AGENTS.md` "Role").
- The workspace core, its tools and its records: English only (code, routes, file names, identifiers, messages, docs, commit messages). Translations of documents live in `i18n/<locale>/` of the product repository, never in the core.
- Projects in `projects/` and POCs in `custom/pocs/`: English code is recommended (file names, identifiers, routes, technical and log messages, commit messages), not required; a project's own rules or `custom/my-rules/` decide. Their docs follow `rules/docs.md`.
- MUST write a docstring/doc comment for every method and function, public or private, in the language of the code.
- Inline comments only when the code cannot express the reason. NEVER comment what the code already says.

## Git

- Every git operation: `rules/git.md`.

## Tooling

- Validation tools live in `docker/compose.yaml`, pinned by tag AND digest. Run them through `scripts/validate.sh`.
- Adding a tool: verify the current release in its official registry, pin it per `rules/security.md` "Dependencies", wire it into `scripts/validate.sh`, document it in `docker/README.md`.
- SonarQube (`docker/sonar/`, `scripts/sonar.sh`) is optional: only when the user asks (`/validate --sonar`), for maintainability signals (duplication, cognitive complexity, smells). It does not replace the coverage gate in `rules/quality.md`.

## Local environment

- MUST respect `custom/pocs/.gitignore` before importing or creating a POC. Ignored PoCs are outside this workspace; an ignore rule never authorizes deleting files.
- This machine runs Linux with Docker Engine; the machine load limits are those of `rules/machine-load.md`.
