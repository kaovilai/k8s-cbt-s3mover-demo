#!/bin/bash
set -euo pipefail

if ! command -v kubectl &>/dev/null; then
    echo "Error: 'kubectl' is required but not found in PATH"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=detect-storage.sh
source "$SCRIPT_DIR/detect-storage.sh"

NAMESPACE="${1:-cbt-demo}"
SNAPSHOT_NAME="${2:-block-snapshot-3}"  # Default to latest snapshot

# Portable md5 helper: md5sum (Linux) vs md5 -q (macOS)
_md5() { if command -v md5sum &>/dev/null; then md5sum | awk '{print $1}'; else md5 -q; fi; }

echo "=========================================="
echo "Restore from Snapshot"
echo "=========================================="
echo ""
echo "This will restore the block-writer workload from snapshot: $SNAPSHOT_NAME"
echo ""

# Check if snapshot exists
if ! kubectl get volumesnapshot "$SNAPSHOT_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "Error: Snapshot '$SNAPSHOT_NAME' not found in namespace '$NAMESPACE'"
    echo ""
    echo "Available snapshots:"
    kubectl get volumesnapshot -n "$NAMESPACE"
    exit 1
fi

# Get snapshot details
SNAPSHOT_SIZE=$(kubectl get volumesnapshot "$SNAPSHOT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.restoreSize}')
SNAPSHOT_READY=$(kubectl get volumesnapshot "$SNAPSHOT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyToUse}')

echo "Snapshot Details:"
echo "  Name:        $SNAPSHOT_NAME"
echo "  Size:        $SNAPSHOT_SIZE"
echo "  Ready:       $SNAPSHOT_READY"
echo ""

if [ "$SNAPSHOT_READY" != "true" ]; then
    echo "Error: Snapshot is not ready to use"
    exit 1
fi

if [ "${NON_INTERACTIVE:-false}" = "false" ]; then
    read -r -p "Press Enter to continue with restore..."
fi

# Step 1: Create PVC from snapshot
echo ""
echo "[1/3] Creating PVC from snapshot..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: block-writer-data
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  volumeMode: Block
  storageClassName: $STORAGE_CLASS
  dataSource:
    name: $SNAPSHOT_NAME
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  resources:
    requests:
      storage: $SNAPSHOT_SIZE
EOF

echo "  Waiting for PVC to be bound..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound \
  pvc/block-writer-data -n "$NAMESPACE" --timeout=300s

echo "✓ PVC created from snapshot and bound"

# Step 2: Deploy block-writer pod
echo ""
echo "[2/3] Deploying block-writer pod..."

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: block-writer
  namespace: $NAMESPACE
  labels:
    app: block-writer
    app.kubernetes.io/name: block-writer
    app.kubernetes.io/component: workload
    app.kubernetes.io/part-of: k8s-cbt-s3mover-demo
spec:
  restartPolicy: Always
  automountServiceAccountToken: false
  containers:
  - name: writer
    image: busybox:1.37.0
    command:
    - /bin/sh
    - -c
    - "tail -f /dev/null"
    securityContext:
      privileged: true
    volumeDevices:
    - name: data-volume
      devicePath: /dev/xvda
    resources:
      requests:
        memory: "32Mi"
        cpu: "10m"
      limits:
        memory: "64Mi"
        cpu: "100m"
  volumes:
  - name: data-volume
    persistentVolumeClaim:
      claimName: block-writer-data
EOF

echo "  Waiting for pod to be ready..."
kubectl wait --for=condition=Ready pod/block-writer -n "$NAMESPACE" --timeout=300s

echo "✓ Block-writer pod is ready"

# Step 3: Verify data
echo ""
echo "[3/3] Verifying restored data..."

# Compute checksum of restored data (first 1MB)
RESTORED_CHECKSUM=$(kubectl exec -n "$NAMESPACE" block-writer -- dd if=/dev/xvda bs=4096 count=256 2>/dev/null | _md5)

echo ""
echo "=========================================="
echo "Restore Complete!"
echo "=========================================="
echo ""
echo "Block-writer Status:"
echo "  Pod:       block-writer"
echo "  Namespace: $NAMESPACE"
echo "  Status:    Running"
echo "  Checksum:  $RESTORED_CHECKSUM (first 1MB of device)"
echo ""

# Compare with pre-disaster state if available
if [ -f /tmp/cbt-demo-pre-disaster-checksum.txt ]; then
    PRE_DISASTER_CHECKSUM=$(cat /tmp/cbt-demo-pre-disaster-checksum.txt)
    echo "Pre-disaster checksum:  $PRE_DISASTER_CHECKSUM"
    echo "Restored checksum:      $RESTORED_CHECKSUM"
    echo ""
    if [ "$RESTORED_CHECKSUM" == "$PRE_DISASTER_CHECKSUM" ]; then
        echo "✓ Data restored successfully! Checksum matches pre-disaster state."
    else
        echo "⚠ Checksum mismatch. This may be expected if you restored from an earlier snapshot."
        echo "  Each snapshot captures the device state at a different point in time."
    fi
else
    echo "Pre-disaster state not found. Cannot compare checksums."
    echo "(Run ./scripts/05-simulate-disaster.sh to save pre-disaster state)"
fi

echo ""
echo "To verify the block device:"
echo "  kubectl exec -n $NAMESPACE block-writer -- dd if=/dev/xvda bs=4096 count=100 | hexdump -C | head -20"
echo ""
echo "To run verification script:"
echo "  ./scripts/07-verify.sh"
echo ""
echo "To write more data and create another snapshot:"
echo "  kubectl exec -n $NAMESPACE block-writer -- dd if=/dev/urandom of=/dev/xvda bs=4096 count=100"
echo "  kubectl apply -f <snapshot-manifest>"
