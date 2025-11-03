#!/usr/bin/env bash
set -euo pipefail
# Report frequency of labels and annotations across policy YAMLs.
# Helps identify candidates for centralization in helpers.

root_dir="$(dirname "$0")/.."
cd "$root_dir"

tmp_annotations=$(mktemp)
tmp_labels=$(mktemp)
trap 'rm -f "$tmp_annotations" "$tmp_labels"' EXIT

# Extract annotation keys
grep -R "^[[:space:]]\{0,6\}[A-Za-z0-9_.\-]\+:" files/ | \
  awk -F: '/annotations:/ {in_ann=1; next} /labels:/ {in_lab=1; next} { \
    if(in_ann){ if($0 ~ /^[[:space:]]{0,2}[A-Za-z0-9_.\-]+:/){print $0} else if($0 !~ /^[[:space:]]/){in_ann=0} } \
    if(in_lab){ if($0 ~ /^[[:space:]]{0,2}[A-Za-z0-9_.\-]+:/){print $0 > "/dev/stderr"} else if($0 !~ /^[[:space:]]/){in_lab=0} } \
  }' 1>"$tmp_annotations" 2>"$tmp_labels" || true

# Normalize & count
printf "Annotation key frequencies:\n" >&2
sed -E 's/^[[:space:]]*([A-Za-z0-9_.\-]+):.*/\1/' "$tmp_annotations" | sort | uniq -c | sort -nr
printf "\nLabel key frequencies:\n" >&2
sed -E 's/^[[:space:]]*([A-Za-z0-9_.\-]+):.*/\1/' "$tmp_labels" | sort | uniq -c | sort -nr

echo "\nTip: Consider moving most frequent keys into templates/_helpers.tpl if safe." >&2
