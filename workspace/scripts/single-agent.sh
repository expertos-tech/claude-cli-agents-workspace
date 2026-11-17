#!/usr/bin/env bash
# Single-agent mode: prepares a target (a repo of projects/, or a tool or POC of the custom layer) for a session opened by
# scripts/single-claude.sh, which runs outside the workspace's instructions, hooks and skills. Writes SINGLE-AGENT.md in
# the target from rules/single-agent/single-agent-template.md, keeps it in the target's .gitignore (never commits),
# reserves and changes the session's name, and imports the target's history file into the workspace history.
set -euo pipefail
# An inherited git environment would point every git call below at another repo.
unset GIT_DIR GIT_COMMON_DIR GIT_WORK_TREE

# src: the copy holding this script and the template. root: the workspace root, where the targets and the state live.
# An installed workspace (.aiwp/manifest.json) is its own root: it is not a git repo. A copy that is the top of a git
# checkout (the product repository, or a worktree of it being tested) finds the main checkout through git's common dir.
src="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workspace_root() {
  local common top
  if [ ! -f "$src/.aiwp/manifest.json" ] &&
    top="$(git -C "$src" rev-parse --show-toplevel 2>/dev/null)" && [ "$top" = "$(cd "$src" && pwd -P)" ] &&
    common="$(git -C "$src" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && [ -n "$common" ]; then
    dirname "$common"
  else
    printf '%s\n' "$src"
  fi
}
root="${EDIT_QUEUE_ROOT:-$(workspace_root)}"
template_rel="rules/single-agent/single-agent-template.md"
instructions="SINGLE-AGENT.md"
history_name="single-agent-history.txt"
ignore_line="/$instructions"
ignore_comment="# single-agent mode (scripts/single-agent.sh): local instructions, never committed"
state="$root/.history/single-agent"
valid_options="--commit, --merge, --review"

usage() {
  cat <<'USAGE'
Usage:
  scripts/single-agent.sh root
  scripts/single-agent.sh target [<path>]
  scripts/single-agent.sh prepare [<path>]
  scripts/single-agent.sh update <path>
  scripts/single-agent.sh options [--commit] [--merge] [--review]
  scripts/single-agent.sh name
  scripts/single-agent.sh rename --task <task>
  scripts/single-agent.sh hook
  scripts/single-agent.sh import-history --target <path> [--dry-run]

  root            prints the workspace root checkout (also from a worktree copy of this script).
  target          resolves the target (default: the current folder) and prints "target: <abs> kind=project|poc".
                  Valid: a git repo folder of projects/ (any depth), or one item of the custom layer: a tool of
                  yours, custom/tools/<name>, or a POC, custom/pocs/<name>, not ignored by the custom layer. The path
                  tools/<name> means custom/tools/<name>: tools/ of the root holds the product's tools, read-only,
                  and a folder inside it is refused. The workspace root and anything else: exit 3 with the reason.
  prepare         deletes and rewrites <target>/SINGLE-AGENT.md from rules/single-agent/single-agent-template.md and
                  adds /SINGLE-AGENT.md to the target's .gitignore when missing; no commit.
  update          the same as prepare, with the path mandatory, and lists what changed in each file.
  options         validates the session options; prints "options: <list>" ("none" when empty). --merge includes
                  --commit. An unknown option: exit 2 with the valid list.
  name            reserves and prints the next free single-agent-default-<n> of the last 7 days.
  rename          records single-agent-<task> as the wanted name of this session (CLAUDE_CODE_SESSION_ID); the next
                  hook firing applies it. Run it in background so its end fires the hook.
  hook            SessionStart / UserPromptSubmit hook of the plugin: reads the hook JSON on stdin and prints the
                  wanted title when it differs from the current one. Always exits 0.
  import-history  appends the entries of <target>/single-agent-history.txt not imported yet to the target's
                  history.txt through scripts/history.sh, each REQUEST starting with "[single-agent <date>]".

Exit codes: 0 ok; 1 failure; 2 usage error; 3 refused target.

Example:
  bash scripts/single-agent.sh update projects/billing-api
USAGE
}

die() {
  echo "single-agent: $2" >&2
  exit "$1"
}

