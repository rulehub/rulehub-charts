#!/usr/bin/env bash
set -euo pipefail

# Generate RuleHub Backstage plugin index (dist/index.json) from manifest.json
# - Groups by rulehub.id
# - Emits id, name (same as id), kyvernoPath, gatekeeperPath, repoPath
# - Paths are repo-relative and point to tracked sources under files/
# - Deterministic ordering by id

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="${ROOT_DIR}/manifest.json"
OUT_DIR="${ROOT_DIR}/dist"
OUT_FILE="${OUT_DIR}/index.json"
# Optional metadata files to enrich packages with display fields
# Back-compat: METADATA_JSON (single file) still supported.
# New: METADATA_JSONS may contain a space-separated list of files to merge in order (last wins).
# Defaults: prefer merging core repo metadata (if present) with local charts metadata (local wins).
DEFAULT_METADATA_JSON="${ROOT_DIR}/metadata/plugin-index-metadata.json"
CORE_METADATA_JSON="${ROOT_DIR}/../rulehub/dist/plugin-index-metadata.json"
# Also consider core full index as a metadata source to pick fields like severity
CORE_INDEX_JSON="${ROOT_DIR}/../rulehub/dist/index.json"
METADATA_JSON="${METADATA_JSON:-}"
METADATA_JSONS_VAR="${METADATA_JSONS:-}"

