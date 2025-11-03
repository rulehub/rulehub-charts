#!/usr/bin/env bash
set -euo pipefail
# semver-analyze.sh
# Heuristically suggest next SemVer based on manifest diff (policies added/removed/modified).
# Usage: hack/semver-analyze.sh --old-manifest prev/manifest.json --new-manifest manifest.json [--format json]
# Rules (initial simple pass):
#   - Removed policy => major
#   - Added policy (and no removals) => minor
#   - Only modified hashes => patch
# Output: human readable by default or JSON with --format json.

OLD_MANIFEST=""
NEW_MANIFEST=""
FORMAT="text"

usage(){ grep '^# ' "$0" | sed 's/^# //'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --old-manifest) OLD_MANIFEST="$2"; shift 2;;
    --new-manifest) NEW_MANIFEST="$2"; shift 2;;
    --format) FORMAT="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

for f in "$OLD_MANIFEST" "$NEW_MANIFEST"; do
  if [[ ! -f "$f" ]]; then echo "File not found: $f" >&2; exit 2; fi
done

if ! command -v jq >/dev/null 2>&1; then echo "jq required" >&2; exit 2; fi

tmp_old=$(mktemp); tmp_new=$(mktemp); trap 'rm -f "$tmp_old" "$tmp_new"' EXIT

jq -r '.[] | .file' "$OLD_MANIFEST" | sort > "$tmp_old"
jq -r '.[] | .file' "$NEW_MANIFEST" | sort > "$tmp_new"

mapfile -t added < <(comm -13 "$tmp_old" "$tmp_new")
mapfile -t removed < <(comm -23 "$tmp_old" "$tmp_new")

# Modified detection: intersection where sha changed
declare -A OLD_HASH NEW_HASH
while IFS=$'\t' read -r file hash; do OLD_HASH[$file]="$hash"; done < <(jq -r '.[] | [.file,.sha256]|@tsv' "$OLD_MANIFEST")
while IFS=$'\t' read -r file hash; do NEW_HASH[$file]="$hash"; done < <(jq -r '.[] | [.file,.sha256]|@tsv' "$NEW_MANIFEST")
modified=()
for f in "${!OLD_HASH[@]}"; do
  if [[ -n "${NEW_HASH[$f]:-}" && "${OLD_HASH[$f]}" != "${NEW_HASH[$f]}" ]]; then
    modified+=("$f")
  fi
done

suggest="patch"
if ((${#removed[@]} > 0)); then
  suggest="major"
elif ((${#added[@]} > 0)); then
  suggest="minor"
fi

if [[ "$FORMAT" == "json" ]]; then
  jq -n --argjson added "$(printf '%s\n' "${added[@]}" | jq -R . | jq -s .)" \
        --argjson removed "$(printf '%s\n' "${removed[@]}" | jq -R . | jq -s .)" \
        --argjson modified "$(printf '%s\n' "${modified[@]}" | jq -R . | jq -s .)" \
        --arg suggest "$suggest" \
        '{added:$added,removed:$removed,modified:$modified,suggest:$suggest}'
else
  echo "== SemVer Diff Analysis =="
  echo "Added: ${#added[@]}"; for a in "${added[@]}"; do echo "  - $a"; done
  echo "Removed: ${#removed[@]}"; for r in "${removed[@]}"; do echo "  - $r"; done
  echo "Modified: ${#modified[@]}"; for m in "${modified[@]}"; do echo "  - $m"; done
  echo
  echo "Suggested next bump: $suggest"
  echo "(Rules: removed->major, added->minor, else patch)"
fi
