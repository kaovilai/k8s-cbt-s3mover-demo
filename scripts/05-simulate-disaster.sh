#!/bin/bash
set -euo pipefail

NAMESPACE="${1:-cbt-demo}"
POD_NAME="block-writer"
PVC_NAME="block-writer-data"
DEVICE="/dev/xvda"

echo "=========================================="
echo "Simulating Disaster Scenario"
echo "=========================================="
echo ""
echo "⚠️  WARNING: This will DELETE:"
echo "  - Block-writer Pod"
echo "  - Block-writer PVC"
echo "  - All data on the block device"
echo ""
echo "VolumeSnapshots will be PRESERVED for restore."
echo ""
read -r -p "Are you sure you want to continue? (type 'yes' to proceed): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "[1/4] Saving current state for verification..."

# Get checksum of a block from the device (first 1MB)
BLOCK_WRITER_POD=$(kubectl get pod -n "$NAMESPACE" "$POD_NAME" -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")

if [ -n "$BLOCK_WRITER_POD" ]; then
    echo "  Computing checksum of first 256 blocks (1MB) from device..."
    PRE_DISASTER_CHECKSUM=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- dd if="$DEVICE" bs=4096 count=256 2>/dev/null | md5sum | awk '{print $1}')
    echo "  Device checksum (first 1MB): $PRE_DISASTER_CHECKSUM"
    echo "$PRE_DISASTER_CHECKSUM" > /tmp/cbt-demo-pre-disaster-checksum.txt
    echo "  Saved to /tmp/cbt-demo-pre-disaster-checksum.txt"
else
    echo "  Block-writer pod not found"
    PRE_DISASTER_CHECKSUM="unknown"
fi

# List snapshots
echo ""
echo "[2/4] Listing available snapshots (these will be preserved)..."
kubectl get volumesnapshot -n "$NAMESPACE" -o custom-columns=\
NAME:.metadata.name,\
READY:.status.readyToUse,\
SIZE:.status.restoreSize,\
AGE:.metadata.creationTimestamp

# Delete block-writer pod
echo ""
echo "[3/4] Deleting block-writer pod..."
if kubectl get pod -n "$NAMESPACE" "$POD_NAME" &>/dev/null; then
    kubectl delete pod "$POD_NAME" -n "$NAMESPACE" --grace-period=10
    echo "✓ Pod deleted"
else
    echo "  Pod not found, skipping"
fi

# Delete PVC
echo ""
echo "[4/4] Deleting block-writer PVC..."
if kubectl get pvc -n "$NAMESPACE" "$PVC_NAME" &>/dev/null; then
    kubectl delete pvc "$PVC_NAME" -n "$NAMESPACE" --grace-period=10
    echo "✓ PVC deleted"
else
    echo "  PVC not found, skipping"
fi

# Wait for PVC to be fully deleted
echo "  Waiting for PVC to be fully removed..."
kubectl wait --for=delete pvc/"$PVC_NAME" -n "$NAMESPACE" --timeout=60s 2>/dev/null || true

echo ""
echo "=========================================="
echo "Disaster Simulation Complete"
echo "=========================================="
echo ""
echo "What was deleted:"
echo "  ✗ Block-writer pod"
echo "  ✗ Block-writer PVC ($PVC_NAME)"
echo "  ✗ All block device data"
echo ""
echo "What was preserved:"
echo "  ✓ VolumeSnapshots in namespace $NAMESPACE"
echo "  ✓ VolumeSnapshotContents"
echo "  ✓ Underlying snapshot data in CSI driver"
echo ""
echo "To verify snapshots are still available:"
echo "  kubectl get volumesnapshot -n $NAMESPACE"
echo "  kubectl get volumesnapshotcontent | grep $NAMESPACE"
echo ""
echo "To restore from snapshot:"
echo "  ./scripts/06-restore.sh"
echo ""
if [ "$PRE_DISASTER_CHECKSUM" != "unknown" ]; then
    echo "Expected checksum after restore: $PRE_DISASTER_CHECKSUM"
    echo "(Saved to /tmp/cbt-demo-pre-disaster-checksum.txt)"
fi
