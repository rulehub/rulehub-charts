#!/usr/bin/env bash
# verify-size.sh
# Compute total rendered manifest size (bytes) and fail if above threshold (default 256000 ~= 250KB)
# Also reports source policy YAML aggregate size for context.
# Usage: hack/verify-size.sh [--threshold BYTES] [--values values.yaml]
set -euo pipefail

threshold=${THRESHOLD:-256000}
values_file=""
args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --threshold) threshold="$2"; shift 2 ;;
    --values) values_file="$2"; shift 2 ;;
    *) args+=("$1"); shift ;;
  esac
done
# Reset positional args only if any were collected (avoid unbound under set -u)
if (( ${#args[@]:-0} > 0 )); then
  set -- "${args[@]}"
else
  set --
fi

chart_dir="$(cd "$(dirname "$0")/.." && pwd)"
values_arg=()
if [[ -n "$values_file" ]]; then
  values_arg=(-f "$values_file")
elif [[ -f "$chart_dir/values.yaml" ]]; then
  values_arg=(-f "$chart_dir/values.yaml")
fi

tmp_render="$(mktemp)"; trap 'rm -f "$tmp_render"' EXIT
helm template rulehub-policies "$chart_dir" ${values_arg[@]:-} > "$tmp_render"
if grep -qE '^Error:' "$tmp_render"; then
  echo "Helm template produced error lines:" >&2
  grep -E '^Error:' "$tmp_render" >&2 || true
  exit 1
fi

render_size=$(wc -c < "$tmp_render" | tr -d ' ')  # bytes

# Source policy YAML sizes (only files/ directory)
src_size=$( (find "$chart_dir/files" -type f -name '*.yaml' -print0 2>/dev/null || true) | xargs -0 cat 2>/dev/null | wc -c | tr -d ' ' ) || src_size=0

printf 'Rendered manifest size (bytes): %s\n' "$render_size"
printf 'Source policy YAML size (bytes): %s\n' "$src_size"
printf 'Threshold (bytes): %s\n' "$threshold"

if (( render_size > threshold )); then
  echo "FAIL: Rendered size exceeds threshold (${render_size} > ${threshold})" >&2
  exit 1
fi

echo "Size OK (${render_size} <= ${threshold})"
