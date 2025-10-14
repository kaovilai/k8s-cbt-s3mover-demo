#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Deploying PostgreSQL workload"
echo "=========================================="

# Deploy PostgreSQL StatefulSet
echo "Deploying PostgreSQL with block PVC..."
kubectl apply -f manifests/workload/postgres-statefulset.yaml

# Wait for PostgreSQL pod to be created
echo "Waiting for PostgreSQL pod to be created..."
RETRIES=0
MAX_RETRIES=30
until kubectl get pod -n cbt-demo -l app=postgres 2>/dev/null | grep -q postgres; do
    if [ $RETRIES -ge $MAX_RETRIES ]; then
        echo "✗ PostgreSQL pod not created within timeout"
        kubectl get pods -n cbt-demo
        kubectl get pvc -n cbt-demo
        exit 1
    fi
    echo "Waiting for pod to be created... ($RETRIES/$MAX_RETRIES)"
    sleep 2
    RETRIES=$((RETRIES + 1))
done

# Wait for PostgreSQL to be ready
echo "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=Ready pod -l app=postgres -n cbt-demo --timeout=300s || {
    echo "✗ PostgreSQL pod not ready. Checking logs..."
    kubectl logs -n cbt-demo -l app=postgres --tail=50
    kubectl describe pod -n cbt-demo -l app=postgres
    exit 1
}

# Populate initial data
echo "Populating initial data..."
kubectl apply -f manifests/workload/init-data-job.yaml

# Wait for init job to complete
echo "Waiting for data population to complete (this may take a few minutes)..."
kubectl wait --for=condition=Complete job/postgres-init-data -n cbt-demo --timeout=600s

# Show results
echo ""
echo "✓ PostgreSQL workload deployed and initialized successfully!"
echo ""
echo "Database info:"
kubectl logs -n cbt-demo job/postgres-init-data --tail=5
echo ""
echo "To connect to PostgreSQL:"
echo "  kubectl exec -it -n cbt-demo postgres-0 -- psql -U demo -d cbtdemo"
