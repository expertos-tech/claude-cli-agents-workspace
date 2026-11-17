#!/usr/bin/env bash
# Tests of scripts/guard-subagent-model.sh (+ guard-subagent-model.py) against a throwaway project root (never the real one).
# Run: bash scripts/tests/guard-subagent-model/test-guard-subagent-model.sh
#
# Decision list (rules/quality.md "Tests", bash exception). Every decision and error path -> test function.
#  D1  usage: --help/-h prints usage, exit 0 ................................. test_help_and_args
#  D2  usage: unknown option, exit 2 ......................................... test_help_and_args
#  D3  python3 missing, exit 2 with a clear message .......................... test_python_missing
#  D4  root = $CLAUDE_PROJECT_DIR; unset -> parent of the script folder ....... test_root_fallback
#  D5  model contains fable (any case/spelling, NFKC) -> ask, English text with the type test_a_fable_asks
#  D6  fork wins over fable (deny, fork reason, checked first) ................ test_a_fable_asks
#  D7  fork, normalized (NFKC, lowercase, no space/-/_) -> deny ............... test_b_fork_denied
#  D8  not fork (fork-like names, null type) -> not denied ................... test_b_fork_denied
#  D9  explicit model in the allowlist -> silent (ids, case, spaces) .......... test_c_allowlist_silent
#  D10 explicit model outside the allowlist -> deny ........................... test_c_allowlist_denied
#  D11 blank explicit model counts as no model ................................ test_c_allowlist_denied
#  D12 no model: built-in types (claude-code-guide, statusline-setup) get opus; a project file decides  test_d_builtin_vs_file
#  D13 frontmatter: allowlisted value (quotes, case, ids) -> fixed ............. test_d_frontmatter_fixed
#  D14 frontmatter: other value -> not fixed -> opus ........................... test_d_frontmatter_not_fixed
#  D14b fixed needs exactly one model: line and one name: equal to the type ...... test_d_one_model_one_name
#  D14c agent file with invalid UTF-8 -> exit 2 (UnicodeDecodeError); non-ASCII text ok under any locale  test_d_utf8_agent_file
#  D15 frontmatter structure: opening ---, closing ---, first model line ...... test_d_frontmatter_structure
#  D16 agent type regex (path traversal, nested, odd chars) -> opus ............ test_d_type_regex
#  D17 no agent file, other types, no type -> opus, input kept ................. test_d_forced_opus
#  D18 bad types: tool_input not object, model/type not string (also falsy) ... test_e_malformed_blocks
#  D19 invalid JSON / empty / missing tool_input / invalid UTF-8 -> exit 2 ...... test_e_malformed_blocks
#  D20 block message names the exception type ................................ test_e_malformed_blocks
#  D21 stdin read as UTF-8 under a non-UTF-8 locale ............................ test_utf8_under_c_locale
#  D22 rules/agents/settings.json: model opus, effortLevel medium, fallbackModel without fable, env, exact hook command  test_settings_static
#  D24 non-ASCII subagent_type after NFKC (e.g. U+FEFF) -> deny ................... test_b_fork_denied
#  D25 stderr noise of python3 on success stays out of stdout .................... test_stderr_apart
#  D26 python runs isolated (-I): a planted json.py next to the script is ignored  test_isolated_python
#  D27 output carries hookEventName; exception type of non-string model/type ..... test_e_malformed_blocks
#  Coverage gate of guard-subagent-model.py: scripts/.coveragerc + scripts/tests/test_guard_subagent_model.py (docker/python-coverage)
#  D23 every real rules/agents/*.md is a fixed-model agent ..................... test_real_agents_fixed
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "$HERE/../.." && pwd)"
SCRIPT="$SCRIPTS/guard-subagent-model.sh"
REPO="$(cd "$SCRIPTS/.." && pwd)"
BASH_BIN="$(command -v bash)"
BASE="$(mktemp -d)"
trap 'rm -rf "$BASE"' EXIT
PASS=0
FAILED=0
OUT=""
ERR=""
RC=0
CURRENT=""
mkdir -p "$BASE/.claude/agents"

