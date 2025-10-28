#!/bin/bash
set -euo pipefail

NAMESPACE="${1:-cbt-demo}"

echo "=========================================="
echo "Backup Integrity Check"
echo "=========================================="

EXIT_CODE=0

# Check block-writer workload integrity
echo "Checking block-writer workload..."
if kubectl get pod -n "$NAMESPACE" -l app=block-writer &> /dev/null; then
    BLOCK_WRITER_POD=$(kubectl get pod -n "$NAMESPACE" -l app=block-writer -o jsonpath='{.items[0].metadata.name}')

    if [ -n "$BLOCK_WRITER_POD" ]; then
        echo "✓ Block-writer pod found: $BLOCK_WRITER_POD"
        echo ""

        # Check if block device is accessible
        if kubectl exec -n "$NAMESPACE" "$BLOCK_WRITER_POD" -- test -b /dev/xvda &> /dev/null; then
            echo "✓ Block device /dev/xvda is accessible"

            # Get device size
            echo ""
            echo "Block device information:"
            kubectl exec -n "$NAMESPACE" "$BLOCK_WRITER_POD" -- sh -c \
                "blockdev --getsize64 /dev/xvda | awk '{printf \"Device size: %.2f MB\\n\", \$1/1024/1024}'" 2>/dev/null || {
                echo "✗ Failed to get device size"
                EXIT_CODE=1
            }

            # Sample some blocks to verify data was written
            echo ""
            echo "Sampling block data (checking for non-zero blocks)..."
            NON_ZERO_BLOCKS=0

            # Check a few known write positions: seek 1,3,5,7,9 (initial write)
            for seek_pos in 1 3 5 7 9; do
                HAS_DATA=$(kubectl exec -n "$NAMESPACE" "$BLOCK_WRITER_POD" -- sh -c \
                    "dd if=/dev/xvda bs=4K count=1 skip=$seek_pos 2>/dev/null | tr -d '\\0' | wc -c" 2>/dev/null || echo "0")

                if [ "$HAS_DATA" -gt 0 ]; then
                    NON_ZERO_BLOCKS=$((NON_ZERO_BLOCKS + 1))
                fi
            done

            if [ "$NON_ZERO_BLOCKS" -gt 0 ]; then
                echo "✓ Found $NON_ZERO_BLOCKS non-zero blocks (data is present)"
            else
                echo "⚠ No non-zero blocks found (data may not have been written yet)"
            fi

        else
            echo "✗ Block device /dev/xvda is not accessible"
            EXIT_CODE=1
        fi
    else
        echo "✗ No block-writer pod found"
        EXIT_CODE=1
    fi
else
    echo "⚠ Block-writer pod not found in namespace '$NAMESPACE'"
    echo "  Skipping workload integrity check"
fi

# Check PVC status
echo ""
echo "=========================================="
echo "PVC Integrity Check"
echo "=========================================="
echo ""
kubectl get pvc -n "$NAMESPACE" -o custom-columns=\
NAME:.metadata.name,\
STATUS:.status.phase,\
VOLUME:.spec.volumeName,\
CAPACITY:.status.capacity.storage,\
ACCESS:.spec.accessModes,\
STORAGECLASS:.spec.storageClassName,\
MODE:.spec.volumeMode

# Verify PVC is bound and using block mode
# Get the block-writer PVC specifically (not the first PVC which might be minio)
PVC_STATUS=$(kubectl get pvc -n "$NAMESPACE" block-writer-data -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
VOLUME_MODE=$(kubectl get pvc -n "$NAMESPACE" block-writer-data -o jsonpath='{.spec.volumeMode}' 2>/dev/null || echo "NotFound")

if [ "$PVC_STATUS" == "Bound" ]; then
    echo ""
    echo "✓ PVC is bound"
else
    echo ""
    echo "✗ PVC is not bound (status: $PVC_STATUS)"
    EXIT_CODE=1
fi

if [ "$VOLUME_MODE" == "Block" ]; then
    echo "✓ PVC is using Block mode (required for CBT)"
else
    echo "✗ PVC is not using Block mode (found: $VOLUME_MODE)"
    EXIT_CODE=1
fi

# Check VolumeSnapshots integrity
echo ""
echo "=========================================="
echo "Snapshot Integrity Check"
echo "=========================================="
echo ""

if kubectl get volumesnapshot -n "$NAMESPACE" &> /dev/null; then
    SNAPSHOT_COUNT=$(kubectl get volumesnapshot -n "$NAMESPACE" --no-headers | wc -l)

    if [ "$SNAPSHOT_COUNT" -gt 0 ]; then
        echo "Found $SNAPSHOT_COUNT snapshot(s)"
        echo ""

        # Check each snapshot
        for snapshot in $(kubectl get volumesnapshot -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
            READY=$(kubectl get volumesnapshot "$snapshot" -n "$NAMESPACE" -o jsonpath='{.status.readyToUse}')
            SIZE=$(kubectl get volumesnapshot "$snapshot" -n "$NAMESPACE" -o jsonpath='{.status.restoreSize}')
            ERROR=$(kubectl get volumesnapshot "$snapshot" -n "$NAMESPACE" -o jsonpath='{.status.error.message}')

            if [ "$READY" == "true" ]; then
                echo "✓ Snapshot '$snapshot' is ready (size: $SIZE)"
            else
                echo "✗ Snapshot '$snapshot' is not ready"
                if [ -n "$ERROR" ]; then
                    echo "  Error: $ERROR"
                fi
                EXIT_CODE=1
            fi
        done
    else
        echo "⚠ No snapshots found"
    fi
else
    echo "⚠ Cannot query snapshots"
fi

# Check S3/MinIO backup files
echo ""
echo "=========================================="
echo "S3 Backup Integrity Check"
echo "=========================================="
echo ""

if kubectl get pod -n cbt-demo -l app=minio &> /dev/null; then
    MINIO_POD=$(kubectl get pod -n cbt-demo -l app=minio -o jsonpath='{.items[0].metadata.name}')

    if [ -n "$MINIO_POD" ]; then
        echo "Checking S3 backup files..."
        kubectl exec -n cbt-demo "$MINIO_POD" -- sh -c "
            mc alias set local http://localhost:9000 minioadmin minioadmin123 2>/dev/null

            # Check if bucket exists
            if mc ls local/snapshots/ &>/dev/null; then
                echo '✓ Snapshots bucket exists'

                # Count metadata files
                METADATA_COUNT=\$(mc find local/snapshots/metadata/ --name '*.json' 2>/dev/null | wc -l)
                echo \"Found \$METADATA_COUNT metadata files\"

                # Count block files
                BLOCK_COUNT=\$(mc find local/snapshots/blocks/ 2>/dev/null | wc -l)
                echo \"Found \$BLOCK_COUNT block files\"

                # Show storage usage
                echo ''
                echo 'Storage usage:'
                mc du local/snapshots/
            else
                echo '⚠ Snapshots bucket not found (no backups created yet)'
            fi
        " || {
            echo "✗ Failed to check S3 backup files"
            EXIT_CODE=1
        }
    fi
else
    echo "⚠ MinIO pod not found - skipping S3 check"
fi

echo ""
echo "=========================================="
echo "Integrity Check Summary"
echo "=========================================="

if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ All integrity checks PASSED"
else
    echo "✗ Some integrity checks FAILED"
    echo "  Please review the errors above"
fi

exit $EXIT_CODE
