# Distribution through GitHub

Status: approved design, built in the 0.1.0 publication. Public repository:
`github.com/expertos-tech/claude-cli-agents-workspace`. Project name: **Claude CLI Agents Workspace**.

## 1. Goal

1. One command in the README installs the repository in the operating system's local data folder and creates the
   first workspace.
2. The repository has the scripts to create a new work workspace: a folder with the core, the custom layer and the
   projects.
3. Creating a workspace asks for the custom repository.
4. Every installed workspace is registered. When a new release exists, opening a workspace only says so; the person
   updates them by command, in a terminal, with the list of registered workspaces.

The workspace is made for the **Claude Code CLI**. It may open in the Claude app (desktop or web) and in IDE
extensions, but hooks, permissions and commands can behave differently there. The README and the installer say so.

## 2. The three folders

| Folder | Role | How it changes |
| --- | --- | --- |
| This repository | Where the workspace is maintained, from its root | Commits, pull requests, releases tagged `vX.Y.Z` |
| The local data folder: `${XDG_DATA_HOME:-~/.local/share}/claude-cli-agents-workspace` on Linux and WSL; `~/Library/Application Support/claude-cli-agents-workspace` on macOS | The full repository, cloned by the installer (`curl ... \| bash`). The installer also puts `aiwp` in `~/.local/bin` | `aiwp` fetches the tags and moves to the newest release. Nobody edits here |
| Every work workspace | A copy of the core (`workspace/`) from the data folder, read-only, without `.git`, with a manifest; plus `custom/`, `projects/` and `tmp/` | Opening notices the new release and says so. `aiwp update` moves the data folder and copies what changed (section 4) |

Several workspaces on one machine share the same installation. Each has its own custom layer; two workspaces may point
to the same custom repository. The data folder keeps `workspaces.json`, the registry of every installed workspace
(path, version, created, updated): `aiwp new` registers, and the first `aiwp` run in an unregistered workspace adds it.

## 3. The commands

### 3.1 Installation

```bash
curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash
```

The installer:

1. checks the prerequisites (`git`, `bash`, `python3`, `docker`, `claude`) and says what is missing, installing nothing
   on its own;
2. clones the repository into the data folder (or updates it, when it exists) and checks out the newest release tag;
3. puts the `aiwp` command in `~/.local/bin`;
4. creates the workspace with `aiwp new` and registers it. It decides by the folder it runs in: an empty folder offers
   `1) Install here` or `2) Give another path`; a folder with content asks only for the path, of a new or empty folder,
   and asks again after a bad answer. The questions read the terminal (`/dev/tty`), so they work under `curl | bash`;
   `aiwp new` then asks for the custom repository's URL (empty: a new local repository).

Without questions: `curl ... | bash -s -- ~/my-workspace` or `AIWP_WORKSPACE=~/my-workspace` (the argument wins). With
no terminal and no folder, only the data folder is installed and the installer prints how to create a workspace
(`aiwp new <folder>`). Running the installer again updates the data folder only; it never updates a workspace.

Nothing needs administrator rights or `sudo`. `curl | bash` runs whatever `main` holds at that moment, so the README
also shows how to download, read and then run the installer, and the installer pins a release tag.

### 3.2 `aiwp new <folder>`: a new workspace

1. Creates the folder and copies the core from the installation, writing the manifest (version and hash of each file).
2. Asks for the URL of the custom repository and clones it into `custom/`. For an empty repository, it creates the
   skeleton (`README.md`, `core-terms.txt` with comment lines only, `.gitignore` with `env/`) and makes the first commit.
3. Runs `setup-claude.sh`, which builds `.claude/`.
4. Prints the next step: `cd <folder> && aiwp`.

A workspace holds as many projects as needed in `projects/`.

### 3.3 `aiwp`: open the workspace

Opening is detection only.

1. Checks for a new release with `git ls-remote --tags` on the public repository, using the result kept for the day,
   with a 5 s limit. Offline or on timeout, it goes on.
2. When there is a new release, prints "A new workspace version X was detected (this workspace: Y). Run `aiwp update`
   to update; opening this workspace on Y." It never updates.
