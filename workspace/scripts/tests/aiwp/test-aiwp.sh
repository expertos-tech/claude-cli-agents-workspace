#!/usr/bin/env bash
# Tests of install.sh, aiwp new, the opening, the release check and notice, a core changed by hand (update stops, repair
# fixes), the registry, the refusals inside a session and the self-update of scripts/aiwp.sh. The shared fixture and
# helpers: lib.sh (fully offline).
# Run: bash scripts/tests/aiwp/test-aiwp.sh [--only <test_name>]
# shellcheck disable=SC2319  # check reads the status of the test right before it, on purpose
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTICE="$(cd "$HERE/../.." && pwd)/release-notice.sh"
SETTINGS="$(cd "$HERE/../../.." && pwd)/rules/agents/settings.json"
# shellcheck source=scripts/tests/aiwp/lib.sh
. "$HERE/lib.sh"

# --- install.sh

test_install_linux() {
  fixture
  run_install
  rc_is 0
  [ -d "$DATA/.git" ]; check "data folder cloned under XDG_DATA_HOME" $?
  [ "$(git -C "$DATA" describe --tags --exact-match HEAD 2>/dev/null)" = v0.1.0 ]; check "checked out v0.1.0" $?
  [ -L "$HOME/.local/bin/aiwp" ]; check "aiwp is a link" $?
  [ "$(readlink "$HOME/.local/bin/aiwp")" = "$DATA/workspace/scripts/aiwp.sh" ]; check "link target" $?
  has "is not on PATH"
  # shellcheck disable=SC2016  # the literal line the installer prints
  has 'export PATH="$HOME/.local/bin:$PATH"'
  has "Installed the data folder only"
  has "aiwp new ~/my-workspace"
  has "cd ~/my-workspace && aiwp"
  absent "$T/sudo-called"
  ! grep -qE '(^|[^a-z])sudo [a-z-]' "$INSTALLER"; check "the installer calls no sudo" $?
}

test_install_warns_about_docker_and_claude() {
  fixture
  local tool
  mkdir -p "$T/bin"
  for tool in git python3 mkdir dirname ls grep sed sort tail cat ln rm; do ln -s "$(command -v "$tool")" "$T/bin/$tool"; done
  OUT="$(PATH="$T/bin" AIWP_OS=linux notty "$(command -v bash)" "$INSTALLER" 2>&1)"
  RC=$?
  rc_is 0
  has "warning: docker not found"
  has "warning: claude not found"
  [ -L "$HOME/.local/bin/aiwp" ]; check "installed anyway" $?
}

test_install_again_updates_and_path_ok() {
  fixture
  run_install
  publish_v2
  PATH="$HOME/.local/bin:$PATH" run_install
  rc_is 0
  has "updating:"
  hasnt "is not on PATH"
  [ "$(git -C "$DATA" describe --tags --exact-match HEAD)" = v0.2.0 ]; check "moved to v0.2.0" $?
}

test_install_ref_override() {
  fixture
  publish_v2
  AIWP_REF=v0.1.0 run_install
  rc_is 0
  [ "$(git -C "$DATA" describe --tags --exact-match HEAD)" = v0.1.0 ]; check "AIWP_REF wins over the newest tag" $?
}

# Pushes a commit to the branch developer of the test's remote, which the fixture lacks: the first on top of v0.1.0
# (VERSION 0.1.0), each next one on top of the last; workspace/docs/dev.md holds $1. Sets DEV_SHA to the commit.
publish_developer() {
  local src="$T/dev-src"
  if [ ! -d "$src" ]; then
    git clone -q "$T/remote.git" "$src"
    git -C "$src" checkout -q -b developer v0.1.0
  fi
  fx_write "$src" workspace/docs/dev.md "$1"
  fx_commit "$src" "developer: $1"
  git -C "$src" push -q origin HEAD:refs/heads/developer
  DEV_SHA="$(git -C "$src" rev-parse HEAD)"
}

test_install_developer_checks_out_the_branch() {
  fixture
  publish_v2
  publish_developer "dev one"
  run_install --developer
  rc_is 0
  [ "$(git -C "$DATA" rev-parse HEAD)" = "$DEV_SHA" ]; check "--developer: the developer commit, not v0.2.0" $?
  has "checked out: developer (0.1.0)"
  has "note: developer is not a release: aiwp update moves this installation only to a release newer than 0.1.0, never to a newer commit of developer"
  # After the folder, repeated, over AIWP_REF: the newest developer commit, and the workspace made from it.
  publish_developer "dev two"
  AIWP_REF=v0.1.0 run_install "$WS" --developer --developer
  rc_is 0
  [ "$(git -C "$DATA" rev-parse HEAD)" = "$DEV_SHA" ]; check "--developer wins over AIWP_REF and follows developer" $?
  content_is "$WS/docs/dev.md" "dev two"
  # Without it, the installer goes back to the newest release.
  run_install
  rc_is 0
  [ "$(data_tag)" = v0.2.0 ]; check "no --developer: back to the newest release" $?
  hasnt "not a release"
}

test_install_developer_and_aiwp_update() {
  fixture
  publish_developer "dev one"
  local first="$DEV_SHA"
  # The pipe form, the option before the folder.
  OUT="$(notty bash -s -- --developer "$WS" <"$INSTALLER" 2>&1)"
  RC=$?
  rc_is 0
  content_is "$WS/docs/dev.md" "dev one"
  # aiwp update leaves the developer commit while no release is newer than its VERSION, even when developer moved.
  publish_developer "dev two"
  run_aiwp_in "$T" update --all
  rc_is 0
  [ "$(git -C "$DATA" rev-parse HEAD)" = "$first" ]; check "aiwp update never follows developer" $?
  # A newer release: aiwp update moves the data folder and the workspace to it.
  publish_v2
  run_aiwp_in "$T" update --all
  rc_is 0
  [ "$(data_tag)" = v0.2.0 ]; check "aiwp update moves to a newer release" $?
  content_is "$WS/docs/change.md" "change v2"
}

test_install_developer_usage_errors() {
  fixture
  run_install --developer a b
  rc_is 2
  has "one workspace folder only"
  run_install a --developer b
  rc_is 2
  run_install --developer --bogus
  rc_is 2
  has "unknown option: --bogus"
  absent "$DATA"
  run_install --help
  rc_is 0
  has "Usage: bash install.sh [--developer] [<workspace folder>] [--help]"
  has "developer/install.sh | bash -s -- --developer ~/my-workspace"
  # A remote with no branch developer: refused, and nothing is linked.
  run_install --developer
  rc_is 1
  has "has no branch developer"
  absent "$HOME/.local/bin/aiwp"
}

