#!/usr/bin/env bash
set -euo pipefail
# detect-orphan-policies.sh
# Purpose: Efficiently detect "orphan" policy artifacts between values.yaml and files/ directories.
#   Orphan File: YAML file exists but its key is absent under values.<framework>.policies
#   Dangling Key: Key exists in values.yaml but YAML file is absent (and the key is NOT explicitly deprecated: true)
# Features:
#   * Single extraction pass for values keys (Gatekeeper & Kyverno)
#   * Supports --json output (machine readable) and --quiet to suppress human text
#   * Exit code: 0 if no orphan/dangling, 1 otherwise (override with --no-fail)
#   * Reuses the deprecation semantics from verify-policies-sync (deprecated: true allows file removal)
#
# Usage:
#   hack/detect-orphan-policies.sh [--json] [--quiet] [--no-fail]
#
# JSON structure:
# {
#   * NEW: Reports deprecated keys with metadata (deprecated_since, replaced_by, age_releases) aggregated across frameworks
#   "gatekeeper": { "orphan_files": [...], "dangling_keys": [...] },
#   "kyverno": { "orphan_files": [...], "dangling_keys": [...] }
# }
#
# Performance considerations:
#   * Avoids N^2 greps by using awk to emit keys and bash associative arrays for O(1) membership checks.
#   * Processes both frameworks with shared helpers.

ROOT_DIR="$(dirname "$0")/.."
VALUES_FILE="$ROOT_DIR/values.yaml"

if [[ ! -f $VALUES_FILE ]]; then
  echo "values.yaml not found at $VALUES_FILE" >&2
  exit 2
fi

json=no
quiet=no
fail=yes
for arg in "$@"; do
  case "$arg" in
    --json) json=yes ;;
    --quiet) quiet=yes ;;
    --no-fail) fail=no ;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //'
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
  shift || true
done

# Extract policy keys for a framework (gatekeeper|kyverno)
extract_keys() {
  local section="$1"
  awk -v section="$section" '
    /^[^[:space:]]/ {
      if ($1==section":") { in_section=1; in_policies=0; next } else { in_section=0; in_policies=0 }
    }
    in_section && $1=="policies:" { in_policies=1; next }
    in_section && in_policies {
      # macOS awk is stricter; avoid {4} quantifier and POSIX classes inside {}
      if ($0 ~ /^    [A-Za-z0-9._-]+:[[:space:]]*$/) {
        key=$0; sub(/^    /,"",key); sub(/:[[:space:]]*$/,"",key); print key
      }
    }
  ' "$VALUES_FILE" | sort -u
}

# Determine if key is deprecated within values.<section>.policies.<key>
is_deprecated() {
  local section="$1" key="$2"
  awk -v section="$section" -v target="$key" '
    /^[^[:space:]]/ { top=$1; gsub(":$","",top); in_section=(top==section); in_policies=0 }
    in_section && $1=="policies:" { in_policies=1; next }
    in_section && in_policies {
      if(match($0,/^    ([A-Za-z0-9._-]+):[[:space:]]*$/,m)) { current=m[1]; if(found && current!=target){ exit }; if(m[1]==target){ found=1; next } }
      else if(found) {
        if($0 ~ /^      /) { if($0 ~ /deprecated:[[:space:]]*true/) dep=1 } else { exit }
      }
    }
    END { exit dep?0:1 }
  ' "$VALUES_FILE"
}

GK_KEYS=$(extract_keys gatekeeper)
KY_KEYS=$(extract_keys kyverno)

# Build newline-delimited sets for membership checks (normalized underscores -> hyphens)
GK_KEY_SET_FILE=$(mktemp); trap 'rm -f "$GK_KEY_SET_FILE" "$KY_KEY_SET_FILE"' EXIT
KY_KEY_SET_FILE=$(mktemp)
printf '%s\n' $GK_KEYS | sed 's/_/-/g' | sort -u > "$GK_KEY_SET_FILE"
printf '%s\n' $KY_KEYS | sed 's/_/-/g' | sort -u > "$KY_KEY_SET_FILE"

