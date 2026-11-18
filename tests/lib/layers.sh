# shellcheck shell=bash
# Checks of the maintenance layers over the product (CLAUDE.md "Layout"), shared by tests/check.sh and
# tests/test-caw-layers.sh. Sourced, never run. Every function takes the repository root as its first argument and
# reads only; it prints one line per problem, indented two spaces and naming the file, and returns 1 when there is any.

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

# Checks every maintenance layer of <repo>: the skills, then the rules. Returns 1 when either has a problem.
check_caw_layers() {
  local repo="$1" bad=0
  check_skill_layers "$repo" || bad=1
  check_rule_layers "$repo" || bad=1
  return "$bad"
}
