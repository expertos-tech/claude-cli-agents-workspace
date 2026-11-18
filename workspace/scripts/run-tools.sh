#!/usr/bin/env bash
# Lists, starts and stops the workspace's local tools: the work behind /run-tools. The logic is in run-tools.py, next
# to this file; this script validates the command line and runs it from the workspace root.
set -euo pipefail

# Prints the command reference.
usage() {
  cat <<'USAGE'
Usage: bash scripts/run-tools.sh list [--json] | status | up <tool>... | down <tool>... | --help

The container tools are the ones tools/compose.yaml includes, all in one compose project, claude-cli-agents-tools, so
the container console shows them as one group; title, description and URL come from the x-run-tools block of each
tool's main service. The container console of this machine is a machine service, not a container:
container-console-docker-ce on Linux and WSL with Docker Engine (docker-ce), container-console-colima on macOS with
colima installed. A tool's configuration comes from custom/: custom/env/<tool>.env (passed with --env-file) and
custom/config/<tool>/.

  list [--json]  The tools of this machine: id, title, description, URL, kind (compose or machine), state (up, stopped,
                 not installed), the project a container tool still runs in, ports, and what keeps it from starting
                 (configuration missing in custom/, a busy port, a tool needed to install a console). Without --json,
                 the same as status.
  status         The same list as a Markdown table.
  up <tool>...   Starts the tools named. A container tool that lacks configuration or a port is refused with the reason,
                 and the others still start. Before the build, the current image of each service gets the tags
                 <name>:rollback-latest and <name>:rollback-<yyyymmdd-hhmmss> (the newest 3 kept). A tool still running
                 in its own old project (its folder's compose.yaml) moves into the group: it stops, each named volume
                 is copied to the group's name and the old volume is kept (deleting it is for the person to confirm),
                 then the old containers and networks go. When another stack uses one of its fixed networks, the tool
                 is refused before anything changes. Then docker compose up -d --build --wait for those tools only, and
                 the console service is started (installed with make install when missing). Ends with the table of
                 the tools named. A tool already up and not named is never touched.
  down <tool>... Stops the tools named (docker compose stop; systemctl --user stop or launchctl bootout for a console).
                 Never removes a container, a volume or an image.

Exit: 0 done; 1 a tool refused or failed (the others still ran); 2 usage error or a tool this machine does not list.

Examples:
  bash scripts/run-tools.sh list --json
  bash scripts/run-tools.sh up observability login-simulator
  bash scripts/run-tools.sh down login-simulator
USAGE
}

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
root="$(cd "$here/.." && pwd -P)"

[ $# -ge 1 ] || {
  usage >&2
  exit 2
}
case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  list)
    [ $# -eq 1 ] || { [ $# -eq 2 ] && [ "$2" = --json ]; } || {
      echo "error: usage: list [--json]" >&2
      exit 2
    }
    ;;
  status)
    [ $# -eq 1 ] || {
      echo "error: status takes no argument" >&2
      exit 2
    }
    ;;
  up | down)
    [ $# -ge 2 ] || {
      echo "error: usage: $1 <tool>... (the ids of list --json)" >&2
      exit 2
    }
    for id in "${@:2}"; do
      [[ "$id" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || {
        echo "error: not a tool id: $id" >&2
        exit 2
      }
    done
    ;;
  *)
    echo "error: unknown command: $1 (see --help)" >&2
    exit 2
    ;;
esac
command -v python3 >/dev/null 2>&1 || {
  echo "error: python3 not found" >&2
  exit 1
}
exec python3 -I -B "$here/run-tools.py" "$root" "$@"
