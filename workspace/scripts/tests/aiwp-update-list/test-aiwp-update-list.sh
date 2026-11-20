#!/usr/bin/env bash
# Tests of aiwp update across the registered workspaces: the list, the choice, the summary, a running claude, the locks,
# and the link of the removed single-agent mode. The shared fixture and helpers: ../aiwp/lib.sh (fully offline).
# Run: bash scripts/tests/aiwp-update-list/test-aiwp-update-list.sh [--only <test_name>]
# shellcheck disable=SC2319  # check reads the status of the test right before it, on purpose
# shellcheck disable=SC2119  # run_install takes optional arguments; these tests need none
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/aiwp/lib.sh
. "$HERE/../aiwp/lib.sh"

# --- the locks

test_git_children_never_hold_the_update_lock() {
  fixture
  run_install
  setup_ws || return
  publish_v2
  # A hook git runs in the data folder at each checkout: it records whether descriptor 9 (the lock) reached it.
  cat >"$DATA/.git/hooks/post-checkout" <<HOOK
#!/usr/bin/env bash
if { true >&9; } 2>/dev/null; then echo open >>"$T/fd9"; else echo closed >>"$T/fd9"; fi
HOOK
  chmod 755 "$DATA/.git/hooks/post-checkout"
  run_aiwp_in "$T" update --all
  rc_is 0
  [ "$(version_of "$WS")" = 0.2.0 ]; check "updated" $?
  AIWP_REF=v0.1.0 AIWP_WORKSPACE="$T/ws-again" run_install
  rc_is 0
  present "$T/fd9"
  ! grep -q open "$T/fd9"; check "no git child got the lock descriptor" $?
}

test_update_keeps_the_data_lock_until_the_end() {
  fixture
  setup_ws || return
  # A python3 that logs each flock of descriptor 9: taking it twice in one run means the lock was dropped between.
  cat >"$T/stub/python3" <<STUB
#!/usr/bin/env bash
case "\$*" in *fcntl.flock*) [ "\${!#}" != 9 ] || echo flock9 >>"$T/flocks" ;; esac
exec "$PY3" "\$@"
STUB
  chmod 755 "$T/stub/python3"
  run_aiwp_in "$T" update --all
  rc_is 0
  [ "$(grep -c flock9 "$T/flocks" 2>/dev/null)" = 1 ]; check "one flock of the data lock in a run with no data move" $?
  rm -f "$T/stub/python3"
}

test_a_busy_workspace_is_skipped_and_a_dead_run_leaves_no_lock() {
  fixture
  setup_ws || return
  second_ws
  publish_v2
  hold_lock "$WS/.aiwp/aiwp.lock"
  run_aiwp_in "$T" update --all
  rc_is 1
  has "another aiwp run is working on this workspace (pid $HOLDER)"
  [ "$(version_of "$WS")" = 0.1.0 ]; check "the busy one is left alone" $?
  [ "$(version_of "$WS2")" = 0.2.0 ]; check "the other one is updated" $?
  run_aiwp_in "$WS"
  rc_is 1
  has "another aiwp run is working on this workspace"
  kill -KILL "$HOLDER" 2>/dev/null
  wait "$HOLDER" 2>/dev/null
  run_aiwp_in "$T" update --all
  rc_is 0
  [ "$(version_of "$WS")" = 0.2.0 ]; check "updated once the holder died" $?
}

test_lock_folder_that_cannot_be_written_fails_fast() {
  fixture
  setup_ws || return
  publish_v2
  chmod 555 "$WS/.aiwp"
  local start
  start="$(date +%s)"
  run_aiwp_in "$T" update "$WS"
  chmod 755 "$WS/.aiwp"
  [ $(($(date +%s) - start)) -lt 30 ]; check "no endless retry" $?
  rc_is 1
  has "cannot take the lock"
}

# --- update: the link of the removed single-agent mode
# The fixture never ships scripts/single-claude.sh, so a link to it in the workspace is the dangling link an update
# leaves once the file is gone: the state the cleanup looks at, with no change to the fixture.

SINGLE_LINE="removed ~/.local/bin/single-claude: the single-agent mode no longer exists"

