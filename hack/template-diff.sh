#!/usr/bin/env bash
set -euo pipefail

# template-diff.sh
# Local helm template diff between current working tree (NEW) and an older git ref (OLD).
# Provides a normalized unified (or side-by-side) diff to review template impact of changes
# without needing a packaged chart. Similar to pseudo-diff-template.sh but sources the
# previous version from git directly.
#
# Usage:
#   hack/template-diff.sh --ref <git-ref> [--values values.yaml] [--context 5] [--y] [--no-color]
# Examples:
#   hack/template-diff.sh --ref v0.2.0
#   hack/template-diff.sh --ref main~1 --values examples/values-minimal.yaml
#   hack/template-diff.sh --ref v0.1.0 --y   # side-by-side view
#
# Exit codes:
#  0 diff produced (or no differences)
#  2 usage / parameter error
#  3 git / helm issues

REF=""
VALUES_FILE="values.yaml"
CTX=5
SIDE_BY_SIDE=0
COLOR=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ref) REF="$2"; shift 2;;
    --values) VALUES_FILE="$2"; shift 2;;
    --context) CTX="$2"; shift 2;;
    --y) SIDE_BY_SIDE=1; shift;;
    --no-color) COLOR=0; shift;;
    -h|--help) sed -n '1,50p' "$0"; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ -z "$REF" ]]; then
  echo "--ref <git-ref> required" >&2
  exit 2
fi

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "Values file $VALUES_FILE not found" >&2
  exit 2
fi

if ! git rev-parse --verify "$REF^{commit}" >/dev/null 2>&1; then
  echo "Git ref $REF not found" >&2
  exit 3
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Extract the chart at the ref into temp directory
git archive "$REF" | tar -x -C "$TMP_DIR"

OLD_DIR="$TMP_DIR"
OLD_OUT="$TMP_DIR/old.render.yaml"
NEW_OUT="$TMP_DIR/new.render.yaml"

helm template rulehub "$OLD_DIR" --values "$VALUES_FILE" > "$OLD_OUT"
helm template rulehub . --values "$VALUES_FILE" > "$NEW_OUT"

normalize() {
  sed -E 's/[[:space:]]+$//' "$1" | \
    grep -v '^# Source: ' | \
    awk 'NF>0 || last_blank==0 {print; last_blank = (NF==0)}' | \
    sed -E 's/([Cc]reation[Tt]imestamp:).*/\1 <normalized>/'
}

normalize "$OLD_OUT" > "$OLD_OUT.norm"
normalize "$NEW_OUT" > "$NEW_OUT.norm"

if diff -q "$OLD_OUT.norm" "$NEW_OUT.norm" >/dev/null; then
  echo "No differences in rendered manifests (after normalization)."
  exit 0
fi

DIFF_CMD=(diff)
if command -v gdiff >/dev/null 2>&1; then
  DIFF_CMD=(gdiff)
fi

if [[ $SIDE_BY_SIDE -eq 1 ]]; then
  DIFF_ARGS=("-y" "-W" "200")
else
  DIFF_ARGS=("-u" "-U" "$CTX")
fi

if [[ $COLOR -eq 1 ]] && (${DIFF_CMD[@]} --help 2>&1 | grep -q -- '--color'); then
  DIFF_ARGS=("--color=always" "${DIFF_ARGS[@]}")
fi

${DIFF_CMD[@]} "${DIFF_ARGS[@]}" "$OLD_OUT.norm" "$NEW_OUT.norm" || true

added=$(grep '^+kind:' "$NEW_OUT.norm" | wc -l || true)
removed=$(grep '^-kind:' "$NEW_OUT.norm" | wc -l || true)
echo "Summary: added kind lines: $added, removed kind lines: $removed" >&2
