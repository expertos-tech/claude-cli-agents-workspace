#!/usr/bin/env bash
# Creates or completes a filled .env from the .env.example of a folder, never printing values. The filled file of a
# core folder (docker/, docker/sonar/, tools/<name>/) lives in custom/env/<name>.env: no .env is written in the core.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/sync-env.sh --path <dir> [--check] [--help]

Creates the filled file from <dir>/.env.example when missing, or appends the keys of
.env.example that it lacks (with the comment lines right above each key).
Existing keys are never changed, reordered or removed. Prints key names only.

Where the filled file goes:
  docker, docker/sonar, tools/<name>   custom/env/<name>.env of the workspace (docker -> docker.env,
                                       docker/sonar -> docker-sonar.env, tools/<name> -> <name>.env), mode 600 in a
                                       folder of mode 700. custom/ must exist. When custom/ is a git repo whose
                                       .gitignore does not ignore env/, the line env/ is added to custom/.gitignore
                                       first (commit it). Compose reads it with --env-file.
  any other folder (a project, a clone of tmp/work/, a POC)
                                       <dir>/.env, refused when git would track it (a repo without an ignore rule).
Another folder of the core: refused (exit 2); the core never holds a .env.

Options:
  --path <dir>  Folder holding .env.example, relative to the workspace root or absolute.
  --check       Do not write. Exit 1 when the filled file is missing or lacks keys.
  --help        Show this help.

Output: "file: <path>", "result: created|updated|unchanged|out of sync", then "added:", "empty:"
and "same as example:" (a placeholder to replace, or a default to confirm).

Exit codes: 0 ok; 1 --check found drift; 2 usage error, a core folder without a custom/env name, no custom/, or a
.env that git would track.

Examples:
  bash scripts/sync-env.sh --path docker          # custom/env/docker.env
  bash scripts/sync-env.sh --path tools/azurite-console
  bash scripts/sync-env.sh --path tmp/work/2026-11-16-login/billing-api
USAGE
}

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
[ -r "$root/scripts/lib/env.sh" ] || { echo "error: scripts/lib/env.sh not found" >&2; exit 2; }
# shellcheck source=lib/env.sh
. "$root/scripts/lib/env.sh"
dir=""
check=0

while [ $# -gt 0 ]; do
  case "$1" in
    --path)
      [ $# -ge 2 ] || { echo "error: --path needs a value" >&2; exit 2; }
      dir="$2"; shift ;;
    --check) check=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -n "$dir" ] || { echo "error: --path is required" >&2; usage >&2; exit 2; }
