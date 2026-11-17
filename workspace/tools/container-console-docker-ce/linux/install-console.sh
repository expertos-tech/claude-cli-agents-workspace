#!/usr/bin/env bash
# Installs the built binary, the systemd --user unit and the desktop launcher for the current
# user. Safe to repeat. It refuses to overwrite a unit or launcher it did not write.
set -euo pipefail

readonly MARKER="Installed by container-console-docker-ce"
readonly UNIT_NAME="container-console-docker-ce.service"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tool_dir="$(dirname "$script_dir")"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"

binary_source="$tool_dir/.data/bin/container-console-docker-ce"
icon_source="$tool_dir/web/public/favicon.png"
binary_target="$HOME/.local/bin/container-console-docker-ce"
unit_target="$config_home/systemd/user/$UNIT_NAME"
desktop_target="$data_home/applications/container-console-docker-ce.desktop"
icon_target="$data_home/container-console-docker-ce/favicon.png"

# Stops the script with a message on stderr.
die() {
  echo "install-console: $1" >&2
  exit 1
}

# Refuses a file that exists and does not carry the marker of this installer.
require_ours() {
  if [[ -e "$1" ]] && ! grep -qF "$MARKER" "$1"; then
    die "refusing to overwrite $1: it was not written by this installer"
  fi
}

# Checks what the install needs before anything changes on disk.
check_prerequisites() {
  [[ -x "$binary_source" ]] || die "$binary_source does not exist: run make build first"
  [[ -f "$icon_source" ]] || die "$icon_source does not exist"
  command -v systemctl >/dev/null || die "systemctl not found"
  systemctl --user show-environment >/dev/null || die "the systemd user manager is not reachable"
  require_ours "$unit_target"
  require_ours "$desktop_target"
}

# Copies the binary, the unit and the icon, which goes unchanged, and writes the launcher.
install_files() {
  install -D -m 0755 "$binary_source" "$binary_target"
  install -D -m 0644 "$script_dir/$UNIT_NAME" "$unit_target"
  install -D -m 0644 "$icon_source" "$icon_target"
  mkdir -p "$(dirname "$desktop_target")"
  ICON_PATH="$icon_target" perl -pe 's/\@ICON_PATH\@/$ENV{ICON_PATH}/g' \
    "$script_dir/container-console-docker-ce.desktop" >"$desktop_target"
  chmod 0644 "$desktop_target"
}

# Enables the unit for each desktop login and restarts it with the new binary.
activate_service() {
  systemctl --user daemon-reload
  systemctl --user enable "$UNIT_NAME" >/dev/null
  systemctl --user restart "$UNIT_NAME"
  if command -v update-desktop-database >/dev/null; then
    update-desktop-database "$(dirname "$desktop_target")" || true
  fi
}

check_prerequisites
install_files
activate_service
echo "installed $UNIT_NAME and $desktop_target"
