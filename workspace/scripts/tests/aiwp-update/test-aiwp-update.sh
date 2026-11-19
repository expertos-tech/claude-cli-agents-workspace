#!/usr/bin/env bash
# Tests of aiwp update and rollback on one workspace: what is swapped, the backups, the default pilot mode, a crash
# halfway. The shared fixture and helpers: ../aiwp/lib.sh (fully offline).
# Run: bash scripts/tests/aiwp-update/test-aiwp-update.sh [--only <test_name>]
# shellcheck disable=SC2319  # check reads the status of the test right before it, on purpose
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/tests/aiwp/lib.sh
. "$HERE/../aiwp/lib.sh"

# --- update

test_update_swaps_only_what_changed() {
  fixture
  setup_ws || return
  echo mine >"$WS/custom/mine.txt"
  echo mine >"$WS/projects/mine.txt"
  echo mine >"$WS/tmp/mine.txt"
  echo mine >"$WS/logs/mine.txt"
  local keep_before agents_before custom_before
  keep_before="$(inode_mtime "$WS/docs/keep.md")"
  agents_before="$(inode_mtime "$WS/AGENTS.md")"
  custom_before="$(inode_mtime "$WS/custom/mine.txt")"
  sleep 1
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 0
  has "update: 0.1.0 -> 0.2.0"
  has "Second release of the fixture"
  hasnt "First release of the fixture"
  has "updated: 0.1.0 -> 0.2.0 (4 changed, 3 added, 2 removed)"
  [ "$(inode_mtime "$WS/docs/keep.md")" = "$keep_before" ]; check "unchanged file keeps inode and mtime" $?
  [ "$(inode_mtime "$WS/AGENTS.md")" = "$agents_before" ]; check "unchanged AGENTS.md untouched" $?
  [ "$(inode_mtime "$WS/custom/mine.txt")" = "$custom_before" ]; check "custom untouched" $?
  content_is "$WS/projects/mine.txt" mine
  content_is "$WS/tmp/mine.txt" mine
  content_is "$WS/logs/mine.txt" mine
  content_is "$WS/docs/change.md" "change v2"
  mode_is "$WS/docs/change.md" 444
  content_is "$WS/docs/new.md" "new in v0.2.0"
  mode_is "$WS/docs/new.md" 444
  mode_is "$WS/scripts/new-tool.sh" 555
  absent "$WS/docs/old.md"
  absent "$WS/docs/gone"
  mode_is "$WS/docs" 555
  mode_is "$WS" 555
  absent "$WS/.aiwp/journal"
  [ -z "$(find "$WS" -name '.aiwp-tmp.*')" ]; check "no temp file left" $?
  [ "$(manifest_field version)" = 0.2.0 ]; check "manifest at 0.2.0" $?
  [ "$(manifest_field tag)" = v0.2.0 ]; check "manifest tag v0.2.0" $?
  content_is "$WS/.aiwp/backup/0.1.0/files/docs/change.md" "change v1"
  present "$WS/.aiwp/backup/0.1.0/files/docs/old.md"
  absent "$WS/.aiwp/backup/0.1.0/files/docs/keep.md"
  absent "$WS/README.md.orig"
  absent "$WS/maintainers"
  run_aiwp_in "$WS" repair
  rc_is 0
  has "nothing to repair"
  run_aiwp_in "$WS" update --all
  rc_is 0
  has "up to date: 0.2.0"
}

