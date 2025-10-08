#!/usr/bin/env bash
set -euo pipefail

# analyze-gk-constrainttemplates-kinds.sh
# Scans all Gatekeeper ConstraintTemplate YAMLs under files/gatekeeper-templates
# and reports duplicate spec.crd.spec.names.kind values (same Kind implemented
# by more than one file). Exits with non-zero if duplicates are found.
# Additionally lists a summary mapping Kind -> files.
#
# Rationale: Duplicate Kinds cause install/upgrade failures because the CRD
# (generated from ConstraintTemplate) must be unique cluster-wide. Detecting
# them early prevents chart drift and naming collisions.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES_DIR="$ROOT_DIR/files/gatekeeper-templates"

if [[ ! -d "$TEMPLATES_DIR" ]]; then
  echo "Directory not found: $TEMPLATES_DIR" >&2
  exit 2
fi

shopt -s nullglob
declare -A KIND_FILES
declare -A FILE_KIND

rc=0

for file in "$TEMPLATES_DIR"/*.yaml; do
  # Extract apiVersion & kind first to ensure it's a ConstraintTemplate
  # Then grab spec.crd.spec.names.kind (first occurrence)
  if grep -q '^kind: *ConstraintTemplate' "$file"; then
    # Use awk to navigate indentation robustly
    extracted_kind=$(awk '
      BEGIN{kind=""}
      /^spec:/ {inspec=1}
      inspec && /^  crd:/ {incrd=1}
      incrd && /^    spec:/ {incrdspec=1}
      incrdspec && /^      names:/ {innames=1}
      innames && /^[[:space:]]*kind:[[:space:]]*[^[:space:]]+/ { \
        if(kind=="") { \
          sub(/^[[:space:]]*kind:[[:space:]]*/,"",$0); kind=$0; \
          print kind; exit \
        } \
      }
    ' "$file" || true)

    if [[ -z "$extracted_kind" ]]; then
      echo "WARN: Unable to locate spec.crd.spec.names.kind in $file" >&2
      continue
    fi

    FILE_KIND["$file"]="$extracted_kind"
    KIND_FILES["$extracted_kind"]+=" $file"
  fi
done

echo "Gatekeeper ConstraintTemplate Kinds summary:"
for k in "${!KIND_FILES[@]}"; do
  files=${KIND_FILES[$k]}
  # shellcheck disable=SC2086
  count=$(for f in $files; do echo "$f"; done | wc -l | tr -d ' ')
  echo "  - $k ($count):${files}"
done | sort

echo
echo "Checking for duplicates..."
dups=()
for k in "${!KIND_FILES[@]}"; do
  files=${KIND_FILES[$k]}
  # shellcheck disable=SC2086
  count=$(for f in $files; do echo "$f"; done | wc -l | tr -d ' ')
  if (( count > 1 )); then
    dups+=("$k ->${files}")
  fi
done

if ((${#dups[@]})); then
  echo "Duplicate Kind definitions detected (${#dups[@]}):" >&2
  for d in "${dups[@]}"; do echo "  $d" >&2; done
  rc=1
else
  echo "No duplicate Kind definitions detected." >&2
fi

exit $rc
