#!/usr/bin/env bash
set -euo pipefail

# verify-integrity.sh
# Verify integrity of policy YAML files against manifest.json.
# manifest.json format (see generate-policies.sh): [{"file":"<name>","sha256":"<hash>","rulehub.id":"..."}, ...]
#
# Steps:
#  1. Collect actual files: files/kyverno/*.yaml, files/gatekeeper/*.yaml, files/gatekeeper-templates/*.yaml
#  2. Compute sha256 for each file (whole file) -> actual map
#  3. Load manifest.json (if present) -> expected map
#  4. Compare:
#       - Files present in actual but missing from manifest (Added)
#       - Files listed in manifest but missing from the directory (Removed)
#       - Hash mismatch (Modified)
#  5. Print a report; exit 1 on any drift
#
# Options:
#   --manifest <path> (default ./manifest.json)
#   --strict-missing (if manifest is missing -> exit 2 instead of a graceful warning)
#
# Usage:
#   bash hack/verify-integrity.sh
#   make integrity-verify

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR="${SCRIPT_DIR%/hack}"
MANIFEST_PATH="$ROOT_DIR/manifest.json"
STRICT_MISSING=0

usage() { grep '^# ' "$0" | sed 's/^# \{0,1\}//'; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --manifest) MANIFEST_PATH="$2"; shift 2;;
      --strict-missing) STRICT_MISSING=1; shift;;
      -h|--help) usage; exit 0;;
      *) echo "Unknown arg: $1" >&2; exit 2;;
    esac
  done
}

sha_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    # macOS fallback
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

collect_files() {
  find "$ROOT_DIR/files" \( -path '*/kyverno/*.yaml' -o -path '*/gatekeeper/*.yaml' -o -path '*/gatekeeper-templates/*.yaml' \) -type f -print | sort
}

# Temp files for portable set operations
TMP_ACTUAL=$(mktemp)
TMP_EXPECTED=$(mktemp)
trap 'rm -f "$TMP_ACTUAL" "$TMP_EXPECTED"' EXIT

load_actual() {
  : > "$TMP_ACTUAL"
  while IFS= read -r f; do
    base="${f#$ROOT_DIR/files/}"
    printf '%s|%s\n' "$base" "$(sha_file "$f")" >> "$TMP_ACTUAL"
  done < <(collect_files)
  sort -t '|' -k1,1 "$TMP_ACTUAL" -o "$TMP_ACTUAL"
}

load_manifest() {
  # manifest may contain only kyverno files; including other types is allowed
  # Support shortened path: file may be a basename for kyverno; normalize to kyverno/<file>
  if [[ ! -f "$MANIFEST_PATH" ]]; then
    if [[ $STRICT_MISSING -eq 1 ]]; then
      echo "manifest.json not found at $MANIFEST_PATH" >&2
      exit 2
    else
  echo "[verify-integrity] manifest.json not found ($MANIFEST_PATH) - skipping comparison, only printing current hashes." >&2
      return 1
    fi
  fi
  # Use jq if available, otherwise use a simple awk-like parsing fallback
  : > "$TMP_EXPECTED"
  if command -v jq >/dev/null 2>&1; then
    jq -r '.[] | (.file + "|" + .sha256)' "$MANIFEST_PATH" |
    awk -v root="$ROOT_DIR" -F'|' '{
      file=$1; hash=$2;
      if (index(file,"/") == 0) { if (system("test -f " root "/files/kyverno/" file) == 0) file="kyverno/" file }
      print file "|" hash
    }' |
    sort -t '|' -k1,1 > "$TMP_EXPECTED"
  else
    # crude JSON parsing fallback
    paste -d'|' \
      <(grep '"file"' "$MANIFEST_PATH" | sed 's/[",]//g' | awk '{print $2}') \
      <(grep '"sha256"' "$MANIFEST_PATH" | sed 's/[",]//g' | awk '{print $2}') |
    awk -v root="$ROOT_DIR" -F'|' '{
      file=$1; hash=$2;
      if (index(file,"/") == 0) { if (system("test -f " root "/files/kyverno/" file) == 0) file="kyverno/" file }
      print file "|" hash
    }' |
    sort -t '|' -k1,1 > "$TMP_EXPECTED"
  fi
}

report() {
  echo '== Integrity Report =='

  # File name lists
  cut -d'|' -f1 "$TMP_ACTUAL" | sort > "$TMP_ACTUAL.files"
  cut -d'|' -f1 "$TMP_EXPECTED" | sort > "$TMP_EXPECTED.files"

  # Added and removed
  ADDED=$(comm -23 "$TMP_ACTUAL.files" "$TMP_EXPECTED.files") || true
  REMOVED=$(comm -13 "$TMP_ACTUAL.files" "$TMP_EXPECTED.files") || true

  if [ -n "$ADDED" ]; then
    echo "Added (not in manifest): $(printf '%s\n' "$ADDED" | grep -c .)"
    printf '  - %s\n' $ADDED
  else
    echo 'Added: none'
  fi

  if [ -n "$REMOVED" ]; then
    echo "Removed (only in manifest): $(printf '%s\n' "$REMOVED" | grep -c .)"
    printf '  - %s\n' $REMOVED
  else
    echo 'Removed: none'
  fi

  # Modified
  MODIFIED=$(join -t '|' -j 1 "$TMP_EXPECTED" "$TMP_ACTUAL" | awk -F'|' '$2!=$3 {print $1}') || true
  if [ -n "$MODIFIED" ]; then
    echo "Modified (hash mismatch): $(printf '%s\n' "$MODIFIED" | grep -c .)"
    printf '  - %s\n' $MODIFIED
  else
    echo 'Modified: none'
  fi

  total=$(( $(printf '%s\n' "$ADDED" | grep -c . || true) + $(printf '%s\n' "$REMOVED" | grep -c . || true) + $(printf '%s\n' "$MODIFIED" | grep -c . || true) ))
  if [ "$total" -gt 0 ]; then
    echo
    echo "Drift detected: $total issue(s)." >&2
    echo "To update manifest.json, regenerate it (see generate-policies.sh --manifest)." >&2
    return 1
  else
    echo
    echo 'Integrity OK (no drift).' >&2
  fi
}

main() {
  parse_args "$@"
  load_actual
  if load_manifest; then
    report || exit 1
  else
    # No manifest - just print current hashes
    echo '== Current Hashes (manifest missing) =='
    for f in $(printf '%s\n' "${!ACTUAL_HASH[@]}" | sort); do
      printf '%s %s\n' "${ACTUAL_HASH[$f]}" "$f"
    done
    exit 0
  fi
}

main "$@"
