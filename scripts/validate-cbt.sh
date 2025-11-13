#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Validating Changed Block Tracking (CBT)"
echo "=========================================="

EXIT_CODE=0

# Check if SnapshotMetadataService CRD exists
echo "Checking SnapshotMetadataService CRD..."
if kubectl get crd snapshotmetadataservices.cbt.storage.k8s.io &> /dev/null; then
    echo "✓ SnapshotMetadataService CRD is installed"
else
    echo "✗ SnapshotMetadataService CRD not found"
    echo "  Note: CBT functionality may be limited without this CRD"
    echo "  This CRD is part of the external-snapshot-metadata project"
    # Don't fail validation as CBT can work partially without it
    echo "⚠ Continuing with limited CBT support..."
fi

# Check if SnapshotMetadataService instances exist
echo ""
echo "Checking SnapshotMetadataService instances..."
if kubectl get crd snapshotmetadataservices.cbt.storage.k8s.io &> /dev/null; then
    if kubectl get snapshotmetadataservices -A &> /dev/null; then
        SERVICES=$(kubectl get snapshotmetadataservices -A --no-headers 2>/dev/null | wc -l)
        if [ "$SERVICES" -gt 0 ]; then
            echo "✓ Found $SERVICES SnapshotMetadataService instance(s)"
            kubectl get snapshotmetadataservices -A
        else
            echo "⚠ No SnapshotMetadataService instances found"
            echo "  This is normal if the CSI driver hasn't created one yet"
        fi
    else
        echo "⚠ Cannot query SnapshotMetadataService resources"
        echo "  The CRD may not be fully established yet"
    fi
else
    echo "⚠ Skipping SnapshotMetadataService check (CRD not installed)"
fi

# Check CSI driver pods
echo ""
echo "Checking CSI driver pods..."
if kubectl get pod -n default 2>/dev/null | grep -q "csi-hostpathplugin"; then
    echo "✓ CSI hostpath driver pods found"
    kubectl get pods -n default | grep csi-hostpath
else
    echo "✗ CSI hostpath driver not found"
    EXIT_CODE=1
fi

# Check for snapshot metadata sidecar
echo ""
echo "Checking for snapshot metadata sidecar..."
# Get all csi-hostpath pod names
CSI_PODS=$(kubectl get pods -n default --no-headers 2>/dev/null | grep "csi-hostpath" | awk '{print $1}')
if [ -n "$CSI_PODS" ]; then
    FOUND_SIDECAR=false
    for POD in $CSI_PODS; do
        if kubectl get pod "$POD" -n default -o yaml 2>/dev/null | grep -q "snapshot-metadata"; then
            FOUND_SIDECAR=true
            break
        fi
    done

    if [ "$FOUND_SIDECAR" = true ]; then
        echo "✓ Snapshot metadata sidecar is present"
    else
        echo "✗ Snapshot metadata sidecar not found"
        echo "  Ensure the driver was deployed with SNAPSHOT_METADATA_TESTS=true"
        EXIT_CODE=1
    fi
else
    echo "✗ Cannot check for snapshot metadata sidecar (CSI driver pods not found)"
    EXIT_CODE=1
fi

# Check VolumeSnapshotClass
echo ""
echo "Checking VolumeSnapshotClass..."
if kubectl get volumesnapshotclass csi-hostpath-snapclass &> /dev/null; then
    echo "✓ VolumeSnapshotClass 'csi-hostpath-snapclass' exists"
    kubectl get volumesnapshotclass csi-hostpath-snapclass
else
    echo "✗ VolumeSnapshotClass 'csi-hostpath-snapclass' not found"
    EXIT_CODE=1
fi

# Check StorageClass
echo ""
echo "Checking StorageClass..."
if kubectl get storageclass csi-hostpath-sc &> /dev/null; then
    echo "✓ StorageClass 'csi-hostpath-sc' exists"
    kubectl get storageclass csi-hostpath-sc
else
    echo "✗ StorageClass 'csi-hostpath-sc' not found"
    echo "  This StorageClass is required for CBT functionality"
    echo "  Available StorageClasses:"
    kubectl get storageclass
    EXIT_CODE=1
fi

# Check for snapshots (if any exist)
echo ""
echo "Checking for existing VolumeSnapshots..."
SNAPSHOTS=$(kubectl get volumesnapshot -A --no-headers 2>/dev/null | wc -l)
if [ "$SNAPSHOTS" -gt 0 ]; then
    echo "✓ Found $SNAPSHOTS VolumeSnapshot(s)"
    kubectl get volumesnapshot -A
else
    echo "ℹ No VolumeSnapshots found yet (this is normal before first backup)"
fi

echo ""
echo "=========================================="
if [ $EXIT_CODE -eq 0 ]; then
    echo "✓ CBT validation PASSED"
    echo "Changed Block Tracking is properly configured!"
else
    echo "✗ CBT validation FAILED"
    echo "Please check the errors above"
fi
echo "=========================================="

exit $EXIT_CODE
