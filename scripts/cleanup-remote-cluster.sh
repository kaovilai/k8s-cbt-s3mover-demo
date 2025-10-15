#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Cleaning up CBT demo from remote cluster"
echo "=========================================="

# Check if kubeconfig is set
if [ -z "${KUBECONFIG:-}" ]; then
    echo "Warning: KUBECONFIG not set, using default kubectl context"
fi

# Verify cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "Connected to: $(kubectl config current-context)"
echo ""
echo "⚠️  WARNING: This will delete the following from the current cluster:"
echo "  - Namespace: cbt-demo (and all resources within)"
echo "  - VolumeSnapshots"
echo "  - VolumeSnapshotContents"
echo ""
read -r -p "Continue with cleanup? (type 'yes' to proceed): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Delete namespace (this removes most resources)
echo ""
echo "[1/3] Deleting namespace cbt-demo..."
if kubectl get namespace cbt-demo &> /dev/null; then
    kubectl delete namespace cbt-demo --timeout=120s
    echo "✓ Namespace deleted"
else
    echo "  Namespace cbt-demo not found, skipping"
fi

# Clean up VolumeSnapshots that might be cluster-scoped or in other namespaces
echo ""
echo "[2/3] Cleaning up VolumeSnapshots..."
SNAPSHOTS=$(kubectl get volumesnapshot -A --no-headers 2>/dev/null | grep -c "cbt-demo" || echo "0")
if [ "$SNAPSHOTS" -gt 0 ]; then
    kubectl delete volumesnapshot -n cbt-demo --all --timeout=60s 2>/dev/null || true
    echo "✓ Cleaned up $SNAPSHOTS snapshot(s)"
else
    echo "  No snapshots found"
fi

# Clean up VolumeSnapshotContents (cluster-scoped)
echo ""
echo "[3/3] Cleaning up VolumeSnapshotContents..."
CONTENTS=$(kubectl get volumesnapshotcontent --no-headers 2>/dev/null | grep -c "cbt-demo" || echo "0")
if [ "$CONTENTS" -gt 0 ]; then
    kubectl get volumesnapshotcontent --no-headers | grep "cbt-demo" | awk '{print $1}' | xargs -r kubectl delete volumesnapshotcontent --timeout=60s 2>/dev/null || true
    echo "✓ Cleaned up $CONTENTS snapshot content(s)"
else
    echo "  No snapshot contents found"
fi

echo ""
echo "=========================================="
echo "✓ Cleanup complete!"
echo "=========================================="
echo ""
echo "Note: The following were NOT removed (if you installed them):"
echo "  - CSI driver (in kube-system or default namespace)"
echo "  - VolumeSnapshot CRDs"
echo "  - Storage classes"
echo ""
echo "To remove these manually:"
echo "  kubectl delete crd volumesnapshotclasses.snapshot.storage.k8s.io"
echo "  kubectl delete crd volumesnapshotcontents.snapshot.storage.k8s.io"
echo "  kubectl delete crd volumesnapshots.snapshot.storage.k8s.io"
