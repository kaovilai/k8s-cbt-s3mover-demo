#!/bin/bash
# Detect storage and snapshot classes for the CBT demo.
# Sources environment variables STORAGE_CLASS and SNAPSHOT_CLASS.
#
# Priority:
#   1. Existing environment variable (user override)
#   2. Ceph RBD (OpenShift ODF / OCS)
#   3. CSI hostpath (demo driver)
#
# Usage: source scripts/detect-storage.sh

_detect_storage_class() {
    if [ -n "${STORAGE_CLASS:-}" ]; then
        return
    fi

    # Check for Ceph RBD storage class
    if kubectl get storageclass ocs-storagecluster-ceph-rbd &>/dev/null; then
        # Verify the RBD CSI controller plugin is healthy
        if kubectl get pods -n openshift-storage --no-headers 2>/dev/null | grep "rbd.*ctrlplugin" | grep -q Running; then
            STORAGE_CLASS="ocs-storagecluster-ceph-rbd"
            return
        fi
    fi

    # Fallback to CSI hostpath
    STORAGE_CLASS="csi-hostpath-sc"
}

_detect_snapshot_class() {
    if [ -n "${SNAPSHOT_CLASS:-}" ]; then
        return
    fi

    # Check for Ceph RBD snapshot class
    if kubectl get volumesnapshotclass ocs-storagecluster-rbdplugin-snapclass &>/dev/null; then
        SNAPSHOT_CLASS="ocs-storagecluster-rbdplugin-snapclass"
        return
    fi

    # Fallback to CSI hostpath
    SNAPSHOT_CLASS="csi-hostpath-snapclass"
}

_detect_storage_class
_detect_snapshot_class

export STORAGE_CLASS
export SNAPSHOT_CLASS

echo "Storage config: STORAGE_CLASS=$STORAGE_CLASS  SNAPSHOT_CLASS=$SNAPSHOT_CLASS"
