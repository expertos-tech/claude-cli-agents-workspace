#!/usr/bin/env bash
# Tests scripts/heavy-run.sh with seams for the CPU and GPU temperatures, and with no real heavy work.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
script="$root/scripts/heavy-run.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export HEAVY_RUN_CPU_TEMP_FILE="$work/cpu"
export HEAVY_RUN_GPU_TEMP_FILE="$work/gpu"
export HEAVY_RUN_POLL_SECONDS=1

passed=0

# Fails the run when two values differ.
assert_equal() {
  if [[ "$1" != "$2" ]]; then
    echo "FAIL: $3: expected '$2', got '$1'" >&2
    exit 1
  fi
  passed=$((passed + 1))
}

# Sets the CPU and GPU temperatures the script reads; an empty value means the sensor is missing.
machine() {
  echo "$1" > "$work/cpu"
  echo "$2" > "$work/gpu"
}

machine 50 40
assert_equal "$(bash "$script" -- echo ran)" "ran" "cool machine runs the command"

status=0
bash "$script" -- bash -c 'exit 7' || status=$?
assert_equal "$status" "7" "exit status of the command"

status=0
bash "$script" 2> /dev/null || status=$?
assert_equal "$status" "2" "no command is invalid usage"

status=0
bash "$script" --max-temp 95 -- true 2> /dev/null || status=$?
assert_equal "$status" "2" "--max-temp is not an option"

assert_equal "$(bash "$script" --status)" "cpu=50 gpu=40 hottest=50" "status shows both readings"

# 87 °C starts at once.
machine 87 60
assert_equal "$(HEAVY_RUN_WAIT_SECONDS=0 bash "$script" -- echo ran)" "ran" "87 °C runs without waiting"

# the hotter of CPU and GPU counts.
machine 60 88
status=0
output="$(HEAVY_RUN_WAIT_SECONDS=1 bash "$script" -- echo ran 2> /dev/null)" || status=$?
assert_equal "$status" "75" "a hot GPU holds the start"
assert_equal "$output" "" "a hot GPU ran nothing"

# 88 °C waits; 86 °C is not enough; 85 °C starts.
machine 88 50
(sleep 1 && machine 86 50 && sleep 2 && machine 85 50) &
output="$(HEAVY_RUN_WAIT_SECONDS=20 bash "$script" -- cat "$work/cpu" 2> /dev/null)"
wait
assert_equal "$output" "85" "88 °C waits past 86 °C and runs once it reads 85 °C"

status=0
HEAVY_RUN_WAIT_SECONDS=30m bash "$script" -- true 2> /dev/null || status=$?
assert_equal "$status" "2" "a wait that is not a whole number is invalid usage"

# Above 85 °C for the whole wait: nothing runs and the last reading is reported.
machine 90 70
(sleep 0.5 && machine 86 70) &
status=0
output="$(HEAVY_RUN_WAIT_SECONDS=2 bash "$script" -- echo ran 2> "$work/err")" || status=$?
wait
assert_equal "$status" "75" "still hot after the wait does not run"
assert_equal "$output" "" "still hot ran nothing"
grep -q "cpu=86 gpu=70 hottest=86" "$work/err" || { echo "FAIL: last reading missing" >&2; exit 1; }
passed=$((passed + 1))

# A machine with no sensor runs, with a warning.
machine "" ""
assert_equal "$(bash "$script" -- echo ran 2> /dev/null)" "ran" "no sensor runs the command"

# two runs at once never wait for each other.
machine 50 40
bash "$script" -- bash -c "sleep 2; echo first >> '$work/order'" &
holder=$!
sleep 0.5
bash "$script" -- bash -c "echo second >> '$work/order'"
wait "$holder"
assert_equal "$(tr '\n' ' ' < "$work/order")" "second first " "no run waits for another"

output="$(bash "$script" --help)"
[[ "$output" == Usage:* ]] || { echo "FAIL: help" >&2; exit 1; }
passed=$((passed + 1))

echo "pass: $passed assertions"
