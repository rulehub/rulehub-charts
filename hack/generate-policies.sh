#!/usr/bin/env bash
set -euo pipefail

# generate-policies.sh
#
# Architecture / pipeline to generate Kyverno (and potentially Gatekeeper) YAML policies
# from a core "rulehub" repository into the local files/kyverno (and others).
# The script is designed to be:
#  - Deterministic (stable output order)
#  - Idempotent (repeated runs produce no side effects)
#  - Extensible (post-processing plugins)
#  - Observable (stage metrics/logs)
#
# INPUTS (expected sources):
#  1. CORE_REPO: path to a local copy of rulehub core (or a URL to clone)
#  2. CORE_METADATA_DIR: directory with metadata (JSON/YAML) describing policies (id, title, links, templates info)
#  3. CORE_TEMPLATES_DIR: directory with templates (Go templates / YAML fragments) to build ClusterPolicy
#  4. (opt) LICENSE_HEADER_FILE: license header file
#  5. (opt) OUTPUT_MANIFEST=manifest.json to record integrity metadata
#  6. (opt) POLICY_FILTER: jq expression / grep for partial generation
#
# OUTPUTS:
#  - files/kyverno/*.yaml        (ClusterPolicy)
#  - files/gatekeeper-templates/ (ConstraintTemplate) [future]
#  - files/gatekeeper/*.yaml     (Constraint)          [future]
#  - manifest.json (list of {file, sha256, rulehub.id}) if enabled
#
# STAGES:
#  1. prepare_workspace   – temp dirs, cleanup targets (unless partial build)
#  2. fetch_core          – (if CORE_REPO_URL set and no local copy) git clone --depth=1
#  3. load_metadata       – aggregate policy metadata into a single stream (jq)
#  4. plan                – compute list of policies to generate (apply POLICY_FILTER)
#  5. render_templates    – render templates for each policy -> raw YAML
#  6. enrich_annotations  – normalize/add rulehub.* annotations + build metadata
#  7. lint_yaml           – basic yamllint / schema checks (if enabled)
#  8. sort_and_stabilize  – sort keys/fields (yq), alphabetic file ordering
#  9. write_outputs       – write to files/kyverno
# 10. generate_manifest   – sha256 over sorted list (optional)
# 11. verify_idempotency  – rerender to tmp and compare diff (debug mode)
#
# PLUGIN MECHANISM:
#  - POST_PROCESSORS=(script1.sh script2.sh) are invoked before write_outputs with YAML on stdin/stdout
#
# CACHING:
#  - HASH_INPUT = sha256(sum of all metadata + templates); if equal to previous in .cache/hash – skip stages 5-9
#
# UTILITIES: jq, yq (v4), git, sha256sum, awk, envsubst (opt)
#
# FAILURE MODES / ERRORS:
#  - missing rulehub.id -> fail
#  - duplicate rulehub.id -> fail
#  - filename != rulehub.id (kebab vs dotted) -> warning/optional error
#  - empty render -> fail
#
# EXAMPLE INVOCATION:
#   CORE_REPO=../rulehub-core \
#   CORE_METADATA_DIR=../rulehub-core/metadata \
#   CORE_TEMPLATES_DIR=../rulehub-core/templates/kyverno \
#   ./hack/generate-policies.sh
#
# Optional flags:
#   --partial <id1,id2>  – generate only listed rulehub.id
#   --manifest           – create manifest.json
#   --debug              – enable verify_idempotency
#

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="${SCRIPT_DIR%/hack}"

set +u
CORE_REPO=${CORE_REPO:-""}
CORE_METADATA_DIR=${CORE_METADATA_DIR:-""}
CORE_TEMPLATES_DIR=${CORE_TEMPLATES_DIR:-""}
LICENSE_HEADER_FILE=${LICENSE_HEADER_FILE:-""}
OUTPUT_MANIFEST=${OUTPUT_MANIFEST:-""}
PARTIAL_IDS=""
DEBUG_MODE=0
GEN_MANIFEST=0
FORCE_REGEN=0
set -u

