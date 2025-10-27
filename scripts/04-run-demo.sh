#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Complete CBT Demo Workflow"
echo "=========================================="
echo ""
echo "This script will demonstrate the complete Changed Block Tracking workflow:"
echo "1. Create initial snapshot (full backup)"
echo "2. Add more data to PostgreSQL"
echo "3. Create second snapshot (incremental backup)"
echo "4. Add even more data"
echo "5. Create third snapshot (incremental backup)"
echo "6. Verify all snapshots and backups"
echo ""
read -r -p "Press Enter to continue or Ctrl+C to cancel..."

NAMESPACE="cbt-demo"

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

if ! kubectl get pod -n "$NAMESPACE" -l app=postgres --no-headers | grep -q Running; then
    echo "Error: PostgreSQL pod is not running"
    exit 1
fi

echo "✓ Infrastructure is ready"

# Get PostgreSQL pod name
POSTGRES_POD=$(kubectl get pod -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}')
PVC_NAME="postgres-data-$POSTGRES_POD"

echo "  PostgreSQL Pod: $POSTGRES_POD"
echo "  PVC: $PVC_NAME"

# Check initial data
echo ""
echo "[Step 1] Checking initial data..."
INITIAL_ROWS=$(kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U demo -d cbtdemo -t -c "SELECT COUNT(*) FROM demo_data;" | tr -d ' ')
echo "  Initial rows: $INITIAL_ROWS"

# Create first snapshot (full backup)
echo ""
echo "[Step 2] Creating first snapshot (full backup)..."
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: postgres-snapshot-1
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: $PVC_NAME
EOF

echo "  Waiting for snapshot to be ready..."
kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/postgres-snapshot-1 -n "$NAMESPACE" --timeout=300s

SNAP1_SIZE=$(kubectl get volumesnapshot postgres-snapshot-1 -n "$NAMESPACE" -o jsonpath='{.status.restoreSize}')
echo "✓ Snapshot 1 created (size: $SNAP1_SIZE)"

# Add more data (blocks 1001-1100)
echo ""
echo "[Step 3] Adding more data (100 blocks)..."
kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U demo -d cbtdemo -c "
INSERT INTO demo_data (data_block, content, checksum)
SELECT generate_series(1001, 1100),
       encode(gen_random_bytes(100000), 'base64'),
       md5(random()::text);
" >/dev/null

AFTER_INSERT1=$(kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U demo -d cbtdemo -t -c "SELECT COUNT(*) FROM demo_data;" | tr -d ' ')
echo "✓ Added $((AFTER_INSERT1 - INITIAL_ROWS)) new rows (total: $AFTER_INSERT1)"

# Create second snapshot (incremental)
echo ""
echo "[Step 4] Creating second snapshot (incremental)..."
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: postgres-snapshot-2
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: $PVC_NAME
EOF

echo "  Waiting for snapshot to be ready..."
kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/postgres-snapshot-2 -n "$NAMESPACE" --timeout=300s

SNAP2_SIZE=$(kubectl get volumesnapshot postgres-snapshot-2 -n "$NAMESPACE" -o jsonpath='{.status.restoreSize}')
echo "✓ Snapshot 2 created (size: $SNAP2_SIZE)"

# Add even more data (blocks 1101-1300)
echo ""
echo "[Step 5] Adding even more data (200 blocks)..."
kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U demo -d cbtdemo -c "
INSERT INTO demo_data (data_block, content, checksum)
SELECT generate_series(1101, 1300),
       encode(gen_random_bytes(100000), 'base64'),
       md5(random()::text);
" >/dev/null

AFTER_INSERT2=$(kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U demo -d cbtdemo -t -c "SELECT COUNT(*) FROM demo_data;" | tr -d ' ')
echo "✓ Added $((AFTER_INSERT2 - AFTER_INSERT1)) new rows (total: $AFTER_INSERT2)"

# Create third snapshot (incremental)
echo ""
echo "[Step 6] Creating third snapshot (incremental)..."
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: postgres-snapshot-3
  namespace: $NAMESPACE
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: $PVC_NAME
EOF

echo "  Waiting for snapshot to be ready..."
kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/postgres-snapshot-3 -n "$NAMESPACE" --timeout=300s

SNAP3_SIZE=$(kubectl get volumesnapshot postgres-snapshot-3 -n "$NAMESPACE" -o jsonpath='{.status.restoreSize}')
echo "✓ Snapshot 3 created (size: $SNAP3_SIZE)"

# Show all snapshots
echo ""
echo "[Step 7] Snapshot Summary"
echo "=========================================="
kubectl get volumesnapshot -n "$NAMESPACE" -o custom-columns=\
NAME:.metadata.name,\
READY:.status.readyToUse,\
SIZE:.status.restoreSize,\
AGE:.metadata.creationTimestamp

echo ""
echo "=========================================="
echo "Demo Workflow Complete!"
echo "=========================================="
echo ""
echo "What was created:"
echo "  - 3 VolumeSnapshots (postgres-snapshot-1, 2, 3)"
echo "  - $AFTER_INSERT2 rows of data in PostgreSQL"
echo "  - Snapshot 1: $SNAP1_SIZE (baseline)"
echo "  - Snapshot 2: $SNAP2_SIZE (+100 blocks)"
echo "  - Snapshot 3: $SNAP3_SIZE (+200 blocks)"
echo ""
echo "Next steps:"
echo "  1. Check backup status:  ./scripts/backup-status.sh"
echo "  2. Verify integrity:     ./scripts/integrity-check.sh"
echo "  3. Test restore:         ./scripts/restore-dry-run.sh cbt-demo postgres-snapshot-1"
echo "  4. Simulate disaster:    ./scripts/05-simulate-disaster.sh"
echo ""
echo "NOTE: Full CBT block-level backup requires completing the gRPC client"
echo "      implementation in tools/cbt-backup/pkg/metadata/cbt_client.go"
