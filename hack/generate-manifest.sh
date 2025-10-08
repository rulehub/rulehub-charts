#!/usr/bin/env bash
set -euo pipefail

# generate-manifest.sh
# Purpose: Produce manifest.json (policy inventory + per-file sha256) in a
# deterministic, schema‑compatible format and print an aggregate integrity hash.
#
# Output file: ./manifest.json
# Format (matches manifest.schema.json):
#   [ {"file":"<basename or subpath>","sha256":"<hex64>","rulehub.id":"...",
#       "kind":"ClusterPolicy|Constraint|ConstraintTemplate|...",
#       "framework":"kyverno|gatekeeper|gatekeeper-template"}, ... ]
# Sorting: ascending by .file (lexicographic, POSIX locale)
#
# Conventions:
#   * Kyverno entries use only the basename of the YAML (legacy convention used
#     by verify-integrity.sh). Gatekeeper / templates use a prefixed path:
#       gatekeeper/<file>, gatekeeper-templates/<file>
#   * rulehub.id extracted from first matching annotation line 'rulehub.id:'
#   * kind extracted from first 'kind:' line (top-level)
#   * Missing rulehub.id -> entry is skipped with a warning (hard fail with --strict)
#
# Aggregate integrity hash:
#   sha256( concat( all per-file sha256 values in sorted order, *without* separators ) )
#   Printed as: aggregateIntegritySha256 <hash> <fileCount>
#   (Can be exported to a ConfigMap or release notes.)
#
# Options:
#   --strict    Fail if any YAML lacks rulehub.id annotation.
#   --out <f>   Path to write manifest (default: manifest.json)
#   --print     Echo manifest to stdout as well.
#   --help      Show this help.
#
# Example (2 files) manifest.json snippet:
# [
#   {"file":"betting-affordability_checks_uk-policy.yaml","sha256":"<64hex>","rulehub.id":"betting.affordability_checks_uk","kind":"ClusterPolicy","framework":"kyverno"},
#   {"file":"gatekeeper/betting-self_exclusion_uk_gamstop-constraint.yaml","sha256":"<64hex>","rulehub.id":"betting.self_exclusion_uk_gamstop","kind":"Constraint","framework":"gatekeeper"}
# ]
#
# CI usage (GitHub Actions step idea):
#   - name: Generate manifest & verify integrity
#     run: |
#       bash hack/generate-manifest.sh --strict
#       make integrity-verify
#       make aggregate-integrity
#       bash hack/verify-manifest-schema.sh

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="${SCRIPT_DIR%/hack}"
OUT_FILE="$REPO_ROOT/manifest.json"
STRICT=0
PRINT=0

usage() { grep '^# ' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) STRICT=1; shift;;
    --out) OUT_FILE="$2"; shift 2;;
    --print) PRINT=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

collect_files() {
  find "$REPO_ROOT/files" \
    \( -path '*/kyverno/*.yaml' -o -path '*/gatekeeper/*.yaml' -o -path '*/gatekeeper-templates/*.yaml' \) \
    -type f -print | sort
}

framework_for() {
  case "$1" in
    */kyverno/*) echo kyverno;;
    */gatekeeper-templates/*) echo gatekeeper-template;;
    */gatekeeper/*) echo gatekeeper;;
    *) echo unknown;;
  esac
}

file_field_for() {
  local path rel
  path="$1"
  rel="${path#$REPO_ROOT/files/}" # e.g. kyverno/x.yaml
  case "$rel" in
    kyverno/*) basename "$rel";;
    *) echo "$rel";;
  esac
}

hash_file() { sha256sum "$1" | awk '{print $1}'; }

warn() { echo "[generate-manifest] WARN: $*" >&2; }
fail() { echo "[generate-manifest] ERROR: $*" >&2; exit 1; }

# Portable resolver (bash 3.x compatible): extract Constraint kind from matching ConstraintTemplate file by stem
template_kind_for_stem() {
  local stem="$1" tdir="$REPO_ROOT/files/gatekeeper-templates" tf tkind
  if [[ -f "$tdir/${stem}-constrainttemplate.yaml" ]]; then
    tf="$tdir/${stem}-constrainttemplate.yaml"
  else
    # Best-effort fallback: search by exact filename in dir
    tf=$(find "$tdir" -type f -name "${stem}-constrainttemplate.yaml" -print -quit 2>/dev/null || true)
  fi
  if [[ -z "$tf" || ! -f "$tf" ]]; then
    echo ""; return 0
  fi
  # Try to read the explicit kind from the template CRD names.
  tkind=$(awk '
    BEGIN{kind=""}
    /^spec:/ {inspec=1}
    inspec && /^  crd:/ {incrd=1}
    incrd && /^    spec:/ {incrdspec=1}
    incrdspec && /^      names:/ {innames=1}
    innames && /^[[:space:]]*kind:[[:space:]]*[^[:space:]]+/ {
      if(kind=="") { sub(/^[[:space:]]*kind:[[:space:]]*/,"",$0); kind=$0; print kind; exit }
    }
  ' "$tf" 2>/dev/null || true)

  # If template has a concrete kind and it's not a placeholder, use it.
  if [[ -n "$tkind" && "$tkind" != "<Kind>" ]]; then
    echo "$tkind"; return 0
  fi

  # Fallback: derive a PascalCase kind from metadata.name and append "Constraint".
  # This provides a deterministic, conventional kind when the template still uses a placeholder.
  # Note: This is a best-effort guess to improve manifest completeness; actual CRD may differ until templates are finalized.
  tkind=$(awk '
    BEGIN{nm=""}
    /^[[:space:]]*metadata:/ {inmeta=1}
    inmeta && /^[[:space:]]*name:[[:space:]]*/ {
      nm=$0; sub(/^[[:space:]]*name:[[:space:]]*/,"",nm);
      # Replace any non-alphanumeric with space, then title-case each token and concatenate.
      gsub(/[^A-Za-z0-9]+/," ",nm)
      out=""
      n=split(nm, parts, /[ ]+/)
      for(i=1;i<=n;i++){
        if(length(parts[i])==0) continue
        token=parts[i]
        first=substr(token,1,1)
        rest=""
        if(length(token)>1){ rest=substr(token,2) } else { rest="" }
        first=toupper(first)
        # Lowercase the rest for stability; numbers remain unchanged.
        rest=tolower(rest)
        out=out first rest
      }
      print out "Constraint"; exit
    }
  ' "$tf" 2>/dev/null || true)
  echo "$tkind"
}

