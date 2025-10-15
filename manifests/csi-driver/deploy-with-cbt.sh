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

# Install SnapshotMetadataService CRD first
echo "Installing SnapshotMetadataService CRD..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshot-metadata/v0.1.0/client/config/crd/cbt.storage.k8s.io_snapshotmetadataservices.yaml || {
    echo "Warning: Could not install SnapshotMetadataService CRD from v0.1.0"
    echo "Trying alternative location..."

    # Alternative: Try from the main branch
    kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshot-metadata/main/client/config/crd/cbt.storage.k8s.io_snapshotmetadataservices.yaml || {
        echo "Warning: Could not install SnapshotMetadataService CRD"
        echo "CBT functionality may be limited"
    }
}

# Wait for CRD to be available
echo "Waiting for CRD to be established..."
kubectl wait --for=condition=Established crd/snapshotmetadataservices.cbt.storage.k8s.io --timeout=60s 2>/dev/null || {
    echo "Note: SnapshotMetadataService CRD not established"
}

# Deploy with snapshot metadata support enabled
echo "Deploying CSI driver with SNAPSHOT_METADATA_TESTS=true..."
SNAPSHOT_METADATA_TESTS=true ./deploy/kubernetes-latest/deploy.sh

echo "Waiting for CSI driver pods to be created..."
RETRIES=0
MAX_RETRIES=30
until kubectl get pods -n default 2>/dev/null | grep -q "csi-hostpathplugin-0"; do
    if [ $RETRIES -ge $MAX_RETRIES ]; then
        echo "✗ CSI driver pods not created within timeout"
        kubectl get pods -n default
        exit 1
    fi
    echo "Waiting for pods to be created... ($RETRIES/$MAX_RETRIES)"
    sleep 3
    RETRIES=$((RETRIES + 1))
done

echo "✓ CSI driver pods created"
echo "Waiting for CSI driver statefulset to be ready..."
kubectl rollout status statefulset/csi-hostpathplugin -n default --timeout=300s

echo "Waiting for CSI driver pods to be ready..."
kubectl wait --for=condition=Ready pod/csi-hostpathplugin-0 -n default --timeout=300s 2>/dev/null || {
    echo "Warning: Pod readiness check failed, checking pod status..."
    kubectl get pods -n default | grep csi-hostpath
    # Check if pod is actually running despite wait failure
    if kubectl get pod csi-hostpathplugin-0 -n default -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; then
        echo "✓ Pod is running"
    else
        echo "✗ Pod is not ready"
        exit 1
    fi
}

echo "✓ CSI Hostpath Driver with CBT support deployed successfully!"
echo ""
echo "Verifying deployment..."
kubectl get pods -n default | grep csi-hostpath || kubectl get pods -n default
echo ""
kubectl get csidriver
echo ""

# Check if SnapshotMetadataService CRD is installed
if kubectl get crd snapshotmetadataservices.cbt.storage.k8s.io &> /dev/null; then
    echo "✓ SnapshotMetadataService CRD is installed"
    kubectl get snapshotmetadataservices -A 2>/dev/null || echo "No SnapshotMetadataService instances yet"
else
    echo "✗ SnapshotMetadataService CRD not found - CBT may not be fully enabled"
fi

echo ""
echo "CSI driver deployment complete!"
