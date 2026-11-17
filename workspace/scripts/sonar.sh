#!/usr/bin/env bash
# Manages the optional local SonarQube (docker/sonar/) and scans a workspace folder.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/sonar.sh <up|down|status|scan> [--key <project-key>] [--path <dir>] [--help]

Commands:
  up       Start SonarQube and its database (http://127.0.0.1:29000). Needs custom/env/docker-sonar.env.
  down     Stop them (data volumes kept).
  status   Print the server status.
  scan     Analyze a folder. Needs SONAR_TOKEN in custom/env/docker-sonar.env and --key. The folder is mounted
           read-only; the scanner's working folder (.scannerwork) stays in the container's /tmp.

The variables come from custom/env/docker-sonar.env, the filled copy of docker/sonar/.env.example in the custom
layer, passed to compose with --env-file. Create it with /local-env docker/sonar in a session, or
bash scripts/sync-env.sh --path docker/sonar.

Options:
  --key <project-key>  Sonar project key (kebab-case), required by scan.
  --path <dir>         Folder to scan, relative to the workspace root. Default: workspace root.
                       A sonar-project.properties inside it is honored (coverage report paths, exclusions).
  --help               Show this help.

Example:
  bash scripts/sync-env.sh --path docker/sonar && scripts/sonar.sh up
  scripts/sonar.sh scan --key billing --path projects/billing
USAGE
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -r "$root/scripts/lib/env.sh" ] || { echo "error: scripts/lib/env.sh not found" >&2; exit 2; }
# shellcheck source=lib/env.sh
. "$root/scripts/lib/env.sh"
compose_file="$root/docker/sonar/compose.yaml"
cmd="${1:-}"
[ -n "$cmd" ] || { usage >&2; exit 2; }
case "$cmd" in --help|-h) usage; exit 0 ;; esac
shift
key=""
target="."

while [ $# -gt 0 ]; do
  case "$1" in
    --key|--path)
      [ $# -ge 2 ] || { echo "error: $1 needs a value" >&2; exit 2; }
      case "$1" in
        --key) key="$2" ;;
        --path) target="$2" ;;
      esac
      shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

env_file=""

# Sets env_file to custom/env/docker-sonar.env, or stops with the message that names /local-env.
require_env() {
  env_file="$(env_file_for_compose "$root" docker/sonar)" || exit 2
}

# Runs docker compose against the Sonar stack with the workspace mounted read-only. Without the filled file (down),
# the template gives compose the variables it interpolates.
compose() {
  local file="$env_file"
  [ -n "$file" ] || file="$(env_file_for_compose "$root" docker/sonar optional)"
  WORKSPACE_DIR="$root" docker compose --progress quiet --env-file "$file" -f "$compose_file" "$@"
}

case "$cmd" in
  up) require_env; compose up -d sonarqube && echo "SonarQube starting at http://127.0.0.1:29000" ;;
  down) compose down ;;
  status) curl -fsS http://127.0.0.1:29000/api/system/status || { echo "SonarQube not reachable"; exit 1; } ;;
  scan)
    require_env
    grep -q -E '^SONAR_TOKEN=.+' "$env_file" || { echo "error: set SONAR_TOKEN in custom/env/docker-sonar.env" >&2; exit 2; }
    [[ "$key" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { echo "error: --key must be kebab-case" >&2; exit 2; }
    target="${target#./}"; target="${target%/}"; [ -n "$target" ] || target="."
    case "$target" in /*|..|../*|*/..|*/../*) echo "error: --path must be relative, without '..'" >&2; exit 2 ;; esac
    [ -d "$root/$target" ] || { echo "error: folder not found: $target" >&2; exit 2; }
    compose --profile scan run --rm -T sonar-scanner \
      -Dsonar.projectKey="$key" \
      -Dsonar.projectBaseDir="/usr/src/$target" \
      -Dsonar.working.directory=/tmp/scannerwork \
      -Dsonar.qualitygate.wait=true 2>&1 | { grep -E "QUALITY GATE|ERROR|EXECUTION (SUCCESS|FAILURE)|ANALYSIS SUCCESSFUL" || true; }
    exit "${PIPESTATUS[0]}" ;;
  *) echo "error: unknown command: $cmd" >&2; usage >&2; exit 2 ;;
esac
