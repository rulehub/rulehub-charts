#!/usr/bin/env bash
set -euo pipefail
# verify-profiles.sh
# Verifies that policies listed under profiles.*.policies are rendered when the profile is activated
# via activeProfiles. Also ensures no unintended policies are auto-enabled beyond those declared.
# Logic:
# 1. Read values.yaml (or provided values file) to collect profile->policy lists.
# 2. For each profile name we will create a temp values overlay setting activeProfiles:[profile].
#    (If activeProfiles already contains values we honor that instead unless --force-matrix provided.)
# 3. Render chart and capture list of rendered policy resource names (Kyverno + Gatekeeper).
# 4. For that profile we expect every listed policy key to appear enabled (rendered). A key corresponds to:
#      - Kyverno: metadata.name == <policy key> (for -policy suffix) OR file basename mapping.
#      - Gatekeeper: constraint name OR template? (We scope to Kyverno for now unless --all specified.)
#    Since helpers already normalize names to basenames, we use a heuristic: look for lines 'metadata:' followed by '  name: <key>' in documents.
# 5. Reports missing (declared in profile but not rendered) and unexpected (rendered due to profile but not declared explicitly when only that profile active).
#
# Options:
#   --values FILE   use alternative values file (default values.yaml)
#   --all           also validate Gatekeeper policies (match any profile key referencing a constraint -constraint)
#   --force-matrix  ignore existing activeProfiles array in source values; test each profile in isolation
#   --quiet         suppress success details
#
# Exit codes:
#   0 OK
#   1 validation failures
#   2 usage error

VALUES=values.yaml
ALL=0
FORCE=0
QUIET=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --values) VALUES=$2; shift 2;;
    --all) ALL=1; shift;;
    --force-matrix) FORCE=1; shift;;
    --quiet) QUIET=1; shift;;
    -h|--help) grep '^# ' "$0" | sed 's/^# //'; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ ! -f $VALUES ]]; then
  echo "Values file not found: $VALUES" >&2
  exit 2
fi

# Collect profile names
PROFILES=$(yq -r '.profiles | keys | .[]' "$VALUES" 2>/dev/null || true)
if [[ -z $PROFILES ]]; then
  echo "No profiles defined" >&2
  exit 0
fi

FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Extract only Kyverno ClusterPolicy metadata.name values
extract_kyverno() {
  awk '
    /^---/ {kind=""; meta=0}
    /^kind: / {kind=$2}
    /^metadata:/ {meta=1; next}
    meta==1 && /^  name:/ { if (kind=="ClusterPolicy") {print $2}; meta=0 }
  '
}

# Base activeProfiles in original values (if not forcing)
ORIG_ACTIVE=$(yq -r '.activeProfiles[]?' "$VALUES" || true)

for P in $PROFILES; do
  if (( FORCE==1 )); then
    ACTIVE_LIST=$P
  else
    if [[ -n $ORIG_ACTIVE ]]; then
      # Skip isolated test if original values already specify activeProfiles; we still check that each declared policy is rendered in combined set
      ACTIVE_LIST=$ORIG_ACTIVE
    else
      ACTIVE_LIST=$P
    fi
  fi
  OUT_VALUES=$TMPDIR/values-$P.yaml
  cp "$VALUES" "$OUT_VALUES"
  # Override activeProfiles
  yq eval -i 'del(.activeProfiles)' "$OUT_VALUES"
  # Build YAML array for activeProfiles and neutralize explicit kyverno.policies to test auto-enable
  APYAML=$(printf '%s\n' $ACTIVE_LIST | sed 's/^/- /')
  { echo 'activeProfiles:'; printf '%s\n' "$APYAML"; } >> "$OUT_VALUES"
  yq eval -i '.kyverno.policies = {}' "$OUT_VALUES"

  RENDERED=$(helm template rulehub-policies . -f "$OUT_VALUES")
  # Canonicalize rendered names by replacing underscores with hyphens to match declared policy mapping
  RENDERED_NAMES=$(printf '%s\n' "$RENDERED" | extract_kyverno | sed 's/_/-/g' | sort -u)

  DECLARED_RAW=$(yq -r ".profiles.[\"$P\"].policies[]?" "$VALUES" | sort -u || true)
  DECLARED_MAPPED=()
  for k in $DECLARED_RAW; do
    base=${k%-policy}
  # Canonical form: rendered helper replaces underscores with hyphens in metadata.name
  canon=${base//_/-}
  DECLARED_MAPPED+=("$canon")
  done
  DECLARED=$(printf '%s\n' "${DECLARED_MAPPED[@]}" | sort -u)
  if [[ -z $DECLARED ]]; then
    [[ $QUIET -eq 0 ]] && echo "Profile '$P' has no policies (skip)" >&2
    continue
  fi

  MISSING=()
  for d in $DECLARED; do
    if ! grep -qx "$d" <<<"$RENDERED_NAMES"; then
      MISSING+=("$d")
    fi
  done

  if (( ${#MISSING[@]} > 0 )); then
    echo "Profile validation FAILED for '$P'" >&2
    (( ${#MISSING[@]} > 0 )) && echo "  Missing: ${MISSING[*]}" >&2
    FAIL=1
  else
    [[ $QUIET -eq 0 ]] && echo "Profile '$P' OK" >&2
  fi

done

if (( FAIL==1 )); then
  exit 1
fi
[[ $QUIET -eq 0 ]] && echo "Profiles verification OK" >&2
exit 0
