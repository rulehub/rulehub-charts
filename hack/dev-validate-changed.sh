#!/usr/bin/env bash
set -euo pipefail

# dev-validate-changed.sh
# Quick developer helper: validate ONLY changed YAML policy/template files relative to a base ref.
#
# Checks performed per changed YAML under files/ (excluding deletions):
#   1. YAML parses (yq eval '.')
#   2. For policy files (files/{kyverno,gatekeeper,gatekeeper-templates}), presence of 'rulehub.id:' annotation
#   3. Detect unquoted angle-bracket placeholders like <something> (simple heuristic) outside of comments
#   4. Optional: basic DNS-1123 validation of metadata.name if present (k8s style)
#
# Usage:
#   hack/dev-validate-changed.sh [--base <git-ref>] [--staged] [--all]
#
#   --base <ref>   Git ref to diff against (default: origin/main if exists, else HEAD~1)
#   --staged       Use staged (index) changes instead of working tree diff
#   --all          Validate all policy YAMLs (shortcut to existing full scripts)
#
# Exit codes:
#   0 success / nothing to validate
#   1 failures found
#   2 script usage / environment issue
#
# Notes:
#   - Designed for fast local feedback before full 'make verify'.
#   - Does not attempt full schema validation (run make verify for exhaustive checks).

BASE_REF=""
MODE="work"
ALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      BASE_REF="$2"; shift 2 ;;
    --staged)
      MODE="staged"; shift ;;
    --all)
      ALL=1; shift ;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //'; exit 0 ;;
    *)
      echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if (( ALL )); then
  echo "[dev-validate] --all specified -> deferring to full verify suite subset (id-annotations + render)" >&2
  bash "$(dirname "$0")/verify-id-annotation.sh"
  exit $?
fi

if [[ -z "$BASE_REF" ]]; then
  if git rev-parse --verify origin/main >/dev/null 2>&1; then
    BASE_REF=origin/main
  else
    BASE_REF=$(git rev-parse HEAD~1 2>/dev/null || git rev-parse HEAD)
  fi
fi

echo "[dev-validate] Base ref: $BASE_REF (mode: $MODE)" >&2

if ! git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
  echo "Base ref '$BASE_REF' not found" >&2; exit 2
fi

diff_cmd=(git diff --name-status "$BASE_REF" --)
if [[ $MODE == staged ]]; then
  diff_cmd=(git diff --cached --name-status "$BASE_REF" --)
fi

mapfile -t CHANGED < <("${diff_cmd[@]}" | awk '/\.(ya?ml)$/ {print}')

POLICY_DIR_REGEX='^files/(kyverno|gatekeeper|gatekeeper-templates)/.*\.ya?ml$'

files_to_check=()
while IFS=$'\t' read -r status path; do
  # status can be e.g. M, A, D, R100
  if [[ $status == D* ]]; then
    continue
  fi
  [[ $path =~ \.ya?ml$ ]] || continue
  if [[ -f $path ]]; then
    files_to_check+=("$path")
  fi
done < <("${diff_cmd[@]}")

if ((${#files_to_check[@]}==0)); then
  echo "[dev-validate] No changed YAML files under current diff scope." >&2
  exit 0
fi

echo "[dev-validate] Files to validate: ${#files_to_check[@]}" >&2
for f in "${files_to_check[@]}"; do
  echo "  - $f" >&2
done

yaml_fail=()
annotation_fail=()
placeholder_fail=()
name_fail=()

DNS1123='^[a-z0-9]([-a-z0-9]*[a-z0-9])?$'

for file in "${files_to_check[@]}"; do
  # 1. YAML parse
  if ! yq eval '.' "$file" >/dev/null 2>&1; then
    yaml_fail+=("$file")
    continue  # Other checks may be noisy if parse fails
  fi

  # 2. rulehub.id annotation for policy files
  if [[ $file =~ $POLICY_DIR_REGEX ]]; then
    if ! grep -qE '^[[:space:]]*rulehub.id:' "$file"; then
      annotation_fail+=("$file")
    fi
  fi

  # 3. Unquoted <placeholder> heuristic (lines with <...> not inside quotes and not comments)
  if grep -qE '\<(.*)\>' "$file"; then
    # allow lines where < > are inside single or double quotes
    while IFS= read -r line; do
      [[ $line =~ ^[[:space:]]*# ]] && continue
      if [[ $line =~ <[^[:space:]>][^>]*> ]]; then
        # If line contains quotes around the first < we skip
        if ! grep -qE "['\"]<[^>]+>['\"]" <<<"$line"; then
          placeholder_fail+=("$file")
          break
        fi
      fi
    done < "$file"
  fi

  # 4. metadata.name basic DNS-1123 (only if present)
  name=$(yq -r '.metadata.name // ""' "$file" 2>/dev/null || echo "")
  if [[ -n $name ]] && ! [[ $name =~ $DNS1123 ]] ; then
    name_fail+=("$file:$name")
  fi

done

rc=0
if ((${#yaml_fail[@]})); then
  echo "\n[YAML Parse Failures]" >&2
  printf ' - %s\n' "${yaml_fail[@]}" >&2
  rc=1
fi
if ((${#annotation_fail[@]})); then
  echo "\n[Missing rulehub.id annotation]" >&2
  printf ' - %s\n' "${annotation_fail[@]}" >&2
  rc=1
fi
if ((${#placeholder_fail[@]})); then
  echo "\n[Unquoted angle bracket placeholders detected] (quote them to avoid Helm/YAML parse issues)" >&2
  printf ' - %s\n' "${placeholder_fail[@]}" >&2
  rc=1
fi
if ((${#name_fail[@]})); then
  echo "\n[Non DNS-1123 metadata.name values]" >&2
  printf ' - %s\n' "${name_fail[@]}" >&2
  rc=1
fi

if (( rc == 0 )); then
  echo "[dev-validate] OK: no issues detected in changed YAMLs." >&2
fi
exit $rc