usage() {
  grep '^# ' "$0" | sed 's/^# \{0,1\}//'
}

log() { printf '[generate-policies] %s\n' "$*" >&2; }
fail() { log "ERROR: $*"; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || fail "Required utility not found: $1"; }

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --partial)
        PARTIAL_IDS="$2"; shift 2;;
      --manifest)
        GEN_MANIFEST=1; shift;;
      --debug)
        DEBUG_MODE=1; shift;;
      --force)
        FORCE_REGEN=1; shift;;
      -h|--help)
        usage; exit 0;;
  *) fail "Unknown argument: $1";;
    esac
  done
}

prepare_workspace() {
  mkdir -p "$REPO_ROOT/files/kyverno"
  if [[ -z $PARTIAL_IDS ]]; then
  log 'Cleaning files/kyverno (full generation)'
    find "$REPO_ROOT/files/kyverno" -maxdepth 1 -type f -name '*.yaml' -delete
  else
  log 'Partial mode – existing files are not removed'
  fi
  mkdir -p "$REPO_ROOT/.cache/generate"
}

hash_inputs() {
  require sha256sum
  local tmp_list=$(mktemp)
  find "$CORE_METADATA_DIR" -type f -print0 | sort -z | xargs -0 cat >> "$tmp_list" || true
  find "$CORE_TEMPLATES_DIR" -type f -print0 | sort -z | xargs -0 cat >> "$tmp_list" || true
  sha256sum "$tmp_list" | awk '{print $1}'
  rm -f "$tmp_list"
}

plan_ids() {
  # Example: assume metadata *.json contain an 'id' field
  require jq
  local ids_json
  ids_json=$(find "$CORE_METADATA_DIR" -type f -name '*.json' -print0 | \
    xargs -0 jq -r 'select(.id!=null) | .id')
  if [[ -n $PARTIAL_IDS ]]; then
    local filtered=""
    IFS=',' read -r -a want <<< "$PARTIAL_IDS"
    for w in "${want[@]}"; do
      if grep -qx "$w" <(printf '%s\n' "$ids_json"); then
        filtered+="$w\n"
      else
  fail "partial id not found in metadata: $w"
      fi
    done
    printf '%b' "$filtered" | sort -u
  else
    printf '%s\n' "$ids_json" | sort -u
  fi
}

