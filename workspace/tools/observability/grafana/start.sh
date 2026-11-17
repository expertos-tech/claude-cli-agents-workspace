#!/usr/bin/env bash
# Container command: provisions one Grafana dashboard provider per project, then runs the image's default command.
set -euo pipefail
shopt -s nullglob

readonly PROJECTS_ROOT="/projects"
readonly PROVIDERS_FILE="/otel-lgtm/grafana/conf/provisioning/dashboards/projects.yaml"

# Prints a value as a double-quoted YAML string.
yaml_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "$value"
}

# Prints the provider entry of one project's dashboards folder: path relative to the projects root, then the folder.
# Providers need unique names, and the same project name can exist under two parents, so the name uses the whole path.
# An interval above 10 s makes Grafana poll by timer: at 10 s or less it only reacts to file events, which a bind mount
# can lose, leaving a removed JSON's dashboard in place until the next change in that folder.
print_provider() {
  local relative_path="$1" dashboards_dir="$2"
  cat <<YAML
  - name: $(yaml_quote "project-$relative_path")
    folder: $(yaml_quote "${relative_path##*/}")
    type: file
    disableDeletion: false
    allowUiUpdates: false
    updateIntervalSeconds: 15
    options:
      path: $(yaml_quote "$dashboards_dir")
      foldersFromFilesStructure: false
YAML
}

# Prints the provisioning file, with a provider for each project that has dashboards, in projects/<name>/ or
# projects/<client>/<name>/. A folder without JSON files is skipped because Grafana would create an empty folder for it.
# A first level with .git is a project, never a client, so what looks like projects/<client>/<name>/ is just a subfolder
# of that repo; .git is a file in a worktree or a submodule.
print_providers_file() {
  local dashboards_dir relative_path json_files providers=""
  for dashboards_dir in "$PROJECTS_ROOT"/*/observability/dashboards/ "$PROJECTS_ROOT"/*/*/observability/dashboards/; do
    json_files=("$dashboards_dir"*.json)
    [ "${#json_files[@]}" -gt 0 ] || continue
    relative_path="${dashboards_dir#"$PROJECTS_ROOT"/}"
    relative_path="${relative_path%/observability/dashboards/}"
    if [[ "$relative_path" == */* ]] && [ -e "$PROJECTS_ROOT/${relative_path%%/*}/.git" ]; then
      continue
    fi
    providers+="$(print_provider "$relative_path" "${dashboards_dir%/}")"$'\n'
  done
  if [ -z "$providers" ]; then
    printf 'apiVersion: 1\n\nproviders: []\n'
  else
    printf 'apiVersion: 1\n\nproviders:\n%s' "$providers"
  fi
}

print_providers_file >"$PROVIDERS_FILE"
exec /otel-lgtm/run-all.sh