# Resolve Gatekeeper Constraint kind: prefer top-level if set and not placeholder, otherwise use template-derived
resolve_gk_constraint_kind() {
  local file_path="$1" top_kind stem base derived
  top_kind=$(grep -E '^kind:' "$file_path" | head -1 | awk '{print $2}' || true)
  if [[ -n "$top_kind" && "$top_kind" != "<Kind>" ]]; then
    echo "$top_kind"; return 0
  fi
  base="$(basename "$file_path")"
  stem="${base%-constraint.yaml}"
  derived="$(template_kind_for_stem "$stem")"
  if [[ -n "$derived" ]]; then
    if [[ "$derived" == "<Kind>" ]]; then
      warn "Template for $base still uses <Kind>; derived fallback kind applied"
    fi
    echo "$derived"; return 0
  fi
  # Fallback: leave as-is (placeholder) to avoid inventing incorrect kind
  [[ -n "$top_kind" ]] && echo "$top_kind" || echo ""
}

tmp=$(mktemp)
printf '[' >"$tmp"
first=1
missing_id=0
declare -a HASHES

while IFS= read -r f; do
  rel_field=$(file_field_for "$f")
  fw=$(framework_for "$f")
  h=$(hash_file "$f")
  # rulehub.id extraction (first match)
  rid=$(grep -E '^[[:space:]]*rulehub.id:' "$f" | head -1 | awk '{print $2}' || true)
  if [[ -z "$rid" ]]; then
    warn "No rulehub.id in $f";
    if [[ $STRICT -eq 1 ]]; then missing_id=1; fi
    continue
  fi
  kind=""
  case "$fw" in
    kyverno)
      kind=$(grep -E '^kind:' "$f" | head -1 | awk '{print $2}' || true)
      ;;
    gatekeeper-template)
      kind="ConstraintTemplate"
      ;;
    gatekeeper)
      kind=$(resolve_gk_constraint_kind "$f")
      ;;
    *)
      kind=$(grep -E '^kind:' "$f" | head -1 | awk '{print $2}' || true)
      ;;
  esac
  HASHES+=("$h")
  if [[ $first -eq 0 ]]; then printf ',' >>"$tmp"; else first=0; fi
  printf '\n  {"file":"%s","sha256":"%s","rulehub.id":"%s","kind":"%s","framework":"%s"}' \
    "$rel_field" "$h" "$rid" "$kind" "$fw" >>"$tmp"
done < <(collect_files)

printf '\n]\n' >>"$tmp"
mv "$tmp" "$OUT_FILE"
echo "[generate-manifest] Wrote $OUT_FILE"

if [[ $missing_id -eq 1 ]]; then
  fail "Missing rulehub.id detected (strict mode)"
fi

# Aggregate integrity hash (concatenate hashes in the same sorted order)
if ((${#HASHES[@]})); then
  concat="$(printf '%s' "${HASHES[@]}")"
  agg=$(printf '%s' "$concat" | sha256sum | awk '{print $1}')
  echo "aggregateIntegritySha256 $agg ${#HASHES[@]}" | tee "$OUT_FILE.aggregate"
else
  echo "aggregateIntegritySha256 - 0" | tee "$OUT_FILE.aggregate"
fi

if [[ $PRINT -eq 1 ]]; then
  cat "$OUT_FILE"
fi
