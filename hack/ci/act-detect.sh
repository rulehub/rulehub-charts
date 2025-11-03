#!/usr/bin/env bash
set -euo pipefail

# act-detect.sh
# Sets IS_ACT=true in GITHUB_ENV when running under nektos/act.

if [[ -n "${ACT:-}" || "${GITHUB_ACTOR:-}" == "nektos/act" ]]; then
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "IS_ACT=true" >> "$GITHUB_ENV"
  else
    echo "IS_ACT=true"
  fi
fi
