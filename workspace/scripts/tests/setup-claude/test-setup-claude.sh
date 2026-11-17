#!/usr/bin/env bash
# Tests of the mod installation, the path-scoped rules and the custom layer in scripts/setup-claude.sh, with a fake HOME and a fake root (never the real ones).
# Run: bash scripts/tests/setup-claude/test-setup-claude.sh [--only <test_name>]
# shellcheck disable=SC2088  # "~" is literal text in the registered entries.
# shellcheck disable=SC2016  # backticks are literal Markdown in the AGENTS.md fixtures.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(cd "$HERE/../.." && pwd)/setup-claude.sh"
MANIFEST="$(cd "$HERE/../../.." && pwd)/rules/manifest.json"
BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT
FAILED=0
OUT=""
RC=0

# Fresh fake HOME and root, with the mod source unless the argument says "nosrc".
fixture() {
  rm -rf "${BASE:?}/home" "${BASE:?}/root"
  mkdir -p "$BASE/home" "$BASE/root/rules/agents"
  printf '# AGENTS.md\n\nRead `rules/git.md`.\n' >"$BASE/root/AGENTS.md"
  cp "$MANIFEST" "$BASE/root/rules/manifest.json"
  if [ "${1:-}" != "nosrc" ]; then
    mkdir -p "$BASE/root/tools/fable-alert/plugin"
    echo fable >"$BASE/root/tools/fable-alert/plugin/a.txt"
  fi
}

run() {
  OUT="$(HOME="$BASE/home" bash "$SCRIPT" --root "$BASE/root" "$@" 2>&1)"
  RC=$?
}

check() { # description, status (0 = ok)
  if [ "$2" -ne 0 ]; then
    FAILED=$((FAILED + 1))
    echo "FAIL $CURRENT: $1 (rc=$RC out=[$OUT])"
  fi
}
has() { case "$OUT" in *"$1"*) check "has [$1]" 0 ;; *) check "missing [$1]" 1 ;; esac; }
hasnt() { case "$OUT" in *"$1"*) check "unexpected [$1]" 1 ;; *) check "no [$1]" 0 ;; esac; }
present() { [ -f "$1" ]; check "$2" $?; }
absent() { [ ! -e "$1" ]; check "$2" $?; }
writable() { [ -w "$1" ]; check "$2" $?; }
rc_is() { [ "$RC" -eq "$1" ]; check "rc $1" $?; }
dirs() { python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["env"]["CLAUDE_CODE_PLUGIN_DIRS"])' "$BASE/home/.claude/settings.json"; }

test_fresh_install() {
  fixture
  run
  rc_is 0
  has "written: ~/.claude/mods/fable-alert"
  has "result: .claude/ in sync"
  present "$BASE/home/.claude/mods/fable-alert/a.txt" "fable copy"
  [ "$(dirs)" = "~/.claude/mods/fable-alert" ]; check "registered" $?
}

test_second_run_no_change() {
  fixture
  run
  local before after
  before="$(find "$BASE/home" -type f -exec cksum {} + | sort)"
  run
  after="$(find "$BASE/home" -type f -exec cksum {} + | sort)"
  rc_is 0
  hasnt "written:"
  [ "$before" = "$after" ]; check "files unchanged" $?
}

test_existing_copy_never_changed() {
  fixture
  run
  echo changed >"$BASE/home/.claude/mods/fable-alert/a.txt"
  run
  rc_is 0
  hasnt "written:"
  [ "$(cat "$BASE/home/.claude/mods/fable-alert/a.txt")" = changed ]; check "copy untouched" $?
  run --check
  rc_is 0
}

test_relative_root_accepted() {
  fixture
  echo '{}' >"$BASE/root/rules/agents/settings.json"
  OUT="$(cd "$BASE" && HOME="$BASE/home" bash "$SCRIPT" --root root 2>&1)"
  RC=$?
  rc_is 0
  has "written: .claude/settings.json"
  present "$BASE/root/.claude/settings.json" "written under the absolute root"
  present "$BASE/home/.claude/mods/fable-alert/a.txt" "mod copied"
}

test_missing_source_skips() {
  fixture nosrc
  run
  rc_is 0
  hasnt "mods/"
  absent "$BASE/home/.claude" "nothing written"
  run --check
  rc_is 0
}

