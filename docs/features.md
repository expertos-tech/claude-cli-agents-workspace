# Features

English · [Português (Brasil)](../i18n/pt-BR/docs/features.md) · [Español](../i18n/es/docs/features.md)

## What you get

- **Rules** for the agent: one page that applies to every session (`AGENTS.md`) and rules per subject (git, security,
  quality, docs, frontend, infrastructure, models, review), read when the subject comes up.
- **Skills**: slash commands for the daily flow (`/merge`, `/commit`, `/push`, `/validate`, `/draft-prompt`,
  `/prompt`, `/pilot`, `/local-env`, `/normalize-projects`).
- **Agents**: subagents for requirements, architecture, implementation, tests, review, verification, infrastructure,
  scripts, documentation and research, each with its model and effort.
- **Hooks** that hold only what must never happen without you: git writes outside the gate, cloud changes, database
  deletions, secrets in a commit. [Hooks that run on your machine](hooks.md) lists them all.
- **A merge gate**: work happens in a clone under `tmp/work/`, and `/merge` brings it to the project's `developer`
  branch after the full test suite, the validations, a secret scan and a review against your request.
- **A custom layer**: your own private git repository in `custom/` for your company, cloud, visual identity, projects
  list, requests and lessons. It never goes into this repository.
- **Tools**: a local Grafana for the Claude Code telemetry, a container console (Docker CE on Linux, Colima on macOS),
  login and Safe Browsing simulators, an Azurite console, a usage report and a model alert. Each one has its README in
  `workspace/tools/`.

## The custom layer

`custom/` is **your** private git repository, separate from the product, and the only place for what belongs to you:
company name and spelling, cloud and tenant, visual identity, the list of your projects, written requests, lessons,
filled `.env` files (`custom/env/`, always git-ignored) and the prompt log. The workspace works without it and asks,
when it needs to, for the cloud, the visual identity and the folder of each project. It never goes into a pull request
to this repository.
