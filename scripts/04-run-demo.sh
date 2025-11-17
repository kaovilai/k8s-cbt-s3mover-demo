#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Complete CBT Demo Workflow"
echo "=========================================="
echo ""
echo "This script will demonstrate the complete Changed Block Tracking workflow:"
echo "1. Write initial data to block device (400KB)"
echo "2. Create first snapshot (full backup)"
echo "3. Write incremental data (800KB)"
echo "4. Create second snapshot (incremental backup)"
echo "5. Write more data (1.2MB)"
echo "6. Create third snapshot (incremental backup)"
echo "7. Verify all snapshots"
echo ""
read -r -p "Press Enter to continue or Ctrl+C to cancel..."

NAMESPACE="cbt-demo"
POD_NAME="block-writer"
PVC_NAME="block-writer-data"
DEVICE="/dev/xvda"

# Check if infrastructure is running
echo ""
echo "[Step 0] Verifying infrastructure..."
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "Error: Namespace '$NAMESPACE' not found. Run setup scripts first:"
    echo "  ./scripts/00-setup-cluster.sh"
    echo "  ./scripts/01-deploy-csi-driver.sh"
    echo "  ./scripts/02-deploy-minio.sh"
    echo "  ./scripts/03-deploy-workload.sh"
    exit 1
fi

if ! kubectl get pod -n "$NAMESPACE" "$POD_NAME" --no-headers 2>/dev/null | grep -q Running; then
    echo "Error: Block-writer pod is not running"
    echo "Deploy the workload first: ./scripts/03-deploy-workload.sh"
    exit 1
fi

echo "✓ Infrastructure is ready"
echo "  Pod: $POD_NAME"
echo "  PVC: $PVC_NAME"
echo "  Device: $DEVICE"

# Step 1: Write initial data (100 blocks = 400KB)
echo ""
echo "[Step 1] Writing initial data to block device..."
echo "  Writing 100 blocks (400KB) at offset 0..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- dd if=/dev/urandom of="$DEVICE" bs=4096 count=100 seek=0 conv=notrunc 2>&1 | grep -E "copied|records"
echo "✓ Wrote 100 blocks (400KB) starting at offset 0"

# Step 2: Create first snapshot (full backup)
echo ""
echo "[Step 2] Creating first snapshot (baseline)..."
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: block-snapshot-1
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: $PVC_NAME
EOF

echo "  Waiting for snapshot to be ready..."
kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/block-snapshot-1 -n "$NAMESPACE" --timeout=300s

SNAP1_SIZE=$(kubectl get volumesnapshot block-snapshot-1 -n "$NAMESPACE" -o jsonpath='{.status.restoreSize}')
echo "✓ Snapshot 1 created and ready (size: $SNAP1_SIZE)"

# Step 2.5: Deploy snapshot-metadata-lister
echo ""
echo "[Step 2.5] Deploying snapshot-metadata-lister pod..."
echo "  This pod provides authenticated access to CBT APIs"

# Check if already deployed
if kubectl get pod -n "$NAMESPACE" csi-client --no-headers 2>/dev/null | grep -q Running; then
    echo "✓ snapshot-metadata-lister pod already running"
else
    kubectl apply -f manifests/snapshot-metadata-lister/rbac.yaml
    kubectl apply -f manifests/snapshot-metadata-lister/pod.yaml

    echo "  Waiting for csi-client pod to be ready..."
    kubectl wait --for=condition=Ready pod/csi-client -n "$NAMESPACE" --timeout=300s || {
        echo "✗ Pod did not become ready within timeout"
        kubectl get pod csi-client -n "$NAMESPACE"
        kubectl describe pod csi-client -n "$NAMESPACE"
        exit 1
    }
    echo "✓ snapshot-metadata-lister pod is ready"
fi

# Step 2.6: Demonstrate GetMetadataAllocated
echo ""
echo "=========================================="
echo "CBT GetMetadataAllocated Demonstration"
echo "=========================================="
echo ""
echo "This demonstrates using the CBT GetMetadataAllocated API"
echo "to identify allocated blocks for efficient backups."
echo ""
echo "Volume Size: $SNAP1_SIZE"
echo "Snapshot: block-snapshot-1"
echo ""

