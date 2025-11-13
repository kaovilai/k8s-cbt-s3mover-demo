#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Deploying CSI Hostpath Driver with CBT"
echo "=========================================="

# Run the CSI driver deployment script
# Note: Now using PR #621 branch which includes the upstream fix for duplicate sidecar injection
# Once PR #621 is merged, we can switch back to the main branch
./manifests/csi-driver/deploy-with-cbt.sh

# Apply the StorageClass
echo "Creating StorageClass..."
kubectl apply -f manifests/csi-driver/storage-class.yaml

# Apply the VolumeSnapshotClass
echo "Creating VolumeSnapshotClass..."
kubectl apply -f manifests/csi-driver/snapshot-class.yaml

echo ""
echo "✓ CSI Hostpath Driver with CBT deployed successfully!"
echo ""
echo "Storage class available:"
kubectl get storageclass
echo ""
echo "VolumeSnapshotClass available:"
kubectl get volumesnapshotclass
