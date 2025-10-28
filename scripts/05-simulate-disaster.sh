#!/bin/bash
set -euo pipefail

NAMESPACE="${1:-cbt-demo}"

echo "=========================================="
echo "Simulating Disaster Scenario"
echo "=========================================="
echo ""
echo "⚠️  WARNING: This will DELETE:"
echo "  - PostgreSQL StatefulSet"
echo "  - All PostgreSQL PVCs"
echo "  - All data in the database"
echo ""
echo "Snapshots in S3/MinIO will be PRESERVED for restore."
echo ""
read -r -p "Are you sure you want to continue? (type 'yes' to proceed): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "[1/4] Saving current state for verification..."

# Get current row count
POSTGRES_POD=$(kubectl get pod -n "$NAMESPACE" -l app=block-writer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$POSTGRES_POD" ]; then
    PRE_DISASTER_ROWS=$(kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U demo -d cbtdemo -t -c "SELECT COUNT(*) FROM demo_data;" 2>/dev/null | tr -d ' ' || echo "unknown")
    echo "  Current rows in database: $PRE_DISASTER_ROWS"
    echo "$PRE_DISASTER_ROWS" > /tmp/cbt-demo-pre-disaster-rows.txt
else
    echo "  PostgreSQL pod not found"
    PRE_DISASTER_ROWS="unknown"
fi

# List snapshots
echo ""
echo "[2/4] Listing available snapshots (these will be preserved)..."
kubectl get volumesnapshot -n "$NAMESPACE" -o custom-columns=\
NAME:.metadata.name,\
READY:.status.readyToUse,\
SIZE:.status.restoreSize

# Delete PostgreSQL StatefulSet
echo ""
echo "[3/4] Deleting PostgreSQL StatefulSet..."
kubectl delete statefulset postgres -n "$NAMESPACE" --grace-period=10

# Delete PVCs
echo ""
echo "[4/4] Deleting PVCs..."
kubectl get pvc -n "$NAMESPACE" -o name | grep postgres | xargs -r kubectl delete -n "$NAMESPACE" --grace-period=10

echo ""
echo "=========================================="
echo "Disaster Simulation Complete"
echo "=========================================="
echo ""
echo "What was deleted:"
echo "  ✗ PostgreSQL StatefulSet"
echo "  ✗ PostgreSQL PVCs"
echo "  ✗ All database data ($PRE_DISASTER_ROWS rows)"
echo ""
echo "What was preserved:"
echo "  ✓ VolumeSnapshots"
echo "  ✓ VolumeSnapshotContents"
echo "  ✓ Backup metadata in MinIO"
echo ""
echo "To verify snapshots are still available:"
echo "  kubectl get volumesnapshot -n $NAMESPACE"
echo "  kubectl get volumesnapshotcontent"
echo ""
echo "To restore from backup:"
echo "  ./scripts/06-restore.sh"
echo ""
echo "Expected row count after restore: $PRE_DISASTER_ROWS"
echo "(Saved to /tmp/cbt-demo-pre-disaster-rows.txt)"
