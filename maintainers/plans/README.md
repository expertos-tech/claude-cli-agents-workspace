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
| `import-workspace.md` | Bringing the work of an older workspace (repositories, worktrees, work clones, backlog), not its rules | `requests/qa/import-workspace.md` |
| `run-tools.md` | The single compose file of the tools and `/run-tools` | `requests/qa/run-tools.md` |
| `tools-hub.md` | The tools page, the menu icon and the Workspace area | `requests/tools-hub.md` |
| `fork-my-rules.md` | Giving own rules back to the project by fork and pull request | `requests/fork-my-rules.md` |
| `assisted-mode.md` | `/pilot assisted`: boxes that teach the workspace to a newcomer, the default per person, `/caw-pilot` | `requests/assisted-mode.md` |
| `preferred-language.md` | The reply language as Claude Code's `language` setting: asked at install, asked by a root hook in the maintenance | `requests/qa/preferred-language.md` |
| `request-in-progress.md` | The "doing" state of a request from the opening of its clone to its merge, so no list suggests a request already running | `requests/request-in-progress.md` |
| `draft-prompt.md` | `/draft-prompt` turns a loose text into a plan in a priority order; `/draft-request` renamed `/new-request`, with a summary on screen; plans in the person's language, requests in English, the screen in the person's language | `requests/draft-prompt.md` |
| `import-workspace-code-folders.md` | Every code folder of an older workspace found by extension, classified in rounds (POC, tool, project) and brought with a local repository | `requests/import-workspace-code-folders.md` |
| `session-names.md` | Session names that follow the life of a request: `ai-workspace-NN`, `rq-<words>`, `rq-done-`, `rq-closed-`; `/rename-workspace`; `/rename` free | `requests/session-names.md` |
| `terms-list.md` | The company-terms list of the maintainer machine, the commit e-mail, a visible SKIP when there is none | none: option A (as today) decided |

The order in which they run is in `maintainers/requests/README.md`.
