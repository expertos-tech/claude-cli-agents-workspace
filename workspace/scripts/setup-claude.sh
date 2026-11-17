#!/usr/bin/env bash
# Generates the local .claude/ folder from the versioned sources in rules/agents/, rules/skills/, rules/*.md and
# AGENTS.md, with the rules configuration of the custom layer (custom/rules-config.json, custom/my-rules/) applied by
# scripts/rules-config.py.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/setup-claude.sh [--check] [--quiet] [--custom-repo <url>] [--root <dir>] [--help]

Creates or syncs .claude/ (git-ignored) from rules/ and the custom layer (versioned):
  AGENTS.md                  -> .claude/AGENTS.md     (the effective one, which CLAUDE.md imports: a rule turned off
                                is no longer named, a replaced one points to its own file)
  rules/agents/*.md          -> .claude/agents/*.md   (stale agents removed)
  rules/agents/settings.json -> .claude/settings.json (plus, in its claudeMdExcludes, the absolute path of each
                                line of custom/claude-md-excludes.txt: instruction files a team keeps in a project,
                                which the workspace must not load; one path or glob relative to the workspace root
                                per line, inside projects/<repo>/ or custom/pocs/<poc>/ only, # and blank lines
                                ignored, any other line skipped with a warning)
  rules/skills/<name>/**     -> .claude/skills/<name>/** (stale files removed)
  rules/*.md with `paths:`   -> .claude/rules/*.md    (path-scoped rules; a rule that loses its
                                front matter or is deleted makes its copy stale)
  custom/my-rules/*.md       -> .claude/rules/custom-*.md (every one: with `paths:` it loads by path,
                                without it loads in every session; a deleted source makes its copy stale)
  custom/my-rules/skills/<name>/ -> .claude/skills/custom-<name>/
  custom/my-rules/agents/<name>.md -> .claude/agents/custom-<name>.md (name: set to custom-<name>; an own skill or
                                agent keeps no front matter key that runs or allows anything: no hooks, no
                                permission mode, no tool grant)
custom/rules-config.json turns core rules, skills and agents off (core.<kind>.exclude) and replaces a core rule
with an own one (replace); the mandatory core of rules/manifest.json always loads, with a warning. A wrong
configuration never fails the setup: it warns and the rest loads (python3 -I -B scripts/rules-config.py --help).
custom/ is the custom layer: a git repo of its own, ignored by the workspace repo, with what belongs to
one company and its projects. Name no rule of rules/ custom-*.md: that prefix is the custom layer's.
Personal overrides belong in .claude/settings.local.json (never touched).
Where deletion is not allowed (Cowork folders), stale files move to .claude/.removed/.

Options:
  --check        Do not write. Exit 1 if .claude/ is missing or out of sync.
  --quiet        Print only what needs attention (the SessionStart hook runs it this way).
  --custom-repo <url>
                 Clone that git repo into custom/ when the folder is missing. Without it, a terminal run
                 asks for the URL; a run with no terminal prints one attention: line and goes on.
  --root <dir>   Workspace root. Default: parent of this script's folder.
  --help         Show this help.

Example:
  scripts/setup-claude.sh --check || scripts/setup-claude.sh
USAGE
}

check=0
quiet=0
custom_repo=""
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --check) check=1 ;;
    --quiet) quiet=1 ;;
    --custom-repo)
      [ $# -ge 2 ] || { echo "error: --custom-repo needs a value" >&2; exit 2; }
      custom_repo="$2"
      shift ;;
    --root)
      [ $# -ge 2 ] || { echo "error: --root needs a value" >&2; exit 2; }
      root="$(cd "$2" 2>/dev/null && pwd)" || { echo "error: --root is not a folder: $2" >&2; exit 2; }
      shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# --quiet: the run prints only the lines that need the human (attention: and warning lines).
if [ "$quiet" -eq 1 ] && [ -z "${SETUP_CLAUDE_FILTERED:-}" ]; then
  args=(--quiet --root "$root")
  [ "$check" -eq 0 ] || args+=(--check)
  [ -z "$custom_repo" ] || args+=(--custom-repo "$custom_repo")
  rc=0
  out="$(SETUP_CLAUDE_FILTERED=1 bash "${BASH_SOURCE[0]}" "${args[@]}" 2>&1)" || rc=$?
  printf '%s\n' "$out" | grep -E '^(attention|warning|error|cloned):' || true
  exit "$rc"
fi

src="$root/rules/agents"
dst="$root/.claude"
[ -d "$src" ] || { echo "error: source folder not found: $src" >&2; exit 2; }

drift=0

# The custom layer lives in custom/, a git repo of its own that the workspace repo ignores. When the folder is
# missing: clones the repo given with --custom-repo, else asks for its URL on a terminal, else says how to get it.
# Runs before the sync, so a fresh clone is copied in the same run. A folder that exists is never touched, and a
# failed clone never fails the setup.
setup_custom_repo() {
  local dir="$root/custom" url="$custom_repo"
  [ ! -e "$dir" ] || return 0
  [ "$check" -eq 0 ] || { echo "attention: custom/ is missing; run scripts/setup-claude.sh on a terminal to clone it"; return 0; }
  if [ -z "$url" ] && [ -t 0 ] && [ -t 1 ]; then
    printf 'custom/ is missing. Git URL of the custom layer repo (empty to skip): '
    IFS= read -r url || url=""
  fi
  if [ -z "$url" ]; then
    echo "attention: custom/ is missing; run scripts/setup-claude.sh --custom-repo <url>, or on a terminal to be asked"
    return 0
  fi
  if git clone -q -- "$url" "$dir" 2>&1; then
    echo "cloned: custom/"
  else
    echo "attention: could not clone the custom layer repo into custom/"
  fi
}

setup_custom_repo

# The rules configuration: scripts/rules-config.py writes into a staging folder the effective AGENTS.md, the own
# items of custom/my-rules/ (custom-*) and the list of core items that must not load. When it cannot run, the whole
# core loads, AGENTS.md as it is, and no own item.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
if ! python3 -I -B "$(dirname "${BASH_SOURCE[0]}")/rules-config.py" --root "$root" build --out "$stage"; then
  echo "warning: scripts/rules-config.py failed: the whole core loads, without the own rules of custom/my-rules/" >&2
  rm -rf "${stage:?}"/* 2>/dev/null || true
  [ ! -f "$root/AGENTS.md" ] || cp "$root/AGENTS.md" "$stage/AGENTS.md"
  : >"$stage/skip"
fi
[ -f "$stage/skip" ] || : >"$stage/skip"

# Succeeds when the core item $2 of kind $1 (rules, skills, agents) must not load.
skipped() {
  grep -qxF -- "$1 $2" "$stage/skip"
}

# Removes a stale generated file; where deletion is not allowed (Cowork folders), moves it to .claude/.removed/.
remove_stale() {
  local f="$1" rel="${1#"$dst"/}"
  if rm "$f" 2>/dev/null; then
    echo "removed: ${f#"$root"/}"
    return 0
  fi
  mkdir -p "$dst/.removed/$(dirname "$rel")"
  mv "$f" "$dst/.removed/$rel.$(date +%Y%m%d%H%M%S).$$"
  echo "moved aside (deletion not allowed): ${f#"$root"/} -> .claude/.removed/"
}

# Reports or applies one file copy; sets drift when the target is missing or differs.
sync_file() {
  local from="$1" to="$2"
  if [ -f "$to" ] && cmp -s "$from" "$to"; then
    return 0
  fi
  drift=1
  if [ "$check" -eq 1 ]; then
    echo "out of sync: ${to#"$root"/}"
  else
    # The source is read-only in an installed workspace (444): the copy is made writable, and an old copy is
    # removed first, so the next sync can replace it.
    mkdir -p "$(dirname "$to")"
    rm -f "$to"
    cp "$from" "$to"
    chmod u+w "$to"
    echo "written: ${to#"$root"/}"
  fi
}

if [ -f "$stage/AGENTS.md" ]; then
  sync_file "$stage/AGENTS.md" "$dst/AGENTS.md"
fi

for f in "$src"/*.md; do
  [ -e "$f" ] || continue
  name="$(basename "$f")"
  case "$name" in
    custom-*) echo "warning: rules/agents/$name not copied: the custom- prefix belongs to the custom layer" >&2; continue ;;
  esac
  skipped agents "${name%.md}" && continue
  sync_file "$f" "$dst/agents/$name"
done

for f in "$stage/agents"/*.md; do
  [ -e "$f" ] || continue
  sync_file "$f" "$dst/agents/$(basename "$f")"
done

# Succeeds when the generated agent file name $1 has a source: an own agent in the staging folder, or a core agent
# that loads.
agent_has_source() {
  case "$1" in
    custom-*) [ -f "$stage/agents/$1" ] ;;
    *) [ -f "$src/$1" ] && ! skipped agents "${1%.md}" ;;
  esac
}

if [ -d "$dst/agents" ]; then
  for f in "$dst/agents"/*.md; do
    [ -e "$f" ] || continue
    if ! agent_has_source "$(basename "$f")"; then
      drift=1
      if [ "$check" -eq 1 ]; then
        echo "stale: ${f#"$root"/}"
      else
        remove_stale "$f"
      fi
    fi
  done
fi

skills_src="$root/rules/skills"
skills_dst="$dst/skills"

if [ -d "$skills_src" ]; then
  while IFS= read -r f; do
    rel="${f#"$skills_src"/}"
    case "$rel" in
      custom-*) echo "warning: rules/skills/$rel not copied: the custom- prefix belongs to the custom layer" >&2; continue ;;
    esac
    skipped skills "${rel%%/*}" && continue
    sync_file "$f" "$skills_dst/$rel"
  done < <(find "$skills_src" -type f ! -name '.DS_Store' | sort)
fi

if [ -d "$stage/skills" ]; then
  while IFS= read -r f; do
    sync_file "$f" "$skills_dst/${f#"$stage/skills"/}"
  done < <(find "$stage/skills" -type f | sort)
fi

# Succeeds when the generated skill file $1 (relative to .claude/skills/) has a source: an own skill in the staging
# folder, or a core skill that loads.
skill_has_source() {
  case "$1" in
    custom-*) [ -f "$stage/skills/$1" ] ;;
    *) [ -f "$skills_src/$1" ] && ! skipped skills "${1%%/*}" ;;
  esac
}

if [ -d "$skills_dst" ]; then
  while IFS= read -r f; do
    if ! skill_has_source "${f#"$skills_dst"/}"; then
      drift=1
      if [ "$check" -eq 1 ]; then
        echo "stale: ${f#"$root"/}"
      else
        remove_stale "$f"
      fi
    fi
  done < <(find "$skills_dst" -type f ! -name '.DS_Store' | sort)
  if [ "$check" -eq 0 ]; then
    find "$skills_dst" -mindepth 1 -type d -empty -delete 2>/dev/null || true
  fi
fi

# Succeeds when the file opens with a YAML front matter block (first line ---) holding a paths: field.
has_paths_front_matter() {
  local line first=1
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$first" -eq 1 ]; then
      [ "$line" = "---" ] || return 1
      first=0
    elif [ "$line" = "---" ]; then
      return 1
    elif [ "${line#paths:}" != "$line" ]; then
      return 0
    fi
  done <"$1"
  return 1
}

rules_src="$root/rules"
rules_dst="$dst/rules"

for f in "$rules_src"/*.md; do
  [ -e "$f" ] || continue
  case "$(basename "$f")" in
    custom-*) echo "warning: rules/$(basename "$f") not copied: the custom- prefix belongs to the custom layer" >&2; continue ;;
  esac
  has_paths_front_matter "$f" || continue
  skipped rules "$(basename "$f")" && continue
  sync_file "$f" "$rules_dst/$(basename "$f")"
done

if [ -d "$rules_dst" ]; then
  for f in "$rules_dst"/*.md; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in custom-*) continue ;; esac
    if [ ! -f "$rules_src/$(basename "$f")" ] || ! has_paths_front_matter "$rules_src/$(basename "$f")" ||
      skipped rules "$(basename "$f")"; then
      drift=1
      if [ "$check" -eq 1 ]; then
        echo "stale: ${f#"$root"/}"
      else
        remove_stale "$f"
      fi
    fi
  done
fi

# The custom layer's rules, from the staging folder: every own rule of custom/my-rules/<name>.md is
# .claude/rules/custom-<name>.md there, and so is a replacement of a core rule that loads by path.
for f in "$stage/rules"/custom-*.md; do
  [ -e "$f" ] || continue
  sync_file "$f" "$rules_dst/$(basename "$f")"
done

for f in "$rules_dst"/custom-*.md; do
  [ -e "$f" ] || continue
  name="$(basename "$f")"
  if [ ! -f "$stage/rules/$name" ]; then
    drift=1
    if [ "$check" -eq 1 ]; then
      echo "stale: ${f#"$root"/}"
    else
      remove_stale "$f"
    fi
  fi
done

# Prints the settings with the claudeMdExcludes of custom/claude-md-excludes.txt added, as absolute patterns (the form
# Claude Code matches), for the root as given and, when it differs, as resolved.
merged_settings() {
  python3 -I - "$1" "$2" "$root" <<'PY_EXCLUDES'
import json
import os
import sys

settings_path, excludes_path, root = sys.argv[1:4]
with open(settings_path, encoding='utf-8') as handle:
    settings = json.load(handle)
roots = [root] + ([os.path.realpath(root)] if os.path.realpath(root) != root else [])
patterns = list(settings.get('claudeMdExcludes') or [])
with open(excludes_path, encoding='utf-8') as handle:
    for raw in handle:
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split('/')
        if '..' in parts or parts[0] not in ('projects', 'custom') or (parts[0] == 'custom' and parts[1:2] != ['pocs']):
            print(
                f'warning: custom/claude-md-excludes.txt: skipped, not inside projects/ or custom/pocs/: {line}',
                file=sys.stderr,
            )
            continue
        if len(parts) < (3 if parts[0] == 'projects' else 4) or '*' in ''.join(parts[: (2 if parts[0] == 'projects' else 3)]):
            print(f'warning: custom/claude-md-excludes.txt: skipped, it names no file of one project: {line}', file=sys.stderr)
            continue
        for base in roots:
            pattern = os.path.join(base, line)
            if pattern not in patterns:
                patterns.append(pattern)
settings['claudeMdExcludes'] = patterns
print(json.dumps(settings, indent=2, ensure_ascii=False))
PY_EXCLUDES
}

if [ -f "$src/settings.json" ]; then
  settings_from="$src/settings.json"
  excludes_file="$root/custom/claude-md-excludes.txt"
  if [ -f "$excludes_file" ] && [ ! -L "$excludes_file" ]; then
    merged_file="$(mktemp)"
    if merged_settings "$src/settings.json" "$excludes_file" >"$merged_file"; then
      settings_from="$merged_file"
    else
      echo "warning: custom/claude-md-excludes.txt could not be merged into .claude/settings.json; copied without it" >&2
    fi
  fi
  sync_file "$settings_from" "$dst/settings.json"
  [ -z "${merged_file:-}" ] || rm -f "$merged_file"
fi

# Installs a user-scope mod once: an existing copy or registration is never changed.
# Args: name, label (for warnings), source folder.
install_user_mod() {
  local name="$1" label="$2" plugin="$3" mod="${HOME:-}/.claude/mods/$1"
  [ -n "${HOME:-}" ] && [ -d "$plugin" ] || return 0
  if [ ! -e "$mod" ]; then
    drift=1
    if [ "$check" -eq 1 ]; then
      echo "out of sync: ~/.claude/mods/$name"
    else
      { mkdir -p "$mod" && cp -R "$plugin/." "$mod/" && chmod -R u+w "$mod" && echo "written: ~/.claude/mods/$name"; } ||
        echo "warning: could not copy the $label" >&2
    fi
  fi
  python3 -I - "$HOME/.claude/settings.json" "$check" "$name" "$label" <<'PY_REGISTER' || drift=1
import json, os, sys
path, check, name, label = sys.argv[1], sys.argv[2] == '1', sys.argv[3], sys.argv[4]
entry = f'~/.claude/mods/{name}'
backup_path = f'{path}.bak.{name}'
try:
    data = json.load(open(path, encoding='utf-8')) if os.path.exists(path) else {}
    current = data.setdefault('env', {}).get('CLAUDE_CODE_PLUGIN_DIRS', '')
    if entry in current.split(':'):
        sys.exit(0)
    if check:
        print('out of sync: ~/.claude/settings.json')
        sys.exit(1)
    data['env']['CLAUDE_CODE_PLUGIN_DIRS'] = f'{current}:{entry}' if current else entry
    text = json.dumps(data, indent=2, ensure_ascii=False) + '\n'
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path) and not os.path.exists(backup_path):
        mode = os.stat(path).st_mode & 0o777
        backup = os.open(backup_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, mode)
        with open(path, 'rb') as src, os.fdopen(backup, 'wb') as dst:
            dst.write(src.read())
    with open(path, 'w', encoding='utf-8') as out:
        out.write(text)
    print('written: ~/.claude/settings.json')
except (OSError, ValueError, AttributeError, TypeError) as error:
    print(f'warning: {label} not registered in {path}: {error}', file=sys.stderr)
PY_REGISTER
}

install_user_mod fable-alert "Fable alert" "$root/tools/fable-alert/plugin"

if [ "$check" -eq 1 ] && [ "$drift" -eq 1 ]; then
  echo "result: .claude/ out of sync; run scripts/setup-claude.sh"
  exit 1
fi
[ "$quiet" -eq 1 ] || echo "result: .claude/ in sync"