test_update_keeps_the_last_three_backups() {
  fixture
  setup_ws || return
  local v
  chmod u+w "$WS/.aiwp"
  for v in 0.0.1 0.0.2 0.0.3; do
    mkdir -p "$WS/.aiwp/backup/$v/files"
    touch -t "20260101000${v##*.}" "$WS/.aiwp/backup/$v"
  done
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 0
  [ "$(find "$WS/.aiwp/backup" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 3 ]; check "three backups kept" $?
  present "$WS/.aiwp/backup/0.1.0"
  absent "$WS/.aiwp/backup/0.0.1"
}

# --- update: the default pilot mode of a workspace from before /pilot assisted (v0.1.0 has no rules/assisted.md)

# Writes a week file of the prompt log of workspace $1 with one record ($2 = empty: a data block with no record).
prompt_log_week() {
  local records='[{"session": "s-1", "timestamp": "2026-11-16T10:00:00Z", "project": "workspace", "text": "hi"}]'
  [ "${2:-}" != empty ] || records='[]'
  mkdir -p "$1/logs/prompts/workspace"
  printf '# workspace · week 2026-W47\n\n<!-- prompt-log-data\n{"format": 1, "records": %s}\n-->\n' "$records" \
    >"$1/logs/prompts/workspace/2026-W47.md"
}

# Publishes v0.3.0 on the test's remote, after v0.2.0: a later release that still has rules/assisted.md.
publish_v3() {
  local src="$T/src3"
  rm -rf "$src"
  git clone -q "$T/remote.git" "$src" && git -C "$src" checkout -q main || return 1
  printf '0.3.0\n' >"$src/workspace/VERSION"
  printf '# Changelog\n\n## [0.3.0] - 2026-11-25\n\n- Third release of the fixture.\n' >"$src/workspace/CHANGELOG.md"
  fx_commit "$src" "release 0.3.0"
  git -C "$src" tag v0.3.0
  git -C "$src" push -q origin main v0.3.0
}

test_update_from_before_assisted_keeps_auto_when_there_is_history() {
  fixture
  setup_ws || return
  second_ws
  local ws3="$T/ws3" ws4="$T/ws4" ws5="$T/ws5"
  run_aiwp_in "$T" new "$ws3"
  run_aiwp_in "$T" new "$ws4"
  run_aiwp_in "$T" new "$ws5"
  # WS: a prompt log with a record. WS2: a project. ws3: no history (a README.md in projects/, a week file with no
  # record, other files in logs/). ws4: history and a default already chosen. ws5: a project and a link at the file.
  prompt_log_week "$WS"
  mkdir -p "$WS2/projects/billing-api"
  echo "mine" >"$ws3/projects/README.md"
  prompt_log_week "$ws3" empty
  echo "mine" >"$ws3/logs/mine.txt"
  mkdir -p "$ws4/projects/billing-api"
  printf 'assisted\n' >"$ws4/.claude/pilot-mode"
  local ws4_before
  ws4_before="$(inode_mtime "$ws4/.claude/pilot-mode")"
  mkdir -p "$ws5/projects/billing-api"
  ln -s "$T/elsewhere" "$ws5/.claude/pilot-mode"
  absent "$WS/.claude/pilot-mode"
  sleep 1
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 0
  [ "$(version_of "$WS")" = 0.2.0 ] && [ "$(version_of "$ws3")" = 0.2.0 ]; check "updated to 0.2.0" $?
  content_is "$WS/.claude/pilot-mode" auto
  content_is "$WS2/.claude/pilot-mode" auto
  has "pilot mode: auto kept as the default of this workspace (it has history)"
  absent "$ws3/.claude/pilot-mode"
  content_is "$ws4/.claude/pilot-mode" assisted
  [ "$(inode_mtime "$ws4/.claude/pilot-mode")" = "$ws4_before" ]; check "an existing default is never rewritten" $?
  [ -L "$ws5/.claude/pilot-mode" ]; check "a link at the file is left alone" $?
  absent "$T/elsewhere"
  # It survives repair, the opening (setup-claude.sh) and a second update.
  run_aiwp_in "$WS" repair
  rc_is 0
  run_aiwp_in "$WS"
  rc_is 0
  content_is "$WS/.claude/pilot-mode" auto
  # ws3 had no history at the update, so it was in assisted at 0.2.0: the rollback writes that default, and the update
  # after it, with history by then, keeps it.
  run_aiwp_in "$ws3" rollback
  rc_is 0
  has "pilot mode: assisted kept as the default of this workspace"
  content_is "$ws3/.claude/pilot-mode" assisted
  mkdir -p "$ws3/projects/billing-api"
  run_aiwp_in "$ws3" update "$ws3"
  rc_is 0
  [ "$(version_of "$ws3")" = 0.2.0 ]; check "ws3 updated again" $?
  hasnt "pilot mode: auto kept"
  content_is "$ws3/.claude/pilot-mode" assisted
  run_aiwp_in "$WS" update "$WS"
  rc_is 0
  has "up to date: 0.2.0"
  content_is "$WS/.claude/pilot-mode" auto
}

test_new_workspace_never_gets_the_pilot_default() {
  fixture
  publish_v2
  setup_ws || return
  [ "$(version_of "$WS")" = 0.2.0 ]; check "created at 0.2.0" $?
  absent "$WS/.claude/pilot-mode"
  # History on a workspace that already has the feature: an update at the same version, then to a later one, never
  # writes the default.
  prompt_log_week "$WS"
  mkdir -p "$WS/projects/billing-api"
  run_aiwp_in "$WS" update "$WS"
  rc_is 0
  has "up to date: 0.2.0"
  absent "$WS/.claude/pilot-mode"
  publish_v3 || { check "publish v0.3.0" 1; return; }
  age_cache
  run_aiwp_in "$WS" update "$WS"
  rc_is 0
  [ "$(version_of "$WS")" = 0.3.0 ]; check "updated to 0.3.0" $?
  hasnt "pilot mode:"
  absent "$WS/.claude/pilot-mode"
  # A rollback between two cores that both have rules/assisted.md writes nothing either.
  run_aiwp_in "$WS" rollback
  rc_is 0
  has "rolled back: 0.3.0 -> 0.2.0"
  hasnt "pilot mode:"
  absent "$WS/.claude/pilot-mode"
}

# A workspace in assisted with no .claude/pilot-mode (no history at its update to 0.2.0, as a new one), used at 0.2.0,
# then rolled back below /pilot assisted: the rollback writes assisted, so the next update keeps the person's default
# instead of taking the workspace for one from before the feature. A default chosen, a link there and a .claude/ that
# cannot be written are left as they are.
test_rollback_below_assisted_keeps_the_default_for_the_next_update() {
  fixture
  setup_ws || return
  second_ws
  local ws3="$T/ws3" ws4="$T/ws4" ws2_before
  run_aiwp_in "$T" new "$ws3"
  run_aiwp_in "$T" new "$ws4"
  publish_v2
  run_aiwp_in "$T" update --all
  rc_is 0
  hasnt "pilot mode:"
  absent "$WS/.claude/pilot-mode"
  # The history comes at 0.2.0, in assisted. WS2 chose auto; ws3 has a link at the file; ws4 a .claude/ read-only.
  prompt_log_week "$WS"
  mkdir -p "$WS/projects/billing-api" "$ws3/projects/billing-api" "$ws4/projects/billing-api"
  printf 'auto\n' >"$WS2/.claude/pilot-mode"
  ws2_before="$(inode_mtime "$WS2/.claude/pilot-mode")"
  ln -s "$T/elsewhere" "$ws3/.claude/pilot-mode"
  chmod 555 "$ws4/.claude"
  sleep 1
  run_aiwp_in "$WS" rollback
  rc_is 0
  has "rolled back: 0.2.0 -> 0.1.0"
  has "pilot mode: assisted kept as the default of this workspace, for the next update; /pilot auto changes it"
  content_is "$WS/.claude/pilot-mode" assisted
  mode_is "$WS/.claude/pilot-mode" 644
  [ -z "$(find "$WS/.claude" -name '.pilot-mode.*')" ]; check "no temporary file left" $?
  run_aiwp_in "$WS2" rollback
  rc_is 0
  hasnt "pilot mode:"
  content_is "$WS2/.claude/pilot-mode" auto
  [ "$(inode_mtime "$WS2/.claude/pilot-mode")" = "$ws2_before" ]; check "a chosen default is never rewritten" $?
  run_aiwp_in "$ws3" rollback
  rc_is 0
  hasnt "pilot mode:"
  [ -L "$ws3/.claude/pilot-mode" ]; check "a link at the file is left alone" $?
  absent "$T/elsewhere"
  run_aiwp_in "$ws4" rollback
  chmod 755 "$ws4/.claude"
  rc_is 0
  has "rolled back: 0.2.0 -> 0.1.0"
  has "warning: could not write .claude/pilot-mode; the next aiwp update may set the default pilot mode to auto"
  absent "$ws4/.claude/pilot-mode"
  # The next update, from a core with no rules/assisted.md and with history: the default stays the person's.
  run_aiwp_in "$T" update "$WS"
  rc_is 0
  has "updated: 0.1.0 -> 0.2.0"
  hasnt "pilot mode: auto kept"
  content_is "$WS/.claude/pilot-mode" assisted
}

test_crash_mid_update_is_undone_by_the_next_run() {
  fixture
  setup_ws || return
  publish_v2
  AIWP_TEST_DIE_AFTER_SWAPS=2 run_aiwp_in "$WS" update --all
  [ "$RC" -ne 0 ]; check "the run was killed" $?
  present "$WS/.aiwp/journal"
  [ "$(manifest_field version)" = 0.1.0 ]; check "manifest still 0.1.0 after the crash" $?
  run_aiwp_in "$WS" version
  has "attention: an aiwp update or rollback stopped halfway"
  present "$WS/.aiwp/journal"
  # The opening never swaps a file: it refuses and names the way out.
  run_aiwp_in "$WS"
  rc_is 1
  has "stopped halfway in this workspace; run aiwp repair"
  hasnt "claude-stub"
  present "$WS/.aiwp/journal"
  run_aiwp_in "$WS" repair
  rc_is 0
  has "recovering: the last aiwp update stopped halfway; restoring version 0.1.0"
  has "recovered: version 0.1.0 restored"
  absent "$WS/.aiwp/journal"
  absent "$WS/docs/new.md"
  absent "$WS/scripts/new-tool.sh"
  content_is "$WS/docs/change.md" "change v1"
  content_is "$WS/docs/old.md" "removed in v0.2.0"
  mode_is "$WS/docs" 555
  mode_is "$WS/scripts" 555
  mode_is "$WS" 555
  [ -z "$(find "$WS" -name '.aiwp-tmp.*')" ]; check "no temp file left" $?
  run_aiwp_in "$WS" repair
  has "nothing to repair"
  run_aiwp_in "$WS" update --all
  rc_is 0
  has "updated: 0.1.0 -> 0.2.0"
}

test_rollback_pins_and_update_clears_the_pin() {
  fixture
  setup_ws || return
  run_aiwp_in "$WS" rollback
  rc_is 1
  has "nothing to roll back to"
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 0
  echo mine >"$WS/projects/mine.txt"
  run_aiwp_in "$WS" rollback
  rc_is 0
  has "rolled back: 0.2.0 -> 0.1.0; pinned at 0.1.0"
  [ "$(manifest_field version)" = 0.1.0 ]; check "manifest back at 0.1.0" $?
  content_is "$WS/.aiwp/pin" 0.1.0
  content_is "$WS/docs/change.md" "change v1"
  content_is "$WS/docs/old.md" "removed in v0.2.0"
  content_is "$WS/docs/gone/only.md" "removed with its folder in v0.2.0"
  absent "$WS/docs/new.md"
  absent "$WS/scripts/new-tool.sh"
  mode_is "$WS/docs/old.md" 444
  mode_is "$WS/docs/gone" 555
  mode_is "$WS" 555
  content_is "$WS/projects/mine.txt" mine
  run_aiwp_in "$WS" repair
  has "nothing to repair"
  run_aiwp_in "$WS"
  rc_is 0
  has "this workspace is pinned at 0.1.0"
  has "claude-stub"
  [ "$(manifest_field version)" = 0.1.0 ]; check "a pinned workspace does not update on open" $?
  run_aiwp_in "$WS" version
  has "pinned at: 0.1.0"
  run_aiwp_in "$WS" list
  has "pinned at 0.1.0"
  # Update all leaves a pinned workspace alone; naming it updates it.
  run_aiwp_in "$WS" update --all
  rc_is 0
  has "skipped: pinned"
  [ "$(manifest_field version)" = 0.1.0 ]; check "update --all keeps the pin" $?
  run_aiwp_in "$T" update "$WS"
  rc_is 0
  has "updated: 0.1.0 -> 0.2.0"
  absent "$WS/.aiwp/pin"
}

test_crash_mid_rollback_is_undone_by_the_next_run() {
  fixture
  setup_ws || return
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 0
  AIWP_TEST_DIE_AFTER_SWAPS=3 run_aiwp_in "$WS" rollback
  [ "$RC" -ne 0 ]; check "the rollback was killed" $?
  present "$WS/.aiwp/journal"
  run_aiwp_in "$WS" repair
  rc_is 0
  has "recovering: the last aiwp rollback stopped halfway; restoring version 0.2.0"
  absent "$WS/.aiwp/journal"
  absent "$WS/.aiwp/pin"
  content_is "$WS/docs/change.md" "change v2"
  content_is "$WS/docs/new.md" "new in v0.2.0"
  absent "$WS/docs/old.md"
  absent "$WS/docs/gone"
  mode_is "$WS/docs" 555
  [ -z "$(find "$WS" -name '.aiwp-tmp.*' -o -name 'work.*' -path '*/.aiwp/*')" ]; check "no leftovers" $?
  run_aiwp_in "$WS" repair
  has "nothing to repair"
}

main aiwp-update "$@"
