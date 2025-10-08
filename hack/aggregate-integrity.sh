#!/usr/bin/env bash
set -euo pipefail

# aggregate-integrity.sh
# Compute an aggregated sha256 hash over all policy YAML files (kyverno, gatekeeper, gatekeeper-templates)
# in a deterministic order (lexicographic sort of relative paths).
# The hash is computed over the concatenation of normalized file contents:
#   * Trailing whitespace removed (rstrip)
#   * Single newline ensured between files and at end of stream
#   * Files whose basename contains 'placeholder' are excluded by default (toggleable)
#
# Formula: sha256( join("\n", map(norm(file_i)), "\n") )
#
# Default output: "aggregate-sha256 <hash> <fileCount>"
# Options:
#   --json            -> output JSON {"aggregateSha256":"<hash>","fileCount":N}
#   --include-placeholders -> do not exclude placeholder files
#   --print-files     -> list files (stdout, before the hash)
#   --files-only      -> only list files (no hash computation)
#   --help            -> show usage
#
# Examples:
#   bash hack/aggregate-integrity.sh
#   bash hack/aggregate-integrity.sh --json > integrity.json
#   HASH=$(bash hack/aggregate-integrity.sh | awk '{print $2}')
#

JSON=0
INCLUDE_PLACEHOLDERS=0
PRINT_FILES=0
FILES_ONLY=0

usage() { grep '^# ' "$0" | sed 's/^# \{0,1\}//'; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --json) JSON=1; shift;;
      --include-placeholders) INCLUDE_PLACEHOLDERS=1; shift;;
      --print-files) PRINT_FILES=1; shift;;
      --files-only) FILES_ONLY=1; shift;;
      -h|--help) usage; exit 0;;
      *) echo "Unknown arg: $1" >&2; exit 2;;
    esac
  done
}

collect_files() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  find "$root/files" \( -path '*/kyverno/*.yaml' -o -path '*/gatekeeper/*.yaml' -o -path '*/gatekeeper-templates/*.yaml' \) -type f -print | sort
}

normalize_and_concat() {
  local files=("$@")
  local first=1
  for f in "${files[@]}"; do
    # shellcheck disable=SC2002
    local content
    content=$(sed -e 's/[[:space:]]*$//' "$f")
    if [[ $first -eq 0 ]]; then
      printf '\n'
    fi
    first=0
    printf '%s' "$content"
  done
  printf '\n'
}

main() {
  parse_args "$@"
  if command -v mapfile >/dev/null 2>&1; then
    mapfile -t FILES < <(collect_files)
  else
    # macOS / older bash compatibility fallback
    FILES=()
    while IFS= read -r line; do FILES+=("$line"); done < <(collect_files)
  fi
  if (( INCLUDE_PLACEHOLDERS == 0 )); then
    local filtered=()
    for f in "${FILES[@]}"; do
      if [[ $(basename "$f") == *placeholder* ]]; then continue; fi
      filtered+=("$f")
    done
    FILES=("${filtered[@]}")
  fi

  if (( FILES_ONLY == 1 )); then
    printf '%s\n' "${FILES[@]}"
    exit 0
  fi

  if (( PRINT_FILES == 1 )); then
    printf '# Files (%d)\n' "${#FILES[@]}"
    for f in "${FILES[@]}"; do echo "$f"; done
  fi

  if ((${#FILES[@]}==0)); then
    echo "No policy YAML files found" >&2
    if (( JSON==1 )); then
      echo '{"aggregateSha256":null,"fileCount":0}'
    else
      echo 'aggregate-sha256 - 0'
    fi
    exit 0
  fi

  local agg
  agg=$(normalize_and_concat "${FILES[@]}" | sha256sum | awk '{print $1}')

  if (( JSON==1 )); then
    printf '{"aggregateSha256":"%s","fileCount":%d}\n' "$agg" "${#FILES[@]}"
  else
    printf 'aggregate-sha256 %s %d\n' "$agg" "${#FILES[@]}"
  fi
}

main "$@"
