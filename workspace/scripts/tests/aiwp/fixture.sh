#!/usr/bin/env bash
# Fixture of the aiwp tests: a product repository with root files that must never reach a workspace, released as
# v0.1.0 and v0.2.0, in two bare repositories (one with v0.1.0 only, one with both). Sourced by test-aiwp.sh.
# Each tree carries the real scripts/aiwp.sh; v0.2.0's has a marker line and padding, to prove the new code runs.

# Writes file $2 under root $1 with content $3.
fx_write() {
  mkdir -p "$(dirname "$1/$2")"
  printf '%s\n' "$3" >"$1/$2"
}

# Commits everything in $1 with message $2.
fx_commit() {
  git -C "$1" add -A
  git -C "$1" -c user.name=fixture -c user.email= commit -q -m "$2"
}

# Builds $1/remote-v1.git (tag v0.1.0) and $1/remote-v2.git (tags v0.1.0 and v0.2.0) from aiwp.sh $2 and install.sh $3.
build_fixture() {
  local base="$1" aiwp="$2" installer="$3" src="$1/src"
  rm -rf "$src"
  git init -q -b main "$src"
  # The repository root: none of it may reach a workspace.
  fx_write "$src" CLAUDE.md "# ROOT maintenance"
  fx_write "$src" README.md "ROOT README"
  fx_write "$src" LICENSE "ROOT LICENSE"
  fx_write "$src" .claude/settings.json '{"root": true}'
  fx_write "$src" maintainers/plans/plan.md "ROOT plan"
  fx_write "$src" tests/check.sh "echo ROOT check"
  fx_write "$src" i18n/pt-BR/README.md "ROOT translation"
  if [ -f "$installer" ]; then cp "$installer" "$src/install.sh"; else fx_write "$src" install.sh "echo ROOT installer"; fi
  # The product.
  fx_write "$src" workspace/VERSION "0.1.0"
  fx_write "$src" workspace/CHANGELOG.md "# Changelog

## [0.1.0] - 2026-11-16

- First release of the fixture."
  fx_write "$src" workspace/README.md "PRODUCT README"
  fx_write "$src" workspace/AGENTS.md "agents v1"
  fx_write "$src" workspace/rules/rules.md "rules v1"
  fx_write "$src" workspace/docs/keep.md "kept in every version"
  fx_write "$src" workspace/docs/change.md "change v1"
  fx_write "$src" workspace/docs/old.md "removed in v0.2.0"
  fx_write "$src" workspace/docs/gone/only.md "removed with its folder in v0.2.0"
  fx_write "$src" workspace/projects/README.md "projects readme"
  fx_write "$src" workspace/tools/observability/compose.yaml "services: {}"
  fx_write "$src" workspace/tools/container-console-colima/internal/webui/dist/placeholder.html "placeholder"
  fx_write "$src" workspace/.gitignore "/custom/"
  # shellcheck disable=SC2016  # the stub's own text, expanded when it runs
  fx_write "$src" workspace/scripts/setup-claude.sh '#!/usr/bin/env bash
# Stub of setup-claude.sh: says it ran and writes in the writable .claude/.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/.claude"
echo "ran $*" >"$root/.claude/setup-stamp"
echo "setup-claude stub ran"'
  chmod 755 "$src/workspace/scripts/setup-claude.sh"
  cp "$aiwp" "$src/workspace/scripts/aiwp.sh"
  chmod 755 "$src/workspace/scripts/aiwp.sh"
  fx_commit "$src" "release 0.1.0"
  git -C "$src" tag v0.1.0
  git clone -q --bare "$src" "$base/remote-v1.git"

  fx_write "$src" workspace/VERSION "0.2.0"
  fx_write "$src" workspace/CHANGELOG.md "# Changelog

## [0.2.0] - 2026-11-20

- Second release of the fixture: change.md changed.

## [0.1.0] - 2026-11-16

- First release of the fixture."
  fx_write "$src" workspace/docs/change.md "change v2"
  fx_write "$src" workspace/docs/new.md "new in v0.2.0"
  rm -rf "$src/workspace/docs/old.md" "$src/workspace/docs/gone"
  fx_write "$src" workspace/scripts/new-tool.sh '#!/usr/bin/env bash
echo new tool'
  chmod 755 "$src/workspace/scripts/new-tool.sh"
  # The new aiwp.sh: a marker after the first lines, and padding that moves every byte offset of the old file.
  {
    head -n 5 "$aiwp"
    echo 'echo "fixture: running the aiwp of v0.2.0" >&2'
    local i
    for i in $(seq 1 300); do echo "# padding line $i of the v0.2.0 fixture, so the old byte offsets point elsewhere"; done
    tail -n +6 "$aiwp"
  } >"$src/workspace/scripts/aiwp.sh"
  fx_write "$src" README.md "ROOT README v2"
  fx_write "$src" maintainers/plans/new-plan.md "ROOT new plan"
  fx_commit "$src" "release 0.2.0"
  git -C "$src" tag v0.2.0
  git clone -q --bare "$src" "$base/remote-v2.git"
}
