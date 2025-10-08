#!/usr/bin/env bash
set -euo pipefail

# verify-policies-sync.sh
# Compares policy keys declared in values.yaml with actual YAML files under files/gatekeeper and files/kyverno.
# Exits non‑zero if there is any drift (missing keys or orphan files).
# Enhancement: A missing file for a policy key is tolerated (NOT counted as drift) only if the policy
# key contains an explicit `deprecated: true` marker under that key block in values.yaml. This enables
# a controlled removal workflow:
#   1. Mark key deprecated: true (and optionally keep enabled: false) – file can then be removed.
#   2. In a later release remove the key entirely from values.yaml.
# Without the deprecation marker, removing the file while the key remains will fail this verification.

VALUES_FILE="$(dirname "$0")/../values.yaml"
ROOT_DIR="$(dirname "$0")/.."
TMPDIR=${TMPDIR:-/tmp}

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "values.yaml not found at $VALUES_FILE" >&2
  exit 2
fi

extract_keys() {
  local section="$1" # gatekeeper | kyverno
  awk -v section="$section" '
    /^[^[:space:]]/ {
      if ($1==section":") { in_section=1; in_policies=0; next } else { in_section=0; in_policies=0 }
    }
    in_section && $1=="policies:" { in_policies=1; next }
    in_section && in_policies {
      # four spaces, then key:
      if ($0 ~ /^    [A-Za-z0-9._-]+:[[:space:]]*$/) {
        line=$0
        sub(/^    /, "", line)
        sub(/:.*/, "", line)
        print line
      }
    }
  ' "$VALUES_FILE" | sort -u
}

declare -a GK_VALUE_KEYS KY_VALUE_KEYS
IFS=$'\n' GK_VALUE_KEYS=($(extract_keys gatekeeper || true))
IFS=$'\n' KY_VALUE_KEYS=($(extract_keys kyverno || true))

# Normalized (kebab) variants of values keys
declare -a GK_VALUE_KEYS_NORM KY_VALUE_KEYS_NORM
GK_VALUE_KEYS_NORM=()
for k in ${GK_VALUE_KEYS[@]+"${GK_VALUE_KEYS[@]}"}; do GK_VALUE_KEYS_NORM+=("$(printf '%s' "$k" | tr '_' '-')"); done
KY_VALUE_KEYS_NORM=()
for k in ${KY_VALUE_KEYS[@]+"${KY_VALUE_KEYS[@]}"}; do KY_VALUE_KEYS_NORM+=("$(printf '%s' "$k" | tr '_' '-')"); done

in_array() { # needle, array[@]
  local needle="$1"; shift
  local e
  for e in "$@"; do [[ "$e" == "$needle" ]] && return 0; done
  return 1
}

# Normalization helpers: treat underscores and hyphens as equivalent
to_kebab() { printf '%s' "$1" | tr '_' '-'; }
to_underscore() { printf '%s' "$1" | tr '-' '_'; }

# Collect file basenames (without .yaml)
declare -a GK_FILE_BASENAMES KY_FILE_BASENAMES
IFS=$'\n' GK_FILE_BASENAMES=($(find "$ROOT_DIR/files/gatekeeper" -maxdepth 1 -type f -name '*.yaml' -exec basename {} \; | sed 's/\.yaml$//' | sort -u || true))
IFS=$'\n' KY_FILE_BASENAMES=($(find "$ROOT_DIR/files/kyverno" -maxdepth 1 -type f -name '*.yaml' -exec basename {} \; | sed 's/\.yaml$//' | sort -u || true))

# Normalized (kebab) variants of file basenames
declare -a GK_FILE_BASENAMES_NORM KY_FILE_BASENAMES_NORM
GK_FILE_BASENAMES_NORM=()
for f in ${GK_FILE_BASENAMES[@]+"${GK_FILE_BASENAMES[@]}"}; do GK_FILE_BASENAMES_NORM+=("$(printf '%s' "$f" | tr '_' '-')"); done
KY_FILE_BASENAMES_NORM=()
for f in ${KY_FILE_BASENAMES[@]+"${KY_FILE_BASENAMES[@]}"}; do KY_FILE_BASENAMES_NORM+=("$(printf '%s' "$f" | tr '_' '-')"); done

declare -a missing_in_values_gk raw_missing_files_gk
missing_in_values_gk=()
raw_missing_files_gk=()

for i in "${!GK_FILE_BASENAMES[@]}"; do
  f="${GK_FILE_BASENAMES[$i]}"; fk="${GK_FILE_BASENAMES_NORM[$i]}"
  in_array "$fk" "${GK_VALUE_KEYS_NORM[@]}" || missing_in_values_gk+=("$f")
done
for i in "${!GK_VALUE_KEYS[@]}"; do
  k="${GK_VALUE_KEYS[$i]}"; kk="${GK_VALUE_KEYS_NORM[$i]}"
  if in_array "$kk" "${GK_FILE_BASENAMES_NORM[@]}"; then :
  else raw_missing_files_gk+=("$k"); fi
done

declare -a missing_in_values_ky raw_missing_files_ky
missing_in_values_ky=()
raw_missing_files_ky=()
for i in "${!KY_FILE_BASENAMES[@]}"; do
  f="${KY_FILE_BASENAMES[$i]}"; fk="${KY_FILE_BASENAMES_NORM[$i]}"
  in_array "$fk" "${KY_VALUE_KEYS_NORM[@]}" || missing_in_values_ky+=("$f")