# Prints the physical absolute path of folder $1, or dies when it does not exist.
physical() {
  [ -d "$1" ] || die 3 "not a folder: $1"
  (cd "$1" && pwd -P)
}

# Sets t_abs, t_kind and t_rel for the target $1 (default: the current folder), or dies with exit 3 and the reason.
# The relative path tools/<name> names the tool of the custom layer, custom/tools/<name>.
resolve_target() {
  local ws given item area ignore_rc
  ws="$(physical "$root")"
  given="${1:-$PWD}"
  case "$given" in tools/* | ./tools/*) given="$ws/custom/tools/${given#*tools/}" ;; esac
  t_abs="$(physical "$given")"
  [ "$t_abs" != "$ws" ] || die 3 "refused: the workspace root is not a single-agent target; use a repo of projects/, one tool of custom/tools/ or one POC of custom/pocs/"
  case "$t_abs/" in
    "$ws"/projects/*)
      [ -e "$t_abs/.git" ] && [ "$(git -C "$t_abs" rev-parse --show-toplevel 2>/dev/null)" = "$t_abs" ] ||
        die 3 "refused: $t_abs is not the root of a git repo of projects/"
      t_kind=project
      ;;
    "$ws"/tools/*)
      die 3 "refused: tools/ holds the product's tools, read-only; a tool of yours lives in custom/tools/<name>"
      ;;
    "$ws"/custom/pocs/*/ | "$ws"/custom/tools/*/)
      area="${t_abs#"$ws"/custom/}"
      item="${area#*/}"
      area="${area%%/*}"
      case "$item" in */*) die 3 "refused: use the item folder itself, custom/$area/${item%%/*}" ;; esac
      ignore_rc=0
      git -C "$ws/custom" check-ignore -q "$area/$item" 2>/dev/null || ignore_rc=$?
      case "$ignore_rc" in
        0) die 3 "refused: custom/$area/$item is ignored by the custom layer, so it is outside the workspace" ;;
        1) ;;
        *) die 1 "could not read the ignore rules of custom/$area/$item (git exit $ignore_rc)" ;;
      esac
      t_kind=poc
      ;;
    *) die 3 "refused: $t_abs is neither a repo of projects/ nor a tool of custom/tools/ or a POC of custom/pocs/" ;;
  esac
  t_rel="${t_abs#"$ws"/}"
}

# Writes the instructions file of the current target from the template, replacing the placeholders.
# Literal replacement: the quoted replacement keeps &, | and \ of a path as they are (bash 5.2 patsub_replacement).
write_instructions() {
  local tpl="$src/$template_rel" out="$t_abs/$instructions" text ws
  [ -f "$tpl" ] || die 1 "template missing: $template_rel"
  ws="$(physical "$root")"
  text="$(cat "$tpl")"
  text="${text//\{\{WORKSPACE\}\}/"$ws"}"
  text="${text//\{\{TARGET\}\}/"$t_abs"}"
  text="${text//\{\{KIND\}\}/"$t_kind"}"
  text="${text//\{\{HISTORY\}\}/"$history_name"}"
  tmp_out="$(mktemp "$t_abs/.single-agent.XXXXXX")"
  trap 'rm -f "$tmp_out"' EXIT
  printf '%s\n' "$text" >"$tmp_out"
  rm -f "$out"
  mv "$tmp_out" "$out"
  trap - EXIT
}

# Adds the ignore line to the target's .gitignore when missing. Prints "added" or "present".
ensure_ignored() {
  local file="$t_abs/.gitignore"
  if [ -f "$file" ] && grep -qxF "$ignore_line" "$file"; then
    echo present
    return 0
  fi
  if [ -s "$file" ] && [ -n "$(tail -c 1 "$file")" ]; then printf '\n' >>"$file"; fi
  printf '%s\n%s\n' "$ignore_comment" "$ignore_line" >>"$file"
  echo added
}

cmd_prepare() {
  local gi
  resolve_target "${1:-}"
  write_instructions
  gi="$(ensure_ignored)"
  echo "prepared: $t_abs kind=$t_kind"
  echo "written: $t_rel/$instructions"
  echo "gitignore: $gi ($t_rel/.gitignore)"
}

cmd_update() {
  local before_md before_gi tmpd changed=0 f
  [ $# -ge 1 ] && [ -n "$1" ] || die 2 "update needs the target path: scripts/single-agent.sh update <path>"
  resolve_target "$1"
  tmpd="$(mktemp -d)"
  before_md="$tmpd/md"
  before_gi="$tmpd/gi"
  if [ -f "$t_abs/$instructions" ]; then cp "$t_abs/$instructions" "$before_md"; else : >"$before_md"; fi
  if [ -f "$t_abs/.gitignore" ]; then cp "$t_abs/.gitignore" "$before_gi"; else : >"$before_gi"; fi
  write_instructions
  ensure_ignored >/dev/null
  for f in "$instructions:$before_md" ".gitignore:$before_gi"; do
    if ! diff -q "${f#*:}" "$t_abs/${f%%:*}" >/dev/null; then
      changed=1
      echo "changed: $t_rel/${f%%:*}"
      diff -u --label before --label after "${f#*:}" "$t_abs/${f%%:*}" | sed -n '3,$p' | grep '^[-+]' || true
    fi
  done
  rm -r "$tmpd"
  [ "$changed" -eq 1 ] || echo "unchanged: $t_rel"
  echo "updated: $t_abs kind=$t_kind"
}

cmd_options() {
  local commit=0 merge=0 review=0 o list=""
  for o in "$@"; do
    case "$o" in
      --commit) commit=1 ;;
      --merge) merge=1 commit=1 ;;
      --review) review=1 ;;
      *) die 2 "unknown option: $o; valid: $valid_options" ;;
    esac
  done
  [ "$commit" -eq 0 ] || list="--commit"
  [ "$merge" -eq 0 ] || list="$list --merge"
  [ "$review" -eq 0 ] || list="$list --review"
  list="${list# }"
  echo "options: ${list:-none}"
}

cmd_name() {
  local n=1
  mkdir -p "$state/names"
  find "$state/names" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rmdir {} + 2>/dev/null || true
  until mkdir "$state/names/default-$n" 2>/dev/null; do
    n=$((n + 1))
    [ "$n" -le 99999 ] || die 1 "no free default name"
  done
  echo "single-agent-default-$n"
}

# Prints $1 in lowercase kebab-case, ASCII letters and digits only.
to_kebab() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | tr -s '-' | sed -e 's/^-//' -e 's/-$//'
}

cmd_rename() {
  local task="" name sid="${CLAUDE_CODE_SESSION_ID:-}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --task)
        [ $# -ge 2 ] || die 2 "--task needs a value"
        task="$2"
        shift 2
        ;;
      *) die 2 "unknown argument: $1" ;;
    esac
  done
  task="$(to_kebab "$task")"
  task="${task#ai-workspace-}"
  [ -n "$task" ] && [ "$task" != ai-workspace ] || die 2 "rename needs a task with letters or digits: --task <task>"
  [ -n "$sid" ] || die 2 "CLAUDE_CODE_SESSION_ID is not set: run it inside the single-agent session"
  case "$sid" in */* | .*) die 2 "invalid session id" ;; esac
  name="single-agent-$task"
  name="${name:0:64}"
  name="${name%-}"
  mkdir -p "$state/sessions"
  printf '%s\n' "$name" >"$state/sessions/$sid"
  echo "wanted: $name (applies at the next firing of the hook)"
}

