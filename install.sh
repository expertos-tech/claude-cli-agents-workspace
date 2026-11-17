#!/usr/bin/env bash
# Installer of Claude CLI Agents Workspace: clones the repository into the local data folder at the newest release
# tag, links the aiwp command into ~/.local/bin and creates a workspace (aiwp new). Needs no administrator rights;
# installs no package. Under curl | bash its input is the script itself, so the questions read the terminal (/dev/tty).
# Run: curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash
set -euo pipefail

# Prints folder $1 as an absolute path: ~ expanded, a relative path taken from the current folder.
abs_path() {
  # shellcheck disable=SC2088  # the literal ~ a person types, expanded here
  case "$1" in
    "~") echo "$HOME" ;;
    "~/"*) echo "$HOME/${1#"~/"}" ;;
    /*) echo "$1" ;;
    *) echo "$PWD/$1" ;;
  esac
}

# Prints why folder $1 cannot hold a new workspace, or nothing when it can: a missing folder or an empty one.
folder_problem() {
  if [ -e "$1" ] || [ -L "$1" ]; then
    if [ ! -d "$1" ]; then
      echo "$1 exists and is not a folder"
    elif [ -n "$(ls -A "$1" 2>/dev/null)" ]; then
      echo "$1 is not empty"
    fi
  fi
  case "$1" in *$'\t'* | *$'\n'* | *$'\r'*) echo "a folder name with a tab or a line break is not supported" ;; esac
}

# Asks on the terminal (/dev/tty) for a new or empty folder until the answer is one; sets WORKSPACE_DIR. $1 = 1 when
# an installation exists: an empty answer then only updates it (WORKSPACE_DIR stays empty). Fails when the terminal
# closes (Ctrl-D).
ask_folder() {
  local installed="$1" answer path problem hint=""
  [ "$installed" -eq 0 ] || hint="; empty: only update the installation"
  while :; do
    printf 'Folder of the new workspace (a new or an empty folder%s): ' "$hint" >/dev/tty
    IFS= read -r answer </dev/tty || { echo >/dev/tty; return 1; }
    if [ -z "$answer" ]; then
      [ "$installed" -eq 0 ] || return 0
      continue
    fi
    path="$(abs_path "$answer")"
    problem="$(folder_problem "$path")"
    if [ -z "$problem" ]; then
      WORKSPACE_DIR="$path"
      return 0
    fi
    echo "$problem: give a new or an empty folder." >/dev/tty
  done
}

# Asks where to create the workspace, by the current folder: an empty one offers itself or another path; one with
# content asks for the path. $1 = 1 when an installation exists: then it also offers to only update it. Sets
# WORKSPACE_DIR (empty: no new workspace); fails when the terminal closes.
ask_workspace() {
  local installed="$1" here answer last=2
  here="$(pwd -P)"
  if [ -n "$(folder_problem "$here")" ]; then
    echo "This folder is not empty ($here): the workspace goes into a new or an empty folder." >/dev/tty
    ask_folder "$installed"
    return
  fi
  {
    echo "Where to create the workspace?"
    echo "  1) Install here: $here"
    echo "  2) Give another path"
    if [ "$installed" -eq 1 ]; then echo "  3) No new workspace: only update the installation"; fi
  } >/dev/tty
  [ "$installed" -eq 0 ] || last=3
  while :; do
    printf 'Choose [1-%s]: ' "$last" >/dev/tty
    IFS= read -r answer </dev/tty || { echo >/dev/tty; return 1; }
    case "$answer" in
      1) WORKSPACE_DIR="$here"; return 0 ;;
      2) ask_folder "$installed"; return ;;
      3) if [ "$installed" -eq 1 ]; then return 0; fi; echo "Answer 1 or 2." >/dev/tty ;;
      *) if [ "$installed" -eq 1 ]; then echo "Answer 1, 2 or 3." >/dev/tty; else echo "Answer 1 or 2." >/dev/tty; fi ;;
    esac
  done
}

# Takes the update lock that aiwp update holds (file $1, flock on descriptor 9), so the data folder never moves under
# a running update; released when the descriptor closes or the installer ends. Fails when an update runs. From then
# on git runs with 9>&-: a child it leaves running (gc, maintenance, fsmonitor) must not keep the lock.
update_lock() {
  local file="$1" pid rc=0
  mkdir -p "$(dirname "$file")"
  exec 9>>"$file" || { echo "error: cannot take the lock $file" >&2; return 1; }
  python3 -I -c 'import fcntl, sys
try:
    fcntl.flock(9, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    sys.exit(1)
except OSError as error:
    print(f"error: flock failed: {error}", file=sys.stderr)
    sys.exit(2)' || rc=$?
  if [ "$rc" -ne 0 ]; then
    exec 9>&-
    if [ "$rc" -ne 1 ]; then
      echo "error: cannot lock $file" >&2
      return 1
    fi
    pid="$(head -n 1 "$file" 2>/dev/null | tr -cd '0-9')" || pid=""
    echo "error: an aiwp update is running (pid ${pid:-unknown}); nothing was changed; run the installer again when it ends" >&2
    return 1
  fi
  echo "$$" >"$file"
}

# The whole installer is one function, read in full before it runs: a pipe from curl that stops halfway runs nothing.
install_main() {
  local default_url="https://github.com/expertos-tech/claude-cli-agents-workspace.git"
  local url="${AIWP_REPO_URL:-$default_url}"
  local os data ref bin link target missing="" tool tty=0 problem installed=0
  WORKSPACE_DIR=""

  case "${1:-}" in
    --help | -h)
      cat <<'HELP'
Usage: bash install.sh [<workspace folder>] [--help]
       curl -fsSL <installer URL> | bash [-s -- <workspace folder>]

Installs or updates Claude CLI Agents Workspace for the current user, then creates a workspace:
  1. checks the prerequisites: git and python3 are required; docker and claude are recommended. It installs nothing.
  2. clones the full repository into the local data folder, or fetches it when it is already there, and checks out
     the newest release tag vX.Y.Z:
       Linux and WSL  ${XDG_DATA_HOME:-~/.local/share}/claude-cli-agents-workspace
       macOS          ~/Library/Application Support/claude-cli-agents-workspace
  3. links ~/.local/bin/aiwp to the aiwp command of that folder, and says how to put ~/.local/bin on PATH.
  4. creates the workspace with aiwp new <folder> (which also asks for the custom layer's repository) and adds it to
     the registry of workspaces. The folder: the argument, else AIWP_WORKSPACE, else a question on the terminal
     (/dev/tty, which works under curl | bash): in an empty current folder, 1) install here or 2) give another
     path; in a folder with content, only the path. The folder must be new or empty; a bad answer is asked again.
     When the data folder is installed already, the question also offers to only update it (3, or an empty path).
     With no terminal and no folder given, only the data folder is installed, and it says how to create one.
Running it again updates the data folder; it never updates a workspace (aiwp update does, in a terminal). Native
Windows shells (Git Bash, MSYS, Cygwin) are refused: use WSL2. Nothing needs sudo.

Environment:
  AIWP_WORKSPACE  the folder of the new workspace, with no question (the argument wins over it)
  AIWP_REF        check out this ref (a tag, a branch or a commit) instead of the newest release tag
  AIWP_REPO_URL   clone from this URL instead of the public repository
  AIWP_OS         linux, macos or windows: the platform to assume (tests)

Exit codes: 0 installed; 1 a prerequisite is missing, the folder is not new or empty, or a step failed; 2 usage
error.

Examples:
  curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/expertos-tech/claude-cli-agents-workspace/main/install.sh | bash -s -- ~/my-workspace
  AIWP_WORKSPACE=~/my-workspace bash install.sh </dev/null
HELP
      return 0 ;;
    -*) echo "error: unknown option: $1; see --help" >&2; return 2 ;;
  esac
  [ $# -le 1 ] || { echo "error: one workspace folder only; see --help" >&2; return 2; }

  os="${AIWP_OS:-}"
  if [ -z "$os" ]; then
    case "$(uname -s)" in
      Linux) os=linux ;;
      Darwin) os=macos ;;
      MINGW* | MSYS* | CYGWIN*) os=windows ;;
      *) os=unknown ;;
    esac
  fi
  case "$os" in
    linux) data="${XDG_DATA_HOME:-$HOME/.local/share}/claude-cli-agents-workspace" ;;
    macos) data="$HOME/Library/Application Support/claude-cli-agents-workspace" ;;
    windows)
      echo "error: native Windows shells are not supported. Install WSL2 with a Linux distribution and run the" >&2
      echo "installer inside it: https://learn.microsoft.com/windows/wsl/install" >&2
      return 1 ;;
    *) echo "error: unsupported platform: $(uname -s); Linux, macOS and WSL2 are supported" >&2; return 1 ;;
  esac

  for tool in git python3; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
  done
  if [ -n "$missing" ]; then
    echo "error: missing prerequisites:$missing. Install them with your package manager and run the installer again." >&2
    return 1
  fi
  for tool in docker claude; do
    command -v "$tool" >/dev/null 2>&1 ||
      echo "warning: $tool not found: the workspace needs it (docker for the validations, claude to open sessions)"
  done

  # The workspace folder, asked before anything is installed: a run cancelled at the question changes nothing.
  if (exec </dev/tty) 2>/dev/null; then tty=1; fi
  if [ -n "${1:-}" ] || [ -n "${AIWP_WORKSPACE:-}" ]; then
    WORKSPACE_DIR="$(abs_path "${1:-$AIWP_WORKSPACE}")"
    problem="$(folder_problem "$WORKSPACE_DIR")"
    if [ -n "$problem" ]; then
      echo "error: $problem: the workspace goes into a new or an empty folder; nothing was installed" >&2
      return 1
    fi
  elif [ "$tty" -eq 1 ]; then
    if [ -d "$data/.git" ]; then installed=1; fi
    ask_workspace "$installed" || { echo "error: no answer; nothing was installed" >&2; return 1; }
  fi


  export GIT_TERMINAL_PROMPT=0
  if [ -d "$data/.git" ]; then
    echo "updating: $data"
    git -C "$data" remote set-url origin "$url"
    git -C "$data" fetch --quiet --tags --force --prune origin
  elif [ -e "$data" ] && [ -n "$(ls -A "$data" 2>/dev/null)" ]; then
    echo "error: $data exists and is not an installation; move it away and run the installer again" >&2
    return 1
  else
    echo "cloning: $url -> $data"
    mkdir -p "$(dirname "$data")"
    git clone --quiet -- "$url" "$data"
  fi

  # aiwp update moves the data folder and then each workspace to it: hold its lock while moving the data folder.
  update_lock "$data/.git/aiwp/update.lock" || return 1

  if [ -n "$(git 9>&- -C "$data" status --porcelain --untracked-files=no)" ]; then
    echo "error: the installation has local changes, and nobody edits it: $data" >&2
    echo "discard them (git -C \"$data\" checkout -- .) and run the installer again" >&2
    return 1
  fi

  ref="${AIWP_REF:-}"
  if [ -z "$ref" ]; then
    ref="$(git 9>&- -C "$data" tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' |
      sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)" || true
    [ -n "$ref" ] || { echo "error: no release tag vX.Y.Z in $url; set AIWP_REF to install a branch" >&2; return 1; }
    ref="v$ref"
  fi
  target="$ref"
  if git 9>&- -C "$data" rev-parse -q --verify "refs/remotes/origin/$ref^{commit}" >/dev/null; then
    target="origin/$ref"
  fi
  git 9>&- -C "$data" rev-parse -q --verify "$target^{commit}" >/dev/null ||
    { echo "error: $ref is not a tag, branch or commit of $url" >&2; return 1; }
  git 9>&- -C "$data" checkout --quiet --detach "$target"
  echo "checked out: $ref ($(cat "$data/workspace/VERSION" 2>/dev/null || echo 'no VERSION'))"

  [ -f "$data/workspace/scripts/aiwp.sh" ] ||
    { echo "error: $ref has no workspace/scripts/aiwp.sh; it predates the installer" >&2; return 1; }
  bin="$HOME/.local/bin"
  link="$bin/aiwp"
  mkdir -p "$bin"
  if [ -e "$link" ] && [ ! -L "$link" ]; then
    echo "error: $link exists and is not a link to aiwp; move it away and run the installer again" >&2
    return 1
  fi
  ln -sfn "$data/workspace/scripts/aiwp.sh" "$link"
  echo "linked: $link -> $data/workspace/scripts/aiwp.sh"
  exec 9>&-

  case ":${PATH:-}:" in
    *":$bin:"*) ;;
    *)
      echo "warning: $bin is not on PATH. Add this line to your shell profile (~/.bashrc, ~/.zshrc) and open a new shell:"
      echo "  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
  esac

  if [ -z "$WORKSPACE_DIR" ] && [ "$installed" -eq 1 ]; then
    echo
    echo "Updated the installation; no new workspace. Update your workspaces with: aiwp update"
    return 0
  fi
  if [ -z "$WORKSPACE_DIR" ]; then
    cat <<NEXT

Installed the data folder only: no terminal to ask, and no workspace folder given. Create a workspace with:
  aiwp new ~/my-workspace
  cd ~/my-workspace && aiwp
(or run the installer again with AIWP_WORKSPACE=<folder>, or with bash -s -- <folder> under curl)
NEXT
    return 0
  fi
  echo
  echo "creating the workspace: $WORKSPACE_DIR"
  # aiwp new asks for the custom layer's repository on the terminal; never on the pipe that holds this script.
  if [ "$tty" -eq 1 ]; then
    bash "$data/workspace/scripts/aiwp.sh" new "$WORKSPACE_DIR" </dev/tty || return 1
  else
    bash "$data/workspace/scripts/aiwp.sh" new "$WORKSPACE_DIR" </dev/null || return 1
  fi
}

install_main "$@"
exit $?