test_existing_plugin_dirs_append_backup_once() {
  fixture
  mkdir -p "$BASE/home/.claude"
  echo '{"model": "x", "env": {"CLAUDE_CODE_PLUGIN_DIRS": "/other/mod", "KEEP": "1"}}' >"$BASE/home/.claude/settings.json"
  cp "$BASE/home/.claude/settings.json" "$BASE/orig.json"
  run
  [ "$(dirs)" = "/other/mod:~/.claude/mods/fable-alert" ]; check "appended" $?
  grep -q '"KEEP": "1"' "$BASE/home/.claude/settings.json"; check "kept env" $?
  cmp -s "$BASE/orig.json" "$BASE/home/.claude/settings.json.bak.fable-alert"; check "fable backup is original" $?
  # Backups exist once: a later registration (entry removed) does not replace them.
  echo '{"env": {"CLAUDE_CODE_PLUGIN_DIRS": "/z"}}' >"$BASE/home/.claude/settings.json"
  run
  cmp -s "$BASE/orig.json" "$BASE/home/.claude/settings.json.bak.fable-alert"; check "backup not replaced" $?
}

test_check_states() {
  fixture
  run --check
  rc_is 1
  has "out of sync: ~/.claude/mods/fable-alert"
  absent "$BASE/home/.claude" "check writes nothing"
  run
  run --check
  rc_is 0
  # Mod present but unregistered.
  echo '{"env": {}}' >"$BASE/home/.claude/settings.json"
  run --check
  rc_is 1
  has "out of sync: ~/.claude/settings.json"
  [ "$(cat "$BASE/home/.claude/settings.json")" = '{"env": {}}' ]; check "settings untouched" $?
}

# Writes a rule source: a "paths:" front matter block unless the second argument says "plain".
rule() {
  if [ "${2:-}" = plain ]; then
    printf '# %s\n\nbody\n' "$1" >"$BASE/root/rules/$1"
  else
    printf -- '---\npaths:\n  - "**/*.sh"\n---\n\n# %s\n\nbody\n' "$1" >"$BASE/root/rules/$1"
  fi
}

test_scoped_rule_generated() {
  fixture
  rule scoped.md
  rule plain.md plain
  run
  rc_is 0
  has "written: .claude/rules/scoped.md"
  cmp -s "$BASE/root/rules/scoped.md" "$BASE/root/.claude/rules/scoped.md"; check "same content" $?
  absent "$BASE/root/.claude/rules/plain.md" "rule without front matter not copied"
  hasnt "plain.md"
}

test_scoped_rule_check() {
  fixture
  rule scoped.md
  run --check
  rc_is 1
  has "out of sync: .claude/rules/scoped.md"
  absent "$BASE/root/.claude/rules" "check writes nothing"
  run
  run --check
  rc_is 0
  hasnt "rules/"
  echo changed >>"$BASE/root/rules/scoped.md"
  run --check
  rc_is 1
  has "out of sync: .claude/rules/scoped.md"
}

test_scoped_rule_obsolete() {
  fixture
  rule kept.md
  rule gone.md
  run
  rule kept.md plain
  rm "$BASE/root/rules/gone.md"
  run --check
  rc_is 1
  has "stale: .claude/rules/kept.md"
  has "stale: .claude/rules/gone.md"
  run
  rc_is 0
  has "removed: .claude/rules/kept.md"
  has "removed: .claude/rules/gone.md"
  absent "$BASE/root/.claude/rules/kept.md" "lost front matter: copy removed"
  absent "$BASE/root/.claude/rules/gone.md" "deleted source: copy removed"
  run --check
  rc_is 0
}

test_custom_repo_missing_says_how_to_get_it() {
  fixture
  run
  rc_is 0
  has "attention: custom/ is missing"
  absent "$BASE/root/custom" "nothing is created without a URL"
  run --check
  has "attention: custom/ is missing"
}

