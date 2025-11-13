#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Cleaning up CSI Hostpath Driver"
echo "=========================================="

# Check for -y flag
YES_FLAG=false
if [ "${1:-}" = "-y" ] || [ "${1:-}" = "--yes" ]; then
    YES_FLAG=true
fi

NAMESPACE="default"

# Verify cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "Connected to: $(kubectl config current-context)"
echo ""
echo "⚠️  WARNING: This will delete CSI driver resources from namespace: $NAMESPACE"
echo "  - StatefulSets: csi-hostpathplugin, csi-hostpath-socat"
echo "  - Services: csi-snapshot-metadata, hostpath-service"
echo "  - SnapshotMetadataService CRs"
echo "  - Secrets: csi-snapshot-metadata-certs"
echo "  - CSIDriver: hostpath.csi.k8s.io"
echo "  - VolumeSnapshotClass: csi-hostpath-snapclass"
echo "  - Deployment: snapshot-controller"
echo ""

if [ "$YES_FLAG" = false ]; then
    read -r -p "Continue with cleanup? (type 'yes' to proceed): " CONFIRM
    if [ "$CONFIRM" != "yes" ]; then
        echo "Aborted."
        exit 1
    fi
else
    echo "Auto-confirmed with -y flag"
fi

echo ""
echo "Cleaning up CSI driver resources..."

# Delete StatefulSets
echo "[1/8] Deleting StatefulSets..."
kubectl delete statefulset csi-hostpathplugin -n "$NAMESPACE" --ignore-not-found
kubectl delete statefulset csi-hostpath-socat -n "$NAMESPACE" --ignore-not-found
echo "✓ StatefulSets deleted"

# Delete Services
echo "[2/8] Deleting Services..."
kubectl delete service csi-snapshot-metadata -n "$NAMESPACE" --ignore-not-found
kubectl delete service hostpath-service -n "$NAMESPACE" --ignore-not-found
echo "✓ Services deleted"

# Delete SnapshotMetadataService CRs
echo "[3/8] Deleting SnapshotMetadataService CRs..."
kubectl delete snapshotmetadataservice --all --ignore-not-found
echo "✓ SnapshotMetadataService CRs deleted"

# Delete Secrets
echo "[4/8] Deleting Secrets..."
kubectl delete secret csi-snapshot-metadata-certs -n "$NAMESPACE" --ignore-not-found
echo "✓ Secrets deleted"

# Delete CSIDriver
echo "[5/8] Deleting CSIDriver..."
kubectl delete csidriver hostpath.csi.k8s.io --ignore-not-found
echo "✓ CSIDriver deleted"

# Delete VolumeSnapshotClass
echo "[6/8] Deleting VolumeSnapshotClass..."
kubectl delete volumesnapshotclass csi-hostpath-snapclass --ignore-not-found
echo "✓ VolumeSnapshotClass deleted"

# Delete Snapshot Controller
echo "[7/8] Deleting Snapshot Controller..."
kubectl delete deployment snapshot-controller -n "$NAMESPACE" --ignore-not-found
echo "✓ Snapshot Controller deleted"

# Delete ServiceAccounts, ClusterRoles, and ClusterRoleBindings
echo "[8/8] Deleting RBAC resources..."
kubectl delete serviceaccount csi-hostpathplugin-sa -n "$NAMESPACE" --ignore-not-found
kubectl delete clusterrolebinding csi-hostpathplugin-attacher-cluster-role --ignore-not-found
kubectl delete clusterrolebinding csi-hostpathplugin-health-monitor-controller-cluster-role --ignore-not-found
kubectl delete clusterrolebinding csi-hostpathplugin-provisioner-cluster-role --ignore-not-found
kubectl delete clusterrolebinding csi-hostpathplugin-resizer-cluster-role --ignore-not-found
kubectl delete clusterrolebinding csi-hostpathplugin-snapshotter-cluster-role --ignore-not-found
kubectl delete clusterrolebinding csi-hostpathplugin-snapshot-metadata-cluster-role --ignore-not-found
kubectl delete rolebinding -n "$NAMESPACE" -l app.kubernetes.io/instance=hostpath.csi.k8s.io --ignore-not-found
echo "✓ RBAC resources deleted"

echo ""
echo "=========================================="
echo "✓ CSI driver cleanup complete!"
echo "=========================================="
echo ""
echo "Note: The following were NOT removed:"
echo "  - VolumeSnapshot CRDs"
echo "  - SnapshotMetadataService CRD"
echo "  - Storage classes (except csi-hostpath-snapclass)"
echo ""
