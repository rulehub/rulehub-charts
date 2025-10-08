#!/usr/bin/env bash
set -euo pipefail

# ci-tag-resolve.sh
# Resolves the CI image tag using precedence:
# 1) first argument (explicit input)
# 2) environment variable CI_IMAGE_TAG (e.g., from repo vars)
# 3) fallback to 'latest' when running under ACT/nektos/act
#
# Emits:
# - GITHUB_OUTPUT: resolved_tag
# - GITHUB_STEP_SUMMARY: human-readable note

arg_input="${1:-}"
env_tag="${CI_IMAGE_TAG:-}"
is_act="${ACT:-}"

resolved=""
if [[ -n "$arg_input" ]]; then
  resolved="$arg_input"
elif [[ -n "$env_tag" ]]; then
  resolved="$env_tag"
elif [[ -n "$is_act" || "${GITHUB_ACTOR:-}" == "nektos/act" ]]; then
  resolved="latest"
  echo "[act] Falling back to 'latest' ci-charts tag." >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || true
else
  echo "Error: CI image tag is not provided." >&2
  echo "❌ CI image tag is required." >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || true
  echo "Set workflow_dispatch input 'ci_image_tag' or repository variable CI_IMAGE_TAG to an immutable tag." >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || true
  exit 1
fi

if ! [[ "$resolved" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Error: Resolved tag contains invalid characters: $resolved" >&2
  exit 1
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "resolved_tag=$resolved" >> "$GITHUB_OUTPUT"
fi
echo "✅ CI image tag detected: $resolved" >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || true
