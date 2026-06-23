#!/bin/bash
set -euo pipefail

# Demonstrates self-healing: deletes one API pod and watches replacement.
NAMESPACE="${NAMESPACE:-k8s-demo}"

POD=$(kubectl get pods -n "${NAMESPACE}" -l app=assignment-api -o jsonpath='{.items[0].metadata.name}')
echo "Deleting pod ${POD}..."
kubectl delete pod -n "${NAMESPACE}" "${POD}"

echo "Watching replacement (Ctrl+C to stop)..."
kubectl get pods -n "${NAMESPACE}" -l app=assignment-api -w
