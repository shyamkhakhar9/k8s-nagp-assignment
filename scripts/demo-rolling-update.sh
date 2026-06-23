#!/bin/bash
set -euo pipefail

# Demonstrates rolling update: set a new image tag on the deployment.
NAMESPACE="${NAMESPACE:-k8s-demo}"
ECR_REGISTRY="${ECR_REGISTRY:-730335193392.dkr.ecr.us-east-2.amazonaws.com}"
REPO_NAME="${REPO_NAME:-k8s-demo}"
TAG="${1:-latest}"

kubectl set image deployment/assignment-api \
  api="${ECR_REGISTRY}/${REPO_NAME}:${TAG}" \
  -n "${NAMESPACE}"

kubectl rollout status deployment/assignment-api -n "${NAMESPACE}"
kubectl get pods -n "${NAMESPACE}" -l app=assignment-api
