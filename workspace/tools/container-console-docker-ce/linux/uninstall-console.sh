#!/usr/bin/env bash
# Removes what linux/install-console.sh wrote. It keeps containers, the Docker daemon, the log,
# the list of Compose projects and the optional settings file.
set -euo pipefail

readonly MARKER="Installed by container-console-docker-ce"
readonly UNIT_NAME="container-console-docker-ce.service"

config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"

binary_target="$HOME/.local/bin/container-console-docker-ce"
unit_target="$config_home/systemd/user/$UNIT_NAME"
desktop_target="$data_home/applications/container-console-docker-ce.desktop"
icon_dir="$data_home/container-console-docker-ce"

# Removes a file only when it carries the marker of the installer.
remove_ours() {
  if [[ ! -e "$1" ]]; then
    return
  fi
  if grep -qF "$MARKER" "$1"; then
    rm -f "$1"
  else
    echo "uninstall-console: kept $1: it was not written by the installer" >&2
  fi
}

systemctl --user disable --now "$UNIT_NAME" 2>/dev/null || true
remove_ours "$unit_target"
remove_ours "$desktop_target"
rm -f "$binary_target" "$icon_dir/favicon.svg" "$icon_dir/favicon.png"
rmdir "$icon_dir" 2>/dev/null || true
systemctl --user daemon-reload
if command -v update-desktop-database >/dev/null; then
  update-desktop-database "$(dirname "$desktop_target")" || true
fi
echo "removed $UNIT_NAME and $desktop_target"
