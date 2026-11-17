#!/usr/bin/env bash
# Runs a task heavy on CPU or GPU only once the hotter of the two is cool enough.
set -euo pipefail

HOT=88
COOL=85
WAIT_SECONDS="${HEAVY_RUN_WAIT_SECONDS:-1800}"
POLL_SECONDS="${HEAVY_RUN_POLL_SECONDS:-15}"

# Prints the command line help.
usage() {
  cat <<'HELP'
Usage: bash scripts/heavy-run.sh [--] <command> [args...]
       bash scripts/heavy-run.sh --status

Runs a task that can demand much CPU or GPU (graphics, 3D rendering) after reading the hotter of
the CPU package and the GPU. Under 88 °C it runs at once. At 88 °C or more it waits until the
reading is 85 °C or less, then runs. Still above 85 °C after 30 minutes: the command does not run
and the last reading is printed. There is no queue: it never waits for another session. Its exit
status is the command's.

  --status  Print the CPU, GPU and hotter readings in Celsius, then exit.
  --help    Show this help.

Exit: the command's status; 2 invalid usage; 75 still hot after the wait, the command did not run.
Environment: HEAVY_RUN_CPU_TEMP_FILE, HEAVY_RUN_GPU_TEMP_FILE, HEAVY_RUN_WAIT_SECONDS,
HEAVY_RUN_POLL_SECONDS (test seams).

Example: bash scripts/heavy-run.sh -- godot --headless --export-release Linux build/game
HELP
}

# Stops with an invalid usage message.
fail_usage() {
  echo "error: $1; see --help" >&2
  exit 2
}

# Prints the CPU package temperature in Celsius, or nothing when the machine does not report it.
cpu_temp() {
  local zone
  if [[ -n "${HEAVY_RUN_CPU_TEMP_FILE:-}" ]]; then
    cat "$HEAVY_RUN_CPU_TEMP_FILE"
    return
  fi
  for zone in /sys/class/thermal/thermal_zone*; do
    [[ -r "$zone/type" && -r "$zone/temp" ]] || continue
    if [[ "$(cat "$zone/type")" == x86_pkg_temp ]]; then
      echo $(($(cat "$zone/temp") / 1000))
      return
    fi
  done
}

# Prints the hottest GPU temperature in Celsius, or nothing when no GPU reports one.
gpu_temp() {
  if [[ -n "${HEAVY_RUN_GPU_TEMP_FILE:-}" ]]; then
    cat "$HEAVY_RUN_GPU_TEMP_FILE"
    return
  fi
  command -v nvidia-smi > /dev/null || return 0
  timeout 10 nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits 2> /dev/null |
    sort -n | tail -n 1 | tr -d ' ' || true
}

# Reads both sensors into CPU, GPU and HOTTEST; HOTTEST is empty when neither reports.
read_temps() {
  CPU="$(cpu_temp)"
  GPU="$(gpu_temp)"
  [[ "$CPU" =~ ^[0-9]+$ ]] || CPU=""
  [[ "$GPU" =~ ^[0-9]+$ ]] || GPU=""
  HOTTEST="$CPU"
  if [[ -n "$GPU" ]] && [[ -z "$HOTTEST" || "$GPU" -gt "$HOTTEST" ]]; then
    HOTTEST="$GPU"
  fi
}

# Prints the last reading.
reading() {
  echo "cpu=${CPU:--} gpu=${GPU:--} hottest=${HOTTEST:--}"
}

[[ "$WAIT_SECONDS" =~ ^[0-9]+$ ]] || fail_usage "HEAVY_RUN_WAIT_SECONDS needs a whole number"
[[ "$POLL_SECONDS" =~ ^[0-9]+$ ]] || fail_usage "HEAVY_RUN_POLL_SECONDS needs a whole number"

case "${1:-}" in
  --status)
    read_temps
    reading
    exit 0
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  --)
    shift
    ;;
  -*)
    fail_usage "unknown option: $1"
    ;;
esac
(($# > 0)) || fail_usage "no command given"

read_temps
if [[ -z "$HOTTEST" ]]; then
  echo "warning: no CPU or GPU temperature reported; running without the check" >&2
elif ((HOTTEST >= HOT)); then
  echo "heavy-run: $(reading); waiting for ${COOL} °C or less, up to ${WAIT_SECONDS} s" >&2
  SECONDS=0
  until [[ -z "$HOTTEST" ]] || ((HOTTEST <= COOL)); do
    if ((SECONDS >= WAIT_SECONDS)); then
      echo "error: still hot after ${WAIT_SECONDS} s ($(reading)); nothing ran" >&2
      exit 75
    fi
    sleep "$POLL_SECONDS"
    read_temps
  done
fi

exec "$@"