test_update_removes_the_single_claude_link_of_this_workspace() {
  fixture
  setup_ws || return
  ln -s "$WS/scripts/single-claude.sh" "$HOME/.local/bin/single-claude"
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 0
  has "updated: 0.1.0 -> 0.2.0"
  has "$SINGLE_LINE"
  absent "$HOME/.local/bin/single-claude"
  [ -L "$HOME/.local/bin/aiwp" ]; check "the aiwp link is untouched" $?
  # The same file through another spelling of the workspace path (a link to it), on a run that is up to date.
  ln -s "$WS" "$T/alias"
  ln -s "$T/alias/scripts/../scripts/single-claude.sh" "$HOME/.local/bin/single-claude"
  run_aiwp_in "$WS" update --all
  rc_is 0
  has "up to date: 0.2.0"
  has "$SINGLE_LINE"
  absent "$HOME/.local/bin/single-claude"
}

test_update_keeps_a_single_claude_link_to_another_folder() {
  fixture
  setup_ws || return
  second_ws
  ln -s "$WS2/scripts/single-claude.sh" "$HOME/.local/bin/single-claude"
  publish_v2
  run_aiwp_in "$T" update "$WS"
  rc_is 0
  has "updated: 0.1.0 -> 0.2.0"
  hasnt "single-claude"
  [ -L "$HOME/.local/bin/single-claude" ]; check "the link to another workspace stays" $?
  [ "$(readlink "$HOME/.local/bin/single-claude")" = "$WS2/scripts/single-claude.sh" ]; check "its target unchanged" $?
  # A link to a single-claude.sh that exists, in a folder outside every workspace, is left alone too.
  rm -f "$HOME/.local/bin/single-claude"
  mkdir -p "$T/elsewhere/scripts"
  echo mine >"$T/elsewhere/scripts/single-claude.sh"
  ln -s "$T/elsewhere/scripts/single-claude.sh" "$HOME/.local/bin/single-claude"
  run_aiwp_in "$T" update "$WS"
  rc_is 0
  has "up to date: 0.2.0"
  hasnt "single-claude"
  [ -L "$HOME/.local/bin/single-claude" ]; check "the link to an existing file stays" $?
}

test_update_keeps_a_regular_file_named_single_claude() {
  fixture
  setup_ws || return
  printf '#!/usr/bin/env bash\necho mine\n' >"$HOME/.local/bin/single-claude"
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 0
  has "updated: 0.1.0 -> 0.2.0"
  hasnt "single-claude"
  [ -f "$HOME/.local/bin/single-claude" ] && [ ! -L "$HOME/.local/bin/single-claude" ]; check "the file stays" $?
  content_is "$HOME/.local/bin/single-claude" "$(printf '#!/usr/bin/env bash\necho mine')"
}

test_update_with_no_single_claude_link_says_nothing() {
  fixture
  setup_ws || return
  local before
  before="$(ls -A "$HOME/.local/bin")"
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 0
  has "updated: 0.1.0 -> 0.2.0"
  hasnt "single-claude"
  [ "$(ls -A "$HOME/.local/bin")" = "$before" ]; check "the bin folder unchanged" $?
}

# --- update: the list, the choice, the summary

test_update_lists_and_updates_all_by_default() {
  fixture
  setup_ws || return
  second_ws
  publish_v2
  answers "$T/answers" "Choose [1]:" ""
  in_pty "$T" "$T/answers" "$HOME/.local/bin/aiwp" update
  rc_is 0
  has "1  0.1.0      update available (0.2.0)      $WS"
  has "2  0.1.0      update available (0.2.0)      $WS2"
  has "[1] Update all (default)"
  has "[2] Choose which (numbers)"
  has "[3] Cancel"
  has "Summary (data folder at 0.2.0):"
  [ "$(version_of "$WS")" = 0.2.0 ] && [ "$(version_of "$WS2")" = 0.2.0 ]; check "both updated" $?
  [ "$(python3 -I -c 'import json, sys; print(" ".join(w["version"] for w in json.load(open(sys.argv[1]))["workspaces"]))' "$DATA/workspaces.json")" = "0.2.0 0.2.0" ]
  check "the registry records the new versions" $?
}

test_update_choose_numbers() {
  fixture
  setup_ws || return
  second_ws
  publish_v2
  answers "$T/answers" "Choose [1]:" 9 "Answer 1, 2 or 3." 2 "(for example: 1 3):" "5 x" "Not a number of the list: x" 2
  in_pty "$T" "$T/answers" "$HOME/.local/bin/aiwp" update
  rc_is 0
  has "Not a number of the list: 5"
  [ "$(version_of "$WS")" = 0.1.0 ]; check "the first one was not chosen" $?
  [ "$(version_of "$WS2")" = 0.2.0 ]; check "the second one was updated" $?
}

