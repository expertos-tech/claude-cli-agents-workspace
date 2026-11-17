#!/usr/bin/env bash
# Tests of scripts/single-agent.sh and scripts/single-claude.sh against a throwaway workspace root (EDIT_QUEUE_ROOT),
# never the real one. Run: bash scripts/tests/single-agent/test-single-agent.sh
# shellcheck source-path=SCRIPTDIR
# shellcheck disable=SC2034,SC2329  # OUT and RC are read by the assertions of lib.sh; run_tests finds the test_* functions.
set -uo pipefail
# shellcheck source=../lib/lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../lib/lib.sh"

SID=cccc3333-0000-4000-8000-000000000003

# Copies the scripts and the template under test into the fixture root, and makes a project repo, a product tool in
# tools/, a tool of the custom layer (custom/tools/demo) and an ignored POC.
setup_root() {
  mkdir -p "$FIX/rules/single-agent" "$FIX/scripts/lib" "$FIX/tools/observability" "$FIX/custom/tools/demo" \
    "$FIX/custom/pocs/hidden"
  cp "$QE_REPO/scripts/single-agent.sh" "$QE_REPO/scripts/single-claude.sh" "$QE_REPO/scripts/history.sh" "$FIX/scripts/"
  cp "$QE_REPO/scripts/lib/projects.sh" "$FIX/scripts/lib/"
  cp -R "$QE_REPO/rules/single-agent/." "$FIX/rules/single-agent/"
  printf '/custom/\n' >>"$FIX/.gitignore"
  printf '# Observability\n' >"$FIX/tools/observability/README.md"
  git -C "$FIX" add tools .gitignore
  git -C "$FIX" commit -q -m "tools"
  git init -q "$FIX/custom"
  printf '# Demo\n' >"$FIX/custom/tools/demo/README.md"
  printf '/hidden/\n' >"$FIX/custom/pocs/.gitignore"
  APP="$FIX/projects/acme/app"
  mkdir -p "$APP"
  git init -q "$APP"
  git -C "$APP" config user.name "Fictitious Person"
  git -C "$APP" config user.email "person@example.test"
  printf '# App\n' >"$APP/README.md"
  printf 'node_modules/\n' >"$APP/.gitignore"
  git -C "$APP" add -A
  git -C "$APP" commit -q -m "app"
}

# Runs single-agent.sh from folder $1 with the rest as arguments.
sa_in() {
  local dir="$1"
  shift
  OUT="$(cd "$dir" && CLAUDE_CODE_SESSION_ID="$SID" bash "$FIX/scripts/single-agent.sh" "$@" 2>&1)"
  RC=$?
  kcov_resync
}

sa() {
  sa_in "$FIX" "$@"
}

test_a_project_repo_is_prepared() {
  setup_root
  sa prepare "$APP"
  assert_exit 0
  assert_contains "$OUT" "kind=project"
  assert_exists "$APP/SINGLE-AGENT.md"
}

test_a_poc_is_prepared_with_its_own_gitignore() {
  setup_root
  sa_in "$FIX/custom/tools/demo" prepare
  assert_exit 0
  assert_contains "$OUT" "kind=poc"
  assert_line_count "$FIX/custom/tools/demo/.gitignore" "/SINGLE-AGENT.md" 1
  assert_not_contains "$(cat "$FIX/.gitignore")" "SINGLE-AGENT"
}

test_a_tools_path_means_the_tool_of_the_custom_layer() {
  setup_root
  sa target tools/demo
  assert_exit 0
  assert_contains "$OUT" "target: $FIX/custom/tools/demo kind=poc"
  sa prepare "$FIX/tools/observability"
  assert_exit 3
  assert_contains "$OUT" "tools/ holds the product's tools, read-only"
  assert_missing "$FIX/tools/observability/SINGLE-AGENT.md"
  sa prepare tools/observability
  assert_exit 3
  assert_missing "$FIX/tools/observability/SINGLE-AGENT.md"
}

test_an_installed_workspace_is_its_own_root() {
  setup_root
  local ws="$AUX/outer/ws"
  mkdir -p "$ws/scripts/lib" "$ws/.aiwp"
  git init -q "$AUX/outer"
  cp "$FIX/scripts/single-agent.sh" "$ws/scripts/"
  printf '{}\n' >"$ws/.aiwp/manifest.json"
  OUT="$(cd "$ws" && env -u EDIT_QUEUE_ROOT bash "$ws/scripts/single-agent.sh" root 2>&1)"
  RC=$?
  assert_exit 0
  assert_eq "$(cd "$ws" && pwd -P)" "$OUT" "root of an installed workspace inside another repo"
}

