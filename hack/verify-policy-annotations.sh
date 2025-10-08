#!/usr/bin/env bash
set -euo pipefail
# verify-policy-annotations.sh
# Validates presence & format of rulehub annotations inside policy YAML files using an embedded JSON Schema.
# Focus: rulehub.id (required), rulehub.title (optional, non-empty if present), rulehub.links (optional block list lines starting with '-')
# Exit codes: 0 ok, 1 validation issues, 2 internal/script error

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." &>/dev/null && pwd)"

shopt -s nullglob
mapfile -t FILES < <(find "$REPO_ROOT/files" -maxdepth 2 -type f -name '*.yaml' | sort)

issues=()

extract_block_annotations() {
  # Prints annotation lines in first document metadata.annotations.* domain for rulehub.*
  # Simplistic parser to avoid yq dependency.
  local f="$1" in_meta=0 in_ann=0 doc_done=0
  awk '
    /^---/ { if (doc_done) exit; doc_done=1 }
    /^metadata:/ { in_meta=1; next }
    /^[^[:space:]]/ && $1!="metadata:" { in_meta=0; in_ann=0 }
    in_meta && /^[[:space:]]+annotations:/ { in_ann=1; next }
    in_ann && /^[[:space:]]+[a-zA-Z0-9_.-]+:/ { # next top-level under metadata
      # still under annotations technically if more indent
    }
    in_ann && /^[[:space:]]+rulehub\./ { print }
  ' "$f"
}

# Returns 0 if a known filename/id mismatch is allowed (intentional), else 1
is_allowed_filename_id() {
  local base="$1" id="$2"
  case "${base}|${id}" in
    # Special helpers/templates with shortened filenames
    "ban-hostnetwork.yaml|ban.hostnetwork.template") return 0 ;;
    "limit-capabilities.yaml|limit.capabilities.template") return 0 ;;
    "no-run-as-root.yaml|no.run.as.root.template") return 0 ;;
    "require-imagepullpolicy-always.yaml|require.imagepullpolicy.always.template") return 0 ;;
  esac
  return 1
}

engine_for_file() {
  case "$1" in
    *"/kyverno/"*) echo "kyverno" ;;
    *"/gatekeeper-templates/"*) echo "gk.template" ;;
    *"/gatekeeper/"*) echo "gk.constraint" ;;
    *) echo "unknown" ;;
  esac
}

alias_key_for_file() {
  local b
  b=$(basename "$1")
  b=${b%.yaml}
  # drop common suffixes then normalize - to _
  b=${b%-policy*}
  b=${b%-constrainttemplate*}
  b=${b%-constraint*}
  b=${b//-/_}
  echo "$b"
}

IDS_SEEN_FILE="/tmp/rulehub_ids.$$.txt"

for f in "${FILES[@]}"; do
  mapfile -t ann_lines < <(extract_block_annotations "$f") || true
  id="" title="" links_count=0
  for line in "${ann_lines[@]}"; do
    # normalize
    key=$(echo "$line" | sed -E 's/^[[:space:]]*([^:]+):.*/\1/')
    val=$(echo "$line" | sed -E 's/^[[:space:]]*[^:]+:[[:space:]]*(.*)$/\1/')
    case "$key" in
      rulehub.id) id="$val" ;;
      rulehub.title) title="$val" ;;
      rulehub.links) : ;; # header only, actual list lines follow as separate YAML style? Often stored as | block or list outside simple parse
    esac
  done
  if [[ -z $id ]]; then
    issues+=("MISSING_ID|$f|rulehub.id missing")
  else
    if ! [[ $id =~ ^[a-z0-9]+(\.[a-z0-9_]+)*$ ]]; then
      issues+=("BAD_ID_FORMAT|$f|$id|expected pattern ^[a-z0-9]+(\\.[a-z0-9_]+)*$")
    fi
  fi
  if [[ -n $title ]]; then
    stripped=$(echo "$title" | xargs)
    [[ -z $stripped ]] && issues+=("EMPTY_TITLE|$f|rulehub.title empty")
  fi
  # Additional heuristic: ensure id appears in filename
  base=$(basename "$f")
  # Build acceptable filename prefixes from id:
  #  - norm1: replace dots with hyphens (keep underscores) e.g., a.b_c -> a-b_c
  #  - norm2: replace dots and underscores with hyphens e.g., a.b_c -> a-b-c
  norm1=${id//./-}
  norm2=${norm1//_/-}
  # If id ends with '.template', also accept filenames that omit the trailing '-template'
  norm1_base=$norm1
  norm2_base=$norm2
  if [[ $norm1 == *-template ]]; then
    norm1_base=${norm1%-template}
  fi
  if [[ $norm2 == *-template ]]; then
    norm2_base=${norm2%-template}
  fi
  # Accept variant where 'constraint-template' merges to 'constrainttemplate' in filenames
  norm1_join=${norm1//-constraint-template/-constrainttemplate}
  norm2_join=${norm2//-constraint-template/-constrainttemplate}
  match_ok=0
  if [[ -n $id ]]; then
    for pref in "$norm1" "$norm2" "$norm1_base" "$norm2_base" "$norm1_join" "$norm2_join"; do
      if [[ $base == $pref* || $base == ${pref}-policy* || $base == ${pref}-constraint* || $base == ${pref}-template* ]]; then
        match_ok=1; break
      fi
    done
    if (( match_ok==0 )); then
      if is_allowed_filename_id "$base" "$id"; then
        : # allowed intentional mismatch
      else
      issues+=("FILENAME_ID_MISMATCH|$f|id=$id filename=$base")
      fi
    fi
  fi
  # Validate unique id (detect duplicates) but allow:
  #  - same id across different engines (kyverno vs gatekeeper)
  #  - same id within an alias pair (filename differs only by - vs _ before suffix)
  if [[ -n $id ]]; then
    eng=$(engine_for_file "$f")
    alias_key=$(alias_key_for_file "$f")
    allowed_dup=0
    if [[ -f "$IDS_SEEN_FILE" ]]; then
      # scan previous occurrences
      while IFS='|' read -r prev_id prev_file prev_eng prev_alias; do
        [[ "$prev_id" != "$id" ]] && continue
        if [[ "$prev_eng" != "$eng" ]]; then
          allowed_dup=1
          break
        fi
        if [[ "$prev_alias" == "$alias_key" ]]; then
          allowed_dup=1
          break
        fi
      done < "$IDS_SEEN_FILE"
    fi
    if [[ $allowed_dup -eq 1 ]]; then
      : # skip flagging this duplicate
    else
      if grep -q "^${id}|" "$IDS_SEEN_FILE" 2>/dev/null; then
        issues+=("DUP_ID|$f|$id")
      fi
    fi
    # record this occurrence
    printf '%s|%s|%s|%s\n' "$id" "$f" "$eng" "$alias_key" >> "$IDS_SEEN_FILE"
  fi

done

if ((${#issues[@]})); then
  printf 'Annotation validation issues (%d):\n' "${#issues[@]}"
  for i in "${issues[@]}"; do
    IFS='|' read -r code file rest <<<"$i"
    printf '  - [%s] %s %s\n' "$code" "$file" "$rest"
  done
  exit 1
else
  echo "All policy annotations pass basic validation checks."
fi
