#!/usr/bin/env bash
set -euo pipefail
# verify-deprecation-window.sh
# Validates deprecation window rules for policy keys having deprecated_since metadata.
# Rules:
# 1. deprecated_since must be valid SemVer (major.minor.patch) already enforced by schema.
# 2. A key with deprecated_since MUST NOT have enabled: true AND (for Kyverno) validationFailureAction=enforce.
# 3. Removal: When a deprecated key disappears from values.yaml, ensure at least WINDOW (default 2) minor bumps have elapsed since deprecated_since.
#    (We can only check removals if an OLD_VALUES file is provided via --old-values <file>.)
# 4. A deprecated key should normally be disabled (enabled: false) after initial deprecation; warn if still true.
# Exit codes: 0 success, 1 violations.

WINDOW_MINORS=2
OLD_VALUES=""
QUIET=0

usage() {
  echo "Usage: $0 [--old-values previous-values.yaml] [--window N] [--quiet]" >&2
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --old-values)
      OLD_VALUES=$2; shift 2;;
    --window)
      WINDOW_MINORS=$2; shift 2;;
    --quiet)
      QUIET=1; shift;;
    -h|--help)
      usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

fail=0

log() { if [[ $QUIET -eq 0 ]]; then echo "$*"; fi }

semver_minor_distance() { # current_version deprecated_since -> distance in minor units assuming same major
  local current=$1; local since=$2
  local cmj=$(echo "$current" | cut -d. -f1)
  local cmi=$(echo "$current" | cut -d. -f2)
  local smj=$(echo "$since" | cut -d. -f1)
  local smi=$(echo "$since" | cut -d. -f2)
  if [[ $cmj != $smj ]]; then
    # Different major: treat as sufficiently distant (allow removal) if current major > since major
    if (( cmj > smj )); then echo 999; else echo 0; fi
  else
    echo $(( cmi - smi ))
  fi
}

CHART_VERSION=$(grep '^version:' Chart.yaml | awk '{print $2}')
if [[ -z $CHART_VERSION ]]; then echo "Unable to determine Chart version" >&2; exit 2; fi

# Extract all current policy entries with deprecated_since
current_json=$(yq -o=json '.gatekeeper.policies + .kyverno.policies' values.yaml 2>/dev/null || echo '{}')

# Iterate keys
while IFS=$'\t' read -r key since enabled action; do
  # Warn if enabled still true
  if [[ $enabled == "true" ]]; then
    log "WARN: deprecated key still enabled: $key (since $since)"
  fi
  # If Kyverno enforced after deprecation -> violation
  if [[ $action == "enforce" ]]; then
    echo "VIOLATION: deprecated key has enforce action: $key (since $since)" >&2
    fail=1
  fi
  # Basic semver ordering (current must be >= since)
  if [[ $(printf '%s\n%s\n' "$CHART_VERSION" "$since" | sort -V | head -n1) != "$since" ]]; then
    echo "VIOLATION: deprecated_since $since is greater than current chart version $CHART_VERSION for $key" >&2
    fail=1
  fi
  # Encourage disabling after 1 minor
  dist=$(semver_minor_distance "$CHART_VERSION" "$since")
  if (( dist >= WINDOW_MINORS )); then
    log "INFO: key eligible for removal (window satisfied): $key (since $since, distance=$dist)"
  fi
done < <(printf '%s\n' "$current_json" | jq -r 'to_entries[] | select(.value.deprecated_since!=null) | [.key, .value.deprecated_since, (.value.enabled//false), (.value.validationFailureAction//"" )] | @tsv')

# Check removals if old values provided
if [[ -n $OLD_VALUES && -f $OLD_VALUES ]]; then
  removed=$(diff -u <(yq -r '.gatekeeper.policies | keys[]' "$OLD_VALUES" 2>/dev/null || true) <(yq -r '.gatekeeper.policies | keys[]' values.yaml 2>/dev/null || true) | grep '^-[^-]' | sed 's/^-//' || true)
  removed+=$'\n'$(diff -u <(yq -r '.kyverno.policies | keys[]' "$OLD_VALUES" 2>/dev/null || true) <(yq -r '.kyverno.policies | keys[]' values.yaml 2>/dev/null || true) | grep '^-[^-]' | sed 's/^-//' || true)
  # For each removed key, ensure it was deprecated and window satisfied
  while IFS= read -r r; do
    [[ -z $r ]] && continue
    # Find deprecated_since from OLD_VALUES
    since=$(yq -r ".gatekeeper.policies.$r.deprecated_since // .kyverno.policies.$r.deprecated_since // empty" "$OLD_VALUES" 2>/dev/null || true)
    if [[ -z $since ]]; then
      echo "VIOLATION: key removed without prior deprecation: $r" >&2
      fail=1
      continue
    fi
    dist=$(semver_minor_distance "$CHART_VERSION" "$since")
    if (( dist < WINDOW_MINORS )); then
      echo "VIOLATION: key removed before deprecation window satisfied: $r (since $since, distance=$dist < $WINDOW_MINORS)" >&2
      fail=1
    else
      log "INFO: removal OK (window satisfied) for $r (since $since, distance=$dist)"
    fi
  done <<< "$removed"
fi

if [[ $fail -eq 1 ]]; then
  echo "Deprecation window verification FAILED" >&2
  exit 1
fi
log "Deprecation window verification OK"
exit 0
