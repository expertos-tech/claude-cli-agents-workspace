# product.md

What must stay true of the product in `workspace/`, whatever the change.

- **Mandatory core**, never made optional by any configuration: `AGENTS.md`, `rules/rules.md`, `rules/git.md`,
  `rules/security.md`; the hooks `guard-bash`, `guard-subagent-model`, `Stop`, `session-title`, `prompt-log`; the
  `deny` rules; `/merge`, `/commit`, `/request`, `aiwp-cmds.sh`, `aiwp-gate.sh`, `setup-claude.sh`.
- **Installs copy only `workspace/`**, by an inclusion list, never by a list of what to exclude. Nothing from the root
  (`CLAUDE.md`, `.claude/`, `tests/`, `maintainers/`, `tmp/`, `i18n/`, `install.sh`, `README.md`, `LICENSE`) ever
  reaches an installed workspace, on install or update. The manifest records only paths of `workspace/`.
- **Read-only installed core**: no `.git`; folders and executables 555, other files 444. Writable only `custom/`,
  `projects/`, `tmp/`, `logs/`, `.claude/`, `.history/` and a closed list of tool outputs, defined once at the top of
  `workspace/scripts/aiwp.sh` (Grafana data, console binaries, `node_modules`, front-end builds). So the product never
  writes inside a core folder at runtime: requests, filled `.env` files and generated files go to `custom/`, logs to
  `logs/`, or to that list.
- **Free project layout**: any folder of `projects/`, at any depth, may be a repository, inside another one too; no
  tool refuses a layout, and `guard-bash` protects the whole tree of `projects/`.
- **`.env`**: `.env.example` next to each tool and in `docker/`; the filled file in `custom/env/<tool>.env`, git-ignored,
  read by compose with `--env-file`.
- **English** in every product file; Claude answers in the person's language; the preferred language of
  communication is the Claude Code setting `language` in `.claude/settings.local.json`, asked at install (`aiwp new`).
- **No company data** in the core: what belongs to one company lives in the custom layer.
- A change to any of these needs a plan with the owner's decision, not only a request.