test_custom_repo_cloned_from_the_url_and_synced_in_the_same_run() {
  fixture
  git init -q -b main "$BASE/custom-origin"
  mkdir -p "$BASE/custom-origin/my-rules"
  printf '# company\n' >"$BASE/custom-origin/my-rules/company.md"
  git -C "$BASE/custom-origin" add my-rules/company.md
  git -C "$BASE/custom-origin" -c user.name=t -c user.email=t@example.com commit -q -m first
  run --custom-repo "$BASE/custom-origin"
  rc_is 0
  has "cloned: custom/"
  present "$BASE/root/custom/my-rules/company.md" "the repo is cloned into custom/"
  present "$BASE/root/.claude/rules/custom-company.md" "its rules are copied in the same run"
  echo local >"$BASE/root/custom/b.md"
  run --custom-repo "$BASE/custom-origin"
  hasnt "cloned: custom/"
  hasnt "attention: custom/"
  present "$BASE/root/custom/b.md" "an existing folder is never touched"
}

test_custom_repo_clone_failure_does_not_fail_the_setup() {
  fixture
  run --custom-repo "$BASE/no-such-repo"
  rc_is 0
  has "attention: could not clone the custom layer repo"
  absent "$BASE/root/custom/.git" "no repo is left behind"
}

test_unknown_option_is_refused() {
  fixture
  run --no-such-option x
  rc_is 2
  has "unknown option: --no-such-option"
}

# Writes a custom layer rule: a "paths:" front matter block unless the second argument says "plain".
custom_rule() {
  mkdir -p "$BASE/root/custom/my-rules"
  if [ "${2:-}" = plain ]; then
    printf '# %s\n\nbody\n' "$1" >"$BASE/root/custom/my-rules/$1"
  else
    printf -- '---\npaths:\n  - "**/*.tf"\n---\n\n# %s\n\nbody\n' "$1" >"$BASE/root/custom/my-rules/$1"
  fi
}

# Excludes of repos at any depth, a repo inside another one included: the root repo's file, a nested repo's file and a
# glob over the repos inside the root repo all reach the settings.
test_claude_md_excludes_of_nested_repos_reach_the_settings() {
  fixture
  printf '{\n  "claudeMdExcludes": []\n}\n' >"$BASE/root/rules/agents/settings.json"
  mkdir -p "$BASE/root/custom"
  printf 'projects/billing/CLAUDE.md\nprojects/billing/billing-api/CLAUDE.md\nprojects/billing/*/AGENTS.md\nprojects/a/b/c/d/e/CLAUDE.md\n' >"$BASE/root/custom/claude-md-excludes.txt"
  run
  rc_is 0
  local got want
  got="$(python3 -I -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["claudeMdExcludes"]))' "$BASE/root/.claude/settings.json")"
  for want in "$BASE/root/projects/billing/CLAUDE.md" "$BASE/root/projects/billing/billing-api/CLAUDE.md" \
    "$BASE/root/projects/billing/*/AGENTS.md" "$BASE/root/projects/a/b/c/d/e/CLAUDE.md"; do
    case " $got " in *" $want "*) check "merged $want" 0 ;; *) check "merged $want: [$got]" 1 ;; esac
  done
  case "$OUT" in *skipped*) check "nothing skipped" 1 ;; *) check "nothing skipped" 0 ;; esac
}

test_claude_md_excludes_of_the_custom_layer_reach_the_settings() {
  fixture
  printf '{\n  "claudeMdExcludes": ["**/tmp/work/**"],\n  "model": "opus"\n}\n' >"$BASE/root/rules/agents/settings.json"
  mkdir -p "$BASE/root/custom"
  printf '# kept for the team\nprojects/acme/billing/CLAUDE.md\n\n/etc/x\nprojects/../x\nprojects/acme/billing/.cursor/**\nCLAUDE.md\n**\ncustom/my-rules/x.md\nprojects/**\nprojects/CLAUDE.md\ncustom/pocs/demo/AGENTS.md\n' >"$BASE/root/custom/claude-md-excludes.txt"
  run
  rc_is 0
  has "skipped, not inside projects/ or custom/pocs/: /etc/x"
  has "skipped, not inside projects/ or custom/pocs/: projects/../x"
  has "skipped, not inside projects/ or custom/pocs/: CLAUDE.md"
  has "skipped, not inside projects/ or custom/pocs/: **"
  has "skipped, not inside projects/ or custom/pocs/: custom/my-rules/x.md"
  has "skipped, it names no file of one project: projects/**"
  has "skipped, it names no file of one project: projects/CLAUDE.md"
  local got
  got="$(python3 -I -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["claudeMdExcludes"]))' "$BASE/root/.claude/settings.json")"
  local want
  for want in "**/tmp/work/**" "$BASE/root/projects/acme/billing/CLAUDE.md" "$BASE/root/projects/acme/billing/.cursor/**" "$BASE/root/custom/pocs/demo/AGENTS.md"; do
    case " $got " in *" $want "*) check "merged $want" 0 ;; *) check "merged $want: [$got]" 1 ;; esac
  done
  case " $got " in *"/etc/x"* | *"../x"* | *" $BASE/root/CLAUDE.md "* | *"/root/** "* | *"custom/my-rules"* | *"/projects/** "*) check "invalid lines left out" 1 ;; esac
  run --check
  rc_is 0
  rm "$BASE/root/custom/claude-md-excludes.txt"
  run --check
  rc_is 1
  has "out of sync: .claude/settings.json"
  run
  cmp -s "$BASE/root/rules/agents/settings.json" "$BASE/root/.claude/settings.json"; check "plain copy again" $?
}

