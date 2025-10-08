#!/usr/bin/env bash
set -euo pipefail

# Resolve CI tag value from:
# 1) Input env TAG_INPUT (preferred)
# 2) GITHUB_EVENT_JSON (full event JSON), using .client_payload.tag for repository_dispatch
# Prints the tag to stdout. Exits non-zero if not resolvable.

TAG_INPUT=${TAG_INPUT:-}
if [[ -n "$TAG_INPUT" ]]; then
  echo "$TAG_INPUT"
  exit 0
fi

if [[ -n "${GITHUB_EVENT_JSON:-}" ]]; then
  tag=$(echo "$GITHUB_EVENT_JSON" | jq -r '.client_payload.tag // ""')
  if [[ -n "$tag" && "$tag" != "null" ]]; then
    echo "$tag"
    exit 0
  fi
fi

echo "No tag provided. Provide TAG_INPUT or set repository_dispatch.client_payload.tag" >&2
exit 1
