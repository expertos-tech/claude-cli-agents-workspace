# shellcheck shell=bash
# Checks of the maintenance layers over the product (CLAUDE.md "Layout"), the session index and its hook included,
# shared by tests/check.sh and tests/test-caw-layers.sh. Sourced, never run. Every function takes the repository root
# as its first argument and reads only; it prints one line per problem, indented two spaces and naming the file, and
# returns 1 when there is any.

# Prints the body of the markdown file <file>: the file without its YAML frontmatter (a "---" first line up to the
# next "---" line), so the first line of a body is never a frontmatter line.
layer_body() {
  awk 'NR == 1 && $0 == "---" { fm = 1; next } fm && $0 == "---" { fm = 0; next } !fm' "$1"
}

# Prints the first non-blank line of the text on stdin, or nothing.
layer_first_line() {
  grep -m1 -v '^[[:space:]]*$' || true
}

# Checks that the text <body> holds each of the section lines given after it, exactly; <label> names the file in the
# messages. Returns 1 when one is missing.
layer_sections() {
  local label="$1" body="$2" section bad=0
  shift 2
  for section in "$@"; do
    printf '%s\n' "$body" | grep -qxF "$section" || { echo "  $label: missing section \"$section\""; bad=1; }
  done
  return "$bad"
}

# Checks the maintenance skills of <repo> that are layers over a product skill. A layer is any
# .claude/skills/caw-*/SKILL.md whose body starts with "@<path>", whatever its name: the path must be an existing
# workspace/rules/skills/<skill>/SKILL.md, and the body must hold the sections "Ignore from the product skill",
# "Mapping" and "CAW rules". A caw-<name> next to a product skill workspace/rules/skills/<name>/ must be a layer over
# that one: its "@" line names it, and a missing "@" line fails.
check_skill_layers() {
  local repo="$1" dir name product body first target bad=0
  for dir in "$repo"/.claude/skills/caw-*/; do
    [ -f "$dir/SKILL.md" ] || continue
    name="$(basename "$dir")"
    product="workspace/rules/skills/${name#caw-}/SKILL.md"
    body="$(layer_body "$dir/SKILL.md")"
    first="$(printf '%s\n' "$body" | layer_first_line)"
    if [ "${first:0:1}" != "@" ]; then
      if [ -f "$repo/$product" ]; then
        echo "  $name: the first line of its body must be @$product"
        bad=1
      fi
      continue
    fi
    target="${first#@}"
    if [ -f "$repo/$product" ] && [ "$target" != "$product" ]; then
      echo "  $name: the first line of its body must be @$product"
      bad=1
    elif [[ ! "$target" =~ ^workspace/rules/skills/[^/]+/SKILL\.md$ ]] || [[ "$target" == *..* ]]; then
      echo "  $name: the target of its @ line is not a product skill: ${target:-<empty>}"
      bad=1
    elif [ ! -f "$repo/$target" ]; then
      echo "  $name: the target of its @ line does not exist: $target"
      bad=1
    fi
    layer_sections "$name" "$body" "## Ignore from the product skill" "## Mapping" "## CAW rules" || bad=1
  done
  return "$bad"
}