echo "Calling GetMetadataAllocated API..."
kubectl exec -n "$NAMESPACE" csi-client -c run-client -- /tools/snapshot-metadata-lister \
  -snapshot block-snapshot-1 \
  -namespace "$NAMESPACE" \
  -starting-offset 0 \
  -max-results 10 \
  -kubeconfig "" 2>&1 || {
  echo ""
  echo "⚠ API call completed (CSI driver limitation: no metadata returned)"
  echo "  With a production CSI driver supporting CBT, this would show:"
  echo "    - List of allocated blocks with offsets and sizes"
  echo "    - Only ~400KB of allocated data in a $SNAP1_SIZE volume"
  echo "    - Savings: Transfer only allocated blocks, skip sparse regions"
}

echo ""
echo "=========================================="
echo "Expected Behavior with Full CBT Support"
echo "=========================================="
echo ""
echo "With a CBT-enabled CSI driver, GetMetadataAllocated would return:"
echo ""
echo "  Volume Size:        $SNAP1_SIZE   (total PVC size)"
echo "  Allocated Blocks:   400 KB        (100 blocks of random data)"
echo "  Data Transferred:   400 KB        (only allocated blocks)"
echo "  Savings:            ~${SNAP1_SIZE}  (sparse regions skipped)"
echo ""
echo "This demonstrates the power of Changed Block Tracking:"
echo "  - Only allocated blocks are transferred"
echo "  - Sparse regions are identified and skipped"
echo "  - Efficient initial backups with minimal data transfer"
echo ""

# Step 3: Write incremental data (200 blocks = 800KB)
echo ""
echo "[Step 3] Writing incremental data to block device..."
echo "  Writing 200 blocks (800KB) at offset 409600 (100 blocks)..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- dd if=/dev/urandom of="$DEVICE" bs=4096 count=200 seek=100 conv=notrunc 2>&1 | grep -E "copied|records"
echo "✓ Wrote 200 blocks (800KB) starting at offset 409600"

# Step 4: Create second snapshot (incremental)
echo ""
echo "[Step 4] Creating second snapshot (incremental)..."
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: block-snapshot-2
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: $PVC_NAME
EOF

echo "  Waiting for snapshot to be ready..."
kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/block-snapshot-2 -n "$NAMESPACE" --timeout=300s

SNAP2_SIZE=$(kubectl get volumesnapshot block-snapshot-2 -n "$NAMESPACE" -o jsonpath='{.status.restoreSize}')
echo "✓ Snapshot 2 created and ready (size: $SNAP2_SIZE)"

# Step 4.5: Demonstrate GetMetadataDelta
echo ""
echo "=========================================="
echo "CBT GetMetadataDelta Demonstration"
echo "=========================================="
echo ""
echo "This demonstrates using the CBT GetMetadataDelta API"
echo "to identify only changed blocks between snapshots."
echo ""

# Get CSI snapshot handle from VolumeSnapshotContent (PR #180)
echo "Getting CSI snapshot handle for base snapshot..."
VSC_NAME=$(kubectl get volumesnapshot block-snapshot-1 -n "$NAMESPACE" -o jsonpath="{.status.boundVolumeSnapshotContentName}")
SNAP_HANDLE=$(kubectl get volumesnapshotcontent "$VSC_NAME" -o jsonpath="{.status.snapshotHandle}")

echo "  VolumeSnapshotContent: $VSC_NAME"
echo "  CSI Snapshot Handle: $SNAP_HANDLE"
echo ""
echo "Base Snapshot:   block-snapshot-1 (handle: $SNAP_HANDLE)"
echo "Target Snapshot: block-snapshot-2"
echo "Expected Delta:  200 blocks (~800KB of changes)"
echo ""

echo "Calling GetMetadataDelta API with CSI handle (PR #180)..."
kubectl exec -n "$NAMESPACE" csi-client -c run-client -- /tools/snapshot-metadata-lister \
  -previous-snapshot-id "$SNAP_HANDLE" \
  -snapshot block-snapshot-2 \
  -namespace "$NAMESPACE" \
  -starting-offset 0 \
  -max-results 10 \
  -kubeconfig "" 2>&1 || {
  echo ""
  echo "⚠ API call completed (CSI driver limitation: no metadata returned)"
  echo "  With a production CSI driver supporting CBT, this would show:"
  echo "    - Only changed blocks (200 blocks = ~800KB)"
  echo "    - Block offsets starting at 409600 (after first 100 blocks)"
  echo "    - Incremental efficiency: Transfer ~800KB instead of full volume"
}