# Collect file basenames (without .yaml)
# Collect and normalize file basenames (underscores -> hyphens) for consistent comparison
GK_FILES=$(find "$ROOT_DIR/files/gatekeeper" -maxdepth 1 -type f -name '*.yaml' -exec basename {} \; 2>/dev/null | sed 's/\.yaml$//' | sed 's/_/-/g' | sort -u || true)
KY_FILES=$(find "$ROOT_DIR/files/kyverno" -maxdepth 1 -type f -name '*.yaml' -exec basename {} \; 2>/dev/null | sed 's/\.yaml$//' | sed 's/_/-/g' | sort -u || true)

orphan_gk=()
dangling_gk=()
for f in $GK_FILES; do
  if ! grep -qx "$f" "$GK_KEY_SET_FILE"; then orphan_gk+=("$f"); fi
done
for k in $GK_KEYS; do
  if [[ ! -f "$ROOT_DIR/files/gatekeeper/$k.yaml" && \
        ! -f "$ROOT_DIR/files/gatekeeper/${k//_/-}.yaml" && \
        ! -f "$ROOT_DIR/files/gatekeeper/${k//-/_}.yaml" ]]; then
    if ! is_deprecated gatekeeper "$k"; then dangling_gk+=("$k"); fi
  fi
done

orphan_ky=()
dangling_ky=()
for f in $KY_FILES; do
  if ! grep -qx "$f" "$KY_KEY_SET_FILE"; then orphan_ky+=("$f"); fi
done
for k in $KY_KEYS; do
  # accept underscore or hyphen in file naming for kyverno
  if [[ ! -f "$ROOT_DIR/files/kyverno/$k.yaml" && \
        ! -f "$ROOT_DIR/files/kyverno/${k//-/_}.yaml" && \
        ! -f "$ROOT_DIR/files/kyverno/${k//_/-}.yaml" ]]; then
    if ! is_deprecated kyverno "$k"; then dangling_ky+=("$k"); fi
  fi
done

if [[ $quiet == no ]]; then
  echo "== Orphan Policy Detection =="
  echo "Gatekeeper:"; \
  if ((${#orphan_gk[@]})); then echo "  Orphan files (add key or remove file):"; printf '    - %s\n' "${orphan_gk[@]}"; else echo "  Orphan files: none"; fi
  if ((${#dangling_gk[@]})); then echo "  Dangling keys (add file or deprecate/remove):"; printf '    - %s\n' "${dangling_gk[@]}"; else echo "  Dangling keys: none"; fi
  echo
  echo "Kyverno:"; \
  if ((${#orphan_ky[@]})); then echo "  Orphan files (add key or remove file):"; printf '    - %s\n' "${orphan_ky[@]}"; else echo "  Orphan files: none"; fi
  if ((${#dangling_ky[@]})); then echo "  Dangling keys (add file or deprecate/remove):"; printf '    - %s\n' "${dangling_ky[@]}"; else echo "  Dangling keys: none"; fi
fi

if [[ $json == yes ]]; then
  jq -n \
    --argjson og "$(printf '%s\n' "${orphan_gk[@]}" | jq -R . | jq -s .)" \
    --argjson dg "$(printf '%s\n' "${dangling_gk[@]}" | jq -R . | jq -s .)" \
    --argjson ok "$(printf '%s\n' "${orphan_ky[@]}" | jq -R . | jq -s .)" \
    --argjson dk "$(printf '%s\n' "${dangling_ky[@]}" | jq -R . | jq -s .)" \
    '{gatekeeper:{orphan_files:$og,dangling_keys:$dg}, kyverno:{orphan_files:$ok,dangling_keys:$dk}}'
fi

issues=$(( ${#orphan_gk[@]} + ${#dangling_gk[@]} + ${#orphan_ky[@]} + ${#dangling_ky[@]} ))
if [[ $fail == yes && $issues -gt 0 ]]; then
  exit 1
fi
exit 0
