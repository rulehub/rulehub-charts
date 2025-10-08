#!/usr/bin/env bash
set -euo pipefail
# verify-performance.sh
# Measure helm template performance and guard against >THRESHOLD regression vs baseline.
# Baseline file persisted in repo (default: perf-baseline.json).
# Usage:
#   hack/verify-performance.sh [--update] [--runs 3] [--threshold 0.20] [--values values.yaml] [--baseline perf-baseline.json]
# Behavior:
#  - If baseline file missing -> create it (unless --update not provided? we create anyway) and exit 0.
#  - Measure average wall time over N runs of `helm template` discarding output.
#  - Fail if current > baseline * (1+threshold).
#  - --update: always write new baseline using current measurement.
# Output: human-readable summary. For automated parsing, you can grep for 'PERF:'.

UPDATE=0
RUNS=3
THRESHOLD=0.20
VALUES_FILE="values.yaml"
BASELINE_FILE="perf-baseline.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --update) UPDATE=1; shift ;;
    --runs) RUNS="$2"; shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --values) VALUES_FILE="$2"; shift 2 ;;
    --baseline) BASELINE_FILE="$2"; shift 2 ;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //'; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if ! command -v helm >/dev/null 2>&1; then echo "helm not found" >&2; exit 2; fi
if ! command -v jq >/dev/null 2>&1; then echo "jq required" >&2; exit 2; fi

CHART_DIR="$(cd "$(dirname "$0")/.." && pwd)"

measure_one() {
  local start end diff_ns diff_ms
  start=$(date +%s%N)
  helm template rulehub-policies "$CHART_DIR" -f "$VALUES_FILE" > /dev/null
  end=$(date +%s%N)
  diff_ns=$((end-start))
  # integer ms
  diff_ms=$((diff_ns/1000000))
  echo "$diff_ms"
}

sum=0
for i in $(seq 1 "$RUNS"); do
  ms=$(measure_one)
  sum=$((sum+ms))
done
avg=$((sum / RUNS))

write_baseline() {
  printf '{"helm_template_ms_avg":%s,"runs":%s,"threshold":%s,"timestamp":"%s"}\n' \
    "$avg" "$RUNS" "$THRESHOLD" "$(date -u +%FT%TZ)" > "$BASELINE_FILE"
}

if [[ ! -f "$BASELINE_FILE" ]]; then
  echo "PERF: baseline file '$BASELINE_FILE' not found -> creating (avg=${avg}ms, runs=${RUNS})"
  write_baseline
  exit 0
fi

baseline_avg=$(jq -r '.helm_template_ms_avg // empty' "$BASELINE_FILE" 2>/dev/null || true)
if [[ -z "$baseline_avg" ]]; then
  echo "PERF: baseline file corrupt or missing field -> rewriting" >&2
  write_baseline
  exit 0
fi

limit=$(( baseline_avg + ( baseline_avg * THRESHOLD / 1 ) )) || true
# Since bash integer math loses decimals, compute using awk for precision
limit_precise=$(awk -v b="$baseline_avg" -v t="$THRESHOLD" 'BEGIN{printf "%.2f", b*(1+t)}')

echo "PERF: baseline=${baseline_avg}ms current=${avg}ms threshold=${THRESHOLD} (limit≈${limit_precise}ms) runs=${RUNS}"

regression=$(awk -v cur="$avg" -v base="$baseline_avg" -v t="$THRESHOLD" 'BEGIN{ if (cur > base*(1+t)) print 1; else print 0 }')

if [[ $UPDATE -eq 1 ]]; then
  write_baseline
  echo "PERF: baseline updated to ${avg}ms"
  exit 0
fi

if [[ "$regression" == "1" ]]; then
  echo "PERF: regression detected (> $THRESHOLD)" >&2
  exit 1
fi

echo "PERF: OK"
