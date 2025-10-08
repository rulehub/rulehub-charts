#!/usr/bin/env bash
set -euo pipefail

# compare-manifest.sh
# Compare two manifest.json files (format: [{"file":"...","sha256":"...","rulehub.id":"..."}, ...])
# and output classification: Added / Removed / Modified / Unchanged.
#
# Usage:
#   bash hack/compare-manifest.sh --old path/to/old/manifest.json --new path/to/new/manifest.json [--fail-on-diff]
# Environment variables OLD/NEW may be used to set paths (if args are omitted).
#
# Exit codes:
#   0 - success; no differences or differences present but --fail-on-diff not requested
#   1 - differences found and --fail-on-diff specified
#   2 - argument error / missing files
#
# Notes:
#  - The .file field may be relative (for example a basename). Comparison is a string match on the .file value.
#  - A future --normalize-kyverno option could normalize files with no '/' to kyverno/<file> for compatibility; not implemented now.

OLD_MANIFEST="${OLD:-}"
NEW_MANIFEST="${NEW:-}"
FAIL_ON_DIFF=0

usage() { grep '^# ' "$0" | sed 's/^# \{0,1\}//'; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --old) OLD_MANIFEST="$2"; shift 2;;
      --new) NEW_MANIFEST="$2"; shift 2;;
      --fail-on-diff) FAIL_ON_DIFF=1; shift;;
      -h|--help) usage; exit 0;;
      *) echo "Unknown arg: $1" >&2; exit 2;;
    esac
  done
}

require_file() {
  local f="$1"; local label="$2"
  if [[ -z "$f" ]]; then
    echo "Path for $label manifest not provided" >&2; exit 2
  fi
  if [[ ! -f "$f" ]]; then
    echo "File not found: $f ($label)" >&2; exit 2
  fi
}

temp_files=()
cleanup() { for t in "${temp_files[@]}"; do [[ -f $t ]] && rm -f "$t" || true; done; }
trap cleanup EXIT

emit_pairs() {
  local m="$1"; local out="$2"
  # Format: file|sha256
  if command -v jq >/dev/null 2>&1; then
    jq -r '.[] | (.file + "|" + .sha256)' "$m" | sort > "$out"
  else
  # Simple fallback (lenient): extract file/sha256 lines in order
    local files hashes
    files=$(mktemp); hashes=$(mktemp); temp_files+=("$files" "$hashes")
    grep '"file"' "$m" | sed 's/[",]//g' | awk '{print $2}' > "$files"
    grep '"sha256"' "$m" | sed 's/[",]//g' | awk '{print $2}' > "$hashes"
    paste -d'|' "$files" "$hashes" | sort > "$out"
  fi
}

generate_maps() {
  local in_file="$1"; declare -n map_ref=$2
  while IFS='|' read -r file hash; do
    [[ -n "$file" ]] || continue
    map_ref["$file"]="$hash"
  done < "$in_file"
}

report_diff() {
  declare -gA OLD_MAP NEW_MAP
  local old_list new_list
  old_list=$(mktemp); new_list=$(mktemp); temp_files+=("$old_list" "$new_list")
  emit_pairs "$OLD_MANIFEST" "$old_list"
  emit_pairs "$NEW_MANIFEST" "$new_list"
  generate_maps "$old_list" OLD_MAP
  generate_maps "$new_list" NEW_MAP

  local -a added removed modified unchanged

  # Added / Modified / Unchanged
  while IFS='|' read -r file hash; do
    if [[ -z "${OLD_MAP[$file]:-}" ]]; then
      added+=("$file")
    else
      if [[ "${OLD_MAP[$file]}" == "$hash" ]]; then
        unchanged+=("$file")
      else
        modified+=("$file")
      fi
    fi
  done < "$new_list"

  # Removed
  while IFS='|' read -r file _hash; do
    [[ -n "${NEW_MAP[$file]:-}" ]] || removed+=("$file")
  done < "$old_list"

  echo '== Manifest Diff Report =='
  if ((${#added[@]})); then
    echo "Added: ${#added[@]}"; printf '  - %s\n' "${added[@]}"
  else echo 'Added: none'; fi
  if ((${#removed[@]})); then
    echo "Removed: ${#removed[@]}"; printf '  - %s\n' "${removed[@]}"
  else echo 'Removed: none'; fi
  if ((${#modified[@]})); then
    echo "Modified: ${#modified[@]}"; printf '  - %s\n' "${modified[@]}"
  else echo 'Modified: none'; fi
  echo "Unchanged: ${#unchanged[@]}"

  local total=$(( ${#added[@]} + ${#removed[@]} + ${#modified[@]} ))
  if (( total > 0 )); then
    echo
    echo "Diff detected: $total file(s) changed." >&2
    if (( FAIL_ON_DIFF == 1 )); then
      return 1
    fi
  else
    echo
    echo 'No differences (manifests identical by file+sha256).' >&2
  fi
}

main() {
  parse_args "$@"
  require_file "$OLD_MANIFEST" OLD
  require_file "$NEW_MANIFEST" NEW
  report_diff || exit 1
}

main "$@"
