#!/usr/bin/env bash
set -euo pipefail

# suggest-semver-bump.sh
# Heuristically proposes next SemVer (major|minor|patch) based on a list of change lines.
#
# INPUT SOURCES (first non-empty wins):
#  1. --file <path>  : Read change log style lines from file
#  2. STDIN (if piped)
#  3. --string "multiline text"
#
# LINE CLASSIFICATION (case-insensitive, leading token before colon or bracket considered):
#  Major triggers (any => MAJOR):
#    Removed:, Breaking:, BREAKING CHANGE, Major:, Renamed Policy:, Policy Removed:
#  Minor triggers (if no Major and any => MINOR):
#    Added:, Add:, New:, Changed:, Change:, Deprecated:, Security:, Enforcement Elevated:, Policy Added:
#  Patch triggers (if no Major/Minor and any => PATCH):
#    Fix:, Fixed:, Bug:, Docs:, Doc:, Documentation:, Refactor:, Chore:, Maintenance:
#
# Additional policy‑specific heuristics:
#  - "enforce -> audit" downgrade treated as MINOR (behavior loosens)
#  - "audit -> enforce" upgrade treated as MINOR (potentially disruptive but not outright removal)
#  - If both additions and removals present -> MAJOR
#
# OUTPUT:
#  JSON summary to stdout, e.g. {"current":"0.1.0","suggested":"0.2.0","level":"minor"}
#  Human readable explanation to stderr.
#
# USAGE:
#   hack/suggest-semver-bump.sh --file changes.txt
#   cat changes.txt | hack/suggest-semver-bump.sh
#   hack/suggest-semver-bump.sh --string $'Added: new policy\nFix: typo'

CHANGES_INPUT=""
FILE_INPUT=""
STRING_INPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      FILE_INPUT="$2"; shift 2;;
    --string)
      STRING_INPUT="$2"; shift 2;;
    -h|--help)
      grep '^# ' "$0" | sed 's/^# //'; exit 0;;
    *)
      echo "Unknown argument: $1" >&2; exit 1;;
  esac
done

if [[ -n "$FILE_INPUT" ]]; then
  if [[ ! -f "$FILE_INPUT" ]]; then
    echo "File not found: $FILE_INPUT" >&2; exit 1
  fi
  CHANGES_INPUT="$(<"$FILE_INPUT")"
elif [[ -n "$STRING_INPUT" ]]; then
  CHANGES_INPUT="$STRING_INPUT"
elif [[ ! -t 0 ]]; then
  CHANGES_INPUT="$(cat)"
else
  echo "No input provided. Use --file, --string or pipe data." >&2; exit 1
fi

CHANGES_INPUT_TRIMMED="$(echo "$CHANGES_INPUT" | sed '/^[[:space:]]*$/d')"
if [[ -z "$CHANGES_INPUT_TRIMMED" ]]; then
  echo "Input empty after trimming." >&2; exit 1
fi

# Read current version from Chart.yaml
CURRENT_VERSION=$(grep -E '^version:' Chart.yaml | awk '{print $2}')
if [[ -z "$CURRENT_VERSION" ]]; then
  echo "Unable to parse current version from Chart.yaml" >&2; exit 1
fi

major_triggers=0
minor_triggers=0
patch_triggers=0
has_add=0
has_remove=0

while IFS= read -r line; do
  ltrim="$(echo "$line" | sed -E 's/^[[:space:]]+//')"
  lower="$(echo "$ltrim" | tr 'A-Z' 'a-z')"
  [[ -z "$lower" ]] && continue
  case "$lower" in
    removed:*|breaking:*|breaking\ change*|major:*|renamed\ policy:*|policy\ removed:*)
      major_triggers=1;;
  esac
  case "$lower" in
    added:*|add:*|new:*|changed:*|change:*|deprecated:*|security:*|enforcement\ elevated:*|policy\ added:*)
      minor_triggers=1;;
  esac
  case "$lower" in
    fix:*|fixed:*|bug:*|docs:*|doc:*|documentation:*|refactor:*|chore:*|maintenance:*)
      patch_triggers=1;;
  esac
  [[ "$lower" =~ added:|add:|new:|policy\ added: ]] && has_add=1 || true
  [[ "$lower" =~ removed:|policy\ removed: ]] && has_remove=1 || true
  if [[ "$lower" =~ audit[[:space:]]*-[>]?[[:space:]]*enforce ]]; then
    minor_triggers=1
  fi
  if [[ "$lower" =~ enforce[[:space:]]*-[>]?[[:space:]]*audit ]]; then
    minor_triggers=1
  fi
done <<< "$CHANGES_INPUT_TRIMMED"

level="patch"
if (( major_triggers == 1 )); then
  level="major"
elif (( has_add == 1 && has_remove == 1 )); then
  level="major"
elif (( minor_triggers == 1 )); then
  level="minor"
elif (( patch_triggers == 1 )); then
  level="patch"
fi

IFS='.' read -r MAJ MIN PAT <<< "$CURRENT_VERSION"
case "$level" in
  major)
    ((MAJ+=1)); MIN=0; PAT=0;;
  minor)
    ((MIN+=1)); PAT=0;;
  patch)
    ((PAT+=1));;
esac
SUGGESTED_VERSION="${MAJ}.${MIN}.${PAT}"

echo "{"\n"  \"current\": \"$CURRENT_VERSION\","\n"  \"suggested\": \"$SUGGESTED_VERSION\","\n"  \"level\": \"$level\""\n"}" | tr -d '\n' | sed 's/}/}\n/'

{
  echo "Detected triggers -> major:$major_triggers minor:$minor_triggers patch:$patch_triggers add:$has_add remove:$has_remove" >&2
  echo "Proposed $level bump: $CURRENT_VERSION -> $SUGGESTED_VERSION" >&2
} || true
