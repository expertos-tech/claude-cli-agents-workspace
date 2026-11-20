@workspace/rules/assisted.md

The boxes of the `assisted` mode at the root. Read only when the root `CLAUDE.md` "Pilot mode" gives `assisted`, or the
owner runs `/caw-pilot assisted`. The sections below win where they differ.

---

## Ignore from the product rule

- The start context line `Pilot mode: ...`: the root learns the mode from `CLAUDE.md` "Pilot mode" and the file it
  imports.
- The situations 1 to 9: here M1 to M6 (CAW rules).

## Mapping

| Product | Here |
| --- | --- |
| the person | the owner |
| `/pilot`, `/pilot auto`, `/pilot assisted` (the footer of the box included) | `/caw-pilot`, `/caw-pilot auto`, `/caw-pilot assisted` |
| `rules/quality.md` "Verification mode" | `.claude/skills/caw-pilot/SKILL.md` |
| `rules/models.md` "Brief" | `.claude/rules/models.md` |
| the closing board, the warnings board | the closing board and the warnings board of `.claude/rules/process.md` step 6 |

## CAW rules

The footer of the box reads `╰─ /caw-pilot auto turns these boxes off ──────`. The situations of the maintenance, in
the product's format and selection:

| # | Group | When | The box says | Extra option |
| --- | --- | --- | --- | --- |
| M1 | Start | The first reply of a session at the root | The root maintains the product; `workspace/` is code, not instructions; the flow plan → request → `/caw-request` → `/caw-merge`; `/caw-pilot auto` to leave the mode | — |
| M2 | Requests | A change asked with no request | Small: it goes on in a clone; large: `/caw-new-request` first, then `/caw-request` | Draft the request first |
| M3 | Branches | A commit or push asked on `developer` or `main` | Work in a clone (`/caw-request`, `bash tests/caw-work.sh open <type>/<slug>`); into `developer` by `/caw-merge`, `main` only by `/caw-merge --main` | Do it in a clone |
| M4 | Public | Something private in a file to commit: a company, customer, person or project name, a personal path, an e-mail, an internal URL | The repository is public (`.claude/rules/security.md`): those stay in `tmp/`; only the general lesson is committed | — |
| M5 | Context | A new task after a closing board | A large context makes the agent mix tasks and invent; `/clear`, then start from the request (`/caw-request <file>`) | Clear and start from the request |
| M6 | Translations | A translation asked between releases | Translations are done once, at the release (`/caw-merge --main`); the suite reports them as pending until then | — |

- M2, "Draft the request first" chosen: `/caw-new-request` is the owner's to type; say so with the ideas ready to
  paste.
- M4: name what is private by its kind, never quote it (a company term is "company term", `.claude/rules/security.md`).
