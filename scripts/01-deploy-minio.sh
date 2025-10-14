#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Deploying MinIO"
echo "=========================================="

# Create namespace
echo "Creating namespace..."
kubectl apply -f manifests/namespace.yaml

# Deploy MinIO using kustomize
echo "Deploying MinIO..."
kubectl apply -k manifests/minio/

# Wait for MinIO pod to be created
echo "Waiting for MinIO pod to be created..."
RETRIES=0
MAX_RETRIES=30
until kubectl get pod -n cbt-demo -l app=minio 2>/dev/null | grep -q minio; do
    if [ $RETRIES -ge $MAX_RETRIES ]; then
        echo "✗ MinIO pod not created within timeout"
        kubectl get pods -n cbt-demo
        exit 1
    fi
    echo "Waiting for pod to be created... ($RETRIES/$MAX_RETRIES)"
    sleep 2
    RETRIES=$((RETRIES + 1))
done

# Wait for MinIO to be ready
echo "Waiting for MinIO to be ready..."
kubectl wait --for=condition=Ready pod -l app=minio -n cbt-demo --timeout=300s

# Get the MinIO endpoint
echo ""
echo "✓ MinIO deployed successfully!"
echo ""
echo "MinIO endpoints:"
echo "  API:     http://localhost:30900"
echo "  Console: http://localhost:30901"
echo ""
echo "Credentials:"
echo "  Username: minioadmin"
echo "  Password: minioadmin123"
echo ""
echo "To access MinIO API from within the cluster:"
echo "  http://minio.cbt-demo.svc.cluster.local:9000"
echo ""
echo "To port-forward MinIO (if NodePort doesn't work):"
echo "  kubectl port-forward -n cbt-demo svc/minio 9000:9000 9001:9001"
