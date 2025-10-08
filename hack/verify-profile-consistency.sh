#!/usr/bin/env bash
set -euo pipefail
# verify-profile-consistency.sh
# Ensures logical consistency of profile bundles declared in values.yaml.
# Checks:
#  1. All profile policy entries reference existing policy keys (kyverno.policies.* or gatekeeper.policies.*).
#  2. No duplicate policy keys inside a single profile list.
#  3. If profiles 'baseline' and 'strict' present, baseline set must be subset of strict (strict claims to extend baseline).
#  4. Reports any missing / duplicate / subset violations and exits non‑zero on failure.
#  5. Warn (not fail) if a policy key appears in a profile but is disabled (enabled: false) in values (may be intentional override).
#
# Usage: hack/verify-profile-consistency.sh [--values FILE] [--quiet]
# Exit codes: 0 OK, 1 validation failure, 2 usage error

VALUES=values.yaml
QUIET=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --values) VALUES=$2; shift 2;;
    --quiet) QUIET=1; shift;;
    -h|--help) grep '^# ' "$0" | sed 's/^# //'; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ ! -f $VALUES ]]; then
  echo "Values file not found: $VALUES" >&2
  exit 2
fi

PROFILES=$(yq -r '.profiles | keys | .[]' "$VALUES" 2>/dev/null || true)
if [[ -z $PROFILES ]]; then
  [[ $QUIET -eq 0 ]] && echo "No profiles defined" >&2
  exit 0
fi

# Collect declared policy keys
KYVERNO_KEYS=$(yq -r '.kyverno.policies | keys | .[]' "$VALUES" 2>/dev/null || true)
GATEKEEPER_KEYS=$(yq -r '.gatekeeper.policies | keys | .[]' "$VALUES" 2>/dev/null || true)

FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

for P in $PROFILES; do
  KEYS=$(yq -r ".profiles.[\"$P\"].policies[]?" "$VALUES" 2>/dev/null || true)
  [[ -z $KEYS ]] && continue
  # Track set for later subset comparison (store unique list in temp file)
  printf '%s\n' "$KEYS" | sort -u > "$TMPDIR/set-$P.txt"
  # Detect duplicates
  DUPS=$(printf '%s\n' "$KEYS" | sort | uniq -d || true)
  if [[ -n $DUPS ]]; then
    echo "Profile '$P' has duplicate entries: $DUPS" >&2
    FAIL=1
  fi
  # Validate existence
  for k in $KEYS; do
    if ! grep -qx "$k" <<<"$KYVERNO_KEYS" && ! grep -qx "$k" <<<"$GATEKEEPER_KEYS"; then
      echo "Profile '$P' references unknown policy key: $k" >&2
      FAIL=1
      continue
    fi
    # Warn if explicitly disabled in values
    if yq -e ".kyverno.policies.[\"$k\"].enabled == false" "$VALUES" >/dev/null 2>&1 || \
       yq -e ".gatekeeper.policies.[\"$k\"].enabled == false" "$VALUES" >/dev/null 2>&1; then
      [[ $QUIET -eq 0 ]] && echo "[warn] Policy '$k' in profile '$P' is disabled (enabled: false)" >&2
    fi
  done
done

# Baseline ⊆ Strict (if both present)
if grep -qx 'baseline' <<<"$PROFILES" && grep -qx 'strict' <<<"$PROFILES"; then
  if [[ -f "$TMPDIR/set-baseline.txt" && -f "$TMPDIR/set-strict.txt" ]]; then
    while IFS= read -r b; do
      [[ -z $b ]] && continue
      if ! grep -qx "$b" "$TMPDIR/set-strict.txt"; then
        echo "Strict profile missing baseline policy: $b" >&2
        FAIL=1
      fi
    done < "$TMPDIR/set-baseline.txt"
  fi
fi

if (( FAIL==1 )); then
  exit 1
fi
[[ $QUIET -eq 0 ]] && echo "Profile consistency OK" >&2
exit 0
