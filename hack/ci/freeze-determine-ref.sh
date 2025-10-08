#!/usr/bin/env bash
set -euo pipefail

# freeze-determine-ref.sh
# Determine freeze baseline ref and communicate outputs to GitHub Actions.
#
# Inputs (env):
#   INPUT_REF   - Manual freeze_ref input (may be empty)
#   EVENT_NAME  - GitHub event name
#   LABELS_CSV  - Comma-separated label names for the PR (if PR)
#
# Outputs (GITHUB_OUTPUT):
#   ref   - selected ref (if any)
#   skip  - 'true' to skip freeze check

OUT=${GITHUB_OUTPUT:-}

if [[ -z "$OUT" ]]; then
  echo "GITHUB_OUTPUT not set" >&2
  exit 2
fi

INPUT_REF=${INPUT_REF:-}
EVENT_NAME=${EVENT_NAME:-}
LABELS_CSV=${LABELS_CSV:-}

# Skip for PRs without 'freeze' label
if [[ "$EVENT_NAME" == "pull_request" ]]; then
  if ! echo ",$LABELS_CSV," | grep -q ',freeze,'; then
    echo 'Freeze label not present on PR; skipping freeze check.'
    echo "skip=true" >> "$OUT"
    exit 0
  fi
fi

# Manual override
if [[ -n "$INPUT_REF" ]]; then
  echo "ref=$INPUT_REF" >> "$OUT"
  exit 0
fi

# Fallback to latest tag
git fetch --tags --quiet || true
latest=$(git describe --tags --abbrev=0 2>/dev/null || echo '')
if [[ -z "$latest" ]]; then
  echo 'No tags found; skipping freeze check.'
  echo 'skip=true' >> "$OUT"
else
  echo "Using latest tag as freeze ref: $latest"
  echo "ref=$latest" >> "$OUT"
fi