test_install_macos_data_folder() {
  fixture
  AIWP_OS=macos run_install
  rc_is 0
  [ -d "$HOME/Library/Application Support/claude-cli-agents-workspace/.git" ]; check "macOS data folder" $?
  absent "$DATA"
}

test_install_refuses_native_windows() {
  fixture
  AIWP_OS=windows run_install
  rc_is 1
  has "WSL2"
  absent "$DATA"
  absent "$HOME/.local/bin/aiwp"
}

test_install_missing_prerequisite() {
  fixture
  mkdir -p "$T/onlygit"
  ln -s "$(command -v git)" "$T/onlygit/git"
  OUT="$(PATH="$T/onlygit" AIWP_OS=linux notty "$(command -v bash)" "$INSTALLER" 2>&1)"
  RC=$?
  rc_is 1
  has "missing prerequisites: python3"
  absent "$DATA"
}

# --- install.sh creates the workspace

test_install_empty_folder_install_here() {
  fixture
  mkdir -p "$T/empty"
  answers "$T/answers" "Choose [1-2]:" 1 "custom layer repository" "" "Preferred language" portuguese
  in_pty "$T/empty" "$T/answers" bash "$INSTALLER"
  rc_is 0
  has "1) Install here: $T/empty"
  has "2) Give another path"
  has "created: $T/empty (version 0.1.0, v0.1.0)"
  [ "$(version_of "$T/empty")" = 0.1.0 ]; check "workspace created in the current folder" $?
  [ -d "$T/empty/custom/.git" ]; check "custom answered on the terminal: a local repository" $?
  [ "$(registry_paths)" = "$T/empty" ]; check "registered" $?
  # The language answered on the terminal, through the installer: the native setting of Claude Code.
  has "language: portuguese, in .claude/settings.local.json"
  content_is "$T/empty/.claude/settings.local.json" $'{\n  "language": "portuguese"\n}'
}

test_install_empty_folder_another_path() {
  fixture
  mkdir -p "$T/empty" "$T/full"
  echo mine >"$T/full/mine.txt"
  answers "$T/answers" "Choose [1-2]:" 3 "Answer 1 or 2." 2 "(a new or an empty folder):" "$T/full" \
    "give a new or an empty folder." "$T/ws-other" "custom layer repository" "" "Preferred language" ""
  in_pty "$T/empty" "$T/answers" bash "$INSTALLER"
  rc_is 0
  has "$T/full is not empty: give a new or an empty folder."
  has "created: $T/ws-other"
  absent "$T/ws-other/.claude/settings.local.json"
  [ "$(version_of "$T/ws-other")" = 0.1.0 ]; check "workspace created in the path given" $?
  [ -z "$(ls -A "$T/empty")" ]; check "the current folder stays empty" $?
  content_is "$T/full/mine.txt" mine
}

test_install_non_empty_folder_asks_only_the_path() {
  fixture
  mkdir -p "$T/cwd"
  echo mine >"$T/cwd/mine.txt"
  # shellcheck disable=SC2088  # the answer a person types: the installer expands the ~
  answers "$T/answers" "(a new or an empty folder):" "" "(a new or an empty folder):" "$T/cwd/mine.txt" \
    "not a folder: give a new or an empty folder." "~/ws-home" "custom layer repository" "" "Preferred language" ""
  # As curl | bash runs it: the script on stdin, the answers from the terminal.
  # shellcheck disable=SC2016  # $1 expands in the inner bash
  in_pty "$T/cwd" "$T/answers" bash -c 'cat "$1" | bash' _ "$INSTALLER"
  rc_is 0
  has "This folder is not empty ($T/cwd)"
  hasnt "Install here"
  has "created: $HOME/ws-home"
  absent "$HOME/ws-home/.claude/settings.local.json"
  [ "$(version_of "$HOME/ws-home")" = 0.1.0 ]; check "~ expands to HOME" $?
}

test_install_again_can_only_update_the_installation() {
  fixture
  run_install
  publish_v2
  mkdir -p "$T/empty" "$T/cwd"
  echo mine >"$T/cwd/mine.txt"
  answers "$T/answers" "Choose [1-3]:" 3
  in_pty "$T/empty" "$T/answers" bash "$INSTALLER"
  rc_is 0
  has "3) No new workspace: only update the installation"
  has "Updated the installation; no new workspace"
  [ "$(data_tag)" = v0.2.0 ]; check "the data folder moved" $?
  [ -z "$(ls -A "$T/empty")" ]; check "no workspace created" $?
  answers "$T/answers" "empty: only update the installation):" ""
  in_pty "$T/cwd" "$T/answers" bash "$INSTALLER"
  rc_is 0
  has "Updated the installation; no new workspace"
  # The installer and aiwp update share one lock: while one holds it, the other stops and names the pid.
  hold_lock "$DATA/.git/aiwp/update.lock"
  AIWP_WORKSPACE="$T/ws-locked" run_install
  rc_is 1
  has "an aiwp update is running (pid $HOLDER)"
  absent "$T/ws-locked"
  run_aiwp_in "$T" update --all
  rc_is 1
  has "another aiwp update is running (pid $HOLDER)"
  kill "$HOLDER" 2>/dev/null
  wait "$HOLDER" 2>/dev/null
  # A holder that is gone leaves no lock behind: the kernel drops it.
  AIWP_WORKSPACE="$T/ws-after" run_install
  rc_is 0
  run_aiwp_in "$T" update --all
  rc_is 0
}

test_version_and_list_read_a_large_manifest() {
  fixture
  setup_ws || return
  # A manifest of the size of the real product (hundreds of files): head -n 1 closes the pipe early.
  chmod u+w "$WS/.aiwp"
  python3 -I - "$WS/.aiwp/manifest.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
data["files"] += [{"path": f"pad/{i:05d}-" + "x" * 150, "sha256": "0" * 64, "mode": "444"} for i in range(2000)]
import os
os.chmod(path, 0o644)
json.dump(data, open(path, "w"), indent=2)
PY
  run_aiwp_in "$WS" version
  rc_is 0
  has "workspace: 0.1.0"
  hasnt "Traceback"
  run_aiwp_in "$WS" list
  rc_is 0
  has "1  0.1.0"
  hasnt "Traceback"
}

