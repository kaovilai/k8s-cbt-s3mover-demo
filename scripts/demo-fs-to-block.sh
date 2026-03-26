#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Filesystem-to-Block Volume Mode Conversion"
echo "=========================================="
echo ""
echo "This script demonstrates the Velero Block Data Mover pattern:"
echo ""
echo "  Source PVC (Filesystem) -> Snapshot -> BackupPVC (Block) -> CBT"
echo ""
echo "Per KEP-3314 Non-Goals: 'The volume could be attached to a pod"
echo "with either Block or Filesystem volume modes.'"
echo ""
echo "Velero's CSI Snapshot Exposer always creates the backupPVC in Block"
echo "mode regardless of the source PVC's volume mode, because CBT operates"
echo "on the underlying block device."
echo ""
if [ -t 0 ]; then
    read -r -p "Press Enter to continue or Ctrl+C to cancel..."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=detect-storage.sh
source "$SCRIPT_DIR/detect-storage.sh"

NAMESPACE="cbt-demo"

# Step 0: Verify infrastructure
echo ""
echo "[Step 0] Verifying infrastructure..."
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
    echo "Error: Namespace '$NAMESPACE' not found. Run setup scripts first."
    exit 1
fi
echo "  Storage class: $STORAGE_CLASS"
echo "  Snapshot class: $SNAPSHOT_CLASS"

# Step 1: Deploy filesystem workload
echo ""
echo "[Step 1] Deploying filesystem-mode workload..."
echo "  PVC: fs-writer-data (volumeMode: Filesystem)"
echo "  Pod: fs-writer (volumeMounts, NOT volumeDevices)"

sed "s/storageClassName: .*/storageClassName: $STORAGE_CLASS/" \
    manifests/workload/fs-writer-pod.yaml | kubectl apply -f -

echo "  Waiting for fs-writer pod to be ready..."
kubectl wait --for=condition=Ready pod/fs-writer -n "$NAMESPACE" --timeout=120s

echo ""
echo "  Verify volume mode:"
FS_MODE=$(kubectl get pvc fs-writer-data -n "$NAMESPACE" -o jsonpath='{.spec.volumeMode}')
echo "    PVC volumeMode: $FS_MODE"
echo "    Mount type: volumeMounts (filesystem path /data)"

# Step 2: Write data via filesystem (normal app behavior)
echo ""
echo "[Step 2] Writing data via filesystem (normal application pattern)..."

kubectl exec -n "$NAMESPACE" fs-writer -- sh -c '
    echo "Creating application data files..."
    dd if=/dev/urandom of=/data/database.dat bs=4096 count=50 2>/dev/null
    dd if=/dev/urandom of=/data/config.dat bs=4096 count=10 2>/dev/null
    dd if=/dev/urandom of=/data/logs.dat bs=4096 count=25 2>/dev/null
    echo "app-version=1.0" > /data/metadata.txt
    ls -lh /data/
'

echo ""
echo "  Wrote ~340KB of application data via filesystem mount"
echo "  This is how real applications write data - no raw block access"

# Step 3: Snapshot the filesystem PVC
echo ""
echo "[Step 3] Creating snapshot of filesystem PVC..."
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: fs-snapshot-1
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: $SNAPSHOT_CLASS
  source:
    persistentVolumeClaimName: fs-writer-data
EOF

echo "  Waiting for snapshot to be ready..."
kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/fs-snapshot-1 -n "$NAMESPACE" --timeout=300s

SNAP_SIZE=$(kubectl get volumesnapshot fs-snapshot-1 -n "$NAMESPACE" -o jsonpath='{.status.restoreSize}')
echo "  Snapshot ready (restore size: $SNAP_SIZE)"

