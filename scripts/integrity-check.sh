#!/bin/bash
set -euo pipefail

NAMESPACE="${1:-cbt-demo}"

echo "=========================================="
echo "Backup Integrity Check"
echo "=========================================="

EXIT_CODE=0

# Check PostgreSQL data integrity
echo "Checking PostgreSQL data..."
if kubectl get pod -n "$NAMESPACE" -l app=postgres &> /dev/null; then
    POSTGRES_POD=$(kubectl get pod -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}')

    if [ -n "$POSTGRES_POD" ]; then
        echo "✓ PostgreSQL pod found: $POSTGRES_POD"
        echo ""

        # Check if PostgreSQL is ready
        if kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- pg_isready -U demo &> /dev/null; then
            echo "✓ PostgreSQL is ready"

            # Get row count
            echo ""
            echo "Database statistics:"
            kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U demo -d cbtdemo -c \
                "SELECT COUNT(*) as total_rows,
                        pg_size_pretty(pg_total_relation_size('demo_data')) as table_size
                 FROM demo_data;" 2>/dev/null || {
                echo "✗ Failed to query database"
                EXIT_CODE=1
            }

            # Verify checksums
            echo ""
            echo "Verifying data checksums (sampling)..."
            CHECKSUM_ERRORS=$(kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U demo -d cbtdemo -t -c \
                "SELECT COUNT(*) FROM demo_data
                 WHERE checksum != md5(content)
                 LIMIT 100;" 2>/dev/null | tr -d ' ')

            if [ "$CHECKSUM_ERRORS" == "0" ]; then
                echo "✓ Checksum validation passed (sampled 100 rows)"
            else
                echo "✗ Found $CHECKSUM_ERRORS checksum mismatches"
                EXIT_CODE=1
            fi

            # Check for data blocks distribution
            echo ""
            echo "Data block distribution:"
            kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U demo -d cbtdemo -c \
                "SELECT MIN(data_block) as min_block,
                        MAX(data_block) as max_block,
                        COUNT(DISTINCT data_block) as unique_blocks
                 FROM demo_data;" 2>/dev/null

        else
            echo "✗ PostgreSQL is not ready"
            EXIT_CODE=1
        fi
    else
        echo "✗ No PostgreSQL pod found"
        EXIT_CODE=1
    fi
else
    echo "⚠ PostgreSQL pod not found in namespace '$NAMESPACE'"
    echo "  Skipping database integrity check"
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
# Get the postgres PVC specifically (not the first PVC which might be minio)
PVC_STATUS=$(kubectl get pvc -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].status.phase}')
VOLUME_MODE=$(kubectl get pvc -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].spec.volumeMode}')

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
