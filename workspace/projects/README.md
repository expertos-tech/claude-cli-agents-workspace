# projects

The repositories of the projects the workspace works on live here. The folder belongs to the workspace; its content does not: the subfolders are ignored by the core, and only this README is part of it.

## How the folder works

- **Any structure.** Any folder, at any depth, may be a git repository, inside another one too: one repository per project, a root repository that holds the project's repositories (`projects/billing/` with `billing-api/` and `billing-web/` inside), or a plain folder that groups repositories. The structure is yours; a path belongs to the nearest `.git` above it. A root repository keeps the project's own `CHANGELOG.md`: the version of the whole, with the versions of its repositories (`rules/docs.md`).
- **The project list lives in the custom layer**, in `custom/projects.md`: path, remote, purpose and ports of each project. A new project is registered there, with a commit in the `custom/` repository.
- **Always on `developer`.** The checkout of each repository stays on `developer` (or on `main`, when the project has no `developer`) and is not edited here. All work happens in a clone under `tmp/work/` (`bash scripts/aiwp-cmds.sh open`) and reaches this folder only through the gate (`/merge`). A hook refuses any git write in this folder outside it.
- **Open Claude at the workspace root**, not inside a project, so that `AGENTS.md`, `rules/` and the hooks apply.

## How to bring a project in

- **One that already exists:** in a session, `/normalize-projects --from <url | folder> --name [<folder>/]<name>`. It clones the project here and brings it into the workspace: an analysis, a plan you approve, the migration on a tested branch, `developer` and `main` with the marker. A project cloned here by hand works too: the session warns that it has no marker and asks to normalize it.
- **A new one:** `bash scripts/init-repo.sh --type project --name <name> [--parent <folder>]`, which creates the repository, writes the marker in its `README.md` and registers its row in `custom/projects.md`.
- **The marker:** line 1 of each project's `README.md` on `developer`, `<!-- AI-WORKSPACE-PROJECT x.y.z -->`. `bash scripts/aiwp-project-state.sh` shows the state of every project.

## Conventions

- **Ports:** each project uses host ports of its own, registered in `custom/projects.md`; those of the workspace tools are in `tools/README.md`. Pick one that is in neither table, outside 32768–60999, and register it in the same commit that starts using it (`rules/rules.md` "Workspace layout").
- **Dashboards in the local Grafana:** `observability/dashboards/*.json` in the project's repository (convention in `tools/observability/README.md`).
- **Language:** English code is recommended, not required (`rules/rules.md` "Language").
