#!/usr/bin/env bash
set -euo pipefail

# gen-kyverno-core.sh
# Deterministically generate Kyverno ClusterPolicies for core K8s controls
# using a small built-in template library.
#
# Supported IDs:
#  - ban.hostnetwork                -> ClusterPolicy ban-hostnetwork
#  - limit.capabilities             -> ClusterPolicy limit-capabilities
#  - no.run.as.root                 -> ClusterPolicy no-run-as-root
#  - require.imagepullpolicy.always -> ClusterPolicy require-imagepullpolicy-always
#
# Usage:
#   hack/gen/gen-kyverno-core.sh [--all] [id1 id2 ...]

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="${SCRIPT_DIR%/hack}"
OUT_DIR="$REPO_ROOT/files/kyverno"
mkdir -p "$OUT_DIR"

ids=()
if [[ $# -eq 0 ]]; then
  echo "Usage: $0 [--all] [id1 id2 ...]" >&2
  exit 2
fi

if [[ ${1:-} == "--all" ]]; then
  ids=(ban.hostnetwork limit.capabilities no.run.as.root require.imagepullpolicy.always)
else
  ids=("$@")
fi

emit_policy() {
  local id="$1" kebab=${id//./-}
  case "$id" in
    ban.hostnetwork)
      cat <<'YAML'
# NOTE: placeholders quoted for Helm parse stability
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: ban-hostnetwork
  annotations:
    rulehub.id: ban.hostnetwork
spec:
  validationFailureAction: enforce
  background: true
  rules:
    - name: forbid-hostnetwork
      match:
        resources:
          kinds: ["Pod"]
      validate:
        message: "hostNetwork is not allowed"
        pattern:
          spec:
            =(hostNetwork): "false"
YAML
      ;;
    limit.capabilities)
      cat <<'YAML'
# NOTE: placeholders quoted for Helm parse stability
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: limit-capabilities
  annotations:
    rulehub.id: limit.capabilities
spec:
  validationFailureAction: enforce
  background: true
  rules:
    - name: require-drop-all
      match:
        resources:
          kinds: ["Pod"]
      validate:
        message: "Must drop ALL capabilities"
        pattern:
          spec:
            containers:
              - =(securityContext):
                  =(capabilities):
                    drop: ["ALL"]
YAML
      ;;
    no.run.as.root)
      cat <<'YAML'
# NOTE: placeholders quoted for Helm parse stability
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: no-run-as-root
  annotations:
    rulehub.id: no.run.as.root
spec:
  validationFailureAction: enforce
  background: true
  rules:
    - name: require-non-root
      match:
        resources:
          kinds: ["Pod"]
      validate:
        message: "Containers must run as non-root"
        pattern:
          spec:
            containers:
              - =(securityContext):
                  =(runAsNonRoot): "true"
YAML
      ;;
    require.imagepullpolicy.always)
      cat <<'YAML'
# NOTE: placeholders quoted for Helm parse stability
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-imagepullpolicy-always
  annotations:
    rulehub.id: require.imagepullpolicy.always
spec:
  validationFailureAction: enforce
  background: true
  rules:
    - name: require-always
      match:
        resources:
          kinds: ["Pod"]
      validate:
        message: "imagePullPolicy must be Always"
        pattern:
          spec:
            containers:
              - =(imagePullPolicy): "Always"
YAML
      ;;
    *)
      echo "Unsupported id for Kyverno policy: $id" >&2; return 1;;
  esac
}

for id in "${ids[@]}"; do
  out="$OUT_DIR/${id//./-}.yaml"
  if [[ -f "$out" ]]; then
    echo "[skip] kyverno exists: $(basename "$out")" >&2
  else
    echo "[gen] kyverno: $id -> $(basename "$out")" >&2
    emit_policy "$id" >"$out"
  fi
done

echo "Done." >&2
