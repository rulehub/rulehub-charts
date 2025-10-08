#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME=${CLUSTER_NAME:-rulehub-charts-smoke}
NAMESPACE=${NAMESPACE:-policies}
RELEASE=${RELEASE:-rulehub-policies}
VALUES_FILE=${VALUES_FILE:-values.yaml}
KIND_IMAGE=${KIND_IMAGE:-}

echo "[kind-smoke] Creating kind cluster: $CLUSTER_NAME" >&2
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "[kind-smoke] Cluster already exists, reusing." >&2
else
  if [ -n "$KIND_IMAGE" ]; then
    kind create cluster --name "$CLUSTER_NAME" --image "$KIND_IMAGE"
  else
    kind create cluster --name "$CLUSTER_NAME"
  fi
fi

echo "[kind-smoke] Helm install (namespace=$NAMESPACE release=$RELEASE)" >&2
helm upgrade --install "$RELEASE" . \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --values "$VALUES_FILE" \
  --wait --timeout 120s

echo "[kind-smoke] Listing installed resources (filtered)" >&2
kubectl get pods -A | head -n 20 || true
kubectl get constrainttemplates.constraints.gatekeeper.sh 2>/dev/null | head -n 10 || true
kubectl get clusterpolicies.kyverno.io 2>/dev/null | head -n 10 || true

echo "[kind-smoke] Uninstalling release" >&2
helm uninstall "$RELEASE" -n "$NAMESPACE" || true

echo "[kind-smoke] Deleting cluster" >&2
kind delete cluster --name "$CLUSTER_NAME"
echo "[kind-smoke] Done." >&2
