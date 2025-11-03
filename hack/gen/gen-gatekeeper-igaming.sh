#!/usr/bin/env bash
set -euo pipefail

# gen-gatekeeper-igaming.sh
# Generate or update Gatekeeper Constraints for igaming.* IDs
# reusing existing ConstraintTemplates (Betting* kinds) and wiring
# rulehub.id to igaming.* with a required Namespace label parameter.
#
# Usage:
#   hack/gen/gen-gatekeeper-igaming.sh --all
#   hack/gen/gen-gatekeeper-igaming.sh id1 id2 ...

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="${SCRIPT_DIR%/hack}"
OUT_DIR="$REPO_ROOT/files/gatekeeper"
mkdir -p "$OUT_DIR"

map_id() {
  local id="$1"
  case "$id" in
    igaming.deposit_limit_controls)
      KIND=BettingDepositLimitControls
      FILE=betting-deposit_limit_controls-constraint.yaml;;
    igaming.geofencing_regulated_markets)
      KIND=BettingGeofencingRegulatedMarkets
      FILE=betting-geofencing_regulated_markets-constraint.yaml;;
    igaming.license_check_adm_it)
      KIND=BettingLicenseCheckAdmIt
      FILE=betting-license_check_adm_it-constraint.yaml;;
    igaming.license_check_anj_fr)
      KIND=BettingLicenseCheckAnjFr
      FILE=betting-license_check_anj_fr-constraint.yaml;;
    igaming.license_check_dgoj_es)
      KIND=BettingLicenseCheckDgojEs
      FILE=betting-license_check_dgoj_es-constraint.yaml;;
    igaming.license_check_ukgc)
      KIND=BettingLicenseCheckUkgc
      FILE=betting-license_check_ukgc-constraint.yaml;;
    igaming.license_check_us_nj_dge)
      KIND=BettingLicenseCheckUsNjDge
      FILE=betting-license_check_us_nj_dge-constraint.yaml;;
    igaming.license_check_us_nv_ngcb)
      KIND=BettingLicenseCheckUsNvNgcb
      FILE=betting-license_check_us_nv_ngcb-constraint.yaml;;
    igaming.license_check_us_pa_pgcb)
      KIND=BettingLicenseCheckUsPaPgcb
      FILE=betting-license_check_us_pa_pgcb-constraint.yaml;;
    igaming.self_exclusion_uk_gamstop)
      KIND=BettingSelfExclusionUkGamstop
      FILE=betting-self_exclusion_uk_gamstop-constraint.yaml;;
    *)
      echo "Unknown mapping for $id" >&2; return 1;;
  esac
  return 0
}

ids=()
if [[ $# -eq 0 ]]; then
  echo "Usage: $0 --all | <igaming.id>..." >&2
  exit 2
fi
if [[ ${1:-} == "--all" ]]; then
  ids=(
    igaming.deposit_limit_controls
    igaming.geofencing_regulated_markets
    igaming.license_check_adm_it
    igaming.license_check_anj_fr
    igaming.license_check_dgoj_es
    igaming.license_check_ukgc
    igaming.license_check_us_nj_dge
    igaming.license_check_us_nv_ngcb
    igaming.license_check_us_pa_pgcb
    igaming.self_exclusion_uk_gamstop
  )
else
  ids=("$@")
fi

for id in "${ids[@]}"; do
  KIND="" FILE=""
  map_id "$id" || exit 2
  name_base="${FILE%-constraint.yaml}"
  cat >"$OUT_DIR/$FILE" <<YAML
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: ${KIND}
metadata:
  name: ${name_base}
  annotations:
    rulehub.id: ${id}
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Namespace"]
  parameters:
    requiredLabel: jurisdiction
YAML
  echo "[gen] constraint updated: $FILE (id=${id}, kind=${KIND})" >&2
done

echo "Done." >&2
