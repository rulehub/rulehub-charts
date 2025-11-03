#!/usr/bin/env bash
set -euo pipefail

# verify-igaming-gk-hygiene.sh
# Purpose: lightweight hygiene checks for Gatekeeper ConstraintTemplates mapped to igaming.* policies.
# Checks (best-effort, no yq dependency):
#  1) If a template contains a deny message starting with igaming., ensure schema defines properties.requiredLabel: string.
#  2) Ensure the deny message prefix starts with "igaming." (consistency with external catalog and Constraints annotations).
#
# Exit codes: 0 ok, 1 issues found, 2 internal/script error

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="${SCRIPT_DIR%/hack}"

shopt -s nullglob
FILES=()
while IFS= read -r f; do
  [ -n "$f" ] && FILES+=("$f")
done < <(find "$REPO_ROOT/files/gatekeeper-templates" -maxdepth 1 -type f -name 'betting-*-constrainttemplate.yaml' | sort)

issues=()

for f in "${FILES[@]}"; do
  # Detect igaming mapping via deny message literal (keeps false positives low without heavy parsing)
  if ! grep -qE '^[[:space:]]*msg[[:space:]]*:=[[:space:]]*"igaming\.' "$f"; then
    continue
  fi

  # Check requiredLabel presence in schema
  if ! grep -qE '^[[:space:]]*requiredLabel:' "$f"; then
    issues+=("REQUIRED_LABEL_MISSING|$f|expected openAPIV3Schema.properties.requiredLabel: string")
  else
    # Heuristic: ensure type: string appears near requiredLabel (within next few lines)
    if ! awk 'BEGIN{found=0;ok=0;window=0} /^[[:space:]]*requiredLabel:[[:space:]]*$/ {found=1;window=6;next} found && window>0 { if ($0 ~ /^[[:space:]]*type:[[:space:]]*string/) ok=1; window-- } END{ exit(ok?0:1) }' "$f"; then
      # Fallback loose check: look for any "type: string" in file to avoid false negatives on formatting
      if ! grep -qE '^[[:space:]]*type:[[:space:]]*string' "$f"; then
        issues+=("REQUIRED_LABEL_TYPE_STRING_MISSING_NEARBY|$f|expected type: string for requiredLabel")
      fi
    fi
  fi

  # Validate message prefix is igaming.* (redundant with grep filter, but makes report explicit)
  msg=$(sed -nE 's/^[[:space:]]*msg[[:space:]]*:=[[:space:]]*"([^"]+)".*/\1/p' "$f" | head -n1 || true)
  if [[ -z "$msg" || ! "$msg" =~ ^igaming\. ]]; then
    issues+=("MSG_PREFIX_NOT_IGAMING|$f|msg=\"$msg\"")
  fi
done

if ((${#issues[@]})); then
  printf 'Igaming GK hygiene issues (%d):\n' "${#issues[@]}"
  for i in "${issues[@]}"; do
    IFS='|' read -r code file rest <<<"$i"
    printf '  - [%s] %s %s\n' "$code" "$file" "$rest"
  done
  exit 1
else
  echo "Igaming GK hygiene checks passed."
fi
