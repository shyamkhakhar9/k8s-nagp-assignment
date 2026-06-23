#!/bin/bash
set -euo pipefail

# Collects resource usage vs requests/limits for FinOps analysis.
# Usage: ./scripts/finops-metrics.sh
#
# Prerequisites: metrics-server installed on the cluster.

NAMESPACE="${NAMESPACE:-k8s-demo}"
LABEL="${LABEL:-app=assignment-api}"

echo "=============================================="
echo " FinOps Metrics — API Tier (${NAMESPACE})"
echo "=============================================="
echo ""

if ! kubectl top pods -n "${NAMESPACE}" -l "${LABEL}" &>/dev/null; then
  echo "ERROR: metrics-server not available. Install it on the cluster first."
  echo "  EKS: kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
  exit 1
fi

echo "--- Current pod CPU / memory USAGE (observed) ---"
kubectl top pods -n "${NAMESPACE}" -l "${LABEL}"
echo ""

echo "--- Configured REQUESTS and LIMITS ---"
kubectl get pods -n "${NAMESPACE}" -l "${LABEL}" \
  -o custom-columns=\
'POD:.metadata.name,\
CPU_REQ:.spec.containers[0].resources.requests.cpu,\
CPU_LIM:.spec.containers[0].resources.limits.cpu,\
MEM_REQ:.spec.containers[0].resources.requests.memory,\
MEM_LIM:.spec.containers[0].resources.limits.memory'
echo ""

REPLICAS=$(kubectl get deployment assignment-api -n "${NAMESPACE}" -o jsonpath='{.spec.replicas}')
CPU_REQ=$(kubectl get deployment assignment-api -n "${NAMESPACE}" \
  -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}')
MEM_REQ=$(kubectl get deployment assignment-api -n "${NAMESPACE}" \
  -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}')

echo "--- Cluster reservation (API tier only) ---"
echo "Replicas:          ${REPLICAS}"
echo "CPU request/pod:   ${CPU_REQ}"
echo "Memory request/pod: ${MEM_REQ}"
echo ""

echo "--- HPA status ---"
kubectl get hpa assignment-api-hpa -n "${NAMESPACE}" 2>/dev/null || echo "HPA not found"
echo ""

echo "--- Utilization guidance ---"
echo "Compare USAGE vs REQUESTS above."
echo "  - If usage is consistently << requests → over-provisioned (cost waste)"
echo "  - If usage is near limits        → risk of throttling / OOM"
echo "  - Target: requests ≈ 70-80% of typical usage (headroom for spikes)"
echo ""
echo "To watch live during load test:"
echo "  watch -n 5 'kubectl top pods -n ${NAMESPACE} -l ${LABEL}'"
echo ""
echo "Run load test (set HOST to your ALB DNS):"
echo "  HOST=<alb-dns> ./scripts/demo-hpa.sh"
