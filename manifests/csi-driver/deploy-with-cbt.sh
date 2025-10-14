#!/bin/bash
set -euo pipefail

echo "Deploying CSI Hostpath Driver with Changed Block Tracking support..."

# Clone the CSI hostpath driver repository if not exists
CSI_DRIVER_DIR="/tmp/csi-driver-host-path"
CSI_DRIVER_REPO="https://github.com/kubernetes-csi/csi-driver-host-path.git"

if [ ! -d "$CSI_DRIVER_DIR" ]; then
    echo "Cloning CSI hostpath driver repository..."

    # Retry git clone up to 3 times (network issues)
    CLONE_RETRIES=0
    MAX_CLONE_RETRIES=3
    until [ $CLONE_RETRIES -ge $MAX_CLONE_RETRIES ]; do
        if git clone --depth 1 "$CSI_DRIVER_REPO" "$CSI_DRIVER_DIR"; then
            echo "✓ Successfully cloned CSI driver repository"
            break
        fi
        CLONE_RETRIES=$((CLONE_RETRIES + 1))
        if [ $CLONE_RETRIES -lt $MAX_CLONE_RETRIES ]; then
            echo "Clone failed, retrying ($CLONE_RETRIES/$MAX_CLONE_RETRIES)..."
            sleep 5
        else
            echo "✗ Failed to clone repository after $MAX_CLONE_RETRIES attempts"
            exit 1
        fi
    done
fi

cd "$CSI_DRIVER_DIR"

# Deploy with snapshot metadata support enabled
echo "Deploying CSI driver with SNAPSHOT_METADATA_TESTS=true..."
SNAPSHOT_METADATA_TESTS=true ./deploy/kubernetes-latest/deploy.sh

echo "Waiting for CSI driver pods to be created..."
RETRIES=0
MAX_RETRIES=30
until kubectl get pods -n kube-system -l app=csi-hostpathplugin 2>/dev/null | grep -q csi-hostpath; do
    if [ $RETRIES -ge $MAX_RETRIES ]; then
        echo "✗ CSI driver pods not created within timeout"
        kubectl get pods -n kube-system
        exit 1
    fi
    echo "Waiting for pods to be created... ($RETRIES/$MAX_RETRIES)"
    sleep 2
    RETRIES=$((RETRIES + 1))
done

echo "Waiting for CSI driver pods to be ready..."
kubectl wait --for=condition=Ready pod -l app=csi-hostpathplugin -n kube-system --timeout=300s

echo "✓ CSI Hostpath Driver with CBT support deployed successfully!"
echo ""
echo "Verifying deployment..."
kubectl get pods -n kube-system -l app=csi-hostpathplugin
echo ""
kubectl get csidriver
echo ""

# Check if SnapshotMetadataService CRD is installed
if kubectl get crd snapshotmetadataservices.snapshotmetadata.storage.k8s.io &> /dev/null; then
    echo "✓ SnapshotMetadataService CRD is installed"
    kubectl get snapshotmetadataservices -A 2>/dev/null || echo "No SnapshotMetadataService instances yet"
else
    echo "✗ SnapshotMetadataService CRD not found - CBT may not be fully enabled"
fi

echo ""
echo "CSI driver deployment complete!"