case "$dir" in /*) ;; *) dir="$root/$dir" ;; esac
[ -d "$dir" ] || { echo "error: folder not found: $dir" >&2; exit 2; }
dir="$(cd "$dir" && pwd -P)"
example="$dir/.env.example"
[ -f "$example" ] || { echo "error: file not found: $example" >&2; exit 2; }

# The folder relative to the root, or empty when it is outside the workspace.
rel=""
case "$dir/" in "$root"/*) rel="${dir#"$root"}"; rel="${rel#/}" ;; esac
in_core=0
if [ -n "$rel" ] || [ "$dir" = "$root" ]; then
  case "${rel%%/*}" in custom | projects | tmp | .claude | .history | .aiwp) ;; *) in_core=1 ;; esac
fi

umask 077
if [ "$in_core" -eq 1 ]; then
  env_file="$(env_file_of "$root" "$rel")" ||
    { echo "error: ${rel:-.} is in the core, which never holds a .env, and has no custom/env file (only docker, docker/sonar and tools/<name>)" >&2; exit 2; }
  [ -d "$root/custom" ] ||
    { echo "error: custom/ not found: the filled file lives in custom/env/ of the custom layer (aiwp new sets it up)" >&2; exit 2; }
  if [ "$check" -eq 0 ]; then
    if git -C "$root/custom" rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
      ! git -C "$root/custom" check-ignore -q --no-index "env/$(basename "$env_file")"; then
      if [ -s "$root/custom/.gitignore" ] && [ -n "$(tail -c 1 "$root/custom/.gitignore")" ]; then echo >>"$root/custom/.gitignore"; fi
      printf '# Filled .env files: never committed.\nenv/\n' >>"$root/custom/.gitignore"
      echo "added: env/ to custom/.gitignore (commit it in custom/)"
    fi
    mkdir -p "$root/custom/env"
    chmod 700 "$root/custom/env"
  fi
else
  env_file="$dir/.env"
  if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 && ! git -C "$dir" check-ignore -q .env; then
    echo "error: $dir/.env is not git-ignored; add it to .gitignore first" >&2
    exit 2
  fi
fi

# Prints the key of a KEY=value line (optional leading spaces and "export "), or nothing for other lines.
key_of() {
  local line="${1%$'\r'}"
  if [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)= ]]; then
    echo "${BASH_REMATCH[2]}"
  fi
}

# Prints the value of a key in a file (last definition wins), or nothing when absent.
value_of() {
  local file="$1" key="$2" line value="" k
  while IFS= read -r line || [ -n "$line" ]; do
    k="$(key_of "$line")"
    [ "$k" = "$key" ] && value="${line#*=}"
  done <"$file"
  value="${value%$'\r'}"
  printf '%s' "$value"
}

# Prints the keys of a file, one per line, in order.
keys_of() {
  local line k
  while IFS= read -r line || [ -n "$line" ]; do
    k="$(key_of "$line")"
    [ -n "$k" ] && echo "$k"
  done <"$1"
  return 0
}

status="unchanged"
added=()
skipped=()

if [ ! -f "$env_file" ]; then
  if [ "$check" -eq 1 ]; then
    echo "file: ${env_file#"$root"/}"
    echo "result: out of sync (missing)"
    exit 1
  fi
  tr -d '\r' <"$example" >"$env_file"
  status="created"
else
  existing="$(keys_of "$env_file")"
  block=""
  appended=0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    k="$(key_of "$line")"
    if [ -z "$k" ]; then
      # Comment lines accumulate as the block of the next key; blank lines reset it.
      if [[ "$line" =~ ^[[:space:]]*# ]]; then block+="$line"$'\n'; else block=""; fi
      continue
    fi
    if ! grep -qxF "$k" <<<"$existing"; then
      existing+=$'\n'"$k"
      added+=("$k")
      if [ "$check" -eq 0 ]; then
        if [ "$appended" -eq 0 ] && [ -s "$env_file" ] && [ -n "$(tail -c 1 "$env_file")" ]; then
          echo >>"$env_file"
        fi
        printf '%s%s\n' "$block" "$line" >>"$env_file"
        appended=1
      fi
    fi
    block=""
  done <"$example"
  if [ "${#added[@]}" -gt 0 ]; then
    if [ "$check" -eq 1 ]; then
      echo "result: out of sync"
      echo "missing: ${added[*]}"
      exit 1
    fi
    status="updated"
  fi
fi

# Line numbers of .env.example that are neither blank, comment nor KEY=value (never their content).
# Also line numbers of keys defined twice in .env.example (the first definition is the one appended).
n=0
seen=""
duplicated=()
while IFS= read -r line || [ -n "$line" ]; do
  n=$((n + 1))
  line="${line%$'\r'}"
  [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue
  k="$(key_of "$line")"
  if [ -z "$k" ]; then
    skipped+=("$n")
  elif grep -qxF "$k" <<<"$seen"; then
    duplicated+=("$n")
  else
    seen+=$'\n'"$k"
  fi
done <"$example"

empty=()
template=()
while IFS= read -r k; do
  [ -n "$k" ] || continue
  v="$(value_of "$env_file" "$k")"
  if [ -z "$v" ]; then
    empty+=("$k")
  elif [ "$v" = "$(value_of "$example" "$k")" ]; then
    template+=("$k")
  fi
done < <(keys_of "$example" | awk '!seen[$0]++')

echo "file: ${env_file#"$root"/}"
echo "result: $status"
[ "${#added[@]}" -eq 0 ] || echo "added: ${added[*]}"
[ "${#skipped[@]}" -eq 0 ] || echo "not parsed, .env.example lines: ${skipped[*]}"
[ "${#duplicated[@]}" -eq 0 ] || echo "duplicate key, .env.example lines: ${duplicated[*]}"
[ "${#empty[@]}" -eq 0 ] || echo "empty: ${empty[*]}"
[ "${#template[@]}" -eq 0 ] || echo "same as example: ${template[*]}"
[ "$check" -eq 1 ] || chmod 600 "$env_file"
echo "note: load it in the shell with: set -a; source ${env_file#"$root"/}; set +a"