test_install_no_tty_takes_the_folder_from_the_environment_or_the_argument() {
  fixture
  AIWP_WORKSPACE="$T/from-env" run_install
  rc_is 0
  has "created: $T/from-env"
  hasnt "Installed the data folder only"
  [ "$(version_of "$T/from-env")" = 0.1.0 ]; check "AIWP_WORKSPACE" $?
  [ -d "$T/from-env/custom/.git" ]; check "a local custom skeleton with no terminal" $?
  AIWP_WORKSPACE="$T/ignored" run_install "$T/from-arg"
  rc_is 0
  [ "$(version_of "$T/from-arg")" = 0.1.0 ]; check "the argument wins over AIWP_WORKSPACE" $?
  absent "$T/ignored"
  [ "$(registry_paths | tr '\n' ' ')" = "$T/from-env $T/from-arg " ]; check "both registered" $?
  # The form a pipe uses: bash -s -- <folder>, the script on stdin.
  OUT="$(notty bash -s -- "$T/from-pipe" <"$INSTALLER" 2>&1)"
  RC=$?
  rc_is 0
  [ "$(version_of "$T/from-pipe")" = 0.1.0 ]; check "curl | bash -s -- <folder>" $?
  # A folder with content: refused before anything is installed.
  mkdir -p "$T/full"
  echo mine >"$T/full/mine.txt"
  rm -rf "$DATA"
  AIWP_WORKSPACE="$T/full" run_install
  rc_is 1
  has "is not empty: the workspace goes into a new or an empty folder; nothing was installed"
  absent "$DATA"
  run_install --bogus
  rc_is 2
  run_install a b
  rc_is 2
}

# --- aiwp new

test_new_layout_and_modes() {
  fixture
  setup_ws || return
  has "created: $WS (version 0.1.0, v0.1.0)"
  has "setup-claude stub ran"
  has "cd $WS && aiwp"
  absent "$WS/.git"
  mode_is "$WS" 555
  mode_is "$WS/docs" 555
  mode_is "$WS/docs/gone" 555
  mode_is "$WS/scripts" 555
  mode_is "$WS/AGENTS.md" 444
  mode_is "$WS/docs/keep.md" 444
  mode_is "$WS/scripts/aiwp.sh" 555
  mode_is "$WS/scripts/setup-claude.sh" 555
  local d
  for d in custom projects tmp logs .claude .history tools/observability/.data; do
    [ -d "$WS/$d" ]; check "writable folder $d" $?
    [ -w "$WS/$d" ]; check "$d is writable" $?
  done
  mode_is "$WS/tmp" 755
  mode_is "$WS/logs" 755
  ! manifest_paths | grep -q '^logs/'; check "logs/ is never in the manifest" $?
  mode_is "$WS/tools/observability/.data" 755
  absent "$WS/projects/README.md"
  absent "$WS/logs/README.md"
  mode_is "$WS/tools/container-console-colima/internal/webui/dist" 755
  mode_is "$WS/tools/container-console-colima/internal/webui/dist/placeholder.html" 444
  absent "$WS/tools/azurite-console"
  present "$WS/.claude/setup-stamp"
  # No terminal: the language is never asked, and nothing is written.
  hasnt "Preferred language"
  absent "$WS/.claude/settings.local.json"
  # The product only: nothing of the repository root.
  content_is "$WS/README.md" "PRODUCT README"
  local f
  for f in CLAUDE.md LICENSE install.sh maintainers tests i18n .claude/settings.json; do absent "$WS/$f"; done
  [ "$(core_files_on_disk)" = "$(git --git-dir="$T/remote.git" ls-tree -r --name-only v0.1.0 -- workspace/ |
    sed 's|^workspace/||' | grep -Ev '^(projects|logs)/' | sort)" ]
  check "the core on disk is exactly the tracked files of workspace/" $?
  # The manifest.
  [ "$(manifest_field version)" = 0.1.0 ]; check "manifest version" $?
  [ "$(manifest_field tag)" = v0.1.0 ]; check "manifest tag" $?
  [ "$(manifest_field commit)" = "$(git -C "$DATA" rev-parse HEAD)" ]; check "manifest commit" $?
  [ "$(manifest_paths | sort)" = "$(git --git-dir="$T/remote.git" ls-tree -r --name-only v0.1.0 -- workspace/ |
    sed 's|^workspace/||' | grep -Ev '^(projects|logs)/' | sort)" ]
  check "manifest paths are exactly workspace/, without the user folders" $?
  python3 -I - "$WS" <<'PY'
import hashlib, json, os, sys
root = sys.argv[1]
m = json.load(open(os.path.join(root, ".aiwp/manifest.json")))
for f in m["files"]:
    p = os.path.join(root, f["path"])
    assert hashlib.sha256(open(p, "rb").read()).hexdigest() == f["sha256"], f["path"]
    assert format(os.stat(p).st_mode & 0o777, "o") == f["mode"], f["path"]
    assert f["mode"] in ("444", "555")
PY
  check "manifest hashes and modes match the files" $?
  # The custom skeleton, with no terminal.
  [ -d "$WS/custom/.git" ]; check "custom is a git repo" $?
  [ "$(git -C "$WS/custom" rev-list --count HEAD)" = 1 ]; check "custom skeleton committed" $?
  grep -qx 'env/' "$WS/custom/.gitignore"; check "custom ignores env/" $?
  ! grep -qv '^#' "$WS/custom/core-terms.txt"; check "core-terms.txt has comment lines only" $?
  present "$WS/custom/README.md"
  git -C "$WS/custom" ls-files --error-unmatch requests/.gitkeep >/dev/null 2>&1
  check "custom/requests/ is in the first commit" $?
  grep -q 'doing/. while in progress' "$WS/custom/README.md"; check "the custom README names requests/doing/" $?
  # The core cannot be changed in place.
  ! (echo x >>"$WS/AGENTS.md") 2>/dev/null; check "a core file cannot be written" $?
  ! touch "$WS/docs/new-file" 2>/dev/null; check "no file can be created in a core folder" $?
}

test_new_refuses_non_empty_folder() {
  fixture
  run_install
  mkdir -p "$WS"
  echo mine >"$WS/mine.txt"
  run_aiwp_in "$T" new "$WS"
  rc_is 1
  has "is not empty. Install into a new folder"
  has "/normalize-projects"
  content_is "$WS/mine.txt" mine
}

test_new_usage_errors() {
  fixture
  run_install
  run_aiwp_in "$T" new
  rc_is 2
  run_aiwp_in "$T" new "$WS" --bogus
  rc_is 2
  run_aiwp_in "$T" --help
  rc_is 0
  has "aiwp new <folder>"
}

