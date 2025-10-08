#!/usr/bin/env bash
set -euo pipefail

# deprecation-window-run.sh
# Fetch base values.yaml (if PR) and invoke verify-deprecation-window.sh accordingly.
#
# Env (provided by workflow):
#   EVENT_NAME   - GitHub event name (e.g., pull_request, push)
#   BASE_REF     - Base ref name for PR (e.g., main)
#
# Requires:
#   - yq present (workflow verifies before calling this script)
#   - jq optional (only used by workflow outside)

EVENT_NAME=${EVENT_NAME:-}
BASE_REF=${BASE_REF:-main}

if [[ "$EVENT_NAME" == "pull_request" ]]; then
  git fetch --depth=1 origin "$BASE_REF":origin-base || true
  cp values.yaml current-values.yaml
  if git show origin-base:values.yaml > old-values.yaml 2>/dev/null; then
    bash hack/verify-deprecation-window.sh --old-values old-values.yaml
  else
    echo 'Base values.yaml not found; running without removal checks'
    bash hack/verify-deprecation-window.sh
  fi
else
  bash hack/verify-deprecation-window.sh
fi