cmd_hook() {
  local input sid event title wanted
  input="$(cat)" || exit 0
  command -v jq >/dev/null 2>&1 || exit 0
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)" || exit 0
  event="$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)" || exit 0
  title="$(printf '%s' "$input" | jq -r '.session_title // empty' 2>/dev/null)" || exit 0
  case "$sid" in "" | */* | .*) exit 0 ;; esac
  case "$event" in SessionStart | UserPromptSubmit) ;; *) exit 0 ;; esac
  [ -f "$state/sessions/$sid" ] || exit 0
  wanted="$(head -n 1 "$state/sessions/$sid")"
  [ -n "$wanted" ] && [ "$wanted" != "$title" ] || exit 0
  jq -cn --arg e "$event" --arg t "$wanted" '{hookSpecificOutput: {hookEventName: $e, sessionTitle: $t}}'
}

# Adds one parsed entry through scripts/history.sh, or prints it with --dry-run. Reads the e_* variables.
import_entry() {
  local args=(add --target "$t_rel" --request "[single-agent $e_date] $e_request" --files "$e_files")
  local v
  for v in "${e_facts[@]}"; do args+=(--fact "$v"); done
  for v in "${e_decisions[@]}"; do args+=(--decision "$v"); done
  for v in "${e_pending[@]}"; do args+=(--pending "$v"); done
  for v in "${e_risks[@]}"; do args+=(--risk "$v"); done
  [ -z "$e_author" ] || args+=(--author "$e_author")
  if [ "$dry_run" -eq 1 ]; then
    echo "would import: [single-agent $e_date] $e_request"
  else
    (cd "$root" && bash scripts/history.sh "${args[@]}" >/dev/null) || die 1 "history.sh failed on entry $e_index"
    echo "imported: [single-agent $e_date] $e_request"
  fi
}

# Handles the entry gathered so far: skipped when incomplete, imported when newer than the mark.
flush_entry() {
  [ "$e_index" -gt 0 ] || return 0
  [ "$e_index" -gt "$done_count" ] || return 0
  if [ -z "$e_request" ] || [ "${#e_facts[@]}" -eq 0 ] || [ -z "$e_files" ]; then
    echo "skipped: entry $e_index ($e_date): REQUEST, FACT or FILES missing"
  else
    import_entry
  fi
  last_done="$e_index"
  if [ "$dry_run" -eq 0 ]; then
    mkdir -p "$state/imported"
    printf '%s\n' "$last_done" >"$mark"
  fi
}

cmd_import_history() {
  local target="" line key
  dry_run=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --target)
        [ $# -ge 2 ] || die 2 "--target needs a value"
        target="$2"
        shift 2
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      *) die 2 "unknown argument: $1" ;;
    esac
  done
  [ -n "$target" ] || die 2 "import-history needs --target <path>"
  resolve_target "$target"
  [ -f "$t_abs/$history_name" ] || die 1 "no $history_name in $t_rel"
  key="$(printf '%s' "$t_rel" | tr '/' '_')"
  mark="$state/imported/$key"
  done_count=0
  [ ! -f "$mark" ] || done_count="$(head -n 1 "$mark")"
  case "$done_count" in '' | *[!0-9]*) done_count=0 ;; esac
  e_index=0
  last_done="$done_count"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "--- "*)
        flush_entry
        e_index=$((e_index + 1))
        e_date="${line#--- }"
        e_author=""
        case "$e_date" in *" | "*) e_author="${e_date#* | }" e_date="${e_date%% | *}" ;; esac
        e_request="" e_files=""
        e_facts=() e_decisions=() e_pending=() e_risks=()
        ;;
      REQUEST:*) e_request="$(printf '%s' "${line#REQUEST:}" | sed 's/^ *//')" ;;
      FACT:*) e_facts+=("$(printf '%s' "${line#FACT:}" | sed 's/^ *//')") ;;
      DECISION:*) e_decisions+=("$(printf '%s' "${line#DECISION:}" | sed 's/^ *//')") ;;
      PENDING:*) e_pending+=("$(printf '%s' "${line#PENDING:}" | sed 's/^ *//')") ;;
      RISK:*) e_risks+=("$(printf '%s' "${line#RISK:}" | sed 's/^ *//')") ;;
      FILES:*) e_files="$(printf '%s' "${line#FILES:}" | sed 's/^ *//')" ;;
    esac
  done <"$t_abs/$history_name"
  flush_entry
  [ "$last_done" != "$done_count" ] || echo "nothing new: $t_rel/$history_name"
}

[ $# -ge 1 ] || {
  usage >&2
  exit 2
}
command="$1"
shift
case "$command" in
  -h | --help) usage ;;
  root) printf '%s\n' "$root" ;;
  target)
    resolve_target "${1:-}"
    echo "target: $t_abs kind=$t_kind"
    ;;
  prepare) cmd_prepare "${1:-}" ;;
  update) cmd_update "$@" ;;
  options) cmd_options "$@" ;;
  name) cmd_name ;;
  rename) cmd_rename "$@" ;;
  hook) cmd_hook ;;
  import-history) cmd_import_history "$@" ;;
  *)
    usage >&2
    exit 2
    ;;
esac