test_new_custom_from_url() {
  fixture
  run_install
  git init -q --bare -b main "$T/custom-empty.git"
  run_aiwp_in "$T" new "$WS" --custom "$T/custom-empty.git"
  rc_is 0
  has "the repository was empty; a skeleton was committed"
  [ "$(git -C "$WS/custom" remote get-url origin)" = "$T/custom-empty.git" ]; check "custom cloned from the URL" $?
  present "$WS/custom/core-terms.txt"
  [ "$(git -C "$WS/custom" rev-list --count HEAD)" = 1 ]; check "an empty remote gets one skeleton commit" $?
  git -C "$WS/custom" ls-files --error-unmatch requests/.gitkeep >/dev/null 2>&1
  check "an empty remote's skeleton holds custom/requests/" $?
  # A repository with content is cloned as it is.
  git clone -q "$T/custom-empty.git" "$T/c2" 2>/dev/null
  echo "my rules" >"$T/c2/notes.md"
  git -C "$T/c2" add notes.md && git -C "$T/c2" -c user.name=t -c user.email= commit -q -m notes
  git -C "$T/c2" push -q origin HEAD:refs/heads/main
  run_aiwp_in "$T" new "$T/ws2" --custom "$T/custom-empty.git"
  rc_is 0
  has "custom/: cloned from"
  present "$T/ws2/custom/notes.md"
}

test_new_failure_leaves_nothing() {
  fixture
  run_install
  run_aiwp_in "$T" new "$WS" --custom "$T/no-such-repo.git"
  rc_is 1
  has "could not clone the custom layer"
  absent "$WS"
}

# --- aiwp new: the preferred language of communication

# Runs subcommand $1 of the python helper embedded in aiwp.sh (its py function) with the remaining arguments: the
# helper's own code, read from the script under test. Sets OUT and RC.
aiwp_py() {
  OUT="$(awk "/<<'PY'\$/ && !seen { on = 1; seen = 1; next } /^PY\$/ { on = 0 } on" "$AIWP" | "$PY3" -I - "$@" 2>&1)"
  RC=$?
}

test_new_asks_the_language_on_a_terminal() {
  fixture
  run_install
  local long
  long="$(printf 'a%.0s' $(seq 1 41))"
  # Invalid answers are asked again; the valid one is stored trimmed, as typed.
  answers "$T/answers" "custom layer repository" "" "Preferred language" "portugu3se" "Preferred language" "português" \
    "Preferred language" "$long" "Preferred language" "  portuguese  "
  in_pty "$T" "$T/answers" "$HOME/.local/bin/aiwp" new "$WS"
  rc_is 0
  has "created: $WS"
  has "not a language name: use only English letters, spaces, hyphens and parentheses."
  has "not a language name: at most 40 characters."
  [ "$(grep -o 'Preferred language of communication with Claude' <<<"$OUT" | wc -l | tr -d ' ')" = 4 ]
  check "asked four times" $?
  has "language: portuguese, in .claude/settings.local.json"
  content_is "$WS/.claude/settings.local.json" $'{\n  "language": "portuguese"\n}'
  # The setup ran after the question, and the file stays where the person can edit it.
  present "$WS/.claude/setup-stamp"
  [ -w "$WS/.claude/settings.local.json" ]; check "settings.local.json is writable" $?
  # An empty answer writes nothing.
  answers "$T/answers" "custom layer repository" "" "Preferred language" ""
  in_pty "$T" "$T/answers" "$HOME/.local/bin/aiwp" new "$T/ws2"
  rc_is 0
  has "created: $T/ws2"
  hasnt "language: "
  absent "$T/ws2/.claude/settings.local.json"
  # The end of input (Ctrl-D) writes nothing, and the workspace is still created.
  answers "$T/answers" "custom layer repository" "" "Preferred language" $'\x04'
  in_pty "$T" "$T/answers" "$HOME/.local/bin/aiwp" new "$T/ws3"
  rc_is 0
  has "created: $T/ws3"
  absent "$T/ws3/.claude/settings.local.json"
  [ "$(version_of "$T/ws3")" = 0.1.0 ]; check "workspace created after the end of input" $?
}

test_settings_language_keeps_other_keys() {
  fixture
  mkdir -p "$T/s"
  local f="$T/s/settings.local.json"
  printf '{"model": "sonnet", "language": "spanish", "permissions": {"allow": ["Bash(ls)"]}}' >"$f"
  chmod 600 "$f"
  aiwp_py settings-language "$f" portuguese
  rc_is 0
  "$PY3" -I -c 'import json, sys
data = json.load(open(sys.argv[1]))
assert list(data) == ["model", "language", "permissions"], list(data)
assert data["language"] == "portuguese" and data["model"] == "sonnet", data
assert data["permissions"] == {"allow": ["Bash(ls)"]}, data' "$f"
  check "language replaced, every other key kept in its place" $?
  grep -q '^  "model": "sonnet",$' "$f"; check "2-space indent" $?
  mode_is "$f" 600
  [ "$(ls -A "$T/s")" = settings.local.json ]; check "no temp file left" $?
  # A missing file is created with the key alone.
  aiwp_py settings-language "$T/s/new.json" spanish
  rc_is 0
  content_is "$T/s/new.json" $'{\n  "language": "spanish"\n}'
  # A file that is not a JSON object, or not JSON, or not a regular file, is left as it is, with a warning.
  printf '["language"]\n' >"$T/s/list.json"
  cp "$T/s/list.json" "$T/s/list.orig"
  aiwp_py settings-language "$T/s/list.json" portuguese
  rc_is 1
  has "is not a JSON object; it was left as it is"
  cmp -s "$T/s/list.json" "$T/s/list.orig"; check "a JSON list is left as it is" $?
  printf '{"model": \n' >"$T/s/bad.json"
  cp "$T/s/bad.json" "$T/s/bad.orig"
  aiwp_py settings-language "$T/s/bad.json" portuguese
  rc_is 1
  has "cannot be read"
  cmp -s "$T/s/bad.json" "$T/s/bad.orig"; check "invalid JSON is left as it is" $?
  ln -s new.json "$T/s/link.json"
  aiwp_py settings-language "$T/s/link.json" portuguese
  rc_is 1
  [ -L "$T/s/link.json" ]; check "a link stays a link" $?
  content_is "$T/s/new.json" $'{\n  "language": "spanish"\n}'
}