test_an_ignored_poc_stays_refused_with_an_inherited_git_dir() {
  setup_root
  mkdir -p "$AUX/elsewhere"
  git init -q "$AUX/elsewhere"
  OUT="$(cd "$FIX" && GIT_DIR="$AUX/elsewhere/.git" GIT_WORK_TREE="$AUX/elsewhere" \
    bash "$FIX/scripts/single-agent.sh" target "$FIX/custom/pocs/hidden" 2>&1)"
  RC=$?
  assert_exit 3
  assert_contains "$OUT" "ignored by the custom layer"
}

test_the_workspace_root_and_other_folders_are_refused() {
  setup_root
  sa prepare "$FIX"
  assert_exit 3
  assert_contains "$OUT" "the workspace root is not a single-agent target"
  sa prepare "$FIX/docs"
  assert_exit 3
  sa prepare "$FIX/projects/acme"
  assert_exit 3
  assert_contains "$OUT" "not the root of a git repo"
  mkdir -p "$FIX/custom/tools/demo/sub"
  sa prepare "$FIX/custom/tools/demo/sub"
  assert_exit 3
  sa prepare "$FIX/custom/pocs/hidden"
  assert_exit 3
  assert_contains "$OUT" "ignored by the custom layer"
  assert_missing "$FIX/SINGLE-AGENT.md"
}

test_an_edited_file_goes_back_to_the_template() {
  setup_root
  sa prepare "$APP"
  printf 'edited by hand\n' >"$APP/SINGLE-AGENT.md"
  sa prepare "$APP"
  assert_exit 0
  assert_not_contains "$(cat "$APP/SINGLE-AGENT.md")" "edited by hand"
  assert_contains "$(cat "$APP/SINGLE-AGENT.md")" "$APP/docs/README.md"
  assert_contains "$(cat "$APP/SINGLE-AGENT.md")" "$APP/README.md"
  assert_not_contains "$(cat "$APP/SINGLE-AGENT.md")" "{{"
}

test_only_the_gitignore_changes_and_nothing_is_committed() {
  setup_root
  local head
  head="$(git -C "$APP" rev-parse HEAD)"
  sa prepare "$APP"
  sa prepare "$APP"
  assert_eq " M .gitignore" "$(git -C "$APP" status --porcelain)" "git status"
  assert_eq "$head" "$(git -C "$APP" rev-parse HEAD)" "HEAD"
  assert_line_count "$APP/.gitignore" "/SINGLE-AGENT.md" 1
  assert_contains "$OUT" "gitignore: present"
}

test_update_needs_a_path() {
  setup_root
  sa update
  assert_exit 2
  assert_contains "$OUT" "update needs the target path"
}

test_update_touches_only_that_target_and_lists_the_change() {
  setup_root
  sa prepare "$APP"
  sa prepare "$FIX/custom/tools/demo"
  printf 'new template line\n' >>"$FIX/rules/single-agent/single-agent-template.md"
  sa update "$APP"
  assert_exit 0
  assert_contains "$OUT" "changed: projects/acme/app/SINGLE-AGENT.md"
  assert_contains "$OUT" "+new template line"
  assert_not_contains "$(cat "$FIX/custom/tools/demo/SINGLE-AGENT.md")" "new template line"
  sa update "$APP"
  assert_contains "$OUT" "unchanged: projects/acme/app"
}

# Writes a stub claude that records its arguments, the auto-memory variable and the folder it runs in.
stub_claude() {
  STUB="$AUX/claude"
  # shellcheck disable=SC2016  # the $ expressions belong to the stub, expanded when it runs.
  printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s/args"\nprintf "memory=%%s pwd=%%s\\n" "${CLAUDE_CODE_DISABLE_AUTO_MEMORY:-}" "$PWD" >"%s/env"\n' \
    "$AUX" "$AUX" >"$STUB"
  chmod +x "$STUB"
}

# Runs single-claude.sh with the stub, outside a Claude Code session.
sc() {
  OUT="$(cd "$FIX" && env -u CLAUDECODE SINGLE_CLAUDE_BIN="$STUB" bash "$FIX/scripts/single-claude.sh" "$@" 2>&1)"
  RC=$?
  kcov_resync
}

test_single_claude_opens_claude_isolated() {
  setup_root
  stub_claude
  sc "$APP" --merge -- --model sonnet
  assert_exit 0
  assert_eq "memory= pwd=$APP" "$(cat "$AUX/env")" "what the session inherits"
  assert_contains "$(cat "$AUX/args")" "--setting-sources
user"
  assert_contains "$(cat "$AUX/args")" "--plugin-dir
$FIX/rules/single-agent/plugin"
  assert_contains "$(cat "$AUX/args")" "--name
single-agent-default-1"
  assert_contains "$(cat "$AUX/args")" "--append-system-prompt-file
$APP/SINGLE-AGENT.md"
  assert_contains "$(cat "$AUX/args")" "options: --commit --merge"
  assert_contains "$(cat "$AUX/args")" "--model
sonnet"
}

