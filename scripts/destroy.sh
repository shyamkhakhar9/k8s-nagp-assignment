#!/bin/bash
set -euo pipefail

# Destroys all resources created by create-secrets.sh and deploy.sh.
# Usage: ./scripts/destroy.sh [-y]

#export AWS_PROFILE="${AWS_PROFILE:-devsaas}"

NAMESPACE="${NAMESPACE:-k8s-demo}"
K8S_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../k8s" && pwd)"
FORCE=false

if [[ "${1:-}" == "-y" || "${1:-}" == "--yes" ]]; then
  FORCE=true
fi

if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
  echo "Namespace '${NAMESPACE}' does not exist. Nothing to destroy."
  exit 0
fi

if [[ "${FORCE}" != true ]]; then
  read -rp "Delete all resources in namespace '${NAMESPACE}'? [y/N] " confirm
  if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

echo "Deleting Ingress (public ALB will be removed)..."
kubectl delete -f "${K8S_DIR}/ingress.yaml" --ignore-not-found --wait=true --timeout=300s || true

echo "Deleting API tier..."
kubectl delete -f "${K8S_DIR}/api-hpa.yaml" --ignore-not-found
kubectl delete -f "${K8S_DIR}/api-service.yaml" --ignore-not-found
kubectl delete -f "${K8S_DIR}/api-deployment.yaml" --ignore-not-found --wait=true --timeout=180s || true

echo "Deleting database tier..."
kubectl delete -f "${K8S_DIR}/postgres-networkpolicy.yaml" --ignore-not-found
kubectl delete -f "${K8S_DIR}/postgres-statefulset.yaml" --ignore-not-found --wait=true --timeout=180s || true
kubectl delete -f "${K8S_DIR}/postgres-service.yaml" --ignore-not-found

echo "Deleting ConfigMaps..."
kubectl delete -f "${K8S_DIR}/configmap-api.yaml" --ignore-not-found
kubectl delete -f "${K8S_DIR}/configmap-db-init.yaml" --ignore-not-found

echo "Deleting Secrets..."
kubectl delete secret postgres-secret api-db-secret -n "${NAMESPACE}" --ignore-not-found

echo "Deleting PersistentVolumeClaims..."
kubectl delete pvc --all -n "${NAMESPACE}" --ignore-not-found --wait=true --timeout=120s || true

echo "Deleting namespace..."
kubectl delete -f "${K8S_DIR}/namespace.yaml" --ignore-not-found --wait=true --timeout=300s || true

echo "Destroy complete."