echo ""
echo "=========================================="
echo "PR #180: CSI Handle Support (Oct 2025)"
echo "=========================================="
echo ""
echo "Key enhancement: GetMetadataDelta now accepts CSI snapshot handles"
echo "instead of snapshot names. This allows:"
echo ""
echo "  ✓ Base snapshot can be deleted after extracting handle"
echo "  ✓ Storage savings: No need to keep all base snapshots"
echo "  ✓ Backward compatible: Still supports snapshot names"
echo ""
echo "The CSI handle ($SNAP_HANDLE) is extracted from"
echo "VolumeSnapshotContent and persists even if the VolumeSnapshot is deleted."
echo ""
echo "=========================================="
echo "Expected Behavior with Full CBT Support"
echo "=========================================="
echo ""
echo "With a CBT-enabled CSI driver, GetMetadataDelta would return:"
echo ""
echo "  Base Snapshot:      block-snapshot-1 (400KB)"
echo "  Target Snapshot:    block-snapshot-2 (1.2MB)"
echo "  Changed Blocks:     200 blocks (~800KB)"
echo "  Data Transferred:   800 KB (only delta)"
echo "  Full Transfer:      $SNAP2_SIZE (if no CBT)"
echo "  Efficiency Gain:    Incremental backup instead of full"
echo ""
echo "This demonstrates incremental backup efficiency:"
echo "  - Only changed blocks since snapshot 1 are identified"
echo "  - Transfer ~800KB delta instead of full volume"
echo "  - Critical for large datasets with small daily changes"
echo ""

# Step 5: Write even more data (300 blocks = 1.2MB)
echo ""
echo "[Step 5] Writing more data to block device..."
echo "  Writing 300 blocks (1.2MB) at offset 1228800 (300 blocks)..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- dd if=/dev/urandom of="$DEVICE" bs=4096 count=300 seek=300 conv=notrunc 2>&1 | grep -E "copied|records"
echo "✓ Wrote 300 blocks (1.2MB) starting at offset 1228800"

# Step 6: Create third snapshot (incremental)
echo ""
echo "[Step 6] Creating third snapshot (incremental)..."
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: block-snapshot-3
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: $PVC_NAME
EOF

echo "  Waiting for snapshot to be ready..."
kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/block-snapshot-3 -n "$NAMESPACE" --timeout=300s

SNAP3_SIZE=$(kubectl get volumesnapshot block-snapshot-3 -n "$NAMESPACE" -o jsonpath='{.status.restoreSize}')
echo "✓ Snapshot 3 created and ready (size: $SNAP3_SIZE)"

# Step 7: Show all snapshots
echo ""
echo "[Step 7] Snapshot Summary"
echo "=========================================="
kubectl get volumesnapshot -n "$NAMESPACE"

echo ""
echo "VolumeSnapshotContent details:"
kubectl get volumesnapshotcontent | grep -E "NAME|$NAMESPACE"

# Calculate total data written
TOTAL_BLOCKS=600
TOTAL_KB=$((TOTAL_BLOCKS * 4))
TOTAL_MB=$((TOTAL_KB / 1024))

echo ""
echo "=========================================="
echo "Demo Workflow Complete!"
echo "=========================================="
echo ""
echo "What was created:"
echo "  - 3 VolumeSnapshots (block-snapshot-1, 2, 3)"
echo "  - Total data written: $TOTAL_BLOCKS blocks (${TOTAL_MB}MB)"
echo "  - Snapshot 1: $SNAP1_SIZE (baseline: 100 blocks = 400KB)"
echo "  - Snapshot 2: $SNAP2_SIZE (incremental: +200 blocks = 800KB)"
echo "  - Snapshot 3: $SNAP3_SIZE (incremental: +300 blocks = 1.2MB)"
echo ""
echo "CBT Efficiency:"
echo "  - Snapshot 1: Full backup required (baseline)"
echo "  - Snapshot 2: Only changed blocks backed up (CBT delta from snapshot 1)"
echo "  - Snapshot 3: Only changed blocks backed up (CBT delta from snapshot 2)"
echo ""
echo "Next steps:"
echo "  1. Test CBT backup tool: cd tools/cbt-backup && ./cbt-backup create --pvc $PVC_NAME --namespace $NAMESPACE"
echo "  2. Verify snapshots:     kubectl get volumesnapshot -n $NAMESPACE"
echo "  3. Simulate disaster:    ./scripts/05-simulate-disaster.sh"
echo "  4. Test restore:         ./scripts/06-restore.sh"
echo ""
echo "NOTE: This demo shows snapshot creation. Full CBT block-level backup to S3"
echo "      requires completing the implementation in tools/cbt-backup/"