test_custom_rules_copied_with_and_without_paths() {
  fixture
  custom_rule company.md plain
  custom_rule cloud.md
  rule scoped.md
  run
  rc_is 0
  has "written: .claude/rules/custom-company.md"
  has "written: .claude/rules/custom-cloud.md"
  cmp -s "$BASE/root/custom/my-rules/company.md" "$BASE/root/.claude/rules/custom-company.md"; check "same content, no paths" $?
  cmp -s "$BASE/root/custom/my-rules/cloud.md" "$BASE/root/.claude/rules/custom-cloud.md"; check "same content, paths" $?
  present "$BASE/root/.claude/rules/scoped.md" "core rule still copied"
  run --check
  rc_is 0
  hasnt "stale:"
}

test_custom_rules_check_and_stale() {
  fixture
  custom_rule company.md plain
  custom_rule gone.md plain
  run --check
  rc_is 1
  has "out of sync: .claude/rules/custom-company.md"
  run
  echo changed >>"$BASE/root/custom/my-rules/company.md"
  rm "$BASE/root/custom/my-rules/gone.md"
  run --check
  rc_is 1
  has "out of sync: .claude/rules/custom-company.md"
  has "stale: .claude/rules/custom-gone.md"
  hasnt "stale: .claude/rules/custom-company.md"
  run
  rc_is 0
  has "removed: .claude/rules/custom-gone.md"
  absent "$BASE/root/.claude/rules/custom-gone.md" "deleted source: copy removed"
  run --check
  rc_is 0
}

test_custom_rules_removed_with_the_folder() {
  fixture
  custom_rule company.md plain
  run
  rm -rf "$BASE/root/custom"
  run
  rc_is 0
  has "removed: .claude/rules/custom-company.md"
  has "attention: custom/ is missing"
}

test_core_rule_with_custom_prefix_not_copied() {
  fixture
  rule custom-x.md
  run
  rc_is 0
  has "warning: rules/custom-x.md not copied"
  hasnt "written: .claude/rules/custom-x.md"
  absent "$BASE/root/.claude/rules/custom-x.md" "prefix reserved for the custom layer"
}

test_custom_rules_skip_folders_and_links() {
  fixture
  custom_rule company.md plain
  mkdir -p "$BASE/root/custom/my-rules/dir.md"
  echo SECRET >"$BASE/outside.txt"
  ln -s "$BASE/outside.txt" "$BASE/root/custom/my-rules/link.md"
  ln -s "$BASE/missing.txt" "$BASE/root/custom/my-rules/dangling.md"
  run
  rc_is 0
  has "warning: custom/my-rules/dir.md skipped: not a regular file"
  has "warning: custom/my-rules/link.md skipped: not a regular file"
  has "warning: custom/my-rules/dangling.md skipped: not a regular file"
  present "$BASE/root/.claude/rules/custom-company.md" "the regular rule is still copied"
  absent "$BASE/root/.claude/rules/custom-link.md" "a link is never copied"
  absent "$BASE/root/.claude/rules/custom-dir.md" "a folder is never copied"
  has "result: .claude/ in sync"
}

test_quiet_prints_only_what_needs_attention() {
  fixture
  mkdir -p "$BASE/root/custom"
  run --quiet
  rc_is 0
  [ -z "$OUT" ]; check "quiet and in sync prints nothing" $?
  rm -rf "$BASE/root/custom"
  run --quiet
  has "attention: custom/ is missing"
  hasnt "written:"
  hasnt "result:"
}

