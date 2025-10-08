#!/usr/bin/env bash
set -euo pipefail
# Verifies VALUES_TABLE.md is up to date (ignoring generated timestamp line)

if [[ ! -f VALUES_TABLE.md ]]; then
  echo "VALUES_TABLE.md missing" >&2; exit 1; fi

cp VALUES_TABLE.md VALUES_TABLE.md.orig
./hack/gen-values-table.sh >/dev/null 2>&1 || { echo "Failed regenerating values table" >&2; rm -f VALUES_TABLE.md.orig; exit 1; }
# Strip timestamp lines for diff stability
grep -v 'Generated on' VALUES_TABLE.md.orig > .vt_old || true
grep -v 'Generated on' VALUES_TABLE.md > .vt_new || true
if ! diff -u .vt_old .vt_new >/dev/null; then
  echo "VALUES_TABLE.md outdated. Run: make values-table" >&2
  rm -f VALUES_TABLE.md.orig .vt_old .vt_new
  exit 1
fi
rm -f VALUES_TABLE.md.orig .vt_old .vt_new
exit 0
