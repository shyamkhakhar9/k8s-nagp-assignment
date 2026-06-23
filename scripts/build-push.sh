#!/bin/bash
set -euo pipefail

# Usage: ./scripts/build-push.sh [tag]
# Example: ./scripts/build-push.sh v1

AWS_REGION="${AWS_REGION:-us-east-2}"
ECR_REGISTRY="${ECR_REGISTRY:-730335193392.dkr.ecr.us-east-2.amazonaws.com}"
REPO_NAME="${REPO_NAME:-k8s-demo}"
TAG="${1:-latest}"
IMAGE="${ECR_REGISTRY}/${REPO_NAME}:${TAG}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_DIR="${SCRIPT_DIR}/../api"

echo "Logging in to ECR (${ECR_REGISTRY})..."
aws ecr get-login-password --region "${AWS_REGION}" | \
  docker login --username AWS --password-stdin "${ECR_REGISTRY}"

echo "Building ${IMAGE}..."
docker build -t "${IMAGE}" "${API_DIR}"

echo "Pushing ${IMAGE}..."
docker push "${IMAGE}"

echo "Done. Image: ${IMAGE}"