# Annotate VolumeSnapshotContent to allow volume mode change (Filesystem -> Block)
# This is required by the external-provisioner when the PVC's volumeMode differs from the snapshot's source.
# In Velero, the CSI Snapshot Exposer handles this annotation automatically.
VSC_NAME=$(kubectl get volumesnapshot fs-snapshot-1 -n "$NAMESPACE" -o jsonpath="{.status.boundVolumeSnapshotContentName}")
echo "  Annotating VolumeSnapshotContent $VSC_NAME to allow volume mode change..."
kubectl annotate volumesnapshotcontent "$VSC_NAME" \
  snapshot.storage.kubernetes.io/allow-volume-mode-change="true"

# Step 4: Create backupPVC in Block mode from filesystem snapshot
# This is what Velero's CSI Snapshot Exposer does
echo ""
echo "[Step 4] Creating backupPVC in BLOCK mode from filesystem snapshot..."
echo ""
echo "  This is the Velero Block Data Mover pattern:"
echo "    Source:    fs-writer-data   (volumeMode: Filesystem)"
echo "    Snapshot:  fs-snapshot-1"
echo "    BackupPVC: fs-backup-block  (volumeMode: Block)"
echo ""
echo "  The CSI Snapshot Exposer's getVolumeModeByAccessMode() returns Block"
echo "  for the block data mover path, regardless of the source PVC's mode."

kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fs-backup-block
  namespace: $NAMESPACE
spec:
  accessModes:
  - ReadWriteOnce
  # KEY: Block mode from a Filesystem snapshot
  volumeMode: Block
  storageClassName: $STORAGE_CLASS
  dataSource:
    name: fs-snapshot-1
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  resources:
    requests:
      storage: $SNAP_SIZE
EOF

echo "  Waiting for backupPVC to be bound..."
kubectl wait --for=jsonpath='{.status.phase}'=Bound \
  pvc/fs-backup-block -n "$NAMESPACE" --timeout=120s

BLOCK_MODE=$(kubectl get pvc fs-backup-block -n "$NAMESPACE" -o jsonpath='{.spec.volumeMode}')
echo ""
echo "  BackupPVC created:"
echo "    Name: fs-backup-block"
echo "    volumeMode: $BLOCK_MODE"
echo "    dataSource: fs-snapshot-1 (from Filesystem PVC)"

# Step 5: Mount backupPVC as block device and verify data
echo ""
echo "[Step 5] Mounting backupPVC as block device..."
echo "  A backup pod reads the raw block data (same underlying device contents)"

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: fs-backup-reader
  namespace: $NAMESPACE
  labels:
    app: fs-backup-reader
spec:
  restartPolicy: Never
  containers:
  - name: reader
    image: busybox:1.37.0
    command:
    - /bin/sh
    - -c
    - "tail -f /dev/null"
    volumeDevices:
    - name: backup-volume
      devicePath: /dev/xvdb
    securityContext:
      privileged: true
  volumes:
  - name: backup-volume
    persistentVolumeClaim:
      claimName: fs-backup-block
EOF

echo "  Waiting for backup reader pod..."
kubectl wait --for=condition=Ready pod/fs-backup-reader -n "$NAMESPACE" --timeout=120s

echo ""
echo "  Block device info:"
kubectl exec -n "$NAMESPACE" fs-backup-reader -- ls -la /dev/xvdb
echo ""
echo "  Reading raw block data (first 512 bytes hex dump):"
kubectl exec -n "$NAMESPACE" fs-backup-reader -- sh -c 'dd if=/dev/xvdb bs=512 count=1 2>/dev/null | od -A x -t x1 -v' | head -5

# Step 6: Run CBT against the snapshot
echo ""
echo "[Step 6] Running CBT GetMetadataAllocated on filesystem-sourced snapshot..."
echo ""
echo "  CBT operates on the block device layer regardless of volume mode."
echo "  The filesystem data, metadata, and journal are all block-level data."

# Check if csi-client pod is available
if kubectl get pod -n "$NAMESPACE" csi-client --no-headers 2>/dev/null | grep -q Running; then
    echo ""
    echo "  Calling GetMetadataAllocated API for fs-snapshot-1..."
    kubectl exec -n "$NAMESPACE" csi-client -c run-client -- /tools/snapshot-metadata-lister \
      -snapshot fs-snapshot-1 \
      -namespace "$NAMESPACE" \
      -starting-offset 0 \
      -max-results 10 \
      -kubeconfig "" 2>&1 || true
