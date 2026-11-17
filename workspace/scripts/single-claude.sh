#!/usr/bin/env bash
# Opens a single-agent session: Claude Code in the folder of a target (a repo of projects/ or one item of the custom
# layer, custom/tools/ or custom/pocs/), with no instructions, settings, hooks or skills of the workspace (--setting-sources user), the
# /single-agent command of rules/single-agent/plugin, and the target's SINGLE-AGENT.md as appended instructions.
# In this mode commit, merge and push are done by the human or on the human's explicit request. Run by the human only:
# refusing to run inside a Claude Code session (CLAUDECODE=1) is a speed bump, not a control (env -u CLAUDECODE passes it).
# Install: sudo ln -sf <workspace>/scripts/single-claude.sh /usr/local/bin/single-claude.
set -euo pipefail

# The copy that holds this script (the root checkout, or a worktree being tested) gives the tool, template and plugin;
# single-agent.sh finds the workspace root itself.
src="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
tool="$src/scripts/single-agent.sh"
claude_bin="${SINGLE_CLAUDE_BIN:-claude}"

usage() {
  cat <<'USAGE'
Usage: single-claude [<path>] [--commit] [--merge] [--review] [-- <claude arguments>...]

  <path>      the target: a git repo folder of projects/, or one item folder custom/tools/<name> (tools/<name> means
              the same) or custom/pocs/<name>; default: the current folder. The workspace root and the product's
              tools/ are refused.
  --commit    commit on its own at each step with the tests passing
  --merge     one own branch per request, merged back at the end; includes --commit; asks before merging into main
  --review    before each commit, a review by a new subagent with no context of the session
  --          everything after it goes to claude as is (e.g. -- --model sonnet)

Prepares the target (SINGLE-AGENT.md rewritten, .gitignore kept, no commit), reserves the name
single-agent-default-<n> and opens claude there, without the workspace's instructions, hooks and skills.
Commit, merge and push are done by the human or on the human's explicit request (an option above is one).
No option pushes. Only the human runs it, from a terminal.

Exit codes: 0 claude ended; 2 usage error or run inside a Claude Code session; 3 refused target.
USAGE
}

die() {
  echo "single-claude: $2" >&2
  exit "$1"
}

[ "${CLAUDECODE:-}" != 1 ] || die 2 "refused inside a Claude Code session: the human runs it from a terminal"

target=""
options=()
extra=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      extra=("$@")
      break
      ;;
    -*) options+=("$1") ;;
    *)
      [ -z "$target" ] || die 2 "only one target: $target and $1"
      target="$1"
      ;;
  esac
  shift
done

opts_line="$(bash "$tool" options "${options[@]+"${options[@]}"}")" || exit $?
info="$(bash "$tool" target "${target:-$PWD}")" || exit $?
abs="${info#target: }"
kind="${abs##* kind=}"
abs="${abs% kind=*}"
bash "$tool" prepare "$abs" >/dev/null
name="$(bash "$tool" name)"
root="$(bash "$tool" root)"

# A POC or tool lives inside the workspace folder, whose auto memory is the workspace's: keep it out of the single session.
[ "$kind" != poc ] || export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1

cd "$abs"
echo "single-claude: $name in $abs ($kind), $opts_line"
exec "$claude_bin" --setting-sources user --plugin-dir "$src/rules/single-agent/plugin" --name "$name" \
  --append-system-prompt-file "$abs/SINGLE-AGENT.md" \
  --append-system-prompt "Single-agent session $name. Workspace: $root. Tool: $tool. Target: $abs ($kind). Session $opts_line." \
  "${extra[@]+"${extra[@]}"}"