# Regression: in an installed workspace the sources are 444 and their folders 555; the copies must stay writable,
# or the next sync after a core update fails and stops the SessionStart hook.
test_read_only_sources_give_writable_copies() {
  fixture
  mkdir -p "$BASE/root/rules/skills/demo"
  echo one >"$BASE/root/rules/skills/demo/SKILL.md"
  echo '{}' >"$BASE/root/rules/agents/settings.json"
  chmod 444 "$BASE/root/rules/skills/demo/SKILL.md" "$BASE/root/rules/agents/settings.json" "$BASE/root/tools/fable-alert/plugin/a.txt"
  chmod 555 "$BASE/root/rules/skills/demo" "$BASE/root/tools/fable-alert/plugin"
  run
  rc_is 0
  writable "$BASE/root/.claude/skills/demo/SKILL.md" "skill copy writable"
  writable "$BASE/root/.claude/settings.json" "settings copy writable"
  writable "$BASE/home/.claude/mods/fable-alert" "mod folder writable"
  writable "$BASE/home/.claude/mods/fable-alert/a.txt" "mod file writable"
  chmod u+w "$BASE/root/rules/skills/demo" "$BASE/root/rules/skills/demo/SKILL.md"
  echo two >"$BASE/root/rules/skills/demo/SKILL.md"
  chmod 444 "$BASE/root/rules/skills/demo/SKILL.md"
  run
  rc_is 0
  has "written: .claude/skills/demo/SKILL.md"
  [ "$(cat "$BASE/root/.claude/skills/demo/SKILL.md")" = two ]; check "copy replaced after a core update" $?
  chmod -R u+w "$BASE/root" "$BASE/home"
}

# The rules configuration (custom/rules-config.json, custom/my-rules/), applied by scripts/rules-config.py.

config() { mkdir -p "$BASE/root/custom"; printf '%s\n' "$1" >"$BASE/root/custom/rules-config.json"; }
skill() { mkdir -p "$BASE/root/rules/skills/$1"; printf -- '---\nname: %s\n---\n\nbody\n' "$1" >"$BASE/root/rules/skills/$1/SKILL.md"; }
agent() { printf -- '---\nname: %s\nmodel: claude-haiku-5-5\n---\n\nbody\n' "$1" >"$BASE/root/rules/agents/$1.md"; }
agents_md() { cat "$BASE/root/.claude/AGENTS.md"; }

# AC-1: an excluded rule leaves .claude/rules/ and the effective AGENTS.md (a table row and a parenthesized
# reference); including it again brings both back.
test_config_excluded_rule_leaves_rules_and_agents_md() {
  fixture
  rule frontend.md
  printf '# AGENTS.md\n\n- Build the UI (`rules/frontend.md` "Colors").\n\n| File | Loads with |\n| --- | --- |\n| `rules/frontend.md` | UI |\n| `rules/git.md` | git |\n' >"$BASE/root/AGENTS.md"
  config '{"core": {"rules": {"exclude": ["frontend.md"]}}}'
  run
  rc_is 0
  absent "$BASE/root/.claude/rules/frontend.md" "excluded rule not copied"
  present "$BASE/root/.claude/AGENTS.md" "effective AGENTS.md written"
  case "$(agents_md)" in *'rules/frontend.md'*) check "AGENTS.md still names the rule" 1 ;; esac
  case "$(agents_md)" in *'- Build the UI.'*) ;; *) check "the sentence stays without the reference" 1 ;; esac
  case "$(agents_md)" in *'`rules/git.md`'*) ;; *) check "other rows stay" 1 ;; esac
  config '{}'
  run --check
  rc_is 1
  run
  present "$BASE/root/.claude/rules/frontend.md" "included again"
  cmp -s "$BASE/root/AGENTS.md" "$BASE/root/.claude/AGENTS.md"; check "AGENTS.md as it is" $?
}

# AC-2: a mandatory rule stays, and the (quiet) session start warns.
test_config_mandatory_rule_stays_with_a_warning() {
  fixture
  rule git.md
  config '{"core": {"rules": {"exclude": ["git.md"]}}, "replace": {"security.md": "security.md"}}'
  rule security.md
  mkdir -p "$BASE/root/custom/my-rules"
  echo own >"$BASE/root/custom/my-rules/security.md"
  run --quiet
  rc_is 0
  has 'warning: custom/rules-config.json: "git.md" is mandatory'
  has 'warning: custom/rules-config.json: "security.md" is mandatory'
  present "$BASE/root/.claude/rules/git.md" "mandatory rule copied"
  cmp -s "$BASE/root/rules/security.md" "$BASE/root/.claude/rules/security.md"; check "core security.md kept" $?
}

