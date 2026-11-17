#!/usr/bin/env bash
# launchd helpers shared by the runtime and console install scripts. Source it; it does nothing when run.
# Defaults describe the runtime agent. Another agent sets these variables before sourcing.

: "${AGENT_LABEL:=io.github.expertos-tech.claude-cli-agents-workspace.container-runtime}"
: "${AGENT_INSTALLER:=install-runtime.sh}"
: "${AGENT_OWNER_MARKER:=Installed by container-console-colima/runtime/install-runtime.sh.}"
: "${BOOTOUT_TIMEOUT_SECONDS:=5}"
readonly AGENT_LABEL AGENT_INSTALLER AGENT_OWNER_MARKER BOOTOUT_TIMEOUT_SECONDS
readonly BOOTOUT_POLL_SECONDS=0.2

verbose=0

# Prints a progress message with --verbose only.
show_step() {
  if [ "$verbose" -eq 1 ]; then
    echo "$1"
  fi
}

# Prints the path of the installed plist.
agent_plist_path() {
  printf '%s/Library/LaunchAgents/%s.plist\n' "$HOME" "$AGENT_LABEL"
}

# Prints the launchd domain of the logged-in user.
agent_domain() {
  printf 'gui/%s\n' "$UID"
}

# Succeeds when launchd has the agent loaded.
agent_is_loaded() {
  launchctl print "$(agent_domain)/$AGENT_LABEL" >/dev/null 2>&1
}

# Succeeds when the given plist was written by this agent's installer.
plist_is_ours() {
  grep -qF -- "$AGENT_OWNER_MARKER" "$1"
}

# Exits with an error when the given path holds a plist that this agent's installer did not write.
refuse_foreign_plist() {
  if [ -e "$1" ] && ! plist_is_ours "$1"; then
    echo "error: $1 was not installed by $AGENT_INSTALLER; nothing changed" >&2
    exit 1
  fi
}

# Unloads the agent when loaded and waits until launchd lets it go.
# The bootout status is not trusted: it can fail while the agent does unload, and bootstrapping too early fails.
bootout_agent_if_loaded() {
  local deadline=$((SECONDS + BOOTOUT_TIMEOUT_SECONDS))
  agent_is_loaded || return 0
  launchctl bootout "$(agent_domain)/$AGENT_LABEL" >/dev/null 2>&1 || true
  while agent_is_loaded; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "error: launchd did not unload $AGENT_LABEL" >&2
      return 1
    fi
    sleep "$BOOTOUT_POLL_SECONDS"
  done
}
