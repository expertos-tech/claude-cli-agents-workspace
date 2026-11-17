#!/usr/bin/env bash
# Where the filled .env of a core folder lives. The core holds only the .env.example templates (docker/,
# docker/sonar/, tools/<name>/); the filled file is custom/env/<name>.env, git-ignored by the custom layer, and compose
# reads it with --env-file. Nothing here writes a file. Sourced by sync-env.sh, sonar.sh and validate.sh.

# Prints the name of the filled file of core folder $1 (relative to the workspace root): docker -> docker,
# docker/sonar -> docker-sonar, tools/<name> -> <name>. Fails for any other folder.
env_name() {
  local rel="${1#./}"
  rel="${rel%/}"
  case "$rel" in
    docker) echo docker ;;
    docker/sonar) echo docker-sonar ;;
    tools/*)
      rel="${rel#tools/}"
      [[ "$rel" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || return 1
      echo "$rel" ;;
    *) return 1 ;;
  esac
}

# Prints the path of the filled file of core folder $2 under workspace root $1: <root>/custom/env/<name>.env.
env_file_of() {
  local name
  name="$(env_name "$2")" || return 1
  printf '%s/custom/env/%s.env\n' "$1" "$name"
}

# Prints the file compose reads with --env-file for core folder $2 under root $1: the filled file when it exists,
# else, when $3 is "optional" (the tool works with the defaults), the folder's .env.example, or /dev/null when it has
# none (never a .env of the core). Otherwise fails with a message on stderr that names /local-env.
env_file_for_compose() {
  local root="$1" rel="$2" mode="${3:-required}" file
  file="$(env_file_of "$root" "$rel")" || { echo "error: $rel has no custom/env file" >&2; return 1; }
  if [ -f "$file" ]; then
    printf '%s\n' "$file"
  elif [ "$mode" = optional ] && [ -f "$root/$rel/.env.example" ]; then
    printf '%s\n' "$root/$rel/.env.example"
  elif [ "$mode" = optional ]; then
    echo /dev/null
  else
    echo "error: missing ${file#"$root"/}; create it from $rel/.env.example with /local-env $rel (in a session) or bash scripts/sync-env.sh --path $rel" >&2
    return 1
  fi
}