merge_metadata_files() {
  # args: list of json files to merge, left-to-right (later overrides)
  local out_file="$1"; shift
  local files=("$@")
  # Build jq input dynamically; jq -s reads all docs into an array
  # Merge strategy: concatenate all .packages arrays, group_by(.id), then reduce with last-wins.
  jq -s '
    reduce .[] as $doc ([]; . + ($doc.packages // []))
    | group_by(.id)
    | map(reduce .[] as $p ({}; . * $p))
    | { packages: . }
  ' "${files[@]}" >"${out_file}"
}

# Resolve which metadata sources to use
TMP_MERGED=""
if [[ -n "${METADATA_JSONS_VAR}" ]]; then
  # Use explicit list; filter only existing files
  read -r -a CANDIDATES <<<"${METADATA_JSONS_VAR}"
  EXISTING=()
  for f in "${CANDIDATES[@]}"; do
    [[ -f "$f" ]] && EXISTING+=("$f")
  done
  if [[ ${#EXISTING[@]} -gt 0 ]]; then
    TMP_MERGED="$(mktemp)" || TMP_MERGED="${OUT_DIR}/.metadata.merged.json"
    merge_metadata_files "${TMP_MERGED}" "${EXISTING[@]}"
    METADATA_JSON="${TMP_MERGED}"
  fi
elif [[ -n "${METADATA_JSON}" ]]; then
  # Single explicit file already set; nothing to do
  :
else
  # No explicit env: build sensible defaults
  if [[ -f "${CORE_INDEX_JSON}" || -f "${CORE_METADATA_JSON}" || -f "${DEFAULT_METADATA_JSON}" ]]; then
    # Build list in increasing precedence (last wins): core index -> core plugin metadata -> local metadata
    files_to_merge=()
    [[ -f "${CORE_INDEX_JSON}" ]] && files_to_merge+=("${CORE_INDEX_JSON}")
    [[ -f "${CORE_METADATA_JSON}" ]] && files_to_merge+=("${CORE_METADATA_JSON}")
    [[ -f "${DEFAULT_METADATA_JSON}" ]] && files_to_merge+=("${DEFAULT_METADATA_JSON}")
    if [[ ${#files_to_merge[@]} -gt 0 ]]; then
      TMP_MERGED="$(mktemp)" || TMP_MERGED="${OUT_DIR}/.metadata.merged.json"
      merge_metadata_files "${TMP_MERGED}" "${files_to_merge[@]}"
      METADATA_JSON="${TMP_MERGED}"
    fi
  elif [[ -f "${DEFAULT_METADATA_JSON}" ]]; then
    METADATA_JSON="${DEFAULT_METADATA_JSON}"
  elif [[ -f "${CORE_METADATA_JSON}" ]]; then
    METADATA_JSON="${CORE_METADATA_JSON}"
  fi
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

if [[ ! -f "${MANIFEST}" ]]; then
  echo "ERROR: manifest.json not found at ${MANIFEST}" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"

# Build the packages array from manifest.json (base set)
jq '
  sort_by(."rulehub.id")
  | group_by(."rulehub.id")
  | map(
      {
        id: .[0]."rulehub.id",
        name: .[0]."rulehub.id",
        kyvernoFile: ([ .[] | select(.framework == "kyverno") | .file ] | first),
        gatekeeperFile: ([ .[] | select(.framework == "gatekeeper" or .framework == "gatekeeper-template") | .file ] | first)
      }
      | {
          id,
          name,
          kyvernoPath: (if .kyvernoFile then ("files/kyverno/" + .kyvernoFile) else null end),
          gatekeeperPath: (if .gatekeeperFile then ("files/" + .gatekeeperFile) else null end),
          repoPath: (if .kyvernoFile then ("files/kyverno/" + .kyvernoFile) else (if .gatekeeperFile then ("files/" + .gatekeeperFile) else null end) end)
        }
      | with_entries(select(.value != null))
    )
  | sort_by(.id)
' "${MANIFEST}" \
| jq -S '{ packages: . }' \
> "${OUT_FILE}.tmp.base"

# If metadata file is available, merge fields into packages by id
if [[ -n "${METADATA_JSON}" && -f "${METADATA_JSON}" ]]; then
  echo "Merging metadata from ${METADATA_JSON}"
  jq -s '
      def tc(s): (s | gsub("[^A-Za-z0-9]+";" ") | split(" ") | map(select(. != "")) | map((.[0:1] | ascii_upcase) + (.[1:] | ascii_downcase)) | join(" "));
      def fmt_industry(s):
        (s | tostring | ascii_downcase) as $k
        | if $k == "fintech" then "FinTech"
          elif $k == "medtech" then "MedTech"
          elif $k == "igaming" then "iGaming"
          elif $k == "edtech" then "EdTech"
          elif $k == "legaltech" then "LegalTech"
          elif $k == "gambling" then "Gambling"
          elif $k == "banking" then "Banking"
          elif $k == "payments" then "Payments"
          elif $k == "privacy" then "Privacy"
          elif $k == "platform" then "Platform"
          else tc(s)
          end;
      (.[0] // {}) as $root
      | (.[1] // {}) as $meta
      | ($root.packages // []) as $pkgs
      | ($meta.packages // []) as $metaPkgs
      | {
          packages: (
            $pkgs
            | map(
                . as $p
                | (
                    $metaPkgs
                    | map(select(.id == $p.id))
                    | (if length > 0 then .[0] else null end)
                  ) as $m
                | if $m then
                    $p
                    + (if ($m.name // null) then {name: $m.name} else {} end)
                    + (if ($m.standard // null) then {standard: $m.standard} else {} end)
                    + (if ($m.version // null) then {version: $m.version} else {} end)
                    + (if ($m.jurisdiction // null) then {jurisdiction: $m.jurisdiction} else {} end)
                    + (if ($m.coverage // null) then {coverage: ($m.coverage | (if type=="array" then . else [] end))} else {} end)
                    + (if ($m.severity // null) then {severity: ($m.severity | tostring | ascii_downcase)} else {} end)
                    + (if ($m.industry // null) then {industry: (if ($m.industry | type) == "array" then ($m.industry | map(fmt_industry(.))) else fmt_industry($m.industry) end)} else {} end)
                  else
                    $p
                  end
                | (
                    def up_token(t):
                      (t | ascii_downcase) as $d
                      | if ($d == "uk" or $d == "eu" or $d == "us" or $d == "api" or $d == "aml" or $d == "kyc" or $d == "gdpr" or $d == "pci" or $d == "ivdr" or $d == "mdr" or $d == "fhir" or $d == "hipaa" or $d == "dtac" or $d == "oasis" or $d == "sbom" or $d == "rto" or $d == "rpo")
                        then (t | ascii_upcase)
                        else ((t[0:1] | ascii_upcase) + (t[1:] | ascii_downcase))
                        end;
                    def title_tokens(s): (s | gsub("_";" ") | gsub("-";" ") | split(" ") | map(select(. != "")) | map(up_token(.)) | join(" "));
                    if ((.name // "") == "<Policy Title>" or (.name // "") == (.id // "")) then
                      (.id // "") as $id
                      | ($id | split(".") | .[0]) as $dom
                      | ($id | split(".") | .[1]) as $key
                      | .name = (title_tokens($dom) + " — " + title_tokens($key))
                    else . end
                  )
              )
          )
        }
    ' "${OUT_FILE}.tmp.base" "${METADATA_JSON}" > "${OUT_FILE}.tmp"
else
  cp "${OUT_FILE}.tmp.base" "${OUT_FILE}.tmp"
fi

rm -f "${OUT_FILE}.tmp.base"

# Minimize churn: only update file if content changed
if [[ -f "${OUT_FILE}" ]] && cmp -s "${OUT_FILE}.tmp" "${OUT_FILE}"; then
  rm -f "${OUT_FILE}.tmp"
  echo "dist/index.json unchanged"
else
  mv -f "${OUT_FILE}.tmp" "${OUT_FILE}"
  echo "Wrote ${OUT_FILE}"
fi

# Cleanup temp merged file if used
if [[ -n "${TMP_MERGED}" && -f "${TMP_MERGED}" ]]; then
  rm -f "${TMP_MERGED}"
fi