test_update_and_opening_keep_the_language_setting() {
  fixture
  setup_ws || return
  local f="$WS/.claude/settings.local.json" before
  printf '{\n  "permissions": {"allow": ["Bash(ls)"]},\n  "language": "portuguese"\n}\n' >"$f"
  cp "$f" "$T/before.json"
  before="$(inode_mtime "$f")"
  publish_v2
  # update in a terminal: it never asks the language and never touches the file.
  answers "$T/answers" "Choose [1]:" ""
  in_pty "$T" "$T/answers" "$HOME/.local/bin/aiwp" update
  rc_is 0
  hasnt "Preferred language"
  [ "$(version_of "$WS")" = 0.2.0 ]; check "updated to 0.2.0" $?
  cmp -s "$T/before.json" "$f"; check "update: settings.local.json byte for byte the same" $?
  # The opening (which runs setup-claude.sh), rollback and repair do not touch it either.
  run_aiwp_in "$WS"
  rc_is 0
  run_aiwp_in "$WS" rollback
  rc_is 0
  run_aiwp_in "$WS" repair
  rc_is 0
  hasnt "Preferred language"
  cmp -s "$T/before.json" "$f"; check "opening, rollback, repair: byte for byte the same" $?
  [ "$(inode_mtime "$f")" = "$before" ]; check "never rewritten (same inode and mtime)" $?
}

# --- opening

test_open_runs_setup_and_claude_at_the_root() {
  fixture
  setup_ws || return
  run_aiwp_in "$WS/docs" -- --resume abc
  rc_is 0
  has "claude-stub cwd=$WS args=--resume abc"
  run_aiwp_in "$WS" -- --model sonnet
  has "args=--model sonnet"
  content_is "$WS/.claude/setup-stamp" "ran --quiet"
}

test_unknown_command_is_a_usage_error() {
  fixture
  setup_ws || return
  local word
  for word in --model sonnet updat --resume; do
    run_aiwp_in "$WS" "$word"
    rc_is 2
    has "unknown command: $word"
    hasnt "claude-stub"
  done
}

test_outside_a_workspace() {
  fixture
  run_install
  run_aiwp_in "$T"
  rc_is 1
  has "not inside a workspace"
  run_aiwp_in "$T" update now
  rc_is 1
  has "not a workspace: now"
  run_aiwp_in "$T" update a b
  rc_is 2
  run_aiwp_in "$T" update --all "$T"
  rc_is 2
}

test_release_check_cached_a_day_and_offline() {
  fixture
  setup_ws || return
  run_aiwp_in "$WS" check
  rc_is 0
  has "up to date: 0.1.0"
  publish_v2
  run_aiwp_in "$WS" check
  has "up to date: 0.1.0"
  hasnt "0.2.0"
  age_cache
  run_aiwp_in "$WS" check --quiet
  rc_is 0
  has "attention: Claude CLI Agents Workspace 0.2.0 is available (this workspace: 0.1.0); close every session of it and run aiwp update in a terminal"
  [ "$(git -C "$DATA" describe --tags --exact-match HEAD)" = v0.1.0 ]; check "check never updates" $?
  # Offline: one warning line, and the workspace still opens.
  mv "$T/remote.git" "$T/remote-away.git"
  age_cache
  run_aiwp_in "$WS" check --quiet
  rc_is 0
  [ -z "$OUT" ]; check "check --quiet says nothing offline" $?
  run_aiwp_in "$WS" check
  has "warning: could not check for a new release"
  age_cache
  run_aiwp_in "$WS"
  rc_is 0
  has "warning: could not check for a new release"
  has "claude-stub"
  [ "$(manifest_field version)" = 0.1.0 ]; check "offline keeps the version" $?
}

# Runs the release-notice hook of this repository for workspace $1, as Claude Code does (hook JSON on stdin), with
# the source $2 (default startup).
run_notice() {
  OUT="$(printf '{"hook_event_name":"SessionStart","source":"%s"}' "${2:-startup}" | CLAUDE_PROJECT_DIR="$1" bash "$NOTICE" 2>&1)"
  RC=$?
}

# The pilot line of a workspace with no .claude/pilot-mode.
PILOT_ASSISTED="Pilot mode: assisted (the default of this installation). Read rules/assisted.md in full before your first reply and follow it."

# Succeeds when the hook said nothing about a release: no output, or only the pilot line.
no_release_notice() {
  [ -z "$OUT" ] && return 0
  [ "$(notice_context)" = "$PILOT_ASSISTED" ]
}

# Prints the additionalContext of the hook output, or fails when it is not the SessionStart hook JSON.
notice_context() {
  printf '%s' "$OUT" | python3 -I -c 'import json, sys
data = json.load(sys.stdin)["hookSpecificOutput"]
assert data["hookEventName"] == "SessionStart"
print(data["additionalContext"])'
}

test_release_notice_tells_the_session_and_never_updates() {
  fixture
  setup_ws || return
  run_notice "$WS"
  rc_is 0
  no_release_notice; check "nothing new: no release notice" $?
  publish_v2
  age_cache
  local before
  before="$(core_files_on_disk | (cd "$WS" && xargs cat) | cksum)"
  run_notice "$WS"
  rc_is 0
  OUT="$(notice_context)"; check "valid SessionStart JSON" $?
  has "A new workspace version 0.2.0 was detected (this workspace: 0.1.0). Tell the person to close this session and run \`aiwp update\` in a terminal."
  has "Never run aiwp update, rollback or repair yourself"
  [ "$(printf '%s\n' "$OUT" | head -n 1)" = "$PILOT_ASSISTED" ]; check "the pilot line comes first, on its own line" $?
  [ "$(git -C "$DATA" describe --tags --exact-match HEAD)" = v0.1.0 ]; check "the hook never moves the data folder" $?
  [ "$(manifest_field version)" = 0.1.0 ]; check "the hook never updates the workspace" $?
  [ "$(core_files_on_disk | (cd "$WS" && xargs cat) | cksum)" = "$before" ]; check "the core is untouched" $?
  # The day's answer is kept: a second session start does not ask the remote again.
  mv "$T/remote.git" "$T/remote-away.git"
  run_notice "$WS"
  OUT="$(notice_context)"; check "cached answer still tells" $?
  has "A new workspace version 0.2.0 was detected"
  # A pinned workspace (aiwp rollback) is left alone: aiwp update would clear the pin.
  echo v0.1.0 >"$WS/.aiwp/pin"
  run_notice "$WS"
  rc_is 0
  no_release_notice; check "pinned: no release notice" $?
  rm -f "$WS/.aiwp/pin"
  # An update that died halfway is told too.
  : >"$WS/.aiwp/journal"
  run_notice "$WS"
  OUT="$(notice_context)"; check "journal: valid JSON" $?
  has "An aiwp update or rollback stopped halfway in this workspace"
  rm -f "$WS/.aiwp/journal"
}

