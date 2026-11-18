@workspace/AGENTS.md

The session index of this repository is built from the product's, the section "Reference" of `workspace/AGENTS.md`,
with the sections below applied. `tests/caw-session-index.py`, the SessionStart hook of `.claude/settings.json`,
builds it at the start of a session and after a compaction; this file is never loaded by itself.

---

## Ignore from the product index

A product row whose files are all listed here is left out; a listed file is removed from a row that names others.

- `rules/rules.md`: projects, POCs, ports and layout of an installed workspace.
- `rules/machine-load.md`: the maintenance runs no heavy CPU or GPU task.
- `rules/quality.md`: the maintenance does not follow it; a request may bring it in.
- `rules/frontend.md`, `rules/infra.md`: no UI and no Terraform here.

## Mapping

- A path of the product index is relative to `workspace/`: `rules/git.md` is `workspace/rules/git.md`.
- A product rule `workspace/rules/<name>.md` is read with its layer `.claude/rules/<name>.md` over it, when the layer
  exists.
- "Read before" stays "before"; "Loads with" becomes "when touching": a path-scoped product rule does not load by
  itself here (`claudeMdExcludes`).
- The words of a trigger, replaced as written (the bullets below with an arrow):
- `the review of the gate` → `the review of /caw-merge`
- `the gate` → `/caw-merge`
- `a wave` → `a stage`
- `, a Terraform apply` → nothing

## CAW index

Paths relative to the repository root, in tables of the product's two forms. A row for a file the product index
already names adds its trigger to that file.

| File | Read before |
| --- | --- |
| `workspace/rules/security.md` | anything that goes to this public repository: a commit, a plan, a request |
| `maintainers/requests/README.md` | writing, ordering or running a request |

| File | Loads with |
| --- | --- |
| `workspace/rules/docs.md` | `i18n/`, `maintainers/`, a translation |
| `workspace/rules/scripts.md` | `tests/`, `install.sh`, a hook |