# AC-3: a replaced rule: on demand, AGENTS.md points to the own file; by path, the own file takes the copy's place.
test_config_replaced_rules() {
  fixture
  rule review.md plain
  rule docs.md
  printf '# AGENTS.md\n\n| `rules/review.md` | review |\n' >"$BASE/root/AGENTS.md"
  mkdir -p "$BASE/root/custom/my-rules"
  echo 'own review' >"$BASE/root/custom/my-rules/review.md"
  printf -- '---\npaths:\n  - "**/*.md"\n---\n\nown docs\n' >"$BASE/root/custom/my-rules/our-docs.md"
  config '{"replace": {"review.md": "review.md", "docs.md": "our-docs.md"}}'
  run
  rc_is 0
  case "$(agents_md)" in *'| `custom/my-rules/review.md` | review |'*) ;; *) check "AGENTS.md points to the own rule" 1 ;; esac
  absent "$BASE/root/.claude/rules/custom-review.md" "an on-demand replacement is not copied"
  absent "$BASE/root/.claude/rules/docs.md" "the replaced core copy is gone"
  cmp -s "$BASE/root/custom/my-rules/our-docs.md" "$BASE/root/.claude/rules/custom-our-docs.md"; check "own copy by path" $?
  hasnt "warning:"
}

# AC-4: an own rule with the name of a core rule and no replace is refused; the core one stays.
test_config_own_rule_with_a_core_name_refused() {
  fixture
  rule git.md
  custom_rule git.md
  run
  rc_is 0
  has "warning: custom/my-rules/git.md refused"
  absent "$BASE/root/.claude/rules/custom-git.md" "own copy refused"
  present "$BASE/root/.claude/rules/git.md" "core copy kept"
}

# AC-5: an excluded skill and agent leave .claude/; a mandatory skill stays with a warning.
test_config_excluded_skill_and_agent() {
  fixture
  skill pilot
  skill merge
  agent infra-engineer
  run
  present "$BASE/root/.claude/skills/pilot/SKILL.md" "skill copied first"
  config '{"core": {"skills": {"exclude": ["pilot", "merge"]}, "agents": {"exclude": ["infra-engineer"]}}}'
  run --check
  rc_is 1
  has "stale: .claude/skills/pilot/SKILL.md"
  has "stale: .claude/agents/infra-engineer.md"
  run
  rc_is 0
  absent "$BASE/root/.claude/skills/pilot" "excluded skill removed"
  absent "$BASE/root/.claude/agents/infra-engineer.md" "excluded agent removed"
  present "$BASE/root/.claude/skills/merge/SKILL.md" "mandatory skill kept"
  has 'warning: custom/rules-config.json: "merge" is mandatory'
  run --check
  rc_is 0
}

# AC-6: invalid JSON loads the whole core with a warning, without an error.
test_config_invalid_json_loads_the_whole_core() {
  fixture
  rule frontend.md
  config '{"core": {"rules": {"exclude": ["frontend.md"]'
  run --quiet
  rc_is 0
  has "warning: custom/rules-config.json is not valid JSON"
  present "$BASE/root/.claude/rules/frontend.md" "whole core"
  cmp -s "$BASE/root/AGENTS.md" "$BASE/root/.claude/AGENTS.md"; check "AGENTS.md as it is" $?
}

test_config_own_skill_and_agent_get_the_prefix() {
  fixture
  mkdir -p "$BASE/root/custom/my-rules/skills/deploy/refs" "$BASE/root/custom/my-rules/agents"
  printf -- '---\nname: deploy\ndescription: d\n---\n\nbody\n' >"$BASE/root/custom/my-rules/skills/deploy/SKILL.md"
  echo ref >"$BASE/root/custom/my-rules/skills/deploy/refs/a.md"
  printf -- '---\nname: reviewer\nmodel: claude-haiku-5-5\n---\n\nbody\n' >"$BASE/root/custom/my-rules/agents/sql.md"
  run
  rc_is 0
  present "$BASE/root/.claude/skills/custom-deploy/refs/a.md" "own skill files copied"
  head -2 "$BASE/root/.claude/skills/custom-deploy/SKILL.md" | grep -qx 'name: custom-deploy'; check "skill renamed" $?
  head -2 "$BASE/root/.claude/agents/custom-sql.md" | grep -qx 'name: custom-sql'; check "agent renamed, never a core name" $?
  rm -rf "$BASE/root/custom/my-rules/skills" "$BASE/root/custom/my-rules/agents/sql.md"
  run
  has "removed: .claude/skills/custom-deploy/SKILL.md"
  has "removed: .claude/agents/custom-sql.md"
  absent "$BASE/root/.claude/skills/custom-deploy" "own skill folder gone"
}