test_a_poc_session_drops_the_workspace_auto_memory() {
  setup_root
  stub_claude
  sc "$FIX/custom/tools/demo"
  assert_exit 0
  assert_contains "$(cat "$AUX/env")" "memory=1"
}

test_single_claude_refuses_inside_a_claude_code_session() {
  setup_root
  stub_claude
  OUT="$(cd "$FIX" && CLAUDECODE=1 SINGLE_CLAUDE_BIN="$STUB" bash "$FIX/scripts/single-claude.sh" "$APP" 2>&1)"
  RC=$?
  assert_exit 2
  assert_contains "$OUT" "the human runs it from a terminal"
  assert_missing "$AUX/args"
}

test_single_claude_refuses_the_workspace_root() {
  setup_root
  stub_claude
  sc "$FIX"
  assert_exit 3
  assert_missing "$AUX/args"
}

# Commits the scripts and template into the fixture and adds a worktree copy of it under $AUX (WT).
make_worktree_copy() {
  git -C "$FIX" add scripts rules
  git -C "$FIX" commit -q -m "scripts"
  WT="$AUX/wt"
  git -C "$FIX" worktree add -q "$WT" -b wt-copy
}

test_an_inherited_git_dir_does_not_change_the_root() {
  setup_root
  make_worktree_copy
  OUT="$(cd "$WT" && env -u EDIT_QUEUE_ROOT GIT_DIR="$AUX/elsewhere/.git" GIT_WORK_TREE="$AUX/elsewhere" \
    bash "$WT/scripts/single-agent.sh" root 2>&1)"
  RC=$?
  assert_exit 0
  assert_eq "$(cd "$FIX" && pwd -P)" "$OUT" "root with GIT_DIR set"
}

test_a_worktree_copy_finds_the_workspace_root() {
  setup_root
  stub_claude
  make_worktree_copy
  OUT="$(cd "$WT" && env -u EDIT_QUEUE_ROOT bash "$WT/scripts/single-agent.sh" root 2>&1)"
  RC=$?
  assert_exit 0
  assert_eq "$(cd "$FIX" && pwd -P)" "$OUT" "root from the worktree copy"
  OUT="$(cd "$WT" && env -u EDIT_QUEUE_ROOT bash "$WT/scripts/single-agent.sh" target "$APP" 2>&1)"
  RC=$?
  assert_exit 0
  assert_contains "$OUT" "kind=project"
  OUT="$(cd "$WT" && env -u CLAUDECODE -u EDIT_QUEUE_ROOT SINGLE_CLAUDE_BIN="$STUB" \
    bash "$WT/scripts/single-claude.sh" "$APP" 2>&1)"
  RC=$?
  assert_exit 0
  assert_contains "$(cat "$AUX/env")" "pwd=$APP"
  assert_contains "$(cat "$AUX/args")" "--plugin-dir
$WT/rules/single-agent/plugin"
  assert_contains "$(cat "$AUX/args")" "Workspace: $(cd "$FIX" && pwd -P)."
  assert_contains "$(cat "$AUX/args")" "Tool: $WT/scripts/single-agent.sh."
}

test_a_target_path_with_special_characters_is_written_literally() {
  setup_root
  local odd="$FIX/projects/a&b|c\\d/app" left
  mkdir -p "$odd"
  git init -q "$odd"
  sa prepare "$odd"
  assert_exit 0
  assert_contains "$(cat "$odd/SINGLE-AGENT.md")" "$odd/README.md"
  assert_not_contains "$(cat "$odd/SINGLE-AGENT.md")" "{{"
  left="$(find "$odd" -maxdepth 1 -name '.single-agent.*')"
  assert_eq "" "$left" "temp files left in the target"
  sa prepare "$APP"
  left="$(find "$APP" -maxdepth 1 -name '.single-agent.*')"
  assert_eq "" "$left" "temp files left in the target"
}

test_default_names_are_numbered() {
  setup_root
  sa name
  assert_eq "single-agent-default-1" "$OUT" "first name"
  sa name
  assert_eq "single-agent-default-2" "$OUT" "second name"
}

test_rename_sets_the_title_through_the_hook() {
  setup_root
  sa rename --task "Ajuste Login"
  assert_exit 0
  assert_contains "$OUT" "wanted: single-agent-ajuste-login"
  OUT="$(printf '{"session_id":"%s","hook_event_name":"UserPromptSubmit","session_title":"single-agent-default-1"}' "$SID" |
    bash "$FIX/scripts/single-agent.sh" hook)"
  assert_eq '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","sessionTitle":"single-agent-ajuste-login"}}' "$OUT" "hook"
  OUT="$(printf '{"session_id":"%s","hook_event_name":"UserPromptSubmit","session_title":"single-agent-ajuste-login"}' "$SID" |
    bash "$FIX/scripts/single-agent.sh" hook)"
  assert_eq "" "$OUT" "applied title"
}