test_release_notice_is_silent_offline_and_outside_a_workspace() {
  fixture
  setup_ws || return
  publish_v2
  mv "$T/remote.git" "$T/remote-away.git"
  age_cache
  run_notice "$WS"
  rc_is 0
  no_release_notice; check "offline: no release notice" $?
  # A folder without .aiwp/manifest.json (the product repository, any other folder): silent, even with a newer release.
  mv "$T/remote-away.git" "$T/remote.git"
  age_cache
  mkdir -p "$T/plain/scripts"
  cp "$AIWP" "$T/plain/scripts/aiwp.sh"
  run_notice "$T/plain"
  rc_is 0
  no_release_notice; check "not an installed workspace: no release notice" $?
  # No installation in the data folder: silent.
  mv "$DATA" "$DATA.away"
  run_notice "$WS"
  rc_is 0
  no_release_notice; check "not installed: no release notice" $?
  mv "$DATA.away" "$DATA"
}

test_release_notice_is_bounded_in_time() {
  fixture
  setup_ws || return
  age_cache
  # A remote that never answers: git hangs; the check gives up within its limits and the hook stays silent.
  cat >"$T/stub/git" <<STUB
#!/usr/bin/env bash
case "\$*" in *ls-remote*) sleep 30 ;; esac
exec "$(command -v git)" "\$@"
STUB
  chmod 755 "$T/stub/git"
  local start
  start="$(date +%s)"
  run_notice "$WS"
  rc_is 0
  no_release_notice; check "a hanging remote: no release notice" $?
  [ $(($(date +%s) - start)) -lt 15 ]; check "a hanging remote: done within 15 s" $?
  rm -f "$T/stub/git"
  # An aiwp.sh that hangs (and leaves children holding its output): the hook stops waiting at its limit.
  local fake="$T/hanging"
  mkdir -p "$fake/.aiwp" "$fake/scripts"
  echo '{}' >"$fake/.aiwp/manifest.json"
  printf '#!/usr/bin/env bash\n(sleep 30; echo "attention: late") &\nsleep 30\n' >"$fake/scripts/aiwp.sh"
  start="$(date +%s)"
  OUT="$(echo '{}' | RELEASE_NOTICE_LIMIT_SECONDS=2 CLAUDE_PROJECT_DIR="$fake" bash "$NOTICE" 2>&1)"
  RC=$?
  rc_is 0
  [ "$(notice_context)" = "$PILOT_ASSISTED" ]; check "a hanging aiwp.sh: no release notice, the pilot line still told" $?
  [ $(($(date +%s) - start)) -lt 6 ]; check "a hanging aiwp.sh: the hook ends at its limit" $?
}

test_release_notice_is_registered_at_session_start() {
  python3 -I - "$SETTINGS" <<'PY'
import json, sys
hooks = json.load(open(sys.argv[1]))["hooks"]["SessionStart"]
block = next(b for b in hooks if any("setup-claude.sh" in h["command"] for h in b["hooks"]))
notice = [h for h in block["hooks"] if "scripts/release-notice.sh" in h["command"]]
assert notice and notice[0].get("timeout", 600) <= 30, notice
assert set(block["matcher"].split("|")) == {"startup", "resume", "clear", "compact"}, block["matcher"]
assert sum("release-notice.sh" in h["command"] for b in hooks for h in b["hooks"]) == 1
PY
  check "SessionStart runs release-notice.sh next to setup-claude.sh, with a short timeout, at every start source" $?
  OUT="$(bash "$NOTICE" --help)"
  has "never runs aiwp update"
  has "Pilot mode: auto (/pilot is turned off in custom/rules-config.json)."
}

# The pilot line, by source: startup, clear and compact say it; resume does not (the transcript keeps it); clear and
# compact never run the release check.
test_release_notice_tells_the_pilot_mode_by_source() {
  fixture
  setup_ws || return
  local src
  for src in startup clear compact; do
    run_notice "$WS" "$src"
    rc_is 0
    OUT="$(notice_context)"; check "$src: valid SessionStart JSON" $?
    [ "$OUT" = "$PILOT_ASSISTED" ]; check "$src: the assisted line, exactly" $?
  done
  run_notice "$WS" resume
  rc_is 0
  [ -z "$OUT" ]; check "resume: no pilot line and nothing new: no output" $?
  # No source on stdin (a run by hand): both parts.
  OUT="$(CLAUDE_PROJECT_DIR="$WS" bash "$NOTICE" </dev/null 2>&1)"
  OUT="$(notice_context)"; check "no source: valid JSON" $?
  [ "$OUT" = "$PILOT_ASSISTED" ]; check "no source: the pilot line" $?
  # The default of the installation.
  printf 'auto\n' >"$WS/.claude/pilot-mode"
  run_notice "$WS" clear
  OUT="$(notice_context)"
  [ "$OUT" = "Pilot mode: auto (the default of this installation)." ]; check "auto: the auto line" $?
  # clear and compact never ask about a release, even with one published.
  publish_v2
  age_cache
  for src in clear compact; do
    run_notice "$WS" "$src"
    OUT="$(notice_context)"
    hasnt "new workspace version"
  done
  run_notice "$WS" resume
  OUT="$(notice_context)"; check "resume: valid JSON" $?
  has "A new workspace version 0.2.0 was detected"
  hasnt "Pilot mode:"
  # A copy of the hook with no scripts/pilot-mode.sh next to it: no pilot line, the hook still ends well.
  local copy="$T/notice-alone"
  mkdir -p "$copy"
  cp "$NOTICE" "$copy/release-notice.sh"
  OUT="$(printf '{"source":"clear"}' | CLAUDE_PROJECT_DIR="$WS" bash "$copy/release-notice.sh" 2>&1)"
  RC=$?
  rc_is 0
  [ -z "$OUT" ]; check "no pilot-mode.sh: nothing to say" $?
}

