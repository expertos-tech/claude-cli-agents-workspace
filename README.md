# Claude CLI Agents Workspace

<p align="center"><img src="workspace/assets/logo.png" alt="Claude CLI Agents Workspace" width="320"></p>

<p align="center">English · <a href="i18n/pt-BR/README.md">Português (Brasil)</a> · <a href="i18n/es/README.md">Español</a></p>

A workspace for the **Claude Code CLI**. You say **what** you want, and Claude decides **how**, working in an isolated
clone where everything is allowed. The heavy checks and the questions for you happen in one place: the gate that brings
the work into the project's base branch.

> **Made for the CLI.** Hooks, permissions, skills and session names are designed and tested in the terminal Claude
> Code (`claude`). The Claude app (desktop or web) and the IDE extensions can probably open the workspace, but they may
> handle hooks, permissions and commands differently; there, what this documentation describes is not
> guaranteed.

## Get involved

This workspace grew out of daily use, and it gets better with every person who uses it on a real project. Found a
better way to do something, fixed a defect, wrote a hook or a clearer rule? **Share it**: fork the repository, make
your change and send a pull request. Let's build an open-source community around it. The steps are in
[Contributing](docs/contributing.md).

## Quick start

1. Check the [requirements](docs/getting-started.md#requirements): Linux, macOS or WSL2, `git`, `bash`, `python3`,
   Docker and the Claude Code CLI logged in.
2. Install and create your workspace:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash
   ```

3. Open it at its root: `cd ~/my-workspace && aiwp`.
4. Bring a project into `projects/`, then ask in the session what you want, for example:
   `in my-app, add a GET /health endpoint that answers 200 with the application version`.

Each step, with the options, is in [Getting started](docs/getting-started.md).

## Documentation

| Page | What it covers |
| --- | --- |
| [Getting started](docs/getting-started.md) | Requirements, install, create, open and the first request |
| [Features](docs/features.md) | What you get, and the custom layer |
| [Commands and updates](docs/commands-and-updates.md) | The `aiwp` commands and how updates work |
| [Hooks](docs/hooks.md) | The hooks that run on your machine |
| [Product guide](workspace/docs/usage.md) | The daily use of the workspace |
| [Contributing](docs/contributing.md) | Issues, fork, branch, pull request |
| [Maintenance](docs/maintenance.md) | How the repository is maintained |
| [Releases](docs/releases.md) | Branches, changelogs and the product release |
| [Translations](docs/translations.md) | What is translated and how it is checked |
| [Repository](docs/repository.md) | The layout of the repository |

## License

[MIT](LICENSE).