done
for i in "${!KY_VALUE_KEYS[@]}"; do
  k="${KY_VALUE_KEYS[$i]}"; kk="${KY_VALUE_KEYS_NORM[$i]}"
  if in_array "$kk" "${KY_FILE_BASENAMES_NORM[@]}"; then :
  else raw_missing_files_ky+=("$k"); fi
done

# Determine if a key is explicitly deprecated in values.yaml (section: gatekeeper|kyverno)
is_deprecated() {
  local section="$1" key="$2"; shift 2 || true
  # awk state machine: enter section->policies, find key line, then scan its indented block for deprecated: true
  awk -v section="$section" -v target="$key" '
    /^[^[:space:]]/ { # new top-level key
      top=$1; gsub(":$","",top)
      in_section=(top==section);
      in_policies=0;
    }
    in_section && $1=="policies:" { in_policies=1; next }
    in_section && in_policies {
      # key line (4 spaces then name:)
      if(match($0,/^    ([A-Za-z0-9._-]+):[[:space:]]*$/,m)) {
        current=m[1]; if(found && current!=target){ exit };
        if(m[1]==target){ found=1; next }
      } else if(found) {
        # still inside block if indented >=6 spaces
        if($0 ~ /^      /) {
          if($0 ~ /deprecated:[[:space:]]*true/) { dep=1 }
        } else { exit }
      }
    }
    END { if(dep==1) exit 0; else exit 1 }
  ' "$VALUES_FILE"
}

declare -a missing_files_gk
missing_files_gk=()
for k in ${raw_missing_files_gk[@]+"${raw_missing_files_gk[@]}"}; do
  if ! is_deprecated gatekeeper "$k"; then
    missing_files_gk+=("$k")
  fi
done

declare -a missing_files_ky
missing_files_ky=()
for k in ${raw_missing_files_ky[@]+"${raw_missing_files_ky[@]}"}; do
  if ! is_deprecated kyverno "$k"; then
    missing_files_ky+=("$k")
  fi
done

print_section() {
  local title="$1"; shift
  eval "local count=\"\${#$1[@]}\""
  if [ "$count" -gt 0 ]; then
    printf '%s (%s):\n' "$title" "$count"
    eval "printf '  - %s\\n' \"\${$1[@]}\""
  else
    printf '%s: none\n' "$title"
  fi
}

echo "== Gatekeeper =="
print_section "Missing in values.yaml (file exists, key absent)" missing_in_values_gk
print_section "Missing file for keys (key present, file absent, not deprecated)" missing_files_gk
echo
echo "== Kyverno =="
print_section "Missing in values.yaml (file exists, key absent)" missing_in_values_ky
print_section "Missing file for keys (key present, file absent, not deprecated)" missing_files_ky

issues=$(( ${#missing_in_values_gk[@]} + ${#missing_files_gk[@]} + ${#missing_in_values_ky[@]} + ${#missing_files_ky[@]} ))

# Detect underscore/kebab duplicates (within each framework separately)
dup_report() {
  local -a keys=("$@") norm seen_kebab
  local -a dups=()
  for k in "${keys[@]}"; do
    norm=${k//_/ -}
    norm=${norm// /} # shouldn't happen
    kebab=${k//_/ -}; kebab=${kebab// /}
    # unify multiple hyphens
    kebab=$(echo "$kebab" | tr '_' '-' )
    base=${kebab}
    # no-op placeholder; previously wrote to TMPDIR for debugging, which caused failures when TMPDIR was unset
  done
  # Build duplicates by comparing transformed forms
  # Simpler approach: for each key with underscore, check hyphen variant exists exactly in list
  for k in "${keys[@]}"; do
    if printf '%s' "$k" | grep -q '_'; then
      hy=$(printf '%s' "$k" | tr '_' '-')
      if printf '%s\n' "${keys[@]}" | grep -qx "$hy"; then
        pair="$hy <-> $k"
        if ! printf '%s\n' "${dups[@]}" | grep -qx "$pair"; then
          dups+=("$pair")
        fi
      fi
    fi
  done
  if ((${#dups[@]})); then
    printf '\nPotential underscore/kebab duplicates (%d):\n' "${#dups[@]}"
    printf '  - %s\n' "${dups[@]}"
  fi
}

dup_report "${GK_VALUE_KEYS[@]}" > /tmp/rulehub_dup_gk_$$ 2>/dev/null || true
dup_report "${KY_VALUE_KEYS[@]}" > /tmp/rulehub_dup_ky_$$ 2>/dev/null || true

if (( issues > 0 )); then
  cat /tmp/rulehub_dup_gk_$$ 2>/dev/null || true
  cat /tmp/rulehub_dup_ky_$$ 2>/dev/null || true
  echo
  echo "Drift detected: $issues issue(s)." >&2
  exit 1
else
  cat /tmp/rulehub_dup_gk_$$ 2>/dev/null || true
  cat /tmp/rulehub_dup_ky_$$ 2>/dev/null || true
  echo
  echo "Policy keys are in sync." >&2
fi
