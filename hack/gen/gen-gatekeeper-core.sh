#!/usr/bin/env bash
set -euo pipefail

# gen-gatekeeper-core.sh
# Deterministically generate Gatekeeper ConstraintTemplates + Constraints
# for a small set of core Kubernetes controls using a baked-in template library.
#
# Supported IDs:
#  - disallow.latest                 -> K8sDisallowLatest
#  - require.resources               -> K8sRequireResources
#  - no.privileged                   -> K8sNoPrivileged
# (block.hostpath, ban.hostnetwork, limit.capabilities, no.run.as.root,
#  require.imagepullpolicy.always already exist in repo)
#
# Usage:
#   hack/gen/gen-gatekeeper-core.sh [--all] [id1 id2 ...]
#

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="${SCRIPT_DIR%/hack}"

mkdir -p "$REPO_ROOT/files/gatekeeper-templates" "$REPO_ROOT/files/gatekeeper"

ids=()
if [[ $# -eq 0 ]]; then
  echo "Usage: $0 [--all] [id1 id2 ...]" >&2
  exit 2
fi

if [[ ${1:-} == "--all" ]]; then
  ids=(disallow.latest require.resources no.privileged)
else
  ids=("$@")
fi

emit_template() {
  local id="$1"
  case "$id" in
    disallow.latest)
      cat <<'YAML'
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: k8sdisallowlatest
  annotations:
    rulehub.id: disallow.latest.template
spec:
  crd:
    spec:
      names:
        kind: K8sDisallowLatest
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sdisallowlatest
        deny[msg] {
          some c
          c := input.review.object.spec.containers[_]
          endswith(c.image, ":latest")
          msg := sprintf("image uses latest tag: %s", [c.image])
        }
YAML
      ;;
    require.resources)
      cat <<'YAML'
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: k8srequireresources
  annotations:
    rulehub.id: require.resources.template
spec:
  crd:
    spec:
      names:
        kind: K8sRequireResources
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequireresources
        missing_limits(c) { not c.resources } { not c.resources.limits }
        missing_requests(c) { not c.resources } { not c.resources.requests }
        deny[msg] {
          some c
          c := input.review.object.spec.containers[_]
          missing_limits(c) or missing_requests(c)
          msg := "container must set resources.requests and resources.limits"
        }
YAML
      ;;
    no.privileged)
      cat <<'YAML'
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: k8snoprivileged
  annotations:
    rulehub.id: no.privileged.template
spec:
  crd:
    spec:
      names:
        kind: K8sNoPrivileged
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8snoprivileged
        deny[msg] {
          some c
          c := input.review.object.spec.containers[_]
          c.securityContext.privileged == true
          msg := "privileged containers are not allowed"
        }
YAML
      ;;
    *)
      echo "Unsupported id for template: $id" >&2; return 1;;
  esac
}

emit_constraint() {
  local id="$1" kind name rule_id
  case "$id" in
    disallow.latest) kind=K8sDisallowLatest; name=disallow-latest; rule_id=disallow.latest;;
    require.resources) kind=K8sRequireResources; name=require-resources; rule_id=require.resources;;
    no.privileged) kind=K8sNoPrivileged; name=no-privileged; rule_id=no.privileged;;
    *) echo "Unsupported id for constraint: $id" >&2; return 1;;
  esac
  cat <<YAML
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: ${kind}
metadata:
  name: ${name}
  annotations:
    rulehub.id: ${rule_id}
spec:
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
YAML
}

for id in "${ids[@]}"; do
  tfile="$REPO_ROOT/files/gatekeeper-templates/${id//./-}.yaml"
  cfile="$REPO_ROOT/files/gatekeeper/${id//./-}.yaml"
  if [[ -f "$tfile" ]]; then
    echo "[skip] template exists: $(basename "$tfile")" >&2
  else
    echo "[gen] template: $id -> $(basename "$tfile")" >&2
    emit_template "$id" >"$tfile"
  fi
  if [[ -f "$cfile" ]]; then
    echo "[skip] constraint exists: $(basename "$cfile")" >&2
  else
    echo "[gen] constraint: $id -> $(basename "$cfile")" >&2
    emit_constraint "$id" >"$cfile"
  fi
done

echo "Done." >&2
