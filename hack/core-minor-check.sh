#!/usr/bin/env bash
set -euo pipefail

# Purpose: Verify that Chart.yaml version minor >= core tag minor, else suggest bump.
# Usage:
#   hack/core-minor-check.sh --core-tag vX.Y.Z
#   CORE_TAG=vX.Y.Z hack/core-minor-check.sh
#   (Optionally place a .core-tag file with vX.Y.Z)
#
# Exit codes:
#   0 - OK (chart minor >= core minor)
#   1 - Core tag not provided / invalid
#   2 - Chart.yaml version invalid
#   3 - Chart minor < core minor (bump needed)

core_tag_arg=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --core-tag)
      core_tag_arg="$2"; shift 2 ;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //' >&2; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

CORE_TAG=${core_tag_arg:-${CORE_TAG:-}}
if [[ -z "${CORE_TAG}" && -f .core-tag ]]; then
  CORE_TAG=$(< .core-tag)
fi

if [[ -z "${CORE_TAG}" ]]; then
  echo "Core tag not provided. Use --core-tag vX.Y.Z or CORE_TAG env or .core-tag file." >&2
  exit 1
fi

if [[ ! ${CORE_TAG} =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid core tag format: ${CORE_TAG} (expected vX.Y.Z)" >&2
  exit 1
fi

CHART_VER=$(grep '^version:' Chart.yaml | awk '{print $2}') || true
if [[ -z "${CHART_VER}" ]]; then
  echo "Chart.yaml version field not found" >&2
  exit 2
fi
if [[ ! ${CHART_VER} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Invalid Chart.yaml version: ${CHART_VER}" >&2
  exit 2
fi

core_no_v=${CORE_TAG#v}
core_major=${core_no_v%%.*}
core_minor_patch=${core_no_v#*.}
core_minor=${core_minor_patch%%.*}
core_patch=${core_no_v##*.}

chart_major=${CHART_VER%%.*}
chart_minor_patch=${CHART_VER#*.}
chart_minor=${chart_minor_patch%%.*}
chart_patch=${CHART_VER##*.}

echo "Core tag:    ${CORE_TAG} (major=${core_major} minor=${core_minor} patch=${core_patch})"
echo "Chart.yaml:  ${CHART_VER} (major=${chart_major} minor=${chart_minor} patch=${chart_patch})"

if (( chart_minor < core_minor )); then
  # Suggest bump: keep existing major if >= core major, else align to core major.
  if (( chart_major < core_major )); then
    suggested_major=${core_major}
  else
    suggested_major=${chart_major}
  fi
  suggested_version="${suggested_major}.${core_minor}.0"
  echo "NEED_BUMP: chart minor (${chart_minor}) < core minor (${core_minor}). Suggested new chart version: ${suggested_version}" >&2
  exit 3
fi

echo "OK: chart minor ("${chart_minor}") >= core minor ("${core_minor}")"
exit 0
