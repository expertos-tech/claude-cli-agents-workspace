# Plans

English · [Português (Brasil)](../../i18n/pt-BR/maintainers/plans/README.md) · [Español](../../i18n/es/maintainers/plans/README.md)

The approved designs behind the requests in `maintainers/requests/`. A plan says what to build and why; its request
says what must be true when it is done. Read the plan before running its request.

| Plan | Covers | Request |
| --- | --- | --- |
| `distribution.md` | The three folders, the installer and `aiwp`, the manifest sync, the read-only install, the maintenance at the repository root, platforms and languages | Built in the 0.1.0 publication |
| `normalize-projects.md` | The project analysis and migration, the version marker and the check at every interaction | `requests/done/normalize-projects.md` |
| `rules-config.md` | `custom/rules-config.json`, `custom/my-rules/`, the mandatory core and `/rules` | `requests/qa/rules.md` |
| `autonomous-work.md` | Work in the branch with no prompt, a Docker copy per task, the merge only by the person, the merge review | `requests/autonomous-work.md` |
| `normalize-rules.md` | Bringing the rules of an older workspace into `custom/my-rules/`, and listing its projects | `requests/normalize-rules.md` |
| `run-tools.md` | The single compose file of the tools and `/run-tools` | `requests/qa/run-tools.md` |
| `tools-hub.md` | The tools page, the menu icon and the Workspace area | `requests/tools-hub.md` |
| `fork-my-rules.md` | Giving own rules back to the project by fork and pull request | `requests/fork-my-rules.md` |
| `assisted-mode.md` | `/pilot assisted`: boxes that teach the workspace to a newcomer, the default per person, `/caw-pilot` | `requests/assisted-mode.md` |
| `preferred-language.md` | The reply language as Claude Code's `language` setting: asked at install, asked by a root hook in the maintenance | `requests/preferred-language.md` |

The order in which they run is in `maintainers/requests/README.md`.
