#!/bin/bash
set -euo pipefail

NAMESPACE="${1:-cbt-demo}"
SNAPSHOT_NAME="${2:-}"

echo "=========================================="
echo "Restore Dry Run"
echo "=========================================="

if [ -z "$SNAPSHOT_NAME" ]; then
    echo "Usage: $0 [namespace] <snapshot-name>"
    echo ""
    echo "Available snapshots:"
    kubectl get volumesnapshot -n "$NAMESPACE" -o custom-columns=NAME:.metadata.name,READY:.status.readyToUse,SOURCE:.spec.source.persistentVolumeClaimName
    exit 1
fi

# Check if snapshot exists
if ! kubectl get volumesnapshot "$SNAPSHOT_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "Error: Snapshot '$SNAPSHOT_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

# Get snapshot details
echo "Snapshot Details:"
echo ""
kubectl get volumesnapshot "$SNAPSHOT_NAME" -n "$NAMESPACE" -o yaml | grep -A 10 "status:"

# Get the source PVC
SOURCE_PVC=$(kubectl get volumesnapshot "$SNAPSHOT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.source.persistentVolumeClaimName}')
echo ""
echo "Source PVC: $SOURCE_PVC"

# Check restore size
RESTORE_SIZE=$(kubectl get volumesnapshot "$SNAPSHOT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.restoreSize}')
echo "Restore Size: $RESTORE_SIZE"

# Simulate creating a new PVC from this snapshot
echo ""
echo "=========================================="
echo "Dry Run: Creating PVC from snapshot"
echo "=========================================="
echo ""
echo "Would create PVC with the following spec:"
echo ""
cat <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${SOURCE_PVC}-restored
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Block
  storageClassName: csi-hostpath-sc
  dataSource:
    name: $SNAPSHOT_NAME
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  resources:
    requests:
      storage: $RESTORE_SIZE
EOF

echo ""
echo "=========================================="
echo "Dry Run: Checking snapshot chain"
echo "=========================================="
echo ""

# Check for base snapshots (if this is an incremental snapshot)
echo "Snapshot chain analysis:"
echo "  Snapshot: $SNAPSHOT_NAME"
echo "  Size: $RESTORE_SIZE"
echo "  Ready: $(kubectl get volumesnapshot "$SNAPSHOT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyToUse}')"

# List all snapshots from the same source PVC
echo ""
echo "All snapshots from source PVC '$SOURCE_PVC':"
kubectl get volumesnapshot -n "$NAMESPACE" -o json | \
  jq -r ".items[] | select(.spec.source.persistentVolumeClaimName == \"$SOURCE_PVC\") | \
  {name: .metadata.name, created: .metadata.creationTimestamp, size: .status.restoreSize, ready: .status.readyToUse}"

echo ""
echo "=========================================="
echo "Restore Validation"
echo "=========================================="
echo ""

# Validate the snapshot is ready
READY=$(kubectl get volumesnapshot "$SNAPSHOT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyToUse}')
if [ "$READY" == "true" ]; then
    echo "✓ Snapshot is ready to use"
else
    echo "✗ Snapshot is not ready - cannot restore"
    exit 1
fi

# Check if target PVC already exists
if kubectl get pvc "${SOURCE_PVC}-restored" -n "$NAMESPACE" &> /dev/null; then
    echo "⚠ Target PVC '${SOURCE_PVC}-restored' already exists"
    echo "  You would need to delete it first or choose a different name"
else
    echo "✓ Target PVC '${SOURCE_PVC}-restored' is available"
fi

echo ""
echo "=========================================="
echo "Dry Run Complete"
echo "=========================================="
echo ""
echo "To actually perform the restore, run:"
echo "  kubectl apply -f <(cat <<EOF"
echo "apiVersion: v1"
echo "kind: PersistentVolumeClaim"
echo "metadata:"
echo "  name: ${SOURCE_PVC}-restored"
echo "  namespace: $NAMESPACE"
echo "spec:"
echo "  accessModes: [ReadWriteOnce]"
echo "  volumeMode: Block"
echo "  storageClassName: csi-hostpath-sc"
echo "  dataSource:"
echo "    name: $SNAPSHOT_NAME"
echo "    kind: VolumeSnapshot"
echo "    apiGroup: snapshot.storage.k8s.io"
echo "  resources:"
echo "    requests:"
echo "      storage: $RESTORE_SIZE"
echo "EOF"
echo "  )"