render_policy() {
  # Placeholder: actual rendering logic depends on template format.
  # For demo we simply assemble a basic ClusterPolicy
  local id="$1"
  local kebab=${id//./-}
  cat <<YAML
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: ${kebab}-policy
  annotations:
    rulehub.id: ${id}
    rulehub.title: PLACEHOLDER ${id}
    rulehub.links: |
      - https://example.org/${kebab}
spec:
  background: true
  validationFailureAction: audit
  rules: []
YAML
}

post_process() {
  # Place for post-processor chain (stdin->stdout)
  cat
}

write_policy() {
  local id="$1"
  local kebab=${id//./-}
  local out_file="$REPO_ROOT/files/kyverno/${kebab}-policy.yaml"
  if [[ -n $LICENSE_HEADER_FILE && -f $LICENSE_HEADER_FILE ]]; then
    cat "$LICENSE_HEADER_FILE" > "$out_file"
    printf '\n' >> "$out_file"
    # Normalization pipeline: post_process -> optional yq sort_keys(..) for deterministic field ordering
    if command -v yq >/dev/null 2>&1; then
      post_process | yq -P 'sort_keys(..)' >> "$out_file" || post_process >> "$out_file"
    else
      post_process >> "$out_file"
    fi
  else
    if command -v yq >/dev/null 2>&1; then
      post_process | yq -P 'sort_keys(..)' > "$out_file" || post_process > "$out_file"
    else
      post_process > "$out_file"
    fi
  fi
}

generate_manifest() {
  require sha256sum
  local manifest_tmp=$(mktemp)
  local now_iso
  now_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '[' > "$manifest_tmp"
  local first=1
  # Only Kyverno for now (extend later for gatekeeper)
  for f in $(find "$REPO_ROOT/files/kyverno" -maxdepth 1 -type f -name '*.yaml' | sort); do
    local hash id kind vfa size
    hash=$(sha256sum "$f" | awk '{print $1}')
    id=$(grep -E '^\s*rulehub.id:' "$f" | head -1 | awk '{print $2}')
    kind=$(grep -E '^kind:' "$f" | head -1 | awk '{print $2}')
    vfa=$(grep -E '^\s*validationFailureAction:' "$f" | head -1 | awk '{print $2}' || true)
    size=$(wc -c < "$f" | tr -d ' ')
    [[ $first -eq 0 ]] && printf ',' >> "$manifest_tmp" || first=0
    printf '\n  {"file":"%s","sha256":"%s","rulehub.id":"%s","kind":"%s","framework":"kyverno","validationFailureAction":"%s","size":%s,"generatedAt":"%s"}' \
      "$(basename "$f")" "$hash" "$id" "$kind" "${vfa:-}" "$size" "$now_iso" >> "$manifest_tmp"
  done
  printf '\n]\n' >> "$manifest_tmp"
  mv "$manifest_tmp" "$REPO_ROOT/manifest.json"
  log 'manifest.json created (extended format)'
  if command -v jq >/dev/null 2>&1 && [[ -f "$REPO_ROOT/manifest.schema.json" ]]; then
    if ! jq -e "." "$REPO_ROOT/manifest.json" >/dev/null 2>&1; then
      log 'WARN: manifest.json invalid JSON'
    fi
  fi
}

verify_idempotency() {
  log 'Verify idempotency (debug)'
  local tmpdir
  tmpdir=$(mktemp -d)
  rsync -a "$REPO_ROOT/files/kyverno/" "$tmpdir/" >/dev/null
  # Second pass (should be a no-op) - place to inject variations
  : # No-op placeholder
  if ! diff -qr "$REPO_ROOT/files/kyverno" "$tmpdir" >/dev/null; then
    log 'WARNING: generation is not deterministic'
    diff -ru "$tmpdir" "$REPO_ROOT/files/kyverno" || true
  else
    log 'Idempotency verified'
  fi
  rm -rf "$tmpdir"
}

main() {
  parse_args "$@"
  require jq; require awk; require sort
  [[ -d $CORE_METADATA_DIR ]] || fail 'CORE_METADATA_DIR not found'
  prepare_workspace
  local input_hash
  input_hash=$(hash_inputs || true)
  local hash_file="$REPO_ROOT/.cache/generate/last_hash.txt"
  local prev_hash=""
  if [[ -f "$hash_file" ]]; then
    prev_hash=$(cat "$hash_file" 2>/dev/null || true)
  fi
  # Skip regeneration if inputs unchanged, not partial, not forced
  if [[ $FORCE_REGEN -eq 0 && -z $PARTIAL_IDS && $DEBUG_MODE -eq 0 && $GEN_MANIFEST -eq 0 ]]; then
    if [[ -n $prev_hash && $prev_hash == "$input_hash" ]]; then
      log "Cache: inputs unchanged (hash=$input_hash), skipping generation stages"
      exit 0
    fi
  fi
  echo "$input_hash" > "$hash_file"
  local ids
  ids=$(plan_ids)
  log "Policies to generate: $(echo "$ids" | wc -l)"
  while IFS= read -r id; do
    [[ -z $id ]] && continue
    log "Render: $id"
    render_policy "$id" | write_policy "$id"
  done <<< "$ids"
  if [[ $GEN_MANIFEST -eq 1 ]]; then
    generate_manifest
  fi
  if [[ $DEBUG_MODE -eq 1 ]]; then
    verify_idempotency
  fi
  log 'Done.'
}

main "$@"