# Checks the maintenance rules of <repo> that are layers over a product rule. A rule .claude/rules/<name>.md whose
# body starts with "@<path>" is a layer: the path must be exactly workspace/rules/<name>.md (the same file name, no
# ".."), that file must exist, and the body must hold the sections "Ignore from the product rule", "Mapping" and
# "CAW rules". A rule with a product counterpart workspace/rules/<name>.md and no "@" line fails: it must be a layer.
# A rule with neither passes untouched.
check_rule_layers() {
  local repo="$1" file name label product body first target bad=0
  for file in "$repo"/.claude/rules/*.md; do
    [ -f "$file" ] || continue
    name="$(basename "$file" .md)"
    label=".claude/rules/$name.md"
    product="workspace/rules/$name.md"
    body="$(layer_body "$file")"
    first="$(printf '%s\n' "$body" | layer_first_line)"
    if [ "${first:0:1}" != "@" ]; then
      if [ -f "$repo/$product" ]; then
        echo "  $label: must be a layer: the first line of its body must be @$product"
        bad=1
      fi
      continue
    fi
    target="${first#@}"
    if [ "$target" != "$product" ] || [[ "$target" == *..* ]]; then
      echo "  $label: the target of its @ line must be $product: ${target:-<empty>}"
      bad=1
    elif [ ! -f "$repo/$target" ]; then
      echo "  $label: the product rule of the layer is gone: $target"
      bad=1
    fi
    layer_sections "$label" "$body" "## Ignore from the product rule" "## Mapping" "## CAW rules" || bad=1
  done
  return "$bad"
}

# Checks the session index of <repo>, .claude/session-index.md, a layer over the product's index: it must exist, the
# first line of its body must be "@workspace/AGENTS.md", and it must hold the sections "Ignore from the product
# index", "Mapping" and "CAW index" (tests/caw-session-index.py reads them).
check_session_index() {
  local repo="$1" label=".claude/session-index.md" body first bad=0
  if [ ! -f "$repo/$label" ]; then
    echo "  $label: missing: the SessionStart hook tests/caw-session-index.py builds the index from it"
    return 1
  fi
  body="$(layer_body "$repo/$label")"
  first="$(printf '%s\n' "$body" | layer_first_line)"
  if [ "$first" != "@workspace/AGENTS.md" ]; then
    echo "  $label: the first line of its body must be @workspace/AGENTS.md: ${first:-<empty>}"
    bad=1
  fi
  layer_sections "$label" "$body" "## Ignore from the product index" "## Mapping" "## CAW index" || bad=1
  return "$bad"
}

# Checks the boxes of the assisted mode at the root (CLAUDE.md "Pilot mode"): when the product has
# workspace/rules/assisted.md, .claude/assisted.md must exist, the first line of its body must be
# "@workspace/rules/assisted.md", and it must hold the sections "Ignore from the product rule", "Mapping" and
# "CAW rules". A .claude/assisted.md with no product rule fails too: its pointer names a missing file.
check_assisted_layer() {
  local repo="$1" label=".claude/assisted.md" product="workspace/rules/assisted.md" body first bad=0
  if [ ! -f "$repo/$label" ]; then
    [ ! -f "$repo/$product" ] && return 0
    echo "  $label: missing: the layer over $product (the boxes of /caw-pilot assisted)"
    return 1
  fi
  if [ ! -f "$repo/$product" ]; then
    echo "  $label: its product rule $product is missing"
    bad=1
  fi
  body="$(layer_body "$repo/$label")"
  first="$(printf '%s\n' "$body" | layer_first_line)"
  if [ "$first" != "@$product" ]; then
    echo "  $label: the first line of its body must be @$product: ${first:-<empty>}"
    bad=1
  fi
  layer_sections "$label" "$body" "## Ignore from the product rule" "## Mapping" "## CAW rules" || bad=1
  return "$bad"
}

# The command of the SessionStart hook that builds the session index, exactly as .claude/settings.json registers it.
# shellcheck disable=SC2016
CAW_SESSION_HOOK='python3 -I -B "$CLAUDE_PROJECT_DIR/tests/caw-session-index.py"'

# Checks that .claude/settings.json of <repo> registers the session index: a SessionStart entry whose matcher covers
# startup, resume, clear and compact (no matcher, "" or "*" cover them all) runs the command $CAW_SESSION_HOOK.
check_session_hook() {
  local repo="$1" label=".claude/settings.json" msg
  if [ ! -f "$repo/$label" ]; then
    echo "  $label: missing: it must register the SessionStart hook $CAW_SESSION_HOOK"
    return 1
  fi
  msg="$(python3 -I -B -c '
import json, sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        settings = json.load(handle)
except (OSError, ValueError) as error:
    print("not valid JSON (" + type(error).__name__ + ")")
    sys.exit(1)
entries = settings.get("hooks", {}).get("SessionStart", []) if isinstance(settings, dict) else []
found = []
for entry in entries if isinstance(entries, list) else []:
    if not isinstance(entry, dict) or not isinstance(entry.get("hooks"), list):
        continue
    for hook in entry["hooks"]:
        if isinstance(hook, dict) and hook.get("type") == "command" and hook.get("command") == sys.argv[2]:
            found.append(entry.get("matcher", ""))
if not found:
    print("no SessionStart hook runs " + sys.argv[2])
    sys.exit(1)
needed = {"startup", "resume", "clear", "compact"}
for matcher in found:
    if matcher in ("", "*") or (isinstance(matcher, str) and needed <= set(matcher.split("|"))):
        sys.exit(0)
print("the SessionStart hook of tests/caw-session-index.py must match startup|resume|clear|compact: " + str(found[0]))
sys.exit(1)
' "$repo/$label" "$CAW_SESSION_HOOK" 2>&1)" && return 0
  echo "  $label: ${msg:-the check of the SessionStart hook failed}"
  return 1
}

# Checks every maintenance layer of <repo>: the skills, the rules, the boxes, the session index and its hook.
# Returns 1 when any has a problem.
check_caw_layers() {
  local repo="$1" bad=0
  check_skill_layers "$repo" || bad=1
  check_rule_layers "$repo" || bad=1
  check_assisted_layer "$repo" || bad=1
  check_session_index "$repo" || bad=1
  check_session_hook "$repo" || bad=1
  return "$bad"
}
