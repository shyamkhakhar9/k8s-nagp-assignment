#!/bin/bash
set -euo pipefail

# Generates CPU load to trigger HPA scaling (requires metrics-server).
# Set HOST to your ALB DNS name, e.g.:
#   HOST=k8s-demo-xxxxx.us-east-2.elb.amazonaws.com ./scripts/demo-hpa.sh
export AWS_PROFILE="${AWS_PROFILE:-devsaas}"

NAMESPACE="${NAMESPACE:-k8s-demo}"
HOST="${HOST:?Set HOST to your ALB DNS name from: kubectl get ingress -n k8s-demo}"

echo "Load testing http://${HOST}/api/products for 120s..."
end=$((SECONDS + 120))
while [[ $SECONDS -lt $end ]]; do
  for _ in $(seq 1 20); do
    curl -s "http://${HOST}/api/products" > /dev/null &
  done
  wait
done

echo "Current HPA status:"
kubectl get hpa -n "${NAMESPACE}"
