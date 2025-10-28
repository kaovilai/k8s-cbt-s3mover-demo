#! /bin/bash

# Copyright 2025 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Note: This script requires GNU sed on macOS. Install via Homebrew:
#   brew install gnu-sed
#
# Then add the "gnubin" directory to your PATH in your shell rc file:
#   PATH="$HOMEBREW_PREFIX/opt/gnu-sed/libexec/gnubin:$PATH"

set -e
set -x

# Check for GNU sed on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    if ! sed --version 2>/dev/null | grep -q "GNU sed"; then
        echo "Error: GNU sed is required on macOS but not found in PATH"
        echo ""
        echo "Install GNU sed with Homebrew:"
        echo "  brew install gnu-sed"
        echo ""
        echo "Then add to your PATH in ~/.bashrc or ~/.zshrc:"
        echo "  PATH=\"\$HOMEBREW_PREFIX/opt/gnu-sed/libexec/gnubin:\$PATH\""
        echo ""
        exit 1
    fi
fi

TEMP_DIR="$(mktemp -d)"

# snapshot
SNAPSHOT_VERSION=${SNAPSHOT_VERSION:-"v8.1.0"}
SNAPSHOTTER_URL="https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/${SNAPSHOT_VERSION}"

# snapshot controller
SNAPSHOT_RBAC="${SNAPSHOTTER_URL}/deploy/kubernetes/snapshot-controller/rbac-snapshot-controller.yaml"
SNAPSHOT_CONTROLLER="${SNAPSHOTTER_URL}/deploy/kubernetes/snapshot-controller/setup-snapshot-controller.yaml"

# snapshot CRD
SNAPSHOTCLASS="${SNAPSHOTTER_URL}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml"
VOLUME_SNAPSHOT_CONTENT="${SNAPSHOTTER_URL}/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml"
VOLUME_SNAPSHOT="${SNAPSHOTTER_URL}/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml"

NAMESPACE="default"

function create_or_delete_crds() {
    local action=$1
    if [ "${action}" == "create" ]; then
        # Use apply for idempotent operations
        kubectl apply -f "${SNAPSHOTCLASS}"
        kubectl apply -f "${VOLUME_SNAPSHOT_CONTENT}"
        kubectl apply -f "${VOLUME_SNAPSHOT}"
    else
        kubectl "${action}" -f "${SNAPSHOTCLASS}"
        kubectl "${action}" -f "${VOLUME_SNAPSHOT_CONTENT}"
        kubectl "${action}" -f "${VOLUME_SNAPSHOT}"
    fi
}

function create_or_delete_snapshot_controller() {
    local action=$1
    temp_rbac=${TEMP_DIR}/snapshot-rbac.yaml
    temp_snap_controller=${TEMP_DIR}/snapshot-controller.yaml

    curl -o "${temp_rbac}" "${SNAPSHOT_RBAC}"
    curl -o "${temp_snap_controller}" "${SNAPSHOT_CONTROLLER}"
    sed -i "s/namespace: kube-system/namespace: ${NAMESPACE}/g" "${temp_rbac}"
    sed -i "s/namespace: kube-system/namespace: ${NAMESPACE}/g" "${temp_snap_controller}"
    sed -i -E "s/(image: registry\.k8s\.io\/sig-storage\/snapshot-controller:).*$/\1$SNAPSHOT_VERSION/g" "${temp_snap_controller}"

    if [ "${action}" == "create" ]; then
        # Use apply for idempotent operations
        kubectl apply -f "${temp_rbac}"
        kubectl apply -f "${temp_snap_controller}" -n "${NAMESPACE}"
    else
        kubectl "${action}" -f "${temp_rbac}"
        kubectl "${action}" -f "${temp_snap_controller}" -n "${NAMESPACE}"
    fi

    if [ "${action}" == "delete" ]; then
        return 0
    fi

    pod_ready=$(kubectl get pods -l app.kubernetes.io/name=snapshot-controller -n "${NAMESPACE}" -o jsonpath='{.items[0].status.containerStatuses[0].ready}')
    INC=0
    until [[ "${pod_ready}" == "true" || $INC -gt 20 ]]; do
        sleep 10
        ((++INC))
        pod_ready=$(kubectl get pods -l app.kubernetes.io/name=snapshot-controller -n "${NAMESPACE}" -o jsonpath='{.items[0].status.containerStatuses[0].ready}')
        echo "snapshotter pod status: ${pod_ready}"
    done

    if [ "${pod_ready}" != "true" ]; then
        echo "snapshotter controller creation failed"
        kubectl get pods -l app.kubernetes.io/name=snapshot-controller -n "${NAMESPACE}"
        kubectl describe po -l app.kubernetes.io/name=snapshot-controller -n "${NAMESPACE}"
        exit 1
    fi

    echo "snapshot controller creation successful"
}

function deploy() {
    create_or_delete_crds "create"
    create_or_delete_snapshot_controller "create"
    kubectl get all -n "${NAMESPACE}"
}

function cleanup() {
    create_or_delete_snapshot_controller "delete"
    create_or_delete_crds "delete"
}

case "${1:-}" in
deploy)
    deploy
    ;;
cleanup)
    cleanup
    ;;
*)
    echo "Usage: $0 {deploy|cleanup}"
    exit 1
    ;;
esac
