#!/usr/bin/env bash
# Installs the console service as a login LaunchAgent, plus the Dock icon that opens it. Safe to run again.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly script_dir
tool_dir="$(cd "$script_dir/.." && pwd)"
readonly tool_dir

readonly TEMPLATE_FILE="$script_dir/launchd/io.github.expertos-tech.claude-cli-agents-workspace.container-console-colima.plist.tmpl"
readonly APP_INFO_FILE="$script_dir/app/Info.plist"
readonly APP_LAUNCHER_FILE="$script_dir/app/container-console-colima-launcher.sh"
readonly BUILT_BINARY="$tool_dir/.data/bin/container-console-colima"
readonly ICON_SOURCE="$tool_dir/web/public/favicon.png"
# size:iconset name. The set stops at 256 px: the next size is 512 px, above the 128 px of the source.
readonly ICON_VARIANTS="16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x 128:icon_128x128 256:icon_128x128@2x 256:icon_256x256"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=install-lib.sh
source "$script_dir/install-lib.sh"

readonly LOG_DIR="$HOME/Library/Logs/container-console-colima"
readonly STDERR_LOG="$LOG_DIR/launchd-stderr.log"

rendered_file=""
staged_binary=""
staged_app=""

# Prints the command usage.
usage() {
  cat <<'USAGE'
Usage: install-console.sh [--verbose] [--help]

Installs what "make build" produced. Prefer "make install", which builds first:
  - the binary, in ~/Library/Application Support/container-console-colima/bin
  - the LaunchAgent, in ~/Library/LaunchAgents, loaded right away because of RunAtLoad
  - ~/Applications/Container Console (Colima).app, with the Claude CLI Agents Workspace icon
  - the app in the Dock. When this step fails, the script prints how to do it by hand and
    the install still succeeds.
Exit 0 when installed, 1 on failure, 2 on usage error.

Options:
  --verbose   Show each step.
  --help      Show this help.
USAGE
}

# Fills the global settings from the command line.
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --verbose) verbose=1 ;;
      --help | -h)
        usage
        exit 0
        ;;
      *)
        echo "error: unknown option: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
    shift
  done
}

# Fails when a file this install needs or a required macOS tool is missing. The Dock tools are optional.
check_prerequisites() {
  local required_file required_command
  [ -x "$BUILT_BINARY" ] || { echo "error: $BUILT_BINARY not found; run make install" >&2; exit 1; }
  for required_file in "$TEMPLATE_FILE" "$APP_INFO_FILE" "$APP_LAUNCHER_FILE" "$ICON_SOURCE"; do
    [ -f "$required_file" ] || { echo "error: $required_file not found" >&2; exit 1; }
  done
  for required_command in launchctl plutil sips iconutil; do
    command -v "$required_command" >/dev/null 2>&1 || { echo "error: $required_command not found" >&2; exit 1; }
  done
}