test_update_cancel_changes_nothing() {
  fixture
  setup_ws || return
  publish_v2
  answers "$T/answers" "Choose [1]:" 3
  in_pty "$WS" "$T/answers" "$HOME/.local/bin/aiwp" update
  rc_is 0
  has "cancelled: nothing was changed"
  [ "$(version_of "$WS")" = 0.1.0 ]; check "not updated" $?
  [ "$(data_tag)" = v0.1.0 ]; check "the data folder did not move" $?
}

test_update_needs_a_terminal_or_a_target() {
  fixture
  setup_ws || return
  publish_v2
  run_aiwp_in "$WS" update
  rc_is 2
  has "with no terminal, aiwp update needs --all or a workspace folder"
  [ "$(data_tag)" = v0.1.0 ]; check "nothing moved" $?
}

test_update_one_folder_only() {
  fixture
  setup_ws || return
  second_ws
  publish_v2
  run_aiwp_in "$T" update "$WS2"
  rc_is 0
  has "Summary (data folder at 0.2.0):"
  [ "$(version_of "$WS")" = 0.1.0 ]; check "the other one stays" $?
  [ "$(version_of "$WS2")" = 0.2.0 ]; check "the one named is updated" $?
  # The other one, behind the data folder, is updated by a later run without moving the data folder again.
  run_aiwp_in "$T" update --all
  rc_is 0
  [ "$(version_of "$WS")" = 0.2.0 ]; check "caught up with the data folder" $?
  has "up to date (0.2.0)"
}

test_update_all_skips_a_changed_core_and_a_missing_folder_without_blocking() {
  fixture
  setup_ws || return
  second_ws
  run_aiwp_in "$T" new "$T/ws3"
  chmod u+w "$WS/docs/change.md"
  echo edited >"$WS/docs/change.md"
  chmod -R u+w "$T/ws3"
  rm -rf "$T/ws3"
  publish_v2
  run_aiwp_in "$T" update --all
  rc_is 1
  has "skipped: the core changed (aiwp repair in it, then aiwp update)"
  has "skipped: folder missing (aiwp forget $T/ws3)"
  has "updated 0.1.0 -> 0.2.0"
  [ "$(version_of "$WS")" = 0.1.0 ]; check "the changed one is left as it is" $?
  content_is "$WS/docs/change.md" edited
  [ "$(version_of "$WS2")" = 0.2.0 ]; check "the other one is updated" $?
}

test_update_asks_or_skips_when_claude_runs_in_the_workspace() {
  fixture
  setup_ws || return
  second_ws
  publish_v2
  # A process named claude whose current folder is inside the workspace.
  (cd "$WS/docs" && exec -a claude sleep 120) &
  local fake=$!
  sleep 0.3
  run_aiwp_in "$T" update --all
  rc_is 1
  has "claude is running in this workspace (pid $fake)"
  has "skipped: claude is running (pid $fake)"
  [ "$(version_of "$WS")" = 0.1.0 ]; check "not swapped under the running claude" $?
  [ "$(version_of "$WS2")" = 0.2.0 ]; check "the other one is updated" $?
  answers "$T/answers" "Update it anyway? [y/N]" n
  in_pty "$T" "$T/answers" "$HOME/.local/bin/aiwp" update "$WS"
  rc_is 1
  [ "$(version_of "$WS")" = 0.1.0 ]; check "answered no" $?
  answers "$T/answers" "Update it anyway? [y/N]" y
  in_pty "$T" "$T/answers" "$HOME/.local/bin/aiwp" update "$WS"
  rc_is 0
  [ "$(version_of "$WS")" = 0.2.0 ]; check "answered yes" $?
  kill "$fake" 2>/dev/null
  wait "$fake" 2>/dev/null
}

test_update_up_to_date_with_claude_running_is_not_a_skip() {
  fixture
  setup_ws || return
  (cd "$WS" && exec -a claude sleep 120) &
  local fake=$!
  sleep 0.3
  run_aiwp_in "$T" update --all
  rc_is 0
  has "up to date (0.1.0)"
  hasnt "claude is running"
  kill "$fake" 2>/dev/null
  wait "$fake" 2>/dev/null
}

test_update_force_goes_on_with_claude_running() {
  fixture
  setup_ws || return
  publish_v2
  (cd "$WS" && exec -a claude sleep 120) &
  local fake=$!
  sleep 0.3
  run_aiwp_in "$T" update --all --force
  rc_is 0
  [ "$(version_of "$WS")" = 0.2.0 ]; check "--force updates anyway" $?
  kill "$fake" 2>/dev/null
  wait "$fake" 2>/dev/null
}

main aiwp-update-list "$@"