agent() { # name, frontmatter-and-body text (printf format)
  printf '%b' "$2" >"$BASE/.claude/agents/$1.md"
}
agent fixed '---\nname: fixed\nmodel: sonnet\n---\nbody\n'
agent inh '---\nname: inh\nmodel: inherit\n---\nbody\n'
agent fab '---\nname: fab\nmodel: claude-fable-1\n---\nbody\n'
agent nomodel '---\nname: nomodel\n---\nbody\n'

guard() { # JSON text for stdin; optional 2nd arg: LC_ALL value
  OUT="$(printf '%s' "$1" | env CLAUDE_PROJECT_DIR="$BASE" LC_ALL="${2:-${LC_ALL:-}}" "$BASH_BIN" "$SCRIPT" 2>"$BASE/err")"
  RC=$?
  ERR="$(cat "$BASE/err")"
}

check() {
  if [ "$2" -eq 0 ]; then PASS=$((PASS + 1)); else FAILED=$((FAILED + 1)); echo "FAIL $CURRENT: $1 (rc=$RC out=[$OUT] err=[$ERR])"; fi
}
eq() { [ "$2" = "$3" ]; check "$1: expected [$2] got [$3]" $?; }
has() { case "$3" in *"$2"*) check "$1" 0 ;; *) check "$1: [$2] not in [$3]" 1 ;; esac; }
# Prints a field of the decision JSON (dotted path under hookSpecificOutput), empty when absent.
field() {
  printf '%s' "$OUT" | python3 -I -c '
import json, sys
d = json.load(sys.stdin)["hookSpecificOutput"]
for k in sys.argv[1].split("."):
    d = d.get(k, "") if isinstance(d, dict) else ""
print(json.dumps(d) if isinstance(d, dict) else d)' "$1"
}
expect_deny() { # label, json
  guard "$2"
  eq "rc $1" 0 "$RC"; eq "deny $1" deny "$(field permissionDecision)"
}
expect_silent() { # label, json
  guard "$2"
  eq "rc $1" 0 "$RC"; eq "silent $1" "" "$OUT"
}
expect_opus() { # label, json
  guard "$2"
  eq "rc $1" 0 "$RC"
  eq "allow $1" allow "$(field permissionDecision)"
  eq "opus $1" opus "$(field updatedInput.model)"
}
call() { printf '{"tool_input":{"subagent_type":"%s","prompt":"p"}}' "$1"; }
with_model() { printf '{"tool_input":{"subagent_type":"Plan","model":"%s"}}' "$1"; }