# Regression (review of stage 1): an own skill or agent never brings a hook, a permission mode or a tool grant
# into .claude/; the setup warns and keeps the rest.
test_config_own_items_lose_keys_that_grant_execution() {
  fixture
  mkdir -p "$BASE/root/custom/my-rules/skills/x" "$BASE/root/custom/my-rules/agents"
  printf -- '---\nname: x\nallowed-tools: Bash(*)\nhooks:\n  PreToolUse:\n    - command: touch pwned\n---\n\nbody\n' >"$BASE/root/custom/my-rules/skills/x/SKILL.md"
  printf -- '---\nname: y\npermissionMode: bypassPermissions\nmodel: claude-haiku-5-5\n---\n\nbody\n' >"$BASE/root/custom/my-rules/agents/y.md"
  run --quiet
  rc_is 0
  has "warning: custom/my-rules/skills/x/SKILL.md: front matter not allowed for an own item, left out: allowed-tools, hooks"
  has "warning: custom/my-rules/agents/y.md: front matter not allowed for an own item, left out: permissionMode"
  ! grep -qE 'hooks|allowed-tools|command:' "$BASE/root/.claude/skills/custom-x/SKILL.md"; check "no hook in the skill copy" $?
  ! grep -q permissionMode "$BASE/root/.claude/agents/custom-y.md"; check "no permission mode in the agent copy" $?
  grep -qx 'model: claude-haiku-5-5' "$BASE/root/.claude/agents/custom-y.md"; check "allowed model kept" $?
}

test_config_legacy_custom_rules_still_read() {
  fixture
  mkdir -p "$BASE/root/custom/rules"
  echo company >"$BASE/root/custom/rules/company.md"
  run --quiet
  rc_is 0
  has "warning: custom/rules/ read in place of custom/my-rules/"
  present "$BASE/root/.claude/rules/custom-company.md" "legacy rule copied"
}

# When rules-config.py cannot run, the whole core loads with AGENTS.md as it is, and the setup still succeeds.
test_config_script_failure_loads_the_whole_core() {
  fixture
  rule frontend.md
  config '{"core": {"rules": {"exclude": ["frontend.md"]}}}'
  mkdir -p "$BASE/bin"
  cp "$SCRIPT" "$BASE/bin/setup-claude.sh"
  printf 'import sys\nsys.exit(1)\n' >"$BASE/bin/rules-config.py"
  OUT="$(HOME="$BASE/home" bash "$BASE/bin/setup-claude.sh" --root "$BASE/root" 2>&1)"
  RC=$?
  rc_is 0
  has "warning: scripts/rules-config.py failed"
  present "$BASE/root/.claude/rules/frontend.md" "whole core"
  cmp -s "$BASE/root/AGENTS.md" "$BASE/root/.claude/AGENTS.md"; check "AGENTS.md as it is" $?
}

only=""
if [ "${1:-}" = "--only" ]; then
  [ $# -ge 2 ] || { echo "error: --only needs a test name" >&2; exit 2; }
  only="$2"
elif [ $# -gt 0 ]; then
  echo "usage: $0 [--only <test_name>]" >&2
  exit 2
fi
tests="$(declare -F | awk '{print $3}' | grep '^test_')"
[ -z "$only" ] || { echo "$tests" | grep -qx "$only" || { echo "error: no such test: $only" >&2; exit 2; }; tests="$only"; }
count=0
for t in $tests; do
  CURRENT="$t"
  "$t"
  count=$((count + 1))
done
if [ "$FAILED" -eq 0 ]; then echo "ok: $count tests"; else echo "failed: $FAILED checks"; exit 1; fi
