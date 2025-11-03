#!/usr/bin/env bash
set -euo pipefail

# gen-provenance.sh
# Generate a SLSA v1.0 provenance predicate JSON for the packaged Helm chart (rulehub-policies).

VERSION=""
OUT=""
DO_PACKAGE=0
INCLUDE_PLACEHOLDERS=0
CHART_NAME="rulehub-policies"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILDER_ID="${BUILDER_ID:-https://github.com/marketplace/actions/github-actions}"
BUILD_TYPE="https://github.com/rulehub/charts/helm-package@v1"
SOURCE_URI=""

usage() { grep '^# ' "$0" | sed 's/^# \{0,1\}//'; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version) VERSION="$2"; shift 2;;
      --out) OUT="$2"; shift 2;;
      --package) DO_PACKAGE=1; shift;;
      --include-placeholders) INCLUDE_PLACEHOLDERS=1; shift;;
      --builder-id) BUILDER_ID="$2"; shift 2;;
      --build-type) BUILD_TYPE="$2"; shift 2;;
      --source-uri) SOURCE_URI="$2"; shift 2;;
      -h|--help) usage; exit 0;;
      *) echo "Unknown arg: $1" >&2; exit 2;;
    esac
  done
  [[ -n "$VERSION" ]] || { echo 'Specify --version' >&2; exit 2; }
}

sha_file() { sha256sum "$1" | awk '{print $1}'; }

collect_policy_files() {
  local f
  while IFS= read -r f; do
    if [[ $INCLUDE_PLACEHOLDERS -eq 0 ]] && [[ $(basename "$f") == *placeholder* ]]; then continue; fi
    echo "$f"
  done < <(find "$ROOT_DIR/files" -type f \( -path '*/kyverno/*.yaml' -o -path '*/gatekeeper/*.yaml' -o -path '*/gatekeeper-templates/*.yaml' \) | sort)
}

aggregate_hash() {
  bash "$ROOT_DIR/hack/tools/aggregate-integrity.sh" ${INCLUDE_PLACEHOLDERS:+--include-placeholders} | awk '{print $2}'
}

git_rev() {
  (cd "$ROOT_DIR" && git rev-parse --verify HEAD 2>/dev/null) || echo "unknown"
}

git_dirty() {
  (cd "$ROOT_DIR" && git diff --quiet 2>/dev/null || echo "dirty") || true
}

main() {
  parse_args "$@"
  local pkg="${CHART_NAME}-${VERSION}.tgz"
  if [[ ! -f "$pkg" ]]; then
    if (( DO_PACKAGE )); then
      helm package "$ROOT_DIR" --version "$VERSION" --app-version "$VERSION" >/dev/null
    else
      echo "Package $pkg not found. Use --package or create it first." >&2; exit 2
    fi
  fi
  local pkg_sha pkg_path
  pkg_path="$pkg"
  pkg_sha=$(sha_file "$pkg_path")

  # Build resolvedDependencies JSON array
  local deps_json="["
  local first=1
  while IFS= read -r p; do
    local rel h
    rel="${p#$ROOT_DIR/}"
    h=$(sha_file "$p")
    if [[ $first -eq 0 ]]; then deps_json+=","; fi
    first=0
    deps_json+="{\"uri\":\"file:$rel\",\"digest\":{\"sha256\":\"$h\"}}"
  done < <(collect_policy_files)
  deps_json+="]"

  local agg build_time commit dirty_flag
  agg=$(aggregate_hash)
  build_time=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  commit=$(git_rev)
  dirty_flag=$(git_dirty)
  local invocation_id
  invocation_id=$(uuidgen 2>/dev/null || echo manual-$(date +%s))

  if [[ -z "$SOURCE_URI" ]]; then
    SOURCE_URI="git+$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || echo unknown)#$commit"
  fi

  local json
  json=$(cat <<EOF
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [
    {"name": "${CHART_NAME}-${VERSION}.tgz", "digest": {"sha256": "${pkg_sha}"}}
  ],
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": {
    "buildDefinition": {
      "buildType": "${BUILD_TYPE}",
      "externalParameters": {
        "chartVersion": "${VERSION}",
        "aggregateIntegritySha256": "${agg}",
        "sourceUri": "${SOURCE_URI}",
        "gitCommit": "${commit}",
        "workspaceState": "${dirty_flag:-clean}"
      },
      "internalParameters": {},
      "resolvedDependencies": ${deps_json}
    },
    "runDetails": {
      "builder": {"id": "${BUILDER_ID}"},
      "metadata": {
        "invocationId": "${invocation_id}",
        "startedOn": "${build_time}",
        "finishedOn": "${build_time}"
      },
      "byproducts": [
        {"name": "aggregateIntegrity.sha256", "value": "${agg}"}
      ]
    }
  }
}
EOF
)

  if [[ -n "$OUT" ]]; then
    echo "$json" > "$OUT"
    echo "Provenance written to $OUT" >&2
  else
    echo "$json"
  fi
}

main "$@"
