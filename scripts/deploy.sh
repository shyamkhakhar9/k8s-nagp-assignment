#!/bin/bash
set -euo pipefail

# Deploys the full stack. Run create-secrets.sh first.
# Usage: ./scripts/deploy.sh [tag]

AWS_REGION="${AWS_REGION:-us-east-2}"
#export AWS_PROFILE="${AWS_PROFILE:-devsaas}"

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

ALB_HOST=""

echo "Waiting for ALB hostname to be assigned (may take 2-3 minutes)..."
for _ in $(seq 1 36); do
  ALB_HOST=$(kubectl get ingress assignment-api-ingress -n "${NAMESPACE}" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [[ -n "${ALB_HOST}" ]]; then
    echo "ALB hostname assigned: ${ALB_HOST}"
    break
  fi
  sleep 5
done

if [[ -n "${ALB_HOST}" ]]; then
  ALB_STATE=""
  echo "Waiting for ALB to reach active state..."
  for _ in $(seq 1 36); do
    ALB_STATE=$(aws elbv2 describe-load-balancers --region "${AWS_REGION}" \
      --query "LoadBalancers[?DNSName=='${ALB_HOST}'].State.Code | [0]" \
      --output text 2>/dev/null || true)
    if [[ "${ALB_STATE}" == "active" ]]; then
      echo "ALB state: active"
      break
    fi
    echo "  Current ALB state: ${ALB_STATE:-provisioning}..."
    sleep 5
  done

  HEALTH_OK=false
  if [[ "${ALB_STATE}" == "active" ]]; then
    echo "Waiting for ALB target health checks to pass..."
    for _ in $(seq 1 36); do
      HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
        "http://${ALB_HOST}/health" 2>/dev/null || echo "000")
      if [[ "${HTTP_CODE}" == "200" ]]; then
        echo "ALB health check passed (HTTP 200)"
        HEALTH_OK=true
        break
      fi
      echo "  Waiting for healthy targets (HTTP ${HTTP_CODE})..."
      sleep 5
    done
  fi

  if [[ "${ALB_STATE}" == "active" ]]; then
    echo ""
    echo "========================================"
    echo "  Load Balancer Ready"
    echo "========================================"
    echo "Public ALB URL:  http://${ALB_HOST}"
    echo "ALB state:       active"
    echo "Target health:   $([[ "${HEALTH_OK}" == true ]] && echo "healthy" || echo "pending")"
    echo ""
    echo "Test commands:"
    echo "  curl http://${ALB_HOST}/health"
    echo "  curl http://${ALB_HOST}/api/products"
    echo "========================================"
    echo ""
  else
    echo "ALB hostname assigned but not active yet (state: ${ALB_STATE:-unknown})."
    echo "  kubectl get ingress assignment-api-ingress -n ${NAMESPACE}"
  fi
fi

if [[ -z "${ALB_HOST}" ]]; then
  echo "ALB not ready yet. Check with:"
  echo "  kubectl get ingress assignment-api-ingress -n ${NAMESPACE}"
  echo "  aws elbv2 describe-load-balancers --region ${AWS_REGION} --query 'LoadBalancers[].{DNS:DNSName,State:State.Code}'"
fi

echo "Deployment complete. Check: kubectl get all -n ${NAMESPACE}"
