#!/usr/bin/env bash
# Tests scripts/sync-env.sh and scripts/lib/env.sh in a temp workspace: the filled file of a core folder goes to
# custom/env/<name>.env (never into the core), with modes 600 and 700 and env/ ignored by custom/; a project keeps its own
# .env; values are never printed.
# shellcheck disable=SC2319  # ok reads the status of the test right before it, on purpose
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
work="$(mktemp -d)"
trap 'chmod -R u+w "$work" 2>/dev/null; rm -rf "$work"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

passed=0
ws=""
out=""
rc=0

# Fails the run with the description.
fail() {
  echo "FAIL: $1" >&2
  echo "$out" >&2
  exit 1
}

# Counts one passed check, or fails with description $2 when status $1 is not 0.
ok() {
  [ "$1" -eq 0 ] || fail "$2"
  passed=$((passed + 1))
}

# Succeeds when the last output holds $1.
has() { case "$out" in *"$1"*) return 0 ;; esac; return 1; }

# Prints the permission bits of a path.
mode_of() { if stat -c %a "$1" >/dev/null 2>&1; then stat -c %a "$1"; else stat -f %Lp "$1"; fi; }

# A fresh workspace: the scripts, docker/ and a tool with templates, a custom/ git repo and a project repo.
fresh() {
  ws="$work/ws-$1"
  mkdir -p "$ws/scripts/lib" "$ws/docker/sonar" "$ws/tools/acme-tool" "$ws/rules" "$ws/custom" "$ws/projects/billing-api"
  cp "$repo/scripts/sync-env.sh" "$ws/scripts/"
  cp "$repo/scripts/lib/env.sh" "$ws/scripts/lib/"
  printf '# key of the cost check\nINFRACOST_API_KEY=\n' >"$ws/docker/.env.example"
  printf 'SONAR_DB_PASSWORD=change-me\nSONAR_TOKEN=\n' >"$ws/docker/sonar/.env.example"
  printf 'ACME_PORT=8080\n' >"$ws/tools/acme-tool/.env.example"
  printf 'X=1\n' >"$ws/rules/.env.example"
  git init -q "$ws/custom"
  git init -q "$ws/projects/billing-api"
  printf '.env\n' >"$ws/projects/billing-api/.gitignore"
  printf 'DB_URL=\n' >"$ws/projects/billing-api/.env.example"
}

# Runs sync-env.sh of the temp workspace with the arguments given.
run() {
  rc=0
  out="$(bash "$ws/scripts/sync-env.sh" "$@" 2>&1)" || rc=$?
}

# A core folder: custom/env/<name>.env, modes, env/ ignored, nothing written in the core.
fresh core
run --path docker
ok "$rc" "docker: exit 0"
[ -f "$ws/custom/env/docker.env" ]; ok $? "docker: custom/env/docker.env created"
[ ! -e "$ws/docker/.env" ]; ok $? "docker: no .env in the core"
[ "$(mode_of "$ws/custom/env/docker.env")" = 600 ]; ok $? "docker: file mode 600"
[ "$(mode_of "$ws/custom/env")" = 700 ]; ok $? "docker: folder mode 700"
has "file: custom/env/docker.env"; ok $? "docker: names the file"
has "added: env/ to custom/.gitignore"; ok $? "docker: env/ added to custom/.gitignore"
git -C "$ws/custom" check-ignore -q env/docker.env; ok $? "docker: custom/ ignores env/"
has "empty: INFRACOST_API_KEY"; ok $? "docker: lists the empty key"
run --path docker/sonar
[ -f "$ws/custom/env/docker-sonar.env" ]; ok $? "docker/sonar: docker-sonar.env"
has "same as example: SONAR_DB_PASSWORD"; ok $? "docker/sonar: flags the placeholder"
! has "change-me"; ok $? "docker/sonar: never prints a value"
[ "$(grep -c '^env/$' "$ws/custom/.gitignore")" = 1 ]; ok $? "env/ added once"
run --path "$ws/tools/acme-tool/"
[ -f "$ws/custom/env/acme-tool.env" ]; ok $? "tool by absolute path: acme-tool.env"
[ ! -e "$ws/tools/acme-tool/.env" ]; ok $? "tool: no .env in the core"

