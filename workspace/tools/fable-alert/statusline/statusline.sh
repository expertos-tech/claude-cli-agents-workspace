#!/usr/bin/env bash
# Status line: shows the active model; Fable is highlighted as a quota warning.
set -euo pipefail

input=$(cat)
model=$(printf '%s' "$input" | jq -r '.model.display_name // .model.id // "?"')
id=$(printf '%s' "$input" | jq -r '.model.id // ""')
dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // ""')
dir=${dir/#${HOME:-}/\~}
case "$id $model" in
  *[Ff]able*) color='\033[1;97;41m' ;;  # bold white on red
  *)          color='\033[1;36m' ;;     # bold cyan
esac
printf '%b %s %b  %s' "$color" "$model" '\033[0m' "$dir"