# Prints a value escaped for XML text.
xml_escape() {
  printf '%s' "$1" | LC_ALL=C sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Prints a text with the first occurrence of a placeholder replaced literally: text, placeholder, value.
replace_placeholder() {
  printf '%s%s%s' "${1%%"$2"*}" "$3" "${1#*"$2"}"
}

# Prints the plist, with the paths known only at install time.
render_plist() {
  local rendered
  rendered="$(<"$TEMPLATE_FILE")"
  rendered="$(replace_placeholder "$rendered" "@BINARY_PATH@" "$(xml_escape "$BINARY_PATH")")"
  rendered="$(replace_placeholder "$rendered" "@STDERR_LOG@" "$(xml_escape "$STDERR_LOG")")"
  printf '%s\n' "$rendered"
}

# Writes the rendered plist to a temp file next to its destination and lints it, before anything changes in launchd.
prepare_plist() {
  local plist="$1"
  mkdir -p "$(dirname "$plist")"
  rendered_file="$(mktemp "$(dirname "$plist")/.$AGENT_LABEL.XXXXXX")"
  render_plist >"$rendered_file"
  chmod 644 "$rendered_file"
  if ! plutil -lint -s "$rendered_file" >/dev/null 2>&1; then
    echo "error: the rendered plist is not valid; nothing changed" >&2
    exit 1
  fi
}

# Copies the built binary to a temp file next to its destination, so that it replaces the old one by rename.
# Overwriting a signed binary in place gets the new copy killed by the kernel on Apple Silicon.
prepare_binary() {
  mkdir -p "$BINARY_DIR"
  staged_binary="$(mktemp "$BINARY_DIR/.$BINARY_NAME.XXXXXX")"
  cp "$BUILT_BINARY" "$staged_binary"
  chmod 755 "$staged_binary"
}

# Builds the .icns at the given path from the brand image, skipping any size above the source width.
build_icon() {
  local output="$1" iconset="$2" source_width variant size
  source_width="$(sips -g pixelWidth "$ICON_SOURCE" | awk '/pixelWidth/ { print $2 }')"
  mkdir "$iconset"
  for variant in $ICON_VARIANTS; do
    size="${variant%%:*}"
    if [ "$size" -le "$source_width" ]; then
      sips -z "$size" "$size" "$ICON_SOURCE" --out "$iconset/${variant#*:}.png" >/dev/null
    fi
  done
  iconutil --convert icns --output "$output" "$iconset"
  rm -rf "$iconset"
}

# Builds the app bundle in a temp folder next to its destination, so that it replaces the old one by rename.
prepare_app() {
  mkdir -p "$(dirname "$APP_PATH")"
  staged_app="$(mktemp -d "$(dirname "$APP_PATH")/.container-console-colima-app.XXXXXX")"
  chmod 755 "$staged_app"
  mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
  cp "$APP_INFO_FILE" "$staged_app/Contents/Info.plist"
  cp "$APP_LAUNCHER_FILE" "$staged_app/Contents/MacOS/container-console-colima-launcher"
  chmod 755 "$staged_app/Contents/MacOS/container-console-colima-launcher"
  build_icon "$staged_app/Contents/Resources/AppIcon.icns" "$staged_app/Contents/Resources/AppIcon.iconset"
}

# Loads the installed plist into the user's launchd domain.
bootstrap_agent() {
  local plist="$1" output
  if ! output="$(launchctl bootstrap "$(agent_domain)" "$plist" 2>&1)"; then
    echo "error: launchctl bootstrap failed: $output" >&2
    exit 1
  fi
}

# Puts the prepared app in place of the previous copy, which refuse_foreign_app already proved is ours.
replace_app() {
  rm -rf "$APP_PATH"
  mv "$staged_app" "$APP_PATH"
  staged_app=""
  update_launch_services -f
}

# Adds the app to the Dock unless it is already there. Fails, without exiting, on any step that fails.
pin_app_to_dock() {
  local exported tiles
  exported="$(export_dock_preferences)" || return 1
  tiles="$(dock_tile_indexes "$exported")"
  rm -f "$exported"
  if [ -n "$tiles" ]; then
    return 0
  fi
  defaults write com.apple.dock persistent-apps -array-add \
    "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$(xml_escape "$APP_PATH")</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>" \
    >/dev/null 2>&1 || return 1
  killall Dock >/dev/null 2>&1
}

# Removes the temp files when the install stops early.
cleanup() {
  if [ -n "$rendered_file" ]; then
    rm -f "$rendered_file"
  fi
  if [ -n "$staged_binary" ]; then
    rm -f "$staged_binary"
  fi
  if [ -n "$staged_app" ]; then
    rm -rf "$staged_app"
  fi
}

# Entry point.
main() {
  local plist
  parse_args "$@"
  check_home
  check_prerequisites
  plist="$(agent_plist_path)"
  refuse_foreign_plist "$plist"
  refuse_foreign_app

  trap cleanup EXIT
  show_step "preparing the plist, the binary and the app"
  prepare_plist "$plist"
  prepare_binary
  prepare_app
  mkdir -p "$LOG_DIR"
  chmod 700 "$LOG_DIR"

  show_step "unloading any previous copy"
  bootout_agent_if_loaded
  mv -f "$staged_binary" "$BINARY_PATH"
  staged_binary=""
  mv -f "$rendered_file" "$plist"
  rendered_file=""
  show_step "loading $AGENT_LABEL"
  bootstrap_agent "$plist"

  show_step "installing $APP_PATH"
  replace_app
  show_step "pinning the app to the Dock"
  if ! pin_app_to_dock; then
    echo "warning: could not pin the app to the Dock; drag $APP_PATH to the Dock" >&2
  fi
  echo "installed $AGENT_LABEL and $APP_PATH"
}

main "$@"
