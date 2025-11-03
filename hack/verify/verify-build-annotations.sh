#!/usr/bin/env bash
set -euo pipefail
# verify-build-annotations.sh
# Ensures every rendered resource contains required build annotations when requested via values:
#   policy-sets/build.commit (if .Values.build.commitSha non-empty)
#   policy-sets/build.timestamp (if .Values.build.timestamp non-empty)
#   policy-sets/build.integrity.sha256 (if .Values.build.integritySha256 non-empty)
# Usage: hack/verify-build-annotations.sh [VALUES=values.yaml]

VALUES_FILE="${1:-values.yaml}"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

helm template rulehub-policies . -f "$VALUES_FILE" > "$TMP"

need_commit=$(yq -r '.build.commitSha // ""' "$VALUES_FILE")
need_timestamp=$(yq -r '.build.timestamp // ""' "$VALUES_FILE")
need_integrity=$(yq -r '.build.integritySha256 // ""' "$VALUES_FILE")

fail=0
current=""
index=0
while IFS= read -r line || [ -n "$line" ]; do
  if [[ $line == '---'* ]]; then
    if [[ -n $current ]]; then
      index=$((index+1))
      if [[ -n $need_commit ]] && ! grep -q 'policy-sets/build.commit:' <<<"$current"; then echo "Missing build.commit in doc #$index" >&2; fail=1; fi
      if [[ -n $need_timestamp ]] && ! grep -q 'policy-sets/build.timestamp:' <<<"$current"; then echo "Missing build.timestamp in doc #$index" >&2; fail=1; fi
      if [[ -n $need_integrity ]] && ! grep -q 'policy-sets/build.integrity.sha256:' <<<"$current"; then echo "Missing build.integrity.sha256 in doc #$index" >&2; fail=1; fi
    fi
    current=""
    continue
  fi
  current+="$line"$'\n'
done < "$TMP"

if [[ -n $current ]]; then
  index=$((index+1))
  if [[ -n $need_commit ]] && ! grep -q 'policy-sets/build.commit:' <<<"$current"; then echo "Missing build.commit in doc #$index" >&2; fail=1; fi
  if [[ -n $need_timestamp ]] && ! grep -q 'policy-sets/build.timestamp:' <<<"$current"; then echo "Missing build.timestamp in doc #$index" >&2; fail=1; fi
  if [[ -n $need_integrity ]] && ! grep -q 'policy-sets/build.integrity.sha256:' <<<"$current"; then echo "Missing build.integrity.sha256 in doc #$index" >&2; fail=1; fi
fi

if (( fail==1 )); then
  echo "Build annotations verification FAILED" >&2
  exit 1
fi
echo "Build annotations verification OK" >&2
exit 0
