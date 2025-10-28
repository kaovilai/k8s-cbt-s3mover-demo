#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "CBT Demo - Remote Cluster Deployment"
echo "=========================================="
echo ""
echo "This script will run the complete CBT demo on a remote Kubernetes cluster."
echo ""
echo "Prerequisites:"
echo "  - KUBECONFIG environment variable pointing to your cluster"
echo "  - Cluster with block volume support"
echo "  - kubectl installed and configured"
echo ""

# Check if KUBECONFIG is set
if [ -z "${KUBECONFIG:-}" ]; then
    echo "Error: KUBECONFIG environment variable not set"
    echo ""
    echo "Set it with:"
    echo "  export KUBECONFIG=/path/to/your/kubeconfig"
    exit 1
fi

# Verify cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "Connected to: $(kubectl config current-context)"
echo ""
read -r -p "Press Enter to continue or Ctrl+C to cancel..."

# Step 1: Verify cluster
echo ""
echo "[Step 1/8] Verifying remote cluster..."
./scripts/00-setup-remote-cluster.sh

# Step 2: Deploy MinIO
echo ""
echo "[Step 2/8] Deploying MinIO S3 storage..."
./scripts/02-deploy-minio.sh

# Step 3: Install Snapshot CRDs (if not already installed)
echo ""
echo "[Step 3/8] Installing VolumeSnapshot CRDs..."
echo "  Checking if CRDs are already installed..."
if ! kubectl get crd volumesnapshots.snapshot.storage.k8s.io &> /dev/null; then
    echo "  Installing VolumeSnapshot CRDs..."
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v8.2.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v8.2.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v8.2.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v8.2.0/client/config/crd/groupsnapshot.storage.k8s.io_volumegroupsnapshotclasses.yaml
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v8.2.0/client/config/crd/groupsnapshot.storage.k8s.io_volumegroupsnapshotcontents.yaml
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v8.2.0/client/config/crd/groupsnapshot.storage.k8s.io_volumegroupsnapshots.yaml
    echo "  ✓ CRDs installed"
else
    echo "  ✓ CRDs already installed"
fi

# Step 4: Deploy CSI Driver (optional - cluster might have its own)
echo ""
echo "[Step 4/8] Checking CSI Driver..."
echo "  Note: Your cluster may already have a CSI driver with snapshot support."
echo "  If so, you can skip installing the hostpath driver."
echo ""
read -r -p "Install CSI hostpath driver? (y/n): " INSTALL_CSI

if [[ "$INSTALL_CSI" =~ ^[Yy]$ ]]; then
    echo "  Installing CSI hostpath driver..."
    ./scripts/01-deploy-csi-driver.sh
else
    echo "  Skipping CSI driver installation"
    echo "  Make sure your cluster has a CSI driver with VolumeSnapshot support!"
fi

# Step 5: Validate setup
echo ""
echo "[Step 5/8] Validating CBT setup..."
./scripts/validate-cbt.sh || {
    echo ""
    echo "⚠️  Warning: Validation had issues, but continuing..."
    echo "  This is expected if you're using your cluster's native CSI driver"
}

# Step 6: Deploy block-writer workload
echo ""
echo "[Step 6/8] Deploying block-writer workload..."
./scripts/03-deploy-workload.sh

# Step 7: Check backup status
echo ""
echo "[Step 7/8] Checking backup infrastructure..."
./scripts/backup-status.sh || true

# Step 8: Run integrity check
echo ""
echo "[Step 8/8] Running integrity checks..."
./scripts/integrity-check.sh || true

echo ""
echo "=========================================="
echo "✓ Demo Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Create snapshots: See README.md for manual steps"
echo "  2. Test disaster recovery: ./scripts/05-simulate-disaster.sh"
echo "  3. Restore from backup: ./scripts/06-restore.sh"
echo ""
echo "To clean up when done:"
echo "  ./scripts/cleanup-remote-cluster.sh"
