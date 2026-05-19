#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Setting up Minikube cluster for CBT demo"
echo "=========================================="

# Check if minikube is installed
if ! command -v minikube &> /dev/null; then
    echo "Error: minikube is not installed"
    echo "Install it from: https://minikube.sigs.k8s.io/docs/start/"
    echo "  macOS: brew install minikube"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed"
    echo "Install it from: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

# Delete existing cluster if it exists
if minikube status --profile cbt-demo >/dev/null 2>&1; then
    echo "Deleting existing cluster..."
    minikube delete --profile cbt-demo
fi

# Detect OS and choose appropriate driver
if [[ "$(uname -s)" == "Darwin" ]]; then
    MINIKUBE_VERSION=$(minikube version --short 2>&1 | grep -oE 'v[0-9]+\.[0-9]+' | sed 's/v//' | head -1)
    MAJOR=$(echo "$MINIKUBE_VERSION" | cut -d. -f1)
    MINOR=$(echo "$MINIKUBE_VERSION" | cut -d. -f2)
    if [[ $MAJOR -gt 1 ]] || [[ $MAJOR -eq 1 && $MINOR -ge 36 ]]; then
        DRIVER="vfkit"
        echo "Using vfkit driver (macOS native virtualization)..."
    else
        DRIVER="docker"
        echo "Using Docker driver (upgrade to Minikube 1.36+ for vfkit support)..."
    fi
else
    DRIVER="docker"
    echo "Using Docker driver..."
fi

echo "  Driver: $DRIVER"
echo "  CPUs: 4"
echo "  Memory: 8192MB"
echo "  Kubernetes: v1.33.0 (CBT alpha support)"
echo ""

minikube start \
    --profile cbt-demo \
    --driver="$DRIVER" \
    --cpus=4 \
    --memory=8192 \
    --kubernetes-version=v1.33.0 \
    --container-runtime=containerd \
    --wait=all

# Set kubectl context
kubectl config use-context cbt-demo

# Verify cluster is ready
echo "Verifying cluster..."
kubectl cluster-info
kubectl get nodes

echo ""
echo "✓ Minikube cluster 'cbt-demo' created successfully!"
echo ""
echo "To use this cluster, run:"
echo "  kubectl config use-context cbt-demo"
