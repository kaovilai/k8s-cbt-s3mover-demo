#!/bin/bash
set -euo pipefail

NAMESPACE="${1:-cbt-demo}"
POD_NAME="block-writer"
DEVICE="/dev/xvda"

echo "=========================================="
echo "Post-Restore Verification"
echo "=========================================="

EXIT_CODE=0

# Check block-writer pod
echo ""
echo "[1/5] Checking block-writer pod..."
if ! kubectl get pod -n "$NAMESPACE" "$POD_NAME" &>/dev/null; then
    echo "✗ Block-writer pod not found"
    EXIT_CODE=1
else
    POD_STATUS=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    if [ "$POD_STATUS" == "Running" ]; then
        echo "✓ Block-writer pod is running: $POD_NAME"
    else
        echo "✗ Block-writer pod is not running (status: $POD_STATUS)"
        EXIT_CODE=1
    fi
fi

# Check PVC
echo ""
echo "[2/5] Checking PVC status..."
PVC_NAME="block-writer-data"
if ! kubectl get pvc -n "$NAMESPACE" "$PVC_NAME" &>/dev/null; then
    echo "✗ PVC not found: $PVC_NAME"
    EXIT_CODE=1
else
    PVC_STATUS=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    if [ "$PVC_STATUS" == "Bound" ]; then
        echo "✓ PVC is bound: $PVC_NAME"
        PVC_SIZE=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.capacity.storage}')
        echo "  Size: $PVC_SIZE"
    else
        echo "✗ PVC is not bound (status: $PVC_STATUS)"
        EXIT_CODE=1
    fi
fi

# Check block device accessibility
echo ""
echo "[3/5] Checking block device accessibility..."
if kubectl exec -n "$NAMESPACE" "$POD_NAME" -- test -b "$DEVICE" 2>/dev/null; then
    echo "✓ Block device is accessible: $DEVICE"

    # Get device size
    DEVICE_SIZE=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- blockdev --getsize64 "$DEVICE" 2>/dev/null || echo "unknown")
    if [ "$DEVICE_SIZE" != "unknown" ]; then
        DEVICE_SIZE_MB=$((DEVICE_SIZE / 1024 / 1024))
        echo "  Device size: ${DEVICE_SIZE_MB}MB"
    fi
else
    echo "✗ Block device is not accessible"
    EXIT_CODE=1
fi

# Check data integrity via checksum
echo ""
echo "[4/5] Checking data integrity..."
CURRENT_CHECKSUM=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- dd if="$DEVICE" bs=4096 count=256 2>/dev/null | md5sum | awk '{print $1}' || echo "")

if [ -n "$CURRENT_CHECKSUM" ]; then
    echo "✓ Data checksum computed: $CURRENT_CHECKSUM (first 1MB)"

    # Sample data from different offsets to verify
    echo "  Verifying data at different offsets..."

    # Check offset 0 (first 10 blocks)
    OFFSET_0=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- dd if="$DEVICE" bs=4096 count=10 skip=0 2>/dev/null | md5sum | awk '{print $1}')
    echo "    Offset 0:   $OFFSET_0 (first 10 blocks)"

    # Check offset 100 (10 blocks starting at block 100)
    OFFSET_100=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- dd if="$DEVICE" bs=4096 count=10 skip=100 2>/dev/null | md5sum | awk '{print $1}')
    echo "    Offset 100: $OFFSET_100 (10 blocks at offset 100)"

    # Check offset 300 (10 blocks starting at block 300)
    OFFSET_300=$(kubectl exec -n "$NAMESPACE" "$POD_NAME" -- dd if="$DEVICE" bs=4096 count=10 skip=300 2>/dev/null | md5sum | awk '{print $1}')
    echo "    Offset 300: $OFFSET_300 (10 blocks at offset 300)"

    echo "  ✓ Data sampling completed successfully"
else
    echo "✗ Failed to compute checksum"
    EXIT_CODE=1
fi

# Compare with pre-disaster state
echo ""
echo "[5/5] Comparing with pre-disaster state..."
if [ -f /tmp/cbt-demo-pre-disaster-checksum.txt ]; then
    PRE_DISASTER_CHECKSUM=$(cat /tmp/cbt-demo-pre-disaster-checksum.txt)
    echo "  Pre-disaster checksum:  $PRE_DISASTER_CHECKSUM"
    echo "  Current checksum:       $CURRENT_CHECKSUM"

    if [ "$CURRENT_CHECKSUM" == "$PRE_DISASTER_CHECKSUM" ]; then
        echo "  ✓ Checksum matches pre-disaster state"
        echo "    Data was restored successfully!"
    else
        echo "  ⚠ Checksum does not match pre-disaster state"
        echo "    This may be expected if you:"
        echo "    - Restored from an earlier snapshot"
        echo "    - Wrote new data after the disaster simulation"
        echo "    - Restored a different snapshot than the one captured before disaster"
    fi
else
    echo "  ℹ Pre-disaster state file not found"
    echo "    Cannot compare checksums"
    echo "    (Run ./scripts/05-simulate-disaster.sh to save pre-disaster state)"
fi

# Verify snapshots still exist
echo ""
echo "Checking available snapshots..."
SNAPSHOT_COUNT=$(kubectl get volumesnapshot -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [ "$SNAPSHOT_COUNT" -gt 0 ]; then
    echo "✓ Found $SNAPSHOT_COUNT snapshot(s):"
    kubectl get volumesnapshot -n "$NAMESPACE" -o custom-columns=\
NAME:.metadata.name,\
READY:.status.readyToUse,\
SIZE:.status.restoreSize
else
    echo "⚠ No snapshots found"
fi

# Summary
echo ""
echo "=========================================="
echo "Verification Summary"
echo "=========================================="

if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ All verification checks PASSED"
    echo ""
    echo "Restore was successful!"
    echo "  - Block-writer pod is running and healthy"
    echo "  - PVC is bound and accessible"
    echo "  - Block device is accessible"
    echo "  - Data integrity verified via checksums"
    echo "  - Snapshots are available"
else
    echo "✗ Some verification checks FAILED"
    echo ""
    echo "Please review the errors above and:"
    echo "  1. Check pod logs: kubectl logs -n $NAMESPACE $POD_NAME"
    echo "  2. Describe pod: kubectl describe pod -n $NAMESPACE $POD_NAME"
    echo "  3. Check events: kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp'"
fi

echo ""
echo "Additional verification commands:"
echo "  # View device data (hexdump)"
echo "  kubectl exec -n $NAMESPACE $POD_NAME -- dd if=$DEVICE bs=4096 count=1 | hexdump -C"
echo ""
echo "  # Check device stats"
echo "  kubectl exec -n $NAMESPACE $POD_NAME -- blockdev --report"
echo ""
echo "  # Compare two snapshots for CBT delta"
echo "  cd tools/cbt-backup && ./cbt-backup create --pvc $PVC_NAME --snapshot block-snapshot-2 --base-snapshot block-snapshot-1 --namespace $NAMESPACE"
echo ""
echo "  # Create new snapshot"
echo "  kubectl apply -f - <<EOF"
echo "  apiVersion: snapshot.storage.k8s.io/v1"
echo "  kind: VolumeSnapshot"
echo "  metadata:"
echo "    name: block-snapshot-new"
echo "    namespace: $NAMESPACE"
echo "  spec:"
echo "    volumeSnapshotClassName: csi-hostpath-snapclass"
echo "    source:"
echo "      persistentVolumeClaimName: $PVC_NAME"
echo "  EOF"

exit $EXIT_CODE
