#!/usr/bin/env bash
set -euo pipefail
# Render and validate manifests with kubeconform; filter only Kubernetes resources.
helm template . > rendered.yaml
# Filter to only K8s manifests (having apiVersion+kind)
yq eval-all 'select(has("apiVersion") and has("kind"))' rendered.yaml > rendered.k8s.yaml || true
kubeconform -summary -ignore-missing-schemas < rendered.k8s.yaml