# Completing: a new key is appended, an existing value is kept and never printed.
printf 'INFRACOST_API_KEY=sekret-value\n' >"$ws/custom/env/docker.env"
printf '# key of the cost check\nINFRACOST_API_KEY=\n# new\nNEW_KEY=x\n' >"$ws/docker/.env.example"
run --path docker --check
[ "$rc" -eq 1 ]; ok $? "check: drift is exit 1"
has "missing: NEW_KEY"; ok $? "check: names the missing key"
run --path docker
has "result: updated"; ok $? "update: result"
grep -qx 'INFRACOST_API_KEY=sekret-value' "$ws/custom/env/docker.env"; ok $? "update: value kept"
grep -qx 'NEW_KEY=x' "$ws/custom/env/docker.env"; ok $? "update: key appended"
! has "sekret-value"; ok $? "update: value never printed"
run --path docker --check
ok "$rc" "check: in sync is exit 0"

# The core never holds a .env: another core folder and the root are refused.
run --path rules
[ "$rc" -eq 2 ]; ok $? "rules/: refused"
[ ! -e "$ws/rules/.env" ]; ok $? "rules/: nothing written"
printf 'X=1\n' >"$ws/.env.example"
run --path .
[ "$rc" -eq 2 ]; ok $? "root: refused"
[ ! -e "$ws/.env" ]; ok $? "root: nothing written"

# A project keeps its own .env, git-ignored.
run --path projects/billing-api
ok "$rc" "project: exit 0"
[ -f "$ws/projects/billing-api/.env" ]; ok $? "project: its own .env"
printf '' >"$ws/projects/billing-api/.gitignore"
rm -f "$ws/projects/billing-api/.env"
run --path projects/billing-api
[ "$rc" -eq 2 ]; ok $? "project: refused when .env is not ignored"

# custom/ missing: a clear error, nothing created.
fresh nocustom
rm -rf "$ws/custom"
run --path docker
[ "$rc" -eq 2 ]; ok $? "no custom/: exit 2"
[ ! -e "$ws/custom" ]; ok $? "no custom/: nothing created"

# A custom/.gitignore that already ignores env/ is left alone.
fresh ignored
printf 'env/\n' >"$ws/custom/.gitignore"
run --path docker
! has "added: env/"; ok $? "custom/.gitignore already ignoring env/ is kept"
[ "$(cat "$ws/custom/.gitignore")" = "env/" ]; ok $? "custom/.gitignore unchanged"

# lib/env.sh: names and the compose fallback.
# shellcheck source=scripts/lib/env.sh
. "$repo/scripts/lib/env.sh"
[ "$(env_name docker/sonar/)" = docker-sonar ]; ok $? "env_name docker/sonar"
[ "$(env_name tools/login-simulator)" = login-simulator ]; ok $? "env_name tools/<name>"
! env_name tools/a/b >/dev/null; ok $? "env_name refuses a nested folder"
! env_name rules >/dev/null; ok $? "env_name refuses another core folder"
fresh compose
[ "$(env_file_for_compose "$ws" tools/acme-tool optional)" = "$ws/tools/acme-tool/.env.example" ]; ok $? "optional falls back to the example"
out="$(env_file_for_compose "$ws" docker/sonar 2>&1)" && rc=0 || rc=$?
[ "$rc" -ne 0 ]; ok $? "required fails without the file"
has "/local-env docker/sonar"; ok $? "required names /local-env"
mkdir -p "$ws/custom/env" && : >"$ws/custom/env/docker-sonar.env"
[ "$(env_file_for_compose "$ws" docker/sonar)" = "$ws/custom/env/docker-sonar.env" ]; ok $? "the filled file wins"

out="$(bash "$repo/scripts/sync-env.sh" --help)"
has "custom/env/<name>.env"; ok $? "help names custom/env"

echo "pass: $passed assertions"