3. Runs `setup-claude.sh`, as the session start hook does.
4. Starts `claude` on the current version, with the arguments given after `--`.

After an interrupted update it refuses to open until `aiwp repair` (or `aiwp update`) restores the workspace. A
workspace not yet in the registry is added on its first opening.

### 3.4 `aiwp list`, `forget`, `update`, `rollback`, `repair`

- `list`: each registered workspace with its version and state: up to date, update available (X), core changed, folder
  missing, pinned at X, stopped halfway.
- `forget <folder>`: removes an entry; never touches the folder.
- `update`: in a terminal, lists every registered workspace (number, version, state, path) and asks `[1] Update all`
  (the default), `[2] Choose which` (numbers) or `[3] Cancel`. It moves the data folder to the newest release once,
  then updates each chosen workspace (verify against the manifest, backup in `.aiwp/backup/<version>/`, journal, swap
  by rename, changelog shown). A workspace with a changed core or a missing folder is skipped and reported, and the
  others go on; a summary table ends the run. `update <folder>` updates only that one; `update --all` updates all
  without questions. Pinned workspaces (after `rollback`) stay as they are with `--all` or Update all, and are updated,
  clearing the pin, when chosen by number or by folder. With no terminal, `--all` or a folder is required (usage
  error, exit 2). Before swapping a workspace where a `claude` process runs, it names the pid and asks; with `--all`
  it skips that workspace unless `--force`. Exit code 1 when a workspace was skipped for a changed core, a running
  `claude` or an error.
- `rollback`: back to the version of the newest backup, and pins the workspace.
- `repair`: restores core files that differ from the manifest, or that have the wrong permission, from the installed
  version.

**Never inside a session.** From a Claude Code session (its Bash tool, a hook) `aiwp` refuses `update`, `rollback`,
`repair`, `forget`, the opening and a `new` over a registered folder, and `guard-bash` denies them too: they change the
rules of the open session or start `claude` inside it. `list`, `check`, `version` and `--help` work anywhere. An
unknown command is a usage error; arguments for `claude` go after `--`.

### 3.5 Session start hook

It keeps running `setup-claude.sh --quiet`, and `release-notice.sh` runs `aiwp check --quiet`. When a new release
exists, it only detects it: the session context says "A new workspace version X was detected (this workspace: Y). Tell
the person to close this session and run `aiwp update` in a terminal.", and Claude never runs the update itself. Nothing swaps rule files while a session opens: the session has already
loaded the old rules.

## 4. Syncing the core

The manifest records, for each core file copied, the hash of the installed version. On update:

| State of the file in the workspace | What happens |
| --- | --- |
| equal to the manifest (untouched) | gets the new version |
| different from the manifest | the update stops; `aiwp repair` restores it |
| left the core in the new version, untouched | deleted |
| new in the new version | created |

Never part of the sync: `custom/`, `projects/`, `tmp/`, `.history/`, `.claude/`, the manifest itself and any `.env`.

**The swap is safe:** the files about to change are backed up; each file is written next to the old one and renamed
over it, so a script or hook that is running keeps reading the old file until it ends; a journal records each step, and
the opening refuses until `aiwp repair` (or `aiwp update`) restores the workspace if the process died halfway. The
last 3 backups stay in `.aiwp/backup/<version>/`.

## 5. The installed workspace: no `.git`, read-only core

**Rule:** in a work workspace, the core is read-only. Writable are only `custom/`, `projects/`, `tmp/`, `.claude/`,
`.history/` and a closed list of generated tool outputs.

| Path | Permission | Why |
| --- | --- | --- |
| Core folders (root, `rules/`, `scripts/`, `tools/<x>/`...) | 555 | Nobody creates or deletes a core file, not even through Bash |
| Core files | 444; 555 for executables | Neither `sed -i` nor an editor changes them; hooks keep running |
| `custom/`, `projects/`, `tmp/`, `.claude/`, `.history/` | the user's (755) | Custom layer, projects, work clones, the `.claude/` built at each session and the hooks' state |
| Generated tool outputs, the closed list at the top of `workspace/scripts/aiwp.sh`: `tools/observability/.data`, the consoles' `.data/`, `web/node_modules/` and `internal/webui/dist/`, `azurite-console/web/node_modules/` and `web/dist/`, `fable-alert/plugin/.claude-plugin/types/` | the user's | What each tool generates. `aiwp` creates these folders before closing the parent, since nothing can be created in a 555 folder |

