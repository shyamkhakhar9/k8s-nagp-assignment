#!/bin/bash
set -euo pipefail

# Creates Kubernetes secrets without storing passwords in YAML files.
# Usage: ./scripts/create-secrets.sh

NAMESPACE="${NAMESPACE:-k8s-demo}"

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

read -rsp "PostgreSQL password: " DB_PASSWORD
echo
read -rsp "Confirm password: " DB_PASSWORD_CONFIRM
echo

if [[ "${DB_PASSWORD}" != "${DB_PASSWORD_CONFIRM}" ]]; then
  echo "Passwords do not match" >&2
  exit 1
fi

kubectl create secret generic postgres-secret \
  --namespace="${NAMESPACE}" \
  --from-literal=POSTGRES_PASSWORD="${DB_PASSWORD}" \
  --from-literal=POSTGRES_USER=appuser \
  --from-literal=POSTGRES_DB=appdb \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic api-db-secret \
  --namespace="${NAMESPACE}" \
  --from-literal=db-password="${DB_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets created in namespace ${NAMESPACE}"
