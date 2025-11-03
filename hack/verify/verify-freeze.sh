#!/usr/bin/env bash
set -euo pipefail
# verify-freeze.sh
# Enforces release freeze rules comparing a reference (freeze point) against current HEAD.
# Usage: verify-freeze.sh --ref <git-ref> [--allow-critical] [--verbose]
# Rules (default): After freeze, ONLY the following changes are permitted:
#   - CHANGELOG.md
#   - *.md documentation (excluding files/ tree) and README-like docs
#   - Chart.yaml (version line ONLY)
#   - New release metadata files (e.g., manifest.json) if integrity unchanged
#   - Generated tables: VALUES_TABLE.md, policy table (policy table name TBD)
#   - Scripts under hack/ that do NOT modify rendering logic (optional; default disallowed)
# Disallowed (fail) unless --allow-critical provided AND commit messages include [critical-fix]:
#   - Any changes under files/ (policy YAML)
#   - templates/ (Helm templates)
#   - values.yaml, values.schema.json
#   - scripts impacting rendering (helpers)
# Fails if disallowed diffs present. Prints categorized diff summary.

REF=""
ALLOW_CRITICAL=0
VERBOSE=0
ALLOW_HACK=0

usage(){
  echo "Usage: $0 --ref <git-ref> [--allow-critical] [--allow-hack] [--verbose]" >&2
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --ref) REF=$2; shift 2;;
    --allow-critical) ALLOW_CRITICAL=1; shift;;
    --allow-hack) ALLOW_HACK=1; shift;;
    --verbose) VERBOSE=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

if [[ -z $REF ]]; then echo "--ref required" >&2; exit 2; fi

if ! git rev-parse --verify "$REF" >/dev/null 2>&1; then
  echo "Reference $REF not found" >&2; exit 2
fi

diffs=$(git diff --name-only "$REF"..HEAD || true)
if [[ -z $diffs ]]; then echo "No changes since $REF (freeze clean)"; exit 0; fi

allowed_regex='^(CHANGELOG\.md|[^/]+\.md|Chart\.yaml|manifest\.json|VALUES_TABLE\.md)$'
# Optionally allow hack/ changes if flag set
if [[ $ALLOW_HACK -eq 1 ]]; then
  allowed_regex='^(CHANGELOG\.md|[^/]+\.md|Chart\.yaml|manifest\.json|VALUES_TABLE\.md|hack/[^/]+\.sh)$'
fi

violations=()
warns=()

for f in $diffs; do
  if [[ $f =~ ^files/ ]] || [[ $f =~ ^templates/ ]] || [[ $f == values.yaml ]] || [[ $f == values.schema.json ]]; then
    violations+=("$f")
    continue
  fi
  if [[ ! $f =~ $allowed_regex ]]; then
    warnings_msg="Non-standard change (not explicitly allowed): $f"
    warns+=("$warnings_msg")
  fi
  # Special check: Chart.yaml diff only version line
  if [[ $f == Chart.yaml ]]; then
    chart_diff=$(git diff "$REF"..HEAD -- Chart.yaml || true)
    # Remove version line(s) then check if anything else changed
    stripped=$(echo "$chart_diff" | grep '^[-+]version:' -v || true)
    if echo "$stripped" | grep -q '^[-+]'; then
      violations+=("Chart.yaml (changes beyond version line)")
    fi
  fi
  # manifest.json integrity: ensure no policy file added/removed silently during freeze
  if [[ $f == manifest.json ]]; then
    # Optionally we could diff sha entries (light check)
    if git diff "$REF"..HEAD -- manifest.json | grep -q '^[-+].*"sha256"'; then
      warns+=("manifest.json hash changes during freeze (ensure this is intentional)")
    fi
  fi
  # Hack scripts: warn if modify verify or render when allowed
  if [[ $f =~ ^hack/ ]] && [[ $ALLOW_HACK -eq 1 ]]; then
    if [[ $f =~ (generate|render|verify-deterministic|verify-performance) ]]; then
      warns+=("Potential render-impacting script changed: $f")
    fi
  fi
done

# Critical override: if violations exist but commit history since REF includes [critical-fix]
if (( ${#violations[@]} > 0 )); then
  if [[ $ALLOW_CRITICAL -eq 1 ]]; then
    if git log --oneline "$REF"..HEAD | grep -q '\[critical-fix\]'; then
      echo "CRITICAL FIX OVERRIDE: violations tolerated due to [critical-fix] commit"
    else
      echo "Violations found (no [critical-fix] override):" >&2
      printf ' - %s\n' "${violations[@]}" >&2
      exit 1
    fi
  else
    echo "Freeze violations:" >&2
    printf ' - %s\n' "${violations[@]}" >&2
    exit 1
  fi
fi

if (( VERBOSE == 1 )); then
  echo "Freeze diff summary vs $REF:"; echo "$diffs" | sed 's/^/ - /'
fi

if (( ${#warns[@]} > 0 )); then
  echo "Warnings:"; printf ' - %s\n' "${warns[@]}"
fi

echo "Freeze verification OK"
exit 0