test_a_fable_asks() {
  CURRENT=a
  guard '{"tool_input":{"model":"Claude-FABLE-1","subagent_type":"x","effort":"low"}}'
  has "reason shows the effort" "with effort low" "$(field permissionDecisionReason)"
  guard '{"tool_input":{"model":"Claude-FABLE-1","subagent_type":"x"}}'
  eq "rc" 0 "$RC"; eq "ask" ask "$(field permissionDecision)"
  eq "hookEventName" PreToolUse "$(field hookEventName)"
  has "reason in English with the type" "The subagent of type 'x' asked for the Fable model" "$(field permissionDecisionReason)"
  has "reason says effort is missing" "with effort not given" "$(field permissionDecisionReason)"
  local m
  for m in fable FABLE Fable claude-fable-1 " fable " opusfable "ｆａｂｌｅ"; do
    guard "$(with_model "$m")"
    eq "rc [$m]" 0 "$RC"; eq "fable ask [$m]" ask "$(field permissionDecision)"
    has "fable reason [$m]" "asked for the Fable model" "$(field permissionDecisionReason)"
    has "fable reason names type [$m]" "type 'Plan'" "$(field permissionDecisionReason)"
    eq "no updatedInput [$m]" "" "$(field updatedInput)"
  done
  guard '{"tool_input":{"model":"fable"}}'
  has "no type" "(no type)" "$(field permissionDecisionReason)"
  guard '{"tool_input":{"subagent_type":"fork","model":"fable"}}'
  eq "fork wins over fable" deny "$(field permissionDecision)"
  has "fork reason" inherits "$(field permissionDecisionReason)"
  guard '{"tool_input":{"subagent_type":"Fork","model":"claude-fable-1"}}'
  eq "Fork wins over fable" deny "$(field permissionDecision)"
}
test_b_fork_denied() {
  CURRENT=b
  guard '{"tool_input":{"subagent_type":"fork","model":"haiku"}}'
  eq "deny" deny "$(field permissionDecision)"
  has "reason" inherits "$(field permissionDecisionReason)"
  local t
  for t in fork Fork FORK fo-rk fo_rk "f o r k" "Fo-Rk_" "ｆｏｒｋ"; do expect_deny "fork [$t]" "$(call "$t")"; done
  for t in forks forked fork2 fork-agent for; do expect_opus "not fork [$t]" "$(call "$t")"; done
  for t in $'fork\ufeff' $'for\u200bk' "agentü" "日本"; do expect_deny "non-ASCII type [$t]" "$(call "$t")"; done
  has "non-ASCII reason" "outside ASCII" "$(field permissionDecisionReason)"
  expect_opus "null type" '{"tool_input":{"subagent_type":null,"prompt":"p"}}'
}
test_c_allowlist_silent() {
  CURRENT=c
  local m
  for m in opus sonnet haiku Opus SONNET " haiku " claude-opus-5-5 claude-sonnet-5-5 claude-haiku-5-5 Claude-Opus-5-5 "claude-opus-4-1[1m]"; do
    expect_silent "allowed [$m]" "$(with_model "$m")"
  done
}
test_c_allowlist_denied() {
  CURRENT=c2
  local m
  for m in inherit default best gpt-5 claude-opus claude-opus- claude-3-opus opus-x opusplan "sonnet 4" xopus; do
    expect_deny "denied [$m]" "$(with_model "$m")"
    has "reason [$m]" "allowed for subagents" "$(field permissionDecisionReason)"
  done
  # blank model is no model: Plan is not fixed, so it gets opus
  expect_opus "blank model" '{"tool_input":{"subagent_type":"Plan","model":"  "}}'
  expect_opus "empty model" '{"tool_input":{"subagent_type":"Plan","model":""}}'
}
test_d_builtin_vs_file() {
  CURRENT=d1
  local t
  for t in claude-code-guide statusline-setup; do expect_opus "builtin $t gets opus" "$(call "$t")"; done
  agent statusline-setup '---\nname: statusline-setup\nmodel: fable\n---\n'
  expect_opus "file fable" "$(call statusline-setup)"
  agent statusline-setup '---\nname: statusline-setup\nmodel: inherit\n---\n'
  expect_opus "file inherit" "$(call statusline-setup)"
  agent statusline-setup '---\nname: statusline-setup\nmodel: haiku\n---\n'
  expect_silent "file haiku" "$(call statusline-setup)"
  rm "$BASE/.claude/agents/statusline-setup.md"
  expect_opus "opus again without file" "$(call statusline-setup)"
}
test_d_frontmatter_fixed() {
  CURRENT=d2
  local v i=0
  for v in sonnet opus haiku '"sonnet"' "'haiku'" SONNET 'Claude-Opus-5-5' claude-sonnet-5-5 '  sonnet  ' '"claude-haiku-5-5"'; do
    i=$((i + 1)); agent "fx$i" "---\nname: fx$i\nmodel: $v\n---\n"
    expect_silent "frontmatter fixed [$v]" "$(call "fx$i")"
  done
  agent quoted_trailing '---\nname: quoted_trailing\nmodel: "sonnet"   \n---\n'
  expect_silent "quoted value with trailing spaces" "$(call quoted_trailing)"
  agent quoted_inner '---\nname: quoted_inner\nmodel: " sonnet "\n---\n'
  expect_silent "quoted value with inner spaces" "$(call quoted_inner)"
  agent crlf '---\r\nname: crlf\r\nmodel: sonnet\r\n---\r\n'
  expect_silent "crlf file" "$(call crlf)"
}
test_d_frontmatter_not_fixed() {
  CURRENT=d3
  local v i=0
  for v in inherit default best fable '' '"inherit"' "'inherit'" '"default"' '"best"' 'inherit # x' 'sonnet # c' '>-' '|' 'claude-fable-1' '"fable"' gpt-5 '"sonnet' 'opusplan'; do
    i=$((i + 1)); agent "nf$i" "---\nname: nf$i\nmodel: $v\n---\n"
    expect_opus "frontmatter not fixed [$v]" "$(call "nf$i")"
  done
  agent mismatchq "---\nname: mismatchq\nmodel: \"sonnet'\n---\n"
  expect_opus "mismatched quotes" "$(call mismatchq)"
  agent quotedname '---\nname: "quotedname"\nmodel: sonnet\n---\n'
  expect_silent "quoted name" "$(call quotedname)"
  agent onequote '---\nname: onequote\nmodel: "\n---\n'
  expect_opus "single quote char" "$(call onequote)"
  agent folded '---\nname: folded\nmodel: >-\n  fable\n---\n'
  expect_opus "folded fable" "$(call folded)"
}
test_d_frontmatter_structure() {
  CURRENT=d4
  agent noopen 'name: x\nmodel: sonnet\n---\n'
  expect_opus "no opening ---" "$(call noopen)"
  agent firstblank '\n---\nmodel: sonnet\n---\n'
  expect_opus "blank first line" "$(call firstblank)"
  agent noclose '---\nname: x\nbody only\n'
  expect_opus "never closed" "$(call noclose)"
  agent afterclose '---\nname: x\n---\nmodel: sonnet\n'
  expect_opus "model after closing ---" "$(call afterclose)"
  agent firstwins '---\nname: firstwins\nmodel: inherit\nmodel: sonnet\n---\n'
  expect_opus "two model lines (inherit first)" "$(call firstwins)"
  agent firstwins2 '---\nname: firstwins2\nmodel: sonnet\nmodel: inherit\n---\n'
  expect_opus "two model lines (sonnet first)" "$(call firstwins2)"
  agent spaced '---\nname : spaced\nmodel   :   haiku\n---\n'
  expect_silent "spaces around colon" "$(call spaced)"
  agent indented '---\nname: indented\n  model: sonnet\n---\n'
  expect_opus "indented model is not a key" "$(call indented)"
  agent empty ''
  expect_opus "empty file" "$(call empty)"
  agent closing_spaces '---   \nname: closing_spaces\nmodel: sonnet\n---  \n'
  expect_silent "--- with trailing spaces" "$(call closing_spaces)"
  agent closing_spaces2 '---\nname: closing_spaces2\n---  \nmodel: sonnet\n'
  expect_opus "closing --- with trailing spaces ends the frontmatter" "$(call closing_spaces2)"
  agent opening_spaces '---  \nname: opening_spaces\nmodel: sonnet\n---\n'
  expect_silent "opening --- with trailing spaces" "$(call opening_spaces)"
}
test_d_type_regex() {
  CURRENT=d5
  mkdir -p "$BASE/.claude/agents/sub"
  printf -- '---\nname: nested\nmodel: sonnet\n---\n' >"$BASE/.claude/agents/sub/nested.md"
  local t
  for t in "../agents/fixed" "sub/nested" "fixed/../fixed" "./fixed" "fixed.md" "fi xed" 'fixed$' "fixed;x" "/etc/passwd" ""; do
    expect_opus "type [$t]" "$(call "$t")"
  done
  agent "my.agent_1-x" '---\nname: my.agent_1-x\nmodel: haiku\n---\n'
  expect_silent "dots, underscore, dash in type" "$(call "my.agent_1-x")"
}
test_d_forced_opus() {
  CURRENT=d6
  local t
  for t in inh fab nomodel Plan Explore claude missing-agent "../x"; do
    guard "$(printf '{"tool_input":{"subagent_type":"%s","prompt":"p","description":"d"}}' "$t")"
    eq "allow $t" allow "$(field permissionDecision)"
    eq "model $t" opus "$(field updatedInput.model)"
    eq "prompt kept $t" p "$(field updatedInput.prompt)"
    eq "type kept $t" "$t" "$(field updatedInput.subagent_type)"
    eq "description kept $t" d "$(field updatedInput.description)"
  done
  guard '{"tool_input":{"prompt":"p"}}'
  eq "general-purpose" opus "$(field updatedInput.model)"
  eq "prompt kept" p "$(field updatedInput.prompt)"
  expect_silent "fixed file" "$(call fixed)"
}
test_d_one_model_one_name() {
  CURRENT=d7
  agent nonamefile '---\nmodel: sonnet\n---\n'
  expect_opus "no name line" "$(call nonamefile)"
  agent othername '---\nname: someone-else\nmodel: sonnet\n---\n'
  expect_opus "name differs from the type" "$(call othername)"
  agent twonames '---\nname: twonames\nname: twonames\nmodel: sonnet\n---\n'
  expect_opus "two name lines" "$(call twonames)"
  agent sonnetfable '---\nname: sonnetfable\nmodel: sonnet\nmodel: fable\n---\n'
  expect_opus "model: sonnet then model: fable" "$(call sonnetfable)"
  agent crossed '---\nname: fixed\nmodel: sonnet\n---\n'
  cp "$BASE/.claude/agents/crossed.md" "$BASE/.claude/agents/crossed2.md"
  expect_opus "crossed name in another file" "$(call crossed2)"
  expect_silent "exactly one of each" "$(call fixed)"
}
test_d_utf8_agent_file() {
  CURRENT=d8
  printf -- '---\nname: badutf\nmodel: sonnet\n---\n\377\376\n' >"$BASE/.claude/agents/badutf.md"
  guard "$(call badutf)"
  eq "invalid UTF-8 agent file blocks" 2 "$RC"; has "exception type" UnicodeDecodeError "$ERR"
  printf -- '---\nname: accent\ndescription: ação ünï 日本\nmodel: sonnet\n---\n' >"$BASE/.claude/agents/accent.md"
  local loc
  for loc in C POSIX en_US.ISO8859-1 en_US.US-ASCII; do
    guard "$(call accent)" "$loc"
    eq "accent file rc [$loc]" 0 "$RC"; eq "accent file fixed [$loc]" "" "$OUT"
  done
}
test_stderr_apart() {
  CURRENT=noise
  mkdir -p "$BASE/noisy"
  local real; real="$(command -v python3)"
  printf '#!/bin/sh\necho "DeprecationWarning: noise" >&2\nexec "%s" "$@"\n' "$real" >"$BASE/noisy/python3"; chmod +x "$BASE/noisy/python3"
  for t in dirname head tr rm mktemp; do ln -sf "$(command -v "$t")" "$BASE/noisy/$t"; done
  OUT="$(printf '%s' "$(with_model fable)" | env PATH="$BASE/noisy" CLAUDE_PROJECT_DIR="$BASE" "$BASH_BIN" "$SCRIPT" 2>"$BASE/err")"; RC=$?
  ERR="$(cat "$BASE/err")"
  eq "rc" 0 "$RC"; eq "decision still parseable" ask "$(field permissionDecision)"
  eq "stderr noise not on stdout" "" "$(printf '%s' "$OUT" | grep -c noise | sed 's/^1$/x/;s/^0$//')"
}
test_isolated_python() {
  CURRENT=isolated
  local alt="$BASE/plant"
  mkdir -p "$alt/scripts"
  cp "$SCRIPT" "$SCRIPTS/guard-subagent-model.py" "$alt/scripts/"
  printf 'print("PLANTED")\nraise SystemExit(0)\n' >"$alt/scripts/json.py"
  OUT="$(printf '%s' "$(with_model haiku)" | env CLAUDE_PROJECT_DIR="$BASE" "$BASH_BIN" "$alt/scripts/guard-subagent-model.sh" 2>"$BASE/err")"; RC=$?
  eq "rc" 0 "$RC"; eq "planted module ignored" "" "$OUT"
  OUT="$(printf '%s' "$(with_model gpt-5)" | env CLAUDE_PROJECT_DIR="$BASE" "$BASH_BIN" "$alt/scripts/guard-subagent-model.sh" 2>"$BASE/err")"
  eq "deny still works" deny "$(field permissionDecision)"
}
test_e_malformed_blocks() {
  CURRENT=e
  local t
  for t in '{x' '' '{"a":1}' '{"tool_input":"s"}' '{"tool_input":[]}' '{"tool_input":null}' '[]' \
    '{"tool_input":{"model":3}}' '{"tool_input":{"model":false}}' '{"tool_input":{"model":0}}' '{"tool_input":{"model":[]}}' '{"tool_input":{"model":{}}}' \
    '{"tool_input":{"subagent_type":[]}}' '{"tool_input":{"subagent_type":false}}' '{"tool_input":{"subagent_type":0}}' '{"tool_input":{"subagent_type":{}}}' \
    '{"tool_input":{"subagent_type":7,"model":"haiku"}}'; do
    guard "$t"
    eq "rc for [$t]" 2 "$RC"
    eq "no stdout for [$t]" "" "$OUT"
    has "message for [$t]" "hook input rejected" "$ERR"
  done
  guard '{x'
  has "exception type, bad JSON" JSONDecodeError "$ERR"
  guard '{"a":1}'
  has "exception type, missing key" KeyError "$ERR"
  for t in '{"tool_input":{"model":3}}' '{"tool_input":{"subagent_type":0}}' '{"tool_input":[]}'; do
    guard "$t"
    eq "exception type [$t]" TypeError "$(printf '%s' "$ERR" | sed -n 's/.*(\([A-Za-z]*\)).*/\1/p')"
  done
  # invalid UTF-8 bytes on stdin
  OUT="$(printf '{"tool_input":{"prompt":"\377\376"}}' | CLAUDE_PROJECT_DIR="$BASE" "$BASH_BIN" "$SCRIPT" 2>"$BASE/err")"; RC=$?; ERR="$(cat "$BASE/err")"
  eq "invalid utf-8 rc" 2 "$RC"
  has "exception type, bad utf-8" UnicodeDecodeError "$ERR"
}
test_utf8_under_c_locale() {
  CURRENT=utf8
  local loc
  for loc in C POSIX en_US.ISO8859-1 en_US.US-ASCII; do
    guard '{"tool_input":{"subagent_type":"Plan","prompt":"ação ünï 日本"}}' "$loc"
    eq "rc [$loc]" 0 "$RC"
    eq "prompt intact [$loc]" "ação ünï 日本" "$(field updatedInput.prompt)"
    guard '{"tool_input":{"subagent_type":"ｆｏｒｋ"}}' "$loc"
    eq "unicode fork denied [$loc]" deny "$(field permissionDecision)"
  done
}
test_python_missing() {
  CURRENT=nopython
  mkdir -p "$BASE/nopy"
  ln -sf "$(command -v dirname)" "$BASE/nopy/dirname"
  OUT="$(printf '{"tool_input":{}}' | env PATH="$BASE/nopy" CLAUDE_PROJECT_DIR="$BASE" "$BASH_BIN" "$SCRIPT" 2>"$BASE/err")"; RC=$?
  ERR="$(cat "$BASE/err")"
  eq "rc" 2 "$RC"; eq "stdout" "" "$OUT"
  has "message" "python3 not found" "$ERR"
}
test_root_fallback() {
  CURRENT=root
  local alt="$BASE/alt"
  mkdir -p "$alt/scripts" "$alt/.claude/agents"
  cp "$SCRIPT" "$SCRIPTS/guard-subagent-model.py" "$alt/scripts/"
  printf -- '---\nname: onlyhere\nmodel: haiku\n---\n' >"$alt/.claude/agents/onlyhere.md"
  OUT="$(printf '%s' "$(call onlyhere)" | env -u CLAUDE_PROJECT_DIR "$BASH_BIN" "$alt/scripts/guard-subagent-model.sh" 2>"$BASE/err")"; RC=$?
  eq "rc" 0 "$RC"; eq "fixed via fallback root" "" "$OUT"
  OUT="$(printf '%s' "$(call fixed)" | env -u CLAUDE_PROJECT_DIR "$BASH_BIN" "$alt/scripts/guard-subagent-model.sh" 2>"$BASE/err")"
  eq "other root has no 'fixed'" opus "$(field updatedInput.model)"
}
test_settings_static() {
  CURRENT=settings
  local out
  out="$(python3 -I - "$REPO/rules/agents/settings.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1], encoding="utf-8"))
