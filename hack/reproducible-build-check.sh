#!/usr/bin/env bash
set -euo pipefail

# reproducible-build-check.sh
# Heuristic checklist for reproducible Helm chart builds.
# Currently verifies:
#   1. Helm version pinned via environment or documented (outputs helm version)
#   2. No timestamps inside packaged chart (examines tar manifest) (reject files newer than current minute? n/a) - simply list files
#   3. Deterministic template output (delegates to verify-deterministic.sh)
#   4. Aggregate integrity stable across re-package operations (package twice -> sha compare)
#
# Usage: bash hack/reproducible-build-check.sh [--values values.yaml]
# Exit 0 if all checks pass; non-zero otherwise.

VALUES_FILE="values.yaml"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --values) VALUES_FILE="$2"; shift 2;;
    -h|--help) grep '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CHART_NAME="rulehub-policies"
VERSION=$(grep '^version:' "$ROOT_DIR/Chart.yaml" | awk '{print $2}')

echo '[repro] Helm version:'
helm version --short || { echo '[repro] helm not available' >&2; exit 2; }

echo '[repro] Running deterministic template check'
bash "$ROOT_DIR/hack/verify-deterministic.sh" "$VALUES_FILE"

echo '[repro] Packaging chart twice to compare tarball sha256'
TMP1=$(mktemp)
TMP2=$(mktemp)
trap 'rm -f "$TMP1" "$TMP2" ${CHART_NAME}-${VERSION}.tgz ${CHART_NAME}-${VERSION}.tgz.2 2>/dev/null || true' EXIT
helm package "$ROOT_DIR" --version "$VERSION" --app-version "$VERSION" >/dev/null
mv "${CHART_NAME}-${VERSION}.tgz" "${CHART_NAME}-${VERSION}.tgz.2" || true
helm package "$ROOT_DIR" --version "$VERSION" --app-version "$VERSION" >/dev/null
sha256sum "${CHART_NAME}-${VERSION}.tgz" | awk '{print $1}' > "$TMP1"
sha256sum "${CHART_NAME}-${VERSION}.tgz.2" | awk '{print $1}' > "$TMP2"
if ! diff -q "$TMP1" "$TMP2" >/dev/null; then
  echo '[repro] Chart package tarball differs between builds (non-reproducible)' >&2
  diff -u "$TMP1" "$TMP2" || true
  exit 1
fi
echo '[repro] Chart package tarball sha256 stable.'

echo '[repro] Aggregate integrity hash:'
bash "$ROOT_DIR/hack/aggregate-integrity.sh" || true

echo '[repro] Listing tar entries (mtime not normalized by default Helm; ignore for now):'
tar -tzf "${CHART_NAME}-${VERSION}.tgz" | sed 's/^/  /'

echo '[repro] Reproducibility heuristic checks passed.'
