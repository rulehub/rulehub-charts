#!/usr/bin/env bash
set -euo pipefail
# generate-changelog.sh
# Generate or prepend a structured CHANGELOG.md section based on manifest diff + integrity hash.
# Usage: hack/generate-changelog.sh --version 0.1.0 --old-manifest prev/manifest.json --new-manifest manifest.json [--output CHANGELOG.md]
# Sections: Added / Changed / Deprecated / Removed / Security / Integrity

VERSION=""
OLD_MANIFEST=""
NEW_MANIFEST=""
OUT_FILE="CHANGELOG.md"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="$2"; shift 2;;
    --old-manifest) OLD_MANIFEST="$2"; shift 2;;
    --new-manifest) NEW_MANIFEST="$2"; shift 2;;
    --output) OUT_FILE="$2"; shift 2;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //' ; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

[[ -z "$VERSION" ]] && echo "--version required" >&2 && exit 2
[[ -z "$OLD_MANIFEST" || -z "$NEW_MANIFEST" ]] && echo "--old-manifest and --new-manifest required" >&2 && exit 2
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 2; }
[[ -f "$OLD_MANIFEST" && -f "$NEW_MANIFEST" ]] || { echo "Manifest file missing" >&2; exit 2; }

old_tmp=$(mktemp); new_tmp=$(mktemp)
jq -r '.[].file' "$OLD_MANIFEST" | sort > "$old_tmp"
jq -r '.[].file' "$NEW_MANIFEST" | sort > "$new_tmp"
added=$(comm -13 "$old_tmp" "$new_tmp" || true)
removed=$(comm -23 "$old_tmp" "$new_tmp" || true)
modified_list=""
while read -r f; do
  [[ -z "$f" ]] && continue
  oh=$(jq -r ".[] | select(.file==\"$f\") | .sha256" "$OLD_MANIFEST")
  nh=$(jq -r ".[] | select(.file==\"$f\") | .sha256" "$NEW_MANIFEST")
  [[ -n "$oh" && -n "$nh" && "$oh" != "$nh" ]] && modified_list+="$f\n"
done < <(comm -12 "$old_tmp" "$new_tmp")

integrity=$(bash "$(dirname "$0")/aggregate-integrity.sh" | awk '{print $2}')
release_date=$(date -u +%Y-%m-%d)
section=$(mktemp)
{
  echo "## v$VERSION - $release_date"; echo
  echo "### Added"; if [[ -n "$added" ]]; then printf '%s\n' "$added" | sed 's/^/- /'; else echo '- (none)'; fi; echo
  echo "### Changed"; if [[ -n "$modified_list" ]]; then printf '%b' "$modified_list" | sed 's/^/- /'; else echo '- (none)'; fi; echo
  echo "### Deprecated"; echo '- (none yet)'; echo
  echo "### Removed"; if [[ -n "$removed" ]]; then printf '%s\n' "$removed" | sed 's/^/- /'; else echo '- (none)'; fi; echo
  echo "### Security"; echo '- (no security advisories noted)'; echo
  echo "### Integrity"; echo "- Aggregate SHA256: $integrity"; echo
} > "$section"

if [[ -f "$OUT_FILE" ]]; then
  cat "$OUT_FILE" >> "$section"
fi
mv "$section" "$OUT_FILE"
echo "CHANGELOG updated ($OUT_FILE)"
