#!/usr/bin/env bash
set -euo pipefail

# verify-id-name-alignment.sh
#
# Purpose:
#  Walk through YAML policy files under files/{kyverno,gatekeeper,gatekeeper-templates}
#  and verify that each resource with annotation `rulehub.id: some.dotted.id` has a
#  metadata.name whose kebab-case form matches the dotted id (dots -> hyphens), allowing
#  for common framework suffixes:
#    - <kebab>
#    - <kebab>-policy        (Kyverno ClusterPolicy convention)
#    - <kebab>-constraint    (Gatekeeper Constraint convention)
#    - <kebab>-template      (Gatekeeper ConstraintTemplate convention)
#
# Output:
#  Human-readable report to stdout; exits non-zero if mismatches are found.
#
# Heuristics / Notes:
#  - Multi-document YAML: only the first document's metadata is validated (typical for these policies).
#  - If rulehub.id annotation is missing -> skipped (other scripts validate presence).
#  - Name extraction is YAML-format tolerant but simplistic (awk state machine) to avoid yq dependency.
#  - A warning (not error) is emitted if file basename (minus .yaml) does not start with the kebab id, since
#    naming drift might be intentional; does not affect exit code.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"

shopt -s nullglob

FILES=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  FILES+=("$f")
done < <(find "$REPO_ROOT/files" -maxdepth 2 -type f -name '*.yaml' | sort)

errors=()
warnings=()

extract_rulehub_id() {
  # Grep first occurrence of rulehub.id: <value>
  local f="$1"
  local line
  line=$(grep -E '^[[:space:]]*rulehub.id:' "$f" | head -1 || true)
  [[ -z $line ]] && return 1
  echo "${line#*:}" | awk '{gsub(/^[[:space:]]+|[[:space:]]+$/,"",$0); print}'
}

extract_metadata_kind() {
  local f="$1"
  awk 'NR<50 && /^kind:/ { print $2; exit }' "$f"
}

extract_metadata_name() {
  local f="$1"
  awk '
    /^---/ { if (doc>0) exit; doc++ } # stop after first document
    /^[^[:space:]]/ { top=$1 }
    /^metadata:/ { in_meta=1; next }
    /^[^[:space:]]/ && $1!="metadata:" { in_meta=0 }
    in_meta && /^[[:space:]]+name:/ {
      name=$0; sub(/^[[:space:]]+name:[[:space:]]*/,"",name); gsub(/"/,"",name); print name; exit
    }
  ' "$f"
}

printf '[verify-id-name-alignment] Files scanned: %d\n' "${#FILES[@]}" >&2

# Normalize separators: treat sequences of '_' or '-' as '-'
normalize_sep() {
  echo "$1" | sed -E 's/[._]+/-/g; s/-+/-/g'
}

for f in "${FILES[@]}"; do
  id=$(extract_rulehub_id "$f" || true)
  [[ -z $id ]] && continue
  kind=$(extract_metadata_kind "$f" || true)
  # Skip ConstraintTemplate (template kind names are not expected to match dotted id)
  if [[ "$kind" == "ConstraintTemplate" ]]; then
    continue
  fi
  name=$(extract_metadata_name "$f" || true)
  [[ -z $name ]] && { errors+=("NO_NAME|$f|$id|(none)"); continue; }
  # Expected base from id: dots/underscores -> '-'
  kebab=$(normalize_sep "$id")
  base_ok=0
  name_n=$(normalize_sep "$name")
  # Variants fully qualified
  variants=("$kebab" "$kebab-policy" "$kebab-constraint" "$kebab-template")
  # Accept suffix-only match to allow different domain prefixes (e.g., betting- vs igaming-)
  id_suffix=$(echo "$kebab" | sed -E 's/^[^-]+-//')
  variants+=("$id_suffix" "$id_suffix-policy" "$id_suffix-constraint" "$id_suffix-template")
  # Explicit alias exceptions for historical names
  case "$id" in
    no.run.as.root)
      variants+=("require-nonroot")
      ;;
    require.imagepullpolicy.always)
      variants+=("require-imagepull-always")
      ;;
  esac
  for variant in "${variants[@]}"; do
    v_n=$(normalize_sep "$variant")
    if [[ "$name_n" == "$v_n" || "$name_n" == *"-$v_n" ]]; then
      base_ok=1; break
    fi
  done
  if [[ $base_ok -eq 0 ]]; then
    errors+=("MISMATCH|$f|$id|$name|expected ~ $kebab[-policy|-constraint|-template]")
  fi
  file_base=$(basename "$f" .yaml)
  if [[ "$(normalize_sep "$file_base")" != $(normalize_sep "$kebab")* ]]; then
    warnings+=("BASENAME_DRIFT|$f|$id|$file_base|expected prefix $kebab")
  fi
done

if ((${#warnings[@]})); then
  echo 'Warnings:'
  for w in "${warnings[@]}"; do
    IFS='|' read -r code file id base msg <<<"$w"
    printf '  - [%s] %s id=%s file-base=%s %s\n' "$code" "$file" "$id" "$base" "$msg"
  done
  echo
fi

if ((${#errors[@]})); then
  echo 'Errors:'
  for e in "${errors[@]}"; do
    IFS='|' read -r code file id name msg <<<"$e"
    printf '  - [%s] %s id=%s name=%s %s\n' "$code" "$file" "$id" "$name" "$msg"
  done
  echo
  printf 'Total mismatches: %d\n' "${#errors[@]}" >&2
  exit 1
else
  echo 'All rulehub.id annotations align with metadata.name variants.'
fi
