#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Setting up Kind cluster for CBT demo"
echo "=========================================="

# Check if kind is installed
if ! command -v kind &> /dev/null; then
    echo "Error: kind is not installed"
    echo "Install it from: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed"
    echo "Install it from: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

# Create temp directories for hostPath mounts
echo "Creating temporary directories for CSI and MinIO storage..."
mkdir -p /tmp/cbt-demo-csi
mkdir -p /tmp/cbt-demo-minio

# Delete existing cluster if it exists
if kind get clusters | grep -q "^cbt-demo$"; then
    echo "Deleting existing cluster..."
    kind delete cluster --name cbt-demo
fi

# Create the cluster
echo "Creating Kind cluster..."
kind create cluster --config cluster/kind-config.yaml --wait 10m

# Verify cluster is ready
echo "Verifying cluster..."
kubectl cluster-info --context kind-cbt-demo
kubectl get nodes

echo ""
echo "✓ Kind cluster 'cbt-demo' created successfully!"
echo ""
echo "To use this cluster, run:"
echo "  kubectl config use-context kind-cbt-demo"
