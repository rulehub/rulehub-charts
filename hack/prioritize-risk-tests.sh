#!/usr/bin/env bash
set -euo pipefail
# Generate a prioritized test plan for policies based on risk classification.
# Output tiers (High, Medium, Low) with suggested test focus order.
# Optionally regenerate risk table first (default: yes) unless --no-regenerate passed.
# Usage: hack/prioritize-risk-tests.sh [--no-regenerate] [--format markdown|text|json] [--limit-low N]

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GEN_SCRIPT="$ROOT_DIR/hack/gen-risk-table.sh"
RISK_TABLE_MD="$ROOT_DIR/RISK_TABLE.md"
FORMAT=text
REGENERATE=1
LOW_LIMIT=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-regenerate) REGENERATE=0; shift;;
    --format) FORMAT="$2"; shift 2;;
    --limit-low) LOW_LIMIT="$2"; shift 2;;
    -h|--help)
      echo "Usage: $0 [--no-regenerate] [--format markdown|text|json] [--limit-low N]"; exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

if [[ $REGENERATE -eq 1 ]]; then
  bash "$GEN_SCRIPT" >/dev/null
fi

if [[ ! -f "$RISK_TABLE_MD" ]]; then
  echo "Risk table not found: $RISK_TABLE_MD" >&2
  exit 3
fi

# Parse rows (skip header lines starting with |----)
# Columns: Policy Key | Framework | Enforcement | Risk | Rationale
mapfile -t ROWS < <(grep '^|' "$RISK_TABLE_MD" | grep -v '^|----' | tail -n +3)

# Arrays to hold entries as TSV: key\tframework\tenforcement\trisk\trationale
ENTRIES=()
for row in "${ROWS[@]}"; do
  # strip leading/trailing | and spaces
  trimmed="${row#| }"; trimmed="${trimmed% |}"
  IFS='|' read -r key framework enforcement risk rationale <<<"$trimmed"
  key="${key// /}" # remove stray spaces around key
  framework="${framework// /}"
  enforcement="${enforcement// /}"
  risk="${risk// /}"
  rationale="${rationale# }"; rationale="${rationale% }"
  [[ -z "$key" || "$key" == "Policy Key" ]] && continue
  ENTRIES+=("$key\t$framework\t$enforcement\t$risk\t$rationale")
done

high=(); medium=(); low=()
for e in "${ENTRIES[@]}"; do
  IFS=$'\t' read -r key framework enforcement risk rationale <<<"$e"
  case "$risk" in
    High) high+=("$e");;
    Medium) medium+=("$e");;
    Low) low+=("$e");;
  esac
done

# Sort each tier deterministically by key
IFS=$'\n' high_sorted=($(printf '%s\n' "${high[@]}" | sort)); unset IFS
IFS=$'\n' medium_sorted=($(printf '%s\n' "${medium[@]}" | sort)); unset IFS
IFS=$'\n' low_sorted=($(printf '%s\n' "${low[@]}" | sort)); unset IFS

if [[ $FORMAT == json ]]; then
  printf '{"generated":"%s","tiers":{"high":[' "$(date -u +%FT%TZ)"
  first=1
  for e in "${high_sorted[@]}"; do
    IFS=$'\t' read -r key framework enforcement risk rationale <<<"$e"
    if [[ $first -eq 0 ]]; then printf ','; fi; first=0
    printf '{"key":"%s","framework":"%s","enforcement":"%s","risk":"%s","rationale":"%s"}' "$key" "$framework" "$enforcement" "$risk" "${rationale//"/\"}"
  done
  printf '],"medium":['
  first=1
  for e in "${medium_sorted[@]}"; do
    IFS=$'\t' read -r key framework enforcement risk rationale <<<"$e"
    if [[ $first -eq 0 ]]; then printf ','; fi; first=0
    printf '{"key":"%s","framework":"%s","enforcement":"%s","risk":"%s","rationale":"%s"}' "$key" "$framework" "$enforcement" "$risk" "${rationale//"/\"}"
  done
  printf '],"low":['
  first=1; count=0
  for e in "${low_sorted[@]}"; do
    ((count++)); [[ $count -gt $LOW_LIMIT ]] && break
    IFS=$'\t' read -r key framework enforcement risk rationale <<<"$e"
    if [[ $first -eq 0 ]]; then printf ','; fi; first=0
    printf '{"key":"%s","framework":"%s","enforcement":"%s","risk":"%s","rationale":"%s"}' "$key" "$framework" "$enforcement" "$risk" "${rationale//"/\"}"
  done
  printf ']},"notes":"Low tier truncated to %d (use --limit-low to change)"}\n' "$LOW_LIMIT"
  exit 0
fi

if [[ $FORMAT == markdown ]]; then
  echo '## Policy Test Priority Plan'
  echo
  echo '### Tier 1 (High Risk)'
  echo
  echo '| Policy | Framework | Enforcement | Rationale |'
  echo '|--------|-----------|-------------|-----------|'
  for e in "${high_sorted[@]}"; do
    IFS=$'\t' read -r key framework enforcement risk rationale <<<"$e"
    echo "| $key | $framework | $enforcement | $rationale |"
  done
  echo
  echo '### Tier 2 (Medium Risk)'
  echo
  echo '| Policy | Framework | Enforcement | Rationale |'
  echo '|--------|-----------|-------------|-----------|'
  for e in "${medium_sorted[@]}"; do
    IFS=$'\t' read -r key framework enforcement risk rationale <<<"$e"
    echo "| $key | $framework | $enforcement | $rationale |"
  done
  echo
  echo "### Tier 3 (Low Risk — top ${LOW_LIMIT})"
  echo
  echo '| Policy | Framework | Enforcement | Rationale |'
  echo '|--------|-----------|-------------|-----------|'
  count=0
  for e in "${low_sorted[@]}"; do
    ((count++)); [[ $count -gt $LOW_LIMIT ]] && break
    IFS=$'\t' read -r key framework enforcement risk rationale <<<"$e"
    echo "| $key | $framework | $enforcement | $rationale |"
  done
  echo
  echo '#### Suggested Execution Order'
  echo '1. All High policies (fail-fast)'
  echo '2. Medium policies (breadth)'
  echo '3. Rotating subset of Low policies (change-based or random sample)'
  exit 0
fi

# Plain text output
printf 'High Risk Policies (%d):\n' "${#high_sorted[@]}"
for e in "${high_sorted[@]}"; do IFS=$'\t' read -r key _ _ _ _ <<<"$e"; echo "  - $key"; done
printf '\nMedium Risk Policies (%d):\n' "${#medium_sorted[@]}"
for e in "${medium_sorted[@]}"; do IFS=$'\t' read -r key _ _ _ _ <<<"$e"; echo "  - $key"; done
printf '\nLow Risk Policies (top %d of %d):\n' "$LOW_LIMIT" "${#low_sorted[@]}"
count=0
for e in "${low_sorted[@]}"; do ((count++)); [[ $count -gt $LOW_LIMIT ]] && break; IFS=$'\t' read -r key _ _ _ _ <<<"$e"; echo "  - $key"; done

cat <<'EOF'

Suggested strategy:
1. Execute all High tier tests in parallel (gate admission & critical compliance).
2. Run Medium tier sequentially or batched; capture flaky candidates.
3. Sample Low tier (random N per run) to maintain baseline coverage without time explosion.
4. On policy change (git diff touches file), always elevate that policy to the front regardless of tier.
EOF
