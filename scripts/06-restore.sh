#!/bin/bash
set -euo pipefail

NAMESPACE="${1:-cbt-demo}"
SNAPSHOT_NAME="${2:-postgres-snapshot-3}"  # Default to latest snapshot

echo "=========================================="
echo "Restore from Snapshot"
echo "=========================================="
echo ""
echo "This will restore PostgreSQL from snapshot: $SNAPSHOT_NAME"
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
SOURCE_PVC=$(kubectl get volumesnapshot "$SNAPSHOT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.source.persistentVolumeClaimName}')

echo "Snapshot Details:"
echo "  Name:        $SNAPSHOT_NAME"
echo "  Size:        $SNAPSHOT_SIZE"
echo "  Source PVC:  $SOURCE_PVC"
echo ""
read -p "Press Enter to continue with restore..."

# Restore PostgreSQL StatefulSet (it will create PVCs from snapshot)
echo ""
echo "[1/3] Recreating PostgreSQL StatefulSet with snapshot restore..."

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: $NAMESPACE
  labels:
    app: postgres
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      securityContext:
        fsGroup: 999
      initContainers:
      - name: format-block-device
        image: busybox:1.36
        command: ['sh', '-c']
        args:
          - |
            if ! blkid /dev/xvda; then
              echo "Formatting block device..."
              mkfs.ext4 -F /dev/xvda
            fi
            mkdir -p /mnt/data
            mount /dev/xvda /mnt/data
            chmod 777 /mnt/data
            umount /mnt/data
        securityContext:
          privileged: true
        volumeDevices:
        - name: postgres-data
          devicePath: /dev/xvda
      containers:
      - name: postgres
        image: postgres:16-alpine
        env:
        - name: POSTGRES_DB
          value: cbtdemo
        - name: POSTGRES_USER
          value: demo
        - name: POSTGRES_PASSWORD
          value: demopassword
        - name: PGDATA
          value: /mnt/pgdata
        ports:
        - containerPort: 5432
          name: postgres
        command: ['sh', '-c']
        args:
          - |
            mkdir -p /mnt/data
            mount /dev/xvda /mnt/data
            mkdir -p /mnt/pgdata
            chown -R postgres:postgres /mnt/pgdata
            exec docker-entrypoint.sh postgres
        securityContext:
          privileged: true
          runAsUser: 0
        volumeDevices:
        - name: postgres-data
          devicePath: /dev/xvda
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - pg_isready -U demo
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          exec:
            command:
            - /bin/sh
            - -c
            - pg_isready -U demo
          initialDelaySeconds: 10
          periodSeconds: 5
  volumeClaimTemplates:
  - metadata:
      name: postgres-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      volumeMode: Block
      storageClassName: csi-hostpath-sc
      dataSource:
        name: $SNAPSHOT_NAME
        kind: VolumeSnapshot
        apiGroup: snapshot.storage.k8s.io
      resources:
        requests:
          storage: $SNAPSHOT_SIZE
EOF

echo "✓ StatefulSet created with snapshot restore"

# Wait for PostgreSQL to be ready
echo ""
echo "[2/3] Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=Ready pod -l app=postgres -n "$NAMESPACE" --timeout=300s

POSTGRES_POD=$(kubectl get pod -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}')
echo "✓ PostgreSQL pod is ready: $POSTGRES_POD"

# Verify data
echo ""
echo "[3/3] Verifying restored data..."
sleep 5  # Give PostgreSQL a moment to fully start

RESTORED_ROWS=$(kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U demo -d cbtdemo -t -c "SELECT COUNT(*) FROM demo_data;" 2>/dev/null | tr -d ' ')

echo ""
echo "=========================================="
echo "Restore Complete!"
echo "=========================================="
echo ""
echo "PostgreSQL Status:"
echo "  Pod:     $POSTGRES_POD"
echo "  Status:  Running"
echo "  Rows:    $RESTORED_ROWS"
echo ""

# Compare with pre-disaster state if available
if [ -f /tmp/cbt-demo-pre-disaster-rows.txt ]; then
    PRE_DISASTER_ROWS=$(cat /tmp/cbt-demo-pre-disaster-rows.txt)
    echo "Pre-disaster rows:  $PRE_DISASTER_ROWS"
    echo "Restored rows:      $RESTORED_ROWS"
    echo ""
    if [ "$RESTORED_ROWS" == "$PRE_DISASTER_ROWS" ]; then
        echo "✓ Data restored successfully! Row count matches pre-disaster state."
    else
        echo "⚠ Row count mismatch. This may be expected if you restored from an earlier snapshot."
    fi
else
    echo "Pre-disaster state not found. Cannot compare row counts."
fi

echo ""
echo "To verify data integrity:"
echo "  ./scripts/07-verify.sh"
echo ""
echo "To connect to the database:"
echo "  kubectl exec -it -n $NAMESPACE $POSTGRES_POD -- psql -U demo -d cbtdemo"
