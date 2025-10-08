#!/usr/bin/env bash
set -euo pipefail
# Package the chart with optional dependency build (non-fatal if no dependencies)
helm dependency build || true
helm package .
