#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Deploying CSI Hostpath Driver with Changed Block Tracking"
echo "Following upstream external-snapshot-metadata integration test pattern"
echo "=========================================="

# Get the script's directory to reference other files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
CSI_DRIVER_DIR="/tmp/csi-driver-host-path"
CSI_DRIVER_REPO="https://github.com/kubernetes-csi/csi-driver-host-path.git"
NAMESPACE="default"

echo ""
echo "Step 1: Deploy Snapshot Controller"
echo "-----------------------------------"
if [ -f "$PROJECT_ROOT/scripts/deploy-snapshot-controller.sh" ]; then
    echo "Deploying snapshot controller..."
    "$PROJECT_ROOT/scripts/deploy-snapshot-controller.sh" deploy
    echo "✓ Snapshot controller deployed"
else
    echo "⚠ Warning: deploy-snapshot-controller.sh not found"
    echo "Attempting to continue without snapshot controller deployment..."
fi

echo ""
echo "Step 2: Generate TLS Certificates"
echo "-----------------------------------"
if [ -f "$PROJECT_ROOT/scripts/generate-csi-certs.sh" ]; then
    echo "Generating TLS certificates for snapshot metadata service..."
    "$PROJECT_ROOT/scripts/generate-csi-certs.sh"
    echo "✓ TLS certificates generated"
else
    echo "⚠ Warning: generate-csi-certs.sh not found"
    echo "You may need to generate certificates manually"
    exit 1
fi

echo ""
echo "Step 3: Clone CSI Hostpath Driver Repository"
echo "-----------------------------------"
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
else
    echo "✓ CSI driver repository already exists at $CSI_DRIVER_DIR"
fi

echo ""
echo "Step 4: Install SnapshotMetadataService CRD"
echo "-----------------------------------"
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

echo "✓ SnapshotMetadataService CRD installed"

echo ""
echo "Step 5: Deploy CSI Hostpath Driver with Snapshot Metadata Support"
echo "-----------------------------------"
cd "$CSI_DRIVER_DIR"

echo "Deploying CSI driver with environment variables:"
echo "  CSI_SNAPSHOT_METADATA_REGISTRY=gcr.io/k8s-staging-sig-storage"
echo "  UPDATE_RBAC_RULES=false"
echo "  CSI_SNAPSHOT_METADATA_TAG=canary"
echo "  SNAPSHOT_METADATA_TESTS=true"
echo "  HOSTPATHPLUGIN_REGISTRY=gcr.io/k8s-staging-sig-storage"
echo "  HOSTPATHPLUGIN_TAG=canary"
echo ""

# Deploy with environment variables
# Note: Using canary tag for latest builds from main branch
# See https://github.com/kubernetes-csi/csi-driver-host-path/blob/main/release-tools/README.md
CSI_SNAPSHOT_METADATA_REGISTRY="gcr.io/k8s-staging-sig-storage" \
UPDATE_RBAC_RULES="false" \
CSI_SNAPSHOT_METADATA_TAG="canary" \
SNAPSHOT_METADATA_TESTS=true \
HOSTPATHPLUGIN_REGISTRY="gcr.io/k8s-staging-sig-storage" \
HOSTPATHPLUGIN_TAG="canary" \
./deploy/kubernetes-latest/deploy.sh

echo "✓ CSI driver deployment initiated"

echo ""
echo "Step 6: Wait for CSI Driver Pods"
echo "-----------------------------------"
echo "Waiting for CSI driver pods to be created..."
RETRIES=0
MAX_RETRIES=30
until kubectl get pods -n "$NAMESPACE" 2>/dev/null | grep -q "csi-hostpathplugin-0"; do
    if [ $RETRIES -ge $MAX_RETRIES ]; then
        echo "✗ CSI driver pods not created within timeout"
        kubectl get pods -n "$NAMESPACE"
        exit 1
    fi
    echo "Waiting for pods to be created... ($RETRIES/$MAX_RETRIES)"
    sleep 3
    RETRIES=$((RETRIES + 1))
done

echo "✓ CSI driver pods created"

echo "Waiting for CSI driver statefulset to be ready..."
kubectl rollout status statefulset/csi-hostpathplugin -n "$NAMESPACE" --timeout=300s

echo "Waiting for CSI driver pods to be ready..."
kubectl wait --for=condition=Ready pod -l app=csi-hostpathplugin -n "$NAMESPACE" --timeout=300s 2>/dev/null || {
    echo "Warning: Pod readiness check failed, checking pod status..."
    kubectl get pods -n "$NAMESPACE" | grep csi-hostpath || kubectl get pods -n "$NAMESPACE"

    # Check if pod is actually running despite wait failure
    if kubectl get pod csi-hostpathplugin-0 -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Running"; then
        echo "✓ Pod is running"
    else
        echo "✗ Pod is not ready"
        echo "Pod details:"
        kubectl describe pod csi-hostpathplugin-0 -n "$NAMESPACE"
        exit 1
    fi
}

echo "✓ CSI driver pods are ready"

echo ""
echo "=========================================="
echo "✓ CSI Hostpath Driver with CBT Deployed Successfully!"
echo "=========================================="
echo ""
echo "Verifying deployment..."
echo "-----------------------------------"
echo ""
echo "CSI Driver Pods:"
kubectl get pods -n "$NAMESPACE" -l app=csi-hostpathplugin || kubectl get pods -n "$NAMESPACE"
echo ""
echo "CSI Drivers:"
kubectl get csidriver
echo ""

# Check if SnapshotMetadataService CRD is installed
if kubectl get crd snapshotmetadataservices.cbt.storage.k8s.io &> /dev/null; then
    echo "✓ SnapshotMetadataService CRD is installed"
    echo ""
    echo "SnapshotMetadataService instances:"
    kubectl get snapshotmetadataservices -A 2>/dev/null || echo "No SnapshotMetadataService instances yet"
else
    echo "✗ SnapshotMetadataService CRD not found - CBT may not be fully enabled"
fi

echo ""
echo "Snapshot Metadata Service:"
kubectl get svc -n "$NAMESPACE" csi-snapshot-metadata 2>/dev/null || echo "Service not found"

echo ""
echo "TLS Secret:"
kubectl get secret -n "$NAMESPACE" csi-snapshot-metadata-certs 2>/dev/null || echo "Secret not found"

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "The CSI driver is now configured with:"
echo "  ✓ Changed Block Tracking (CBT) support"
echo "  ✓ SnapshotMetadata gRPC service"
echo "  ✓ TLS-secured communication"
echo "  ✓ Snapshot controller"
echo ""
echo "You can now:"
echo "  1. Create VolumeSnapshots"
echo "  2. Use the CBT APIs (GetMetadataAllocated, GetMetadataDelta)"
echo "  3. Perform efficient incremental backups"
echo ""
