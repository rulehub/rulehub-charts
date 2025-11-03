#!/usr/bin/env bash
set -euo pipefail
# verify-removed-without-deprecation.sh
# Fails if any policy YAML file present in a previous git ref was removed in the
# current working tree without having been marked deprecated (deprecated_since)
# in the previous release's values.yaml.
#
# Rationale: Enforces deprecation lifecycle: a policy file (files/kyverno|gatekeeper|gatekeeper-templates)
# must first be marked deprecated (values.yaml key has deprecated_since) before
# being removed in a later release.
#
# Usage:
#   hack/verify-removed-without-deprecation.sh --ref <git-ref> [--quiet]
# Exit codes: 0 = ok, 1 = violations, 2 = usage error.

REF=""
QUIET=0

usage() {
  cat >&2 <<EOF
Usage: $0 --ref <git-ref> [--quiet]
Checks removed policy YAML files vs previous ref ensuring prior deprecation.
Ref should normally be the previous release tag (e.g. v0.1.0).
EOF
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --ref) REF=$2; shift 2;;
    --quiet) QUIET=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

[[ -z $REF ]] && { echo "--ref required" >&2; usage; exit 2; }

log() { if [[ $QUIET -eq 0 ]]; then echo "$*"; fi }

# Ensure ref exists
if ! git rev-parse --verify --quiet "$REF" >/dev/null; then
  echo "Ref not found: $REF" >&2; exit 2
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Extract previous values.yaml
if ! git show "$REF:values.yaml" >"$tmpdir/old-values.yaml" 2>/dev/null; then
  echo "values.yaml not found at ref $REF" >&2; exit 2
fi

# Collect previous file list (only policy YAMLs)
git ls-tree -r --name-only "$REF" -- files/kyverno files/gatekeeper files/gatekeeper-templates \
  | grep -E '\\.ya?ml$' | sort -u >"$tmpdir/old-files.txt" || true

# Current file list
{ find files/kyverno files/gatekeeper files/gatekeeper-templates -maxdepth 1 -type f -name '*.yaml' 2>/dev/null || true; } \
  | sed 's#^./##' | sort -u >"$tmpdir/new-files.txt"

if [[ ! -s $tmpdir/old-files.txt ]]; then
  log "No previous policy files detected at ref (nothing to compare)."; exit 0
fi

comm -23 "$tmpdir/old-files.txt" "$tmpdir/new-files.txt" >"$tmpdir/removed.txt" || true

if [[ ! -s $tmpdir/removed.txt ]]; then
  log "No removed policy files (OK)."; exit 0
fi

fail=0
while IFS= read -r path; do
  [[ -z $path ]] && continue
  base=$(basename "$path" .yaml)
  # Determine framework guess (kyverno/gatekeeper) just for logging
  framework="unknown"
  case $path in
    files/kyverno/*) framework="kyverno";;
    files/gatekeeper/*) framework="gatekeeper";;
    files/gatekeeper-templates/*) framework="gatekeeper";;
  esac
  # Check deprecated_since in previous values
  dep_since=$(yq -r ".kyverno.policies.$base.deprecated_since // .gatekeeper.policies.$base.deprecated_since // empty" "$tmpdir/old-values.yaml" 2>/dev/null || true)
  if [[ -z $dep_since ]]; then
    echo "VIOLATION: removed policy file without prior deprecation: $path (key=$base)" >&2
    fail=1
  else
    log "OK: removed $path had deprecated_since=$dep_since"
  fi
done <"$tmpdir/removed.txt"

if (( fail )); then
  echo "Removal deprecation verification FAILED" >&2
  exit 1
fi
log "Removal deprecation verification OK"
exit 0