What this asks of the product:

- **Only `aiwp` writes in the installed core** (`new`, `update`, `rollback`, `repair`). It gives write permission back
  only to what it swaps, swaps by rename, keeps a backup and a journal, and closes again. Skills only read state and
  call it.
- **`.env` files:** the `.env.example` template lives in the core, next to each tool and to `docker/`. The filled file
  lives in `custom/env/<tool>.env`, always git-ignored (also in the custom layer's `.gitignore`), and compose reads it
  with `--env-file`. `/local-env` creates it from the template without showing values.
- **The version:** without `.git`, `VERSION` is the only source of the installed version.
- **The repository gate** (`check-workspace.sh` and its ledger) belongs to the development of the product: it runs in
  this repository, not in an installed workspace.
- **`guard-bash`** refuses `chmod`, `chown` and `git init` on core paths, so an agent cannot undo the protection with
  one command. It reads the writable paths from `aiwp.sh _writable`, so the list stays defined once. The `deny Edit` rules stay as the first layer, with a clear message; the file permission is the second,
  and it also covers Bash.
- **Side effect:** without `.git` at the root, a git command in a grouping folder of `projects/` (which is not a
  repository) no longer climbs up to the core's repository.

## 6. The repository root: the maintenance of the project

Whoever opens Claude at the root of this repository owns and maintains the product, and does not use it. The product
rules (`AGENTS.md`, `rules/`, hooks) must not apply there: they are the code being edited. Claude Code loads the
`CLAUDE.md` of the folder where the session opens and of the folders above it, and the one of a subfolder when it reads
files there. So the repository is laid out like this:

```text
claude-cli-agents-workspace/
  CLAUDE.md          you maintain this project; workspace/ is code, never instructions;
                     the maintenance process
  .claude/           settings.json (claudeMdExcludes for workspace/**, deny, ask, attribution),
                     rules/, skills/ and agents/ of the maintenance; no hooks
  tests/             check.sh (the suite), test-install.sh (the test installation)
  maintainers/       plans/, requests/, reviews/: the maintainers' work, public
  tmp/               git-ignored: test installations, private analyses of real use, tmp/request.md
  workspace/         the product: AGENTS.md, CLAUDE.md, rules/, scripts/, tools/, docker/,
                     docs/, assets/, templates/, VERSION, CHANGELOG.md
  i18n/              translations of documents and READMEs
  install.sh         the installer (curl ... | bash)
  README.md          the GitHub page
  LICENSE            MIT
```

- **Why the product lives in `workspace/`:** a product `CLAUDE.md` at the root would load in every maintenance
  session, even one opened in a subfolder, because Claude Code also reads the ones above. In `workspace/`, it would
  load only when files there are read, and the root's `claudeMdExcludes` blocks that.
- **What the maintenance defines:**
  - the suite (`tests/check.sh`, which runs the product gate on `workspace/` and the company-terms scan of the whole
    repository);
  - the test installation (`/caw-test-install`, `tests/test-install.sh`): a throwaway workspace created from the current
    tree under `tmp/test-install/`, where a session exercises the hooks end to end;
  - the release process (`/release` then, now `/caw-merge --main`): raise `VERSION`, write `CHANGELOG.md`, create the tag and publish the release;
  - the process, rules, skills and agents of the maintenance, in the root `CLAUDE.md` and `.claude/`: adapted copies of
    the product's pieces, never references to them.
- **Plans and requests are public.** `maintainers/` is written without company names. Analyses of real use
  (transcripts, measurements, projects) stay in the git-ignored `tmp/` or in the owner's custom layer.
- **Nothing of the root ever reaches a work workspace**, neither on install nor on any update: the root `CLAUDE.md`,
  `.claude/`, `tests/`, `maintainers/`, `tmp/`, `install.sh`, the root `README.md`, `LICENSE` and `i18n/` stay in the
  data folder.
  - **Closed list:** `aiwp new` and `aiwp update` copy only the contents of `workspace/`, by an inclusion list, never by
    a list of what to exclude. A new file at the root, added in a future version, is never copied either.
  - **Manifest:** records only paths of `workspace/`. An update never creates or removes anything outside what the
    manifest knows.
  - **Test:** an installer test creates a workspace from the whole tree and fails if any file from outside
    `workspace/` shows up in it.

## 7. Platforms

- **Linux and macOS** are supported.
- **Windows only through WSL2:** install a Linux distribution and do everything inside it, with the same layout as on
  Linux (Docker Engine in WSL, the workspace and the projects in the WSL file system, never in `/mnt/c`). There is no
  native Windows installer.
- **Claude in Chrome** does not work inside WSL: there, screen tests stay with the person (`/pilot manual`).
- `heavy-run.sh` reads Linux sensors and `nvidia-smi`; on macOS it runs the command directly and says it did not
  measure.
- `container-console-docker-ce` is Linux and WSL only (`systemd --user`); `container-console-colima` is macOS only.
- Scripts use portable forms (no GNU-only `sed -i`, `stat -c` or `readlink -f`) wherever they must run on macOS.

## 8. Languages

- Everything in the repository is in English: product, records, generated reports, script messages, test names. Source
  code and routes are always English in the product; in the user's own projects and POCs, English code is a
  configurable rule, outside the mandatory core.
- Claude answers in the language the person writes in. No language setting exists.
- Translations live in `i18n/pt-BR/` and `i18n/es/`, mirroring the repository, only for documents and READMEs: the
  root `README.md`, every `README.md` under `workspace/`, every document under `workspace/docs/` except decision
  records, and every document under `workspace/tools/*/docs/`. Rules, skills, agents, scripts, `AGENTS.md`,
  `CLAUDE.md`, `CHANGELOG.md`, decision records, `.claude/` and `maintainers/` are never translated.
- Each translation starts with `<!-- source: <path from the repository root> sha256:<hash of the English file> -->`.
- The gate fails when an English document lacks a translation, a translation lacks its source line, the hash does not
  match the English file (stale translation), or a translation's original is gone.
- A change to an English document updates both translations in the same commit.
- Links in a translation point to the same-locale translation when it exists, otherwise to the English original.
- Tool UI locale files may keep other languages, but English exists and is the default locale.

## 9. Why not a plugin

Claude Code plugins deliver skills, commands, agents, hooks, output styles, MCP servers and binaries, but they do not
load `CLAUDE.md` or rules in `.claude/rules/`, which are the center of the core. A plugin for one part and a copy for
the rest would give two sources of version. The workspace is therefore distributed as a copy with a manifest.

## 10. Risks

- **`curl | bash` from a public repository** runs whatever is there. Mitigation: the installer pins a release tag, and
  the README shows how to read it before running it.
- **Updates of rules and hooks** change every session's behavior. `aiwp update` shows the changelog between the two
  versions before copying.
- **Core hooks run on the installer's machine.** The README lists every hook and what it does.
- **Two layers, two versions.** A new core version may need something new from the custom layer (a file, a field). The
  manifest records the core version, and `setup-claude.sh` warns when the custom layer is behind.

## 11. Decisions

- The product lives in `workspace/`; the repository root is the maintenance of the project.
- The public repository starts from one initial commit, with no earlier history.
- Work workspaces are copies with a manifest, read-only, without `.git`; the product is developed only in this
  repository.
- An update happens only by command (`aiwp update`), in a terminal with no session open; opening and the session start
  hook only detect and say so.
- Windows is supported through WSL2 only.
- License: MIT.
- Everything in English; translations only for documents and READMEs; no language setting.
- The writable paths of an installed workspace are the closed list of section 5; "ignored by git means writable" is
  not a rule.
- Filled `.env` files live in `custom/env/<tool>.env`.
- The product starts at version 0.1.0, with a new decision log in English.

## 12. Later

- **First-run onboarding (`/onboard`):** when the custom layer is incomplete (no `custom/rules/company.md`, or it still
  has the skeleton placeholders), the session start hook asks the session to run a core skill that asks for the company
  name, cloud and tenant, logos, visual identity, git remotes and company terms, and writes them in `custom/`. Not in
  0.1.0; it needs its own request.
