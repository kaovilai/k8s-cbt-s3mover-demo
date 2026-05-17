#!/bin/bash
set -euo pipefail

# Check required tools
if ! command -v kubectl &>/dev/null; then
    echo "Error: 'kubectl' is required but not found in PATH"
    exit 1
fi

# Portable base64 decode: macOS uses -D, Linux uses -d
_base64_decode() { base64 -d 2>/dev/null || base64 -D; }

NAMESPACE="${1:-cbt-demo}"

echo "=========================================="
echo "Backup Status Check"
echo "=========================================="

# Check VolumeSnapshots
echo "VolumeSnapshots in namespace '$NAMESPACE':"
echo ""
if kubectl get volumesnapshot -n "$NAMESPACE" &> /dev/null; then
    kubectl get volumesnapshot -n "$NAMESPACE" -o custom-columns=\
NAME:.metadata.name,\
READY:.status.readyToUse,\
SOURCE:.spec.source.persistentVolumeClaimName,\
SIZE:.status.restoreSize,\
AGE:.metadata.creationTimestamp
    echo ""
    SNAPSHOT_COUNT=$(kubectl get volumesnapshot -n "$NAMESPACE" --no-headers | wc -l | tr -d '[:space:]')
    echo "Total snapshots: $SNAPSHOT_COUNT"
else
    echo "No VolumeSnapshots found in namespace '$NAMESPACE'"
fi

# Check VolumeSnapshotContents (actual storage)
echo ""
echo "VolumeSnapshotContents (actual snapshot storage):"
echo ""
kubectl get volumesnapshotcontent -o custom-columns=\
NAME:.metadata.name,\
READY:.status.readyToUse,\
SIZE:.status.restoreSize,\
SNAPSHOT:.spec.volumeSnapshotRef.name,\
AGE:.metadata.creationTimestamp 2>/dev/null || echo "No VolumeSnapshotContents found"

# Check MinIO S3 storage (if accessible)
echo ""
echo "=========================================="
echo "S3 Storage Status (MinIO)"
echo "=========================================="

# Try to connect to MinIO and get bucket info
if kubectl get pod -n "$NAMESPACE" -l app=minio &> /dev/null; then
    echo "MinIO pod status:"
    kubectl get pod -n "$NAMESPACE" -l app=minio

    # Use kubectl exec to check bucket contents
    MINIO_POD=$(kubectl get pod -n "$NAMESPACE" -l app=minio -o jsonpath='{.items[0].metadata.name}')
    MINIO_USER=$(kubectl get secret minio-credentials -n "$NAMESPACE" -o jsonpath='{.data.root-user}' | _base64_decode)
    MINIO_PASS=$(kubectl get secret minio-credentials -n "$NAMESPACE" -o jsonpath='{.data.root-password}' | _base64_decode)
    echo ""
    echo "Attempting to check S3 bucket contents..."
    kubectl exec -n "$NAMESPACE" "$MINIO_POD" -- sh -c "
        mc alias set local http://localhost:9000 '${MINIO_USER}' '${MINIO_PASS}' 2>/dev/null || true
        echo 'Buckets:'
        mc ls local/ 2>/dev/null || echo 'Cannot list buckets'
        echo ''
        echo 'Snapshots bucket contents:'
        mc ls --recursive local/snapshots/ 2>/dev/null || echo 'Bucket not found or empty'
        echo ''
        echo 'Storage usage:'
        mc du local/snapshots/ 2>/dev/null || echo 'Cannot calculate usage'
    " 2>/dev/null || echo "Cannot access MinIO pod"
else
    echo "MinIO pod not found in namespace '$NAMESPACE'"
fi

echo ""
echo "=========================================="
echo "Backup Status Summary"
echo "=========================================="
echo "✓ Check complete"