test_open_never_updates() {
  fixture
  setup_ws || return
  publish_v2
  age_cache
  local before
  before="$(core_files_on_disk | (cd "$WS" && xargs cat) | cksum)"
  run_aiwp_in "$WS"
  rc_is 0
  has "A new workspace version 0.2.0 was detected (this workspace: 0.1.0). Run \`aiwp update\` to update; opening this workspace on 0.1.0."
  has "claude-stub cwd=$WS"
  hasnt "updated:"
  [ "$(manifest_field version)" = 0.1.0 ]; check "opened at 0.1.0" $?
  [ "$(data_tag)" = v0.1.0 ]; check "the data folder did not move" $?
  [ "$(core_files_on_disk | (cd "$WS" && xargs cat) | cksum)" = "$before" ]; check "the core is untouched" $?
  # The release is in the data folder already (another workspace updated it): still detection only.
  git -C "$DATA" fetch -q --tags origin
  git -C "$DATA" checkout -q --detach v0.2.0
  run_aiwp_in "$WS"
  rc_is 0
  has "A new workspace version 0.2.0 was detected"
  [ "$(manifest_field version)" = 0.1.0 ]; check "still 0.1.0 with the data folder at 0.2.0" $?
}

test_open_offline_after_a_cached_release_still_opens() {
  fixture
  setup_ws || return
  publish_v2
  age_cache
  run_aiwp_in "$WS" check
  has "0.2.0 is available"
  mv "$T/remote.git" "$T/remote-away.git"
  run_aiwp_in "$WS"
  rc_is 0
  has "A new workspace version 0.2.0 was detected"
  has "claude-stub"
  [ "$(manifest_field version)" = 0.1.0 ]; check "still 0.1.0" $?
  [ "$(data_tag)" = v0.1.0 ]; check "data folder not moved" $?
  run_aiwp_in "$WS" update "$WS"
  rc_is 1
  has "could not fetch v0.2.0"
  has "nothing was updated"
  [ "$(data_tag)" = v0.1.0 ]; check "data folder still not moved" $?
}

# --- a core changed by hand: update stops, repair fixes

test_edited_core_stops_update_and_repair_fixes() {
  fixture
  setup_ws || return
  chmod u+w "$WS/docs/change.md"
  echo "edited by hand" >"$WS/docs/change.md"
  chmod 444 "$WS/docs/change.md"
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 1
  has "changed: docs/change.md"
  has "aiwp repair"
  has "skipped: the core changed"
  [ "$(manifest_field version)" = 0.1.0 ]; check "nothing updated" $?
  [ "$(data_tag)" = v0.2.0 ]; check "the data folder moved once" $?
  absent "$WS/docs/new.md"
  run_aiwp_in "$WS" repair
  rc_is 0
  has "fixed: docs/change.md (changed)"
  content_is "$WS/docs/change.md" "change v1"
  mode_is "$WS/docs/change.md" 444
  run_aiwp_in "$WS" update --all
  rc_is 0
  has "updated: 0.1.0 -> 0.2.0"
}

test_chmod_by_hand_stops_update_and_repair_fixes() {
  fixture
  setup_ws || return
  chmod 644 "$WS/AGENTS.md"
  chmod 755 "$WS/docs"
  chmod 444 "$WS/scripts/aiwp.sh"
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 1
  has "permission: AGENTS.md is 644, expected 444"
  has "permission: docs/ is 755, expected 555"
  has "permission: scripts/aiwp.sh is 444, expected 555"
  run_aiwp_in "$WS" repair
  rc_is 0
  has "fixed: AGENTS.md (permission 644 -> 444)"
  has "fixed: docs/ (permission 755 -> 555)"
  mode_is "$WS/AGENTS.md" 444
  mode_is "$WS/docs" 555
  mode_is "$WS/scripts/aiwp.sh" 555
}

test_repair_restores_missing_files_and_folders() {
  fixture
  setup_ws || return
  echo mine >"$WS/custom/mine.txt"
  echo mine >"$WS/logs/mine.txt"
  open_by_hand "$WS/docs"
  rm -f "$WS/docs/keep.md"
  chmod -R u+w "$WS/docs/gone"
  rm -rf "$WS/docs/gone"
  chmod 555 "$WS/docs"
  open_by_hand "$WS/tools/observability"
  rmdir "$WS/tools/observability/.data"
  chmod 555 "$WS/tools/observability"
  run_aiwp_in "$WS" repair
  rc_is 0
  has "fixed: docs/keep.md (missing)"
  has "fixed: docs/gone/only.md (missing)"
  content_is "$WS/docs/keep.md" "kept in every version"
  mode_is "$WS/docs/gone" 555
  mode_is "$WS/tools/observability/.data" 755
  mode_is "$WS/tools/observability" 555
  content_is "$WS/custom/mine.txt" mine
  content_is "$WS/logs/mine.txt" mine
  run_aiwp_in "$WS" repair
  has "nothing to repair"
}

test_symlinked_output_folder_is_never_followed() {
  fixture
  setup_ws || return
  local dist="$WS/tools/container-console-colima/internal/webui/dist"
  mkdir -p "$T/elsewhere"
  echo mine >"$T/elsewhere/mine.txt"
  chmod u+w "$(dirname "$dist")"
  rm -rf "$dist"
  ln -s "$T/elsewhere" "$dist"
  chmod 555 "$(dirname "$dist")"
  publish_v2
  run_aiwp_in "$WS" update --all
  rc_is 1
  has "not a folder: tools/container-console-colima/internal/webui/dist"
  run_aiwp_in "$WS" repair
  rc_is 1
  has "not fixed: tools/container-console-colima/internal/webui/dist is not a folder"
  [ "$(ls "$T/elsewhere")" = mine.txt ]; check "nothing written through the link" $?
  # A core folder replaced by a link to a folder with a subfolder: repair changes nothing there.
  mkdir -p "$T/ext/sub"
  chmod 700 "$T/ext"
  chmod u+w "$WS" "$WS/docs"
  mv "$WS/docs" "$T/docs-away"
  ln -s "$T/ext" "$WS/docs"
  chmod 555 "$WS"
  run_aiwp_in "$WS" repair
  rc_is 1
  has "not fixed: docs is not a folder"
  hasnt "fixed: docs/"
  mode_is "$T/ext" 700
  [ "$(cd "$T/ext" && find . | sort | tr '\n' ' ')" = ". ./sub " ]; check "the link target is unchanged" $?
}

# --- registry

