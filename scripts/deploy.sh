#!/bin/bash
set -euo pipefail

# Deploys the full stack. Run create-secrets.sh first.
# Usage: ./scripts/deploy.sh [tag]

export AWS_PROFILE="${AWS_PROFILE:-devsaas}"

NAMESPACE="${NAMESPACE:-k8s-demo}"
ECR_REGISTRY="${ECR_REGISTRY:-730335193392.dkr.ecr.us-east-2.amazonaws.com}"
REPO_NAME="${REPO_NAME:-k8s-demo}"
TAG="${1:-latest}"
K8S_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../k8s" && pwd)"

kubectl apply -f "${K8S_DIR}/namespace.yaml"

if ! kubectl get secret postgres-secret -n "${NAMESPACE}" &>/dev/null; then
  echo "Error: secrets not found. Run ./scripts/create-secrets.sh first." >&2
  exit 1
fi

kubectl apply -f "${K8S_DIR}/configmap-db-init.yaml"
kubectl apply -f "${K8S_DIR}/configmap-api.yaml"
kubectl apply -f "${K8S_DIR}/postgres-statefulset.yaml"
kubectl apply -f "${K8S_DIR}/postgres-service.yaml"
kubectl apply -f "${K8S_DIR}/postgres-networkpolicy.yaml"

echo "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres -n "${NAMESPACE}" --timeout=180s

sed "s|${ECR_REGISTRY}/${REPO_NAME}:latest|${ECR_REGISTRY}/${REPO_NAME}:${TAG}|g" \
  "${K8S_DIR}/api-deployment.yaml" | kubectl apply -f -

kubectl apply -f "${K8S_DIR}/api-service.yaml"
kubectl apply -f "${K8S_DIR}/api-hpa.yaml"
kubectl apply -f "${K8S_DIR}/ingress.yaml"

echo "Waiting for public ALB hostname (may take 2-3 minutes)..."
for _ in $(seq 1 36); do
  ALB_HOST=$(kubectl get ingress assignment-api-ingress -n "${NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [[ -n "${ALB_HOST}" ]]; then
    echo "Public ALB URL: http://${ALB_HOST}"
    echo "Health check:   curl http://${ALB_HOST}/health"
    echo "Products API:   curl http://${ALB_HOST}/api/products"
    break
  fi
  sleep 5
done

if [[ -z "${ALB_HOST:-}" ]]; then
  echo "ALB not ready yet. Check with:"
  echo "  kubectl get ingress assignment-api-ingress -n ${NAMESPACE}"
fi

echo "Deployment complete. Check: kubectl get all -n ${NAMESPACE}"