hooks = [h for e in s["hooks"]["PreToolUse"] if e["matcher"] == "Agent" for h in e["hooks"]]
guards = [h for h in hooks if "guard-subagent-model" in h["command"]]
print("hook-count", len(guards))
h = guards[0]
print("command", h["command"] == 'bash "$CLAUDE_PROJECT_DIR/scripts/guard-subagent-model.sh"' and h["type"] == "command")
print("onFailure", h.get("onFailure"))
print("model", s.get("model"))
print("effort", s.get("effortLevel"))
fb = s.get("fallbackModel", [])
fb = [fb] if isinstance(fb, str) else fb
print("fallback-fable", any("fable" in str(x).lower() for x in fb))
print("env", s["env"].get("CLAUDE_CODE_SUBAGENT_MODEL", ""))
print("fable", "fable" in s["availableModels"])
print("no-fork-env", "CLAUDE_CODE_FORK_SUBAGENT" not in s["env"])
PY
)"
  has "the guard is one Agent hook, others may sit beside it" "hook-count 1" "$out"
  has "exact command" "command True" "$out"
  has "onFailure block" "onFailure block" "$out"
  has "session model" "model opus" "$out"
  has "session effort" "effort medium" "$out"
  has "fallback without fable" "fallback-fable False" "$out"
  has "subagent model env" "env opus" "$out"
  has "fable available" "fable True" "$out"
  has "no fork env" "no-fork-env True" "$out"
}
test_real_agents_fixed() {
  CURRENT=real
  local f n count=0
  for f in "$REPO"/rules/agents/*.md; do
    n="$(basename "$f" .md)"
    cp "$f" "$BASE/.claude/agents/$n.md"
    expect_silent "real agent $n" "$(call "$n")"
    count=$((count + 1))
  done
  [ "$count" -gt 0 ]; check "found real agents" $?
}
test_help_and_args() {
  CURRENT=args
  OUT="$("$BASH_BIN" "$SCRIPT" --help)"; RC=$?
  eq "help rc" 0 "$RC"
  has "help" Usage "$OUT"
  OUT="$("$BASH_BIN" "$SCRIPT" -h)"; RC=$?
  eq "-h rc" 0 "$RC"
  OUT="$("$BASH_BIN" "$SCRIPT" --bogus 2>&1)"; RC=$?
  eq "bad option rc" 2 "$RC"
  has "bad option text" "unknown option" "$OUT"
}

test_a_fable_asks
test_b_fork_denied
test_c_allowlist_silent
test_c_allowlist_denied
test_d_builtin_vs_file
test_d_frontmatter_fixed
test_d_frontmatter_not_fixed
test_d_frontmatter_structure
test_d_one_model_one_name
test_d_utf8_agent_file
test_stderr_apart
test_isolated_python
test_d_type_regex
test_d_forced_opus
test_e_malformed_blocks
test_utf8_under_c_locale
test_python_missing
test_root_fallback
test_settings_static
test_real_agents_fixed
test_help_and_args
echo "passed=$PASS failed=$FAILED"
[ "$FAILED" -eq 0 ]