test_registry_add_list_forget_and_missing_folder() {
  fixture
  setup_ws || return
  run_aiwp_in "$T" new "$T/ws2"
  rc_is 0
  [ "$(registry_paths | tr '\n' ' ')" = "$WS $T/ws2 " ]; check "aiwp new registers both" $?
  python3 -I - "$DATA/workspaces.json" <<'PY'
import json, re, sys
data = json.load(open(sys.argv[1]))
assert data["format"] == 1, data
for item in data["workspaces"]:
    assert set(item) == {"path", "version", "created", "updated"}, item
    assert item["version"] == "0.1.0", item
    assert re.match(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$", item["created"]), item
PY
  check "registry entries: path, version, created, updated" $?
  run_aiwp_in "$T" list
  rc_is 0
  has "1  0.1.0      up to date                    $WS"
  has "2  0.1.0      up to date                    $T/ws2"
  publish_v2
  age_cache
  chmod u+w "$WS/docs/change.md"
  echo edited >"$WS/docs/change.md"
  chmod -R u+w "$T/ws2"
  rm -rf "$T/ws2"
  run_aiwp_in "$T" list
  rc_is 0
  has "core changed                  $WS"
  has "folder missing                $T/ws2"
  run_aiwp_in "$T" forget "$T/ws2"
  rc_is 0
  has "forgotten: $T/ws2"
  [ "$(registry_paths)" = "$WS" ]; check "forget removes only that entry" $?
  run_aiwp_in "$T" forget "$T/ws2"
  rc_is 1
  has "not in the registry"
  run_aiwp_in "$T" forget
  rc_is 2
  present "$WS/AGENTS.md"
}

test_registry_parallel_writes_keep_every_entry() {
  fixture
  run_install
  local i
  for i in 1 2 3 4 5 6; do
    (cd "$T" && "$HOME/.local/bin/aiwp" new "$T/p$i" >/dev/null 2>&1) &
  done
  wait
  [ "$(registry_paths | sort | tr '\n' ' ')" = "$T/p1 $T/p2 $T/p3 $T/p4 $T/p5 $T/p6 " ]
  check "six aiwp new at once: six entries" $?
  absent "$DATA/workspaces.json.tmp."*
}

test_registry_corrupt_is_never_overwritten() {
  fixture
  setup_ws || return
  echo '{"workspaces": [' >"$DATA/workspaces.json"
  run_aiwp_in "$T" list
  rc_is 1
  has "cannot be read"
  run_aiwp_in "$T" new "$T/ws2"
  rc_is 1
  absent "$T/ws2"
  content_is "$DATA/workspaces.json" '{"workspaces": ['
  echo '{"workspaces": [{"path": "relative"}]}' >"$DATA/workspaces.json"
  run_aiwp_in "$T" list
  rc_is 1
  has "not in the expected form"
}

test_registry_registers_an_existing_workspace() {
  fixture
  setup_ws || return
  rm -f "$DATA/workspaces.json"
  run_aiwp_in "$WS" version
  absent "$DATA/workspaces.json"
  run_aiwp_in "$WS/docs" list
  rc_is 0
  has "registered: $WS"
  [ "$(registry_paths)" = "$WS" ]; check "list inside it registers it" $?
  rm -f "$DATA/workspaces.json"
  run_aiwp_in "$WS"
  rc_is 0
  has "registered: $WS"
  has "claude-stub"
  [ "$(registry_paths)" = "$WS" ]; check "opening registers it" $?
  # Inside a session nothing is written: list only says so.
  rm -f "$DATA/workspaces.json"
  CLAUDE_CODE_CHILD_SESSION=1 run_aiwp_in "$WS" list
  rc_is 0
  has "this workspace is not registered yet"
  absent "$DATA/workspaces.json"
}

# --- inside a Claude Code session

test_session_refuses_what_changes_state() {
  fixture
  setup_ws || return
  publish_v2
  local args
  while IFS= read -r args; do
    # shellcheck disable=SC2086  # the words of each case
    CLAUDE_CODE_CHILD_SESSION=1 run_aiwp_in "$WS" $args
    rc_is 1
    has "refused inside a Claude Code session"
    has "in a terminal"
  done <<'CASES'

-- --resume
update
update --all
rollback
repair
_sync -- /tmp
forget /tmp/x
CASES
  CLAUDE_CODE_CHILD_SESSION=1 run_aiwp_in "$T" new "$WS"
  rc_is 1
  has "That folder is a registered workspace"
  # Another spelling of a registered folder that is gone.
  chmod -R u+w "$WS"
  mv "$WS" "$T/ws-away"
  CLAUDE_CODE_CHILD_SESSION=1 run_aiwp_in "$T" new "$T/docs/..//ws"
  rc_is 1
  has "That folder is a registered workspace"
  absent "$WS"
  mv "$T/ws-away" "$WS"
  hasnt "claude-stub"
  [ "$(version_of "$WS")" = 0.1.0 ]; check "nothing updated from a session" $?
  [ "$(data_tag)" = v0.1.0 ]; check "the data folder did not move" $?
  for args in list check version --help; do
    CLAUDE_CODE_CHILD_SESSION=1 run_aiwp_in "$WS" "$args"
    rc_is 0
    hasnt "refused"
  done
  # A new folder is fine from a session.
  CLAUDE_CODE_CHILD_SESSION=1 run_aiwp_in "$T" new "$T/ws-session"
  rc_is 0
  # A claude ancestor is a session too, with no variable: a parent process named claude.
  mkdir -p "$T/anc"
  printf '#!/bin/bash\n"$@"\nexit $?\n' >"$T/anc/claude"
  chmod 755 "$T/anc/claude"
  OUT="$(cd "$WS" && env -u AIWP_TEST_NO_ANCESTOR_CHECK "$T/anc/claude" "$HOME/.local/bin/aiwp" update --all 2>&1)"
  RC=$?
  rc_is 1
  has "refused inside a Claude Code session"
}

# --- self-update

test_self_update_runs_the_new_code() {
  fixture
  setup_ws || return
  publish_v2
  run_aiwp_in "$WS" update "$WS"
  rc_is 0
  has "fixture: running the aiwp of v0.2.0"
  has "updated: 0.1.0 -> 0.2.0"
  [ "$(manifest_field version)" = 0.2.0 ]; check "synced by the new code" $?
}

test_running_aiwp_is_immune_to_a_rewrite() {
  fixture
  setup_ws || return
  # A git that rewrites the running aiwp in place (same inode) the first time it is called.
  local running="$DATA/workspace/scripts/aiwp.sh" real_git
  real_git="$(command -v git)"
  cat >"$T/stub/git" <<STUB
#!/usr/bin/env bash
if [ ! -e "$T/rewritten" ]; then
  touch "$T/rewritten"
  for i in \$(seq 1 3000); do echo 'echo CORRUPTED-READ; exit 99'; done >"$running"
fi
exec "$real_git" "\$@"
STUB
  chmod 755 "$T/stub/git"
  run_aiwp_in "$WS" version
  rc_is 0
  present "$T/rewritten"
  has "workspace: 0.1.0"
  hasnt "CORRUPTED-READ"
  rm -f "$T/stub/git"
}

main aiwp "$@"
