# Getting started

English · [Português (Brasil)](../i18n/pt-BR/docs/getting-started.md) · [Español](../i18n/es/docs/getting-started.md)

## Requirements

- **Linux or macOS.** On **Windows, only through WSL2**: install a Linux distribution (Ubuntu, for example) and do
  everything inside it, with the same layout as on Linux. The workspace, the projects, Docker and `claude` live in the
  WSL file system (`~/...`), never in `/mnt/c`. There is no native Windows version.
- `git`, `bash`, `python3` and Docker.
- The Claude Code CLI installed and logged in: `claude` opens a session.
- **Optional, but important: the observability stack** (`workspace/tools/observability/`, a local Grafana at
  <http://localhost:3000>). It shows what each session costs in tokens, time and model; without measurement there is no
  way to know whether a rule change made the work better or worse.
- **Recommended: [Claude in Chrome](https://claude.com/chrome)**, the extension that lets Claude open pages in your
  Chrome, click, read the console and take screenshots, so it can check layouts and screen flows by itself
  (`/pilot auto`). It does not work inside WSL: on Windows, those tests stay with you (`/pilot manual`).

## Quick start

### 1. Install and create the workspace

```bash
curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash
```

`curl | bash` runs whatever the script holds at that moment. To read it before running it:

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh
less install.sh
bash install.sh
```

The installer checks the prerequisites and says what is missing, without installing anything on its own. It clones
the repository into your local data folder at the newest release tag, puts the `aiwp` command in `~/.local/bin`, and
then creates your workspace with `aiwp new` and adds it to the registry of workspaces. It needs no administrator
rights and no `sudo`.

It asks where the workspace goes, on the terminal (it works under `curl | bash`), by the folder it runs in:

- **An empty folder:** `1) Install here` or `2) Give another path`.
- **A folder with content:** only the path, of a new or empty folder. A bad answer is asked again.

`aiwp new` then asks for the URL of your custom repository: create an empty private repository on your git server and
give its URL. An empty repository gets a skeleton and a first commit; an empty answer starts a local repository.

To skip the questions, give the folder:

```bash
curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash -s -- ~/my-workspace
AIWP_WORKSPACE=~/my-workspace bash install.sh
```

The argument wins over `AIWP_WORKSPACE`. With no terminal and no folder, the installer installs only the data folder
and prints how to create a workspace later (`aiwp new <folder>`). Running the installer again updates the data folder
and never a workspace: `aiwp update` does that. When the data folder is installed already, the question also offers
to only update it (`3)`, or an empty path).

### 2. Create another workspace

```bash
aiwp new ~/other-workspace
```

Each workspace is a copy of the product in its own folder, and all of them share the installation in the data folder.

### 3. Open it

```bash
cd ~/my-workspace && aiwp
```

`aiwp` checks for a new release and, when there is one, says so and tells you to run `aiwp update`; it never updates.
Then it starts `claude` on the workspace's current version. Always open the session
at the workspace root, even to work on one project: that is where the rules and the hooks apply. The Claude Code auto
mode is recommended: the workspace leaves the judgment of what is destructive to it and keeps in hooks only what must
never happen.

### 4. Bring a project and ask

```bash
git clone <your project url> projects/my-app
git -C projects/my-app switch developer
```

Then, in the session:

```text
in my-app, add a GET /health endpoint that answers 200 with the application version
```

Claude asks only what blocks the start, opens a clone in `tmp/work/<date>-<subject>/my-app/`, tells you the path and
works only there, with tests. Each commit goes to the remote after a secret scan. When it is done:

```text
/merge <date>-<subject>/my-app
```

The gate brings the updated `developer`, runs the whole suite and the validations, scans for secrets, shows what leaves
the base and asks for a review against your request. You are asked only if something shows up that the request does
not explain. For larger requests, write the request with `/draft-prompt` and run it with `/prompt`. The full guide is
[workspace/docs/usage.md](../workspace/docs/usage.md).