test_rename_never_takes_the_workspace_prefix_nor_an_empty_task() {
  setup_root
  sa rename --task "ai-workspace-x"
  assert_contains "$OUT" "wanted: single-agent-x"
  sa rename --task "!!!"
  assert_exit 2
  OUT="$(cd "$FIX" && env -u CLAUDE_CODE_SESSION_ID bash "$FIX/scripts/single-agent.sh" rename --task y 2>&1)"
  RC=$?
  assert_exit 2
}

test_options_are_validated() {
  setup_root
  sa options --merge --review
  assert_eq "options: --commit --merge --review" "$OUT" "options"
  sa options
  assert_eq "options: none" "$OUT" "no option"
  sa options --push
  assert_exit 2
  assert_contains "$OUT" "valid: --commit, --merge, --review"
  stub_claude
  sc "$APP" --push
  assert_exit 2
  assert_missing "$AUX/args"
}

# Writes the target's history file with two complete entries and one without FACT.
write_target_history() {
  cat >"$APP/single-agent-history.txt" <<'EOF'
--- 2026-11-09 10:00 -0300 | Fictitious Person
REQUEST: adjust the login
FACT: login adjusted; tests passed
FILES: src/login.go
--- 2026-11-09 11:00 -0300 | Fictitious Person
REQUEST: incomplete
FILES: none
--- 2026-11-09 12:00 -0300 | Fictitious Person
REQUEST: fix the logout
FACT: logout fixed
DECISION: keep the cookie (human)
FILES: src/logout.go
EOF
}

test_import_history_appends_new_entries_once() {
  setup_root
  printf '# History\n' >"$APP/history.txt"
  write_target_history
  sa import-history --target "$APP"
  assert_exit 0
  assert_contains "$OUT" "imported: [single-agent 2026-11-09 10:00 -0300] adjust the login"
  assert_contains "$OUT" "skipped: entry 2"
  assert_contains "$(cat "$APP/history.txt")" "REQUEST: [single-agent 2026-11-09 12:00 -0300] fix the logout"
  assert_contains "$(cat "$APP/history.txt")" "DECISION: keep the cookie (human)"
  sa import-history --target "$APP"
  assert_contains "$OUT" "nothing new"
  assert_line_count "$APP/history.txt" "REQUEST: [single-agent 2026-11-09 10:00 -0300] adjust the login" 1
}

test_a_failed_import_keeps_the_mark_of_the_entries_already_imported() {
  setup_root
  printf '# History\n' >"$APP/history.txt"
  write_target_history
  cp "$FIX/scripts/history.sh" "$FIX/scripts/history-real.sh"
  # shellcheck disable=SC2016  # the $ expressions belong to the stub, expanded when it runs.
  printf '#!/bin/sh\ncase "$*" in *logout*) exit 1 ;; esac\nexec bash "$(dirname "$0")/history-real.sh" "$@"\n' \
    >"$FIX/scripts/history.sh"
  sa import-history --target "$APP"
  assert_exit 1
  assert_contains "$OUT" "history.sh failed on entry 3"
  cp "$FIX/scripts/history-real.sh" "$FIX/scripts/history.sh"
  sa import-history --target "$APP"
  assert_exit 0
  assert_contains "$OUT" "imported: [single-agent 2026-11-09 12:00 -0300] fix the logout"
  assert_not_contains "$OUT" "adjust the login"
  assert_line_count "$APP/history.txt" "REQUEST: [single-agent 2026-11-09 10:00 -0300] adjust the login" 1
  assert_line_count "$APP/history.txt" "REQUEST: [single-agent 2026-11-09 12:00 -0300] fix the logout" 1
}

test_import_history_needs_the_file_and_a_target() {
  setup_root
  sa import-history
  assert_exit 2
  sa import-history --target "$APP"
  assert_exit 1
  assert_contains "$OUT" "no single-agent-history.txt"
}

test_workspace_settings_deny_reading_the_single_agent_file() {
  assert_contains "$(cat "$QE_REPO/rules/agents/settings.json")" '"Read(**/SINGLE-AGENT.md)"'
}

test_help_prints_the_usage() {
  setup_root
  sa --help
  assert_exit 0
  assert_contains "$OUT" "Usage:"
  stub_claude
  sc --help
  assert_contains "$OUT" "Usage: single-claude"
}

run_tests
