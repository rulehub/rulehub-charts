#!/usr/bin/env bash
set -euo pipefail
# report-values-vs-files.sh
# Generates a machine & human readable report about drift between values.yaml policy keys
# and existing YAML files under files/gatekeeper and files/kyverno.
# Unlike verify-policies-sync.sh (which exits non-zero), this script always exits 0
# and focuses on structured output for CI annotations or further processing.

ROOT_DIR="$(dirname "$0")/.."
VALUES_FILE="$ROOT_DIR/values.yaml"

if [[ ! -f $VALUES_FILE ]]; then
  echo "values.yaml not found" >&2
  exit 0
fi

# Reuse extraction logic (simplified) to avoid awk duplication complexity from verify script.
extract_keys() {
  local section="$1"
  awk -v section="$section" '
    /^[^[:space:]]/ { # top-level key
      if ($1==section":") { in_section=1; in_policies=0; next } else { in_section=0; in_policies=0 }
    }
    in_section && $1=="policies:" { in_policies=1; next }
    in_section && in_policies && match($0,/^[[:space:]]{4}([a-zA-Z0-9._-]+):[[:space:]]*$/,m) { print m[1] }
  ' "$VALUES_FILE" | sort -u
}

mapfile -t GK_KEYS < <(extract_keys gatekeeper)
mapfile -t KY_KEYS < <(extract_keys kyverno)

mapfile -t GK_FILES < <(find "$ROOT_DIR/files/gatekeeper" -maxdepth 1 -type f -name '*.yaml' -exec basename {} \; 2>/dev/null | sed 's/\.yaml$//' | sort -u || true)
mapfile -t KY_FILES < <(find "$ROOT_DIR/files/kyverno" -maxdepth 1 -type f -name '*.yaml' -exec basename {} \; 2>/dev/null | sed 's/\.yaml$//' | sort -u || true)

# Build associative sets (if bash>=4 which we have) for faster membership.

missing_key_gk=()
missing_file_gk=()

for f in "${GK_FILES[@]}"; do
  if ! printf '%s\n' "${GK_KEYS[@]}" | grep -Fxq -- "$f"; then
    missing_key_gk+=("$f")
  fi
done
for k in "${GK_KEYS[@]}"; do
  if ! printf '%s\n' "${GK_FILES[@]}" | grep -Fxq -- "$k"; then
    missing_file_gk+=("$k")
  fi
done

missing_key_ky=()
missing_file_ky=()
for f in "${KY_FILES[@]}"; do
  if ! printf '%s\n' "${KY_KEYS[@]}" | grep -Fxq -- "$f"; then
    missing_key_ky+=("$f")
  fi
done
for k in "${KY_KEYS[@]}"; do
  if ! printf '%s\n' "${KY_FILES[@]}" | grep -Fxq -- "$k"; then
    missing_file_ky+=("$k")
  fi
done

# Output human readable section
cat <<'HDR'
== Policy Drift Report (values.yaml vs files/) ==
HDR

echo "Gatekeeper:"
if ((${#missing_key_gk[@]})); then
  echo "  Files without key (add to values.yaml):"
  printf '    - %s\n' "${missing_key_gk[@]}"
else
  echo "  Files without key: none"
fi
if ((${#missing_file_gk[@]})); then
  echo "  Keys without file (remove or add file):"
  printf '    - %s\n' "${missing_file_gk[@]}"
else
  echo "  Keys without file: none"
fi

echo

echo "Kyverno:"
if ((${#missing_key_ky[@]})); then
  echo "  Files without key (add to values.yaml):"
  printf '    - %s\n' "${missing_key_ky[@]}"
else
  echo "  Files without key: none"
fi
if ((${#missing_file_ky[@]})); then
  echo "  Keys without file (remove or add file):"
  printf '    - %s\n' "${missing_file_ky[@]}"
else
  echo "  Keys without file: none"
fi

echo
# Structured JSON (single line) for potential machine parsing
jq -n --argjson gkf "$(printf '%s\n' "${missing_key_gk[@]}" | jq -R . | jq -s .)" \
       --argjson gkk "$(printf '%s\n' "${missing_file_gk[@]}" | jq -R . | jq -s .)" \
       --argjson kyf "$(printf '%s\n' "${missing_key_ky[@]}" | jq -R . | jq -s .)" \
       --argjson kyk "$(printf '%s\n' "${missing_file_ky[@]}" | jq -R . | jq -s .)" \
       '{gatekeeper:{files_without_key:$gkf, keys_without_file:$gkk}, kyverno:{files_without_key:$kyf, keys_without_file:$kyk}}'

# Always succeed
exit 0