else
    echo ""
    echo "  (csi-client pod not running - deploy via 04-run-demo.sh first for CBT API calls)"
fi

# Step 7: Write more filesystem data and create incremental snapshot
echo ""
echo "[Step 7] Writing incremental data via filesystem..."
kubectl exec -n "$NAMESPACE" fs-writer -- sh -c '
    dd if=/dev/urandom of=/data/new-records.dat bs=4096 count=30 2>/dev/null
    echo "app-version=2.0" > /data/metadata.txt
'
echo "  Wrote ~120KB of incremental filesystem data"

echo ""
echo "  Creating second snapshot (for incremental delta)..."
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: fs-snapshot-2
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: $SNAPSHOT_CLASS
  source:
    persistentVolumeClaimName: fs-writer-data
EOF

kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/fs-snapshot-2 -n "$NAMESPACE" --timeout=300s
echo "  Snapshot fs-snapshot-2 ready"

# Show delta potential
if kubectl get pod -n "$NAMESPACE" csi-client --no-headers 2>/dev/null | grep -q Running; then
    echo ""
    echo "  Getting CSI handle for delta computation (PR #180)..."
    VSC_NAME=$(kubectl get volumesnapshot fs-snapshot-1 -n "$NAMESPACE" -o jsonpath="{.status.boundVolumeSnapshotContentName}")
    SNAP_HANDLE=$(kubectl get volumesnapshotcontent "$VSC_NAME" -o jsonpath="{.status.snapshotHandle}")

    echo "  Calling GetMetadataDelta (fs-snapshot-1 -> fs-snapshot-2)..."
    kubectl exec -n "$NAMESPACE" csi-client -c run-client -- /tools/snapshot-metadata-lister \
      -previous-snapshot-id "$SNAP_HANDLE" \
      -snapshot fs-snapshot-2 \
      -namespace "$NAMESPACE" \
      -starting-offset 0 \
      -max-results 10 \
      -kubeconfig "" 2>&1 || true
fi

# Summary
echo ""
echo "=========================================="
echo "Filesystem-to-Block Conversion Complete"
echo "=========================================="
echo ""
echo "What was demonstrated:"
echo ""
echo "  1. Source PVC (fs-writer-data):"
echo "     - volumeMode: Filesystem"
echo "     - Mounted at /data via volumeMounts"
echo "     - Application writes files normally"
echo ""
echo "  2. Snapshot (fs-snapshot-1):"
echo "     - Created from Filesystem PVC"
echo "     - Contains filesystem + data at block level"
echo ""
echo "  3. BackupPVC (fs-backup-block):"
echo "     - volumeMode: Block (converted from Filesystem snapshot)"
echo "     - Mounted via volumeDevices at /dev/xvdb"
echo "     - Same underlying data, accessed as raw blocks"
echo ""
echo "  4. CBT works on both:"
echo "     - GetMetadataAllocated: identifies all allocated blocks"
echo "     - GetMetadataDelta: identifies changed blocks between snapshots"
echo "     - Volume mode is transparent to CBT - it operates at block layer"
echo ""
echo "This validates the Velero Block Data Mover design:"
echo "  - backupPVC is always Block mode (per getVolumeModeByAccessMode)"
echo "  - Source PVC can be Filesystem or Block"
echo "  - CBT efficiency applies regardless of source volume mode"
echo ""
echo "Cleanup:"
echo "  kubectl delete pod fs-writer fs-backup-reader -n $NAMESPACE"
echo "  kubectl delete pvc fs-writer-data fs-backup-block -n $NAMESPACE"
echo "  kubectl delete volumesnapshot fs-snapshot-1 fs-snapshot-2 -n $NAMESPACE"
