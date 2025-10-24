#!/usr/bin/env bash
set -euo pipefail

# Guard script to ensure CI image tag is immutable (not 'latest').
# Behavior under ACT/local emulation: skip guard to avoid false negatives.
# Usage: guard-ci-image-tag.sh [tag]

tag="${1:-${TAG:-${CI_IMAGE_TAG:-}}}"

# Detect ACT/local emulation and skip strictly
if [[ "${IS_ACT:-}" == "true" || "${ACT:-}" == "true" || -f "/var/run/act/workflow/0" ]]; then
  echo "[act] Skipping CI image tag guard (tag='${tag:-}')."
  exit 0
fi

if [[ -z "${tag}" ]]; then
  echo "[guard] No tag provided; nothing to enforce." >&2
  exit 0
fi

if [[ "${tag}" == "latest" ]]; then
  echo "[guard] CI image tag must be immutable, not 'latest'. Provided: '${tag}'." >&2
  exit 1
fi

echo "[guard] CI image tag '${tag}' is immutable. OK."
