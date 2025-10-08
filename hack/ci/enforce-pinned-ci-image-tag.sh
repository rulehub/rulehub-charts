#!/usr/bin/env bash
set -euo pipefail

# Enforce that the CI image tag is pinned (not 'latest').
# Inputs (env vars):
#   INPUT_CI_TAG  - workflow_dispatch input value (may be empty)
#   VARS_CI_TAG   - repository variable CI_IMAGE_TAG (may be empty)
# Behavior:
#   - If running under ACT (detected via ACT env or GitHub actor), skip with exit 0.
#   - Resolves the tag from INPUT_CI_TAG, then VARS_CI_TAG, else 'latest'.
#   - Fails if the resolved tag is 'latest'.

if [[ "${ACT:-}" != "" || "${GITHUB_ACTOR:-}" == "nektos/act" ]]; then
  echo "[enforce-ci-tag] Detected ACT environment; skipping guard." >&2
  exit 0
fi

resolved_tag="${INPUT_CI_TAG:-}"
if [[ -z "$resolved_tag" ]]; then
  resolved_tag="${VARS_CI_TAG:-}"
fi
if [[ -z "$resolved_tag" ]]; then
  resolved_tag="latest"
fi

echo "Resolved CI image tag: ${resolved_tag}"
if [[ "$resolved_tag" == "latest" ]]; then
  echo "CI image tag resolves to 'latest'. Provide a pinned tag via workflow input 'ci_image_tag' or repository variable CI_IMAGE_TAG (e.g., 2025.10.03-<sha> or vX.Y.Z)." >&2
  exit 1
fi

echo "[enforce-ci-tag] OK: pinned tag in use (${resolved_tag})."
