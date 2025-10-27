#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Setting up Remote Cluster for CBT demo"
echo "=========================================="

# Check if kubeconfig is provided
if [ -z "${KUBECONFIG:-}" ]; then
    echo "Error: KUBECONFIG environment variable not set"
    echo ""
    echo "Usage:"
    echo "  export KUBECONFIG=/path/to/your/kubeconfig"
    echo "  $0"
    echo ""
    echo "Or:"
    echo "  KUBECONFIG=/path/to/your/kubeconfig $0"
    exit 1
fi

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed"
    echo "Install it from: https://kubernetes.io/docs/tasks/tools/"
    exit 1
fi

# Verify cluster connectivity
echo "Verifying cluster connectivity..."
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster"
    echo "Please check your KUBECONFIG and cluster accessibility"
    exit 1
fi

echo "✓ Connected to cluster successfully"
echo ""

# Display cluster information
echo "Cluster Information:"
kubectl cluster-info
echo ""

# Check node information
echo "Nodes:"
kubectl get nodes
echo ""

# Warn if using a production cluster
echo "⚠️  WARNING: This script will deploy resources to the connected cluster."
echo ""
echo "Connected to: $(kubectl config current-context)"
echo ""
read -r -p "Continue with deployment? (type 'yes' to proceed): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Check for required capabilities
echo ""
echo "Checking cluster capabilities..."

# Check for storage classes
echo "  Checking for storage classes..."
if ! kubectl get storageclass &> /dev/null; then
    echo "  ✗ No storage classes found"
    echo "  Warning: You'll need to configure a CSI driver with block volume support"
else
    STORAGE_CLASSES=$(kubectl get storageclass --no-headers | wc -l)
    echo "  ✓ Found $STORAGE_CLASSES storage class(es)"
    kubectl get storageclass
fi

echo ""
echo "✓ Remote cluster setup verification complete!"
echo ""
echo "Next steps:"
echo "  1. Deploy CSI Driver: ./scripts/01-deploy-csi-driver.sh"
echo "  2. Deploy MinIO: ./scripts/02-deploy-minio.sh"
echo "  3. Deploy workload: ./scripts/03-deploy-workload.sh"
echo ""
echo "Note: Make sure your cluster has:"
echo "  - A CSI driver with VolumeSnapshot support"
echo "  - Block volume support (volumeMode: Block)"
echo "  - Sufficient storage capacity"
