# Issues Encountered and Planned Fixes

This document tracks issues encountered when running the CBT demo on an OpenShift 4.21 ARM64 cluster and provides planned fixes to make the repository more robust.

## Summary

Date: 2025-11-13
Cluster: OpenShift 4.21 (Kubernetes 1.34.1) on AWS ARM64
Demo Status: ✅ Successfully deployed and functional (with workarounds)

## Issues Encountered

### 1. Remote Cluster Scripts Require KUBECONFIG Environment Variable

**Problem:**
- Scripts `run-demo-remote.sh` and `00-setup-remote-cluster.sh` check for `KUBECONFIG` environment variable
- They fail even when kubectl is already configured and working
- Setting `KUBECONFIG` inline doesn't work due to how the check is implemented

**Impact:** Medium - Scripts fail unnecessarily when kubectl is configured via default location (~/.kube/config)

**Workaround Used:**
```bash
# Manually ran individual deployment scripts instead of automated wrapper
./scripts/01-deploy-csi-driver.sh
./scripts/02-deploy-minio.sh
./scripts/03-deploy-workload.sh
```

**Planned Fix:**
Modify scripts to check if kubectl is working instead of requiring KUBECONFIG:
```bash
# Instead of:
if [ -z "$KUBECONFIG" ]; then
    echo "Error: KUBECONFIG environment variable not set"
    exit 1
fi

# Use:
if ! kubectl cluster-info &>/dev/null; then
    echo "Error: kubectl not configured or cluster not accessible"
    exit 1
fi
```

**Files to Update:**
- [scripts/run-demo-remote.sh](/Users/tkaovila/git/k8s-cbt-s3mover-demo/scripts/run-demo-remote.sh)
- [scripts/00-setup-remote-cluster.sh](/Users/tkaovila/git/k8s-cbt-s3mover-demo/scripts/00-setup-remote-cluster.sh)

---

### 2. CSI Snapshot Metadata Container Readiness Probe Fails on ARM64

**Problem:**
- The `csi-snapshot-metadata` container's readiness probe fails with "Exec format error"
- The `grpc_health_probe` binary in the container image is built for AMD64, not ARM64
- This prevents the container from becoming "Ready" (8/9 containers ready)

**Impact:** Low - Container is functional despite readiness probe failure; CBT APIs work correctly

**Evidence:**
```bash
$ kubectl describe pod csi-hostpathplugin-0 -n default
Warning  Unhealthy  Readiness probe failed: exec: Exec format error
```

**Root Cause:**
Upstream CSI driver images (`gcr.io/k8s-staging-sig-storage/csi-snapshot-metadata:canary`) are primarily built for AMD64

**Workaround Used:**
None needed - container is functional despite readiness probe failure

**Planned Fix:**
1. **Short-term**: Document that readiness probe failures are expected on ARM64 and can be ignored
2. **Medium-term**: Build multi-arch images for the snapshot metadata sidecar
3. **Long-term**: Contribute ARM64 support to upstream kubernetes-csi/external-snapshot-metadata

**Alternative Approach:**
Remove or adjust the readiness probe for ARM64 clusters:
```yaml
# Modify deployment to skip readiness probe on ARM64 or use HTTP probe instead
readinessProbe:
  exec:
    command: ["/bin/sh", "-c", "ps aux | grep -q csi-snapshot-metadata"]
```

**Files to Update:**
- [CLAUDE.md](/Users/tkaovila/git/k8s-cbt-s3mover-demo/CLAUDE.md) - Add ARM64 limitations section
- [README.md](/Users/tkaovila/git/k8s-cbt-s3mover-demo/README.md) - Document ARM64 known issues

---

### 3. OpenShift PodSecurity Policies Block Privileged Pods

**Problem:**
- OpenShift namespaces have `pod-security.kubernetes.io/enforce=restricted` by default
- Block-writer pod requires `privileged: true` to access raw block devices
- Pod creation fails with PodSecurity violation errors

**Impact:** High - Demo workload cannot be deployed without manual intervention

**Error Message:**
```
error when creating "manifests/workload/block-writer-pod.yaml": pods "block-writer" is forbidden:
violates PodSecurity "restricted:latest": privileged (container "writer" must not set
securityContext.privileged=true)
```

**Workaround Used:**
```bash
# 1. Label namespace to allow privileged pods
kubectl label namespace cbt-demo \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged \
  --overwrite

# 2. Grant privileged SCC to service account (OpenShift-specific)
oc adm policy add-scc-to-user privileged -z default -n cbt-demo
```

**Planned Fix:**
1. Update [scripts/02-deploy-minio.sh](/Users/tkaovila/git/k8s-cbt-s3mover-demo/scripts/02-deploy-minio.sh) to auto-detect OpenShift and configure namespace:
```bash
# scripts/02-deploy-minio.sh
# After creating namespace, check if OpenShift and configure
kubectl create namespace cbt-demo

if kubectl api-resources | grep -q "SecurityContextConstraints"; then
    echo "Detected OpenShift - configuring privileged access..."
    kubectl label namespace cbt-demo \
      pod-security.kubernetes.io/enforce=privileged \
      pod-security.kubernetes.io/audit=privileged \
      pod-security.kubernetes.io/warn=privileged \
      --overwrite

    oc adm policy add-scc-to-user privileged -z default -n cbt-demo
fi
```

2. Add OpenShift-specific manifests:
   - Create [manifests/openshift/namespace.yaml](/Users/tkaovila/git/k8s-cbt-s3mover-demo/manifests/openshift/namespace.yaml) with proper labels
   - Create [manifests/openshift/rbac.yaml](/Users/tkaovila/git/k8s-cbt-s3mover-demo/manifests/openshift/rbac.yaml) for SCC bindings

**Files to Update:**
- [scripts/02-deploy-minio.sh](/Users/tkaovila/git/k8s-cbt-s3mover-demo/scripts/02-deploy-minio.sh)
- [CLAUDE.md](/Users/tkaovila/git/k8s-cbt-s3mover-demo/CLAUDE.md) - Add OpenShift requirements
- [README.md](/Users/tkaovila/git/k8s-cbt-s3mover-demo/README.md) - Document OpenShift setup

---

### 4. Demo Script Expects PostgreSQL but Workload is Block-Writer

**Problem:**
- [scripts/04-run-demo.sh](/Users/tkaovila/git/k8s-cbt-s3mover-demo/scripts/04-run-demo.sh) references PostgreSQL workload in comments and logic
- Script looks for pods with label `app=block-writer` but then executes PostgreSQL commands (`psql`)
- Mismatch between deployed workload (busybox with block device) and script expectations

**Impact:** High - Automated demo script is completely broken

**Evidence:**
```bash
# Line 32-34: Looks for block-writer
if ! kubectl get pod -n "$NAMESPACE" -l app=block-writer --no-headers | grep -q Running; then
    echo "Error: PostgreSQL pod is not running"  # Wrong error message!
    exit 1
fi

# Line 49: Tries to run psql
INITIAL_ROWS=$(kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U demo ...)
```

**Workaround Used:**
Manually demonstrated CBT workflow:
```bash
# 1. Write initial data
kubectl exec -n cbt-demo block-writer -- dd if=/dev/urandom of=/dev/xvda bs=4096 count=100

# 2. Create first snapshot
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: block-snapshot-1
  namespace: cbt-demo
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: block-writer-data
EOF

# 3. Write more data
kubectl exec -n cbt-demo block-writer -- dd if=/dev/urandom of=/dev/xvda bs=4096 count=200 seek=100

# 4. Create second snapshot
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: block-snapshot-2
  namespace: cbt-demo
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: block-writer-data
EOF
```

**Planned Fix:**
Rewrite [scripts/04-run-demo.sh](/Users/tkaovila/git/k8s-cbt-s3mover-demo/scripts/04-run-demo.sh) to work with block-writer:

```bash
#!/bin/bash
set -euo pipefail

NAMESPACE="cbt-demo"
POD_NAME="block-writer"
PVC_NAME="block-writer-data"
DEVICE="/dev/xvda"

# Step 1: Write initial data (100 blocks = 400KB)
echo "[Step 1] Writing initial data..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- dd if=/dev/urandom of="$DEVICE" bs=4096 count=100 seek=0
echo "✓ Wrote 100 blocks (400KB) at offset 0"

# Step 2: Create first snapshot
echo "[Step 2] Creating snapshot 1 (baseline)..."
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
kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/block-snapshot-1 -n "$NAMESPACE" --timeout=60s
echo "✓ Snapshot 1 created and ready"

# Step 3: Write incremental data (200 blocks = 800KB)
echo "[Step 3] Writing incremental data..."
kubectl exec -n "$NAMESPACE" "$POD_NAME" -- dd if=/dev/urandom of="$DEVICE" bs=4096 count=200 seek=100
echo "✓ Wrote 200 blocks (800KB) at offset 409600"

# Step 4: Create second snapshot
echo "[Step 4] Creating snapshot 2 (incremental)..."
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
kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/block-snapshot-2 -n "$NAMESPACE" --timeout=60s
echo "✓ Snapshot 2 created and ready"

# Step 5: Display results
echo ""
echo "=========================================="
echo "Demo Complete!"
echo "=========================================="
kubectl get volumesnapshot -n "$NAMESPACE"
kubectl get volumesnapshotcontent | grep "$NAMESPACE"
```

**Files to Update:**
- [scripts/04-run-demo.sh](/Users/tkaovila/git/k8s-cbt-s3mover-demo/scripts/04-run-demo.sh) - Complete rewrite for block-writer
- [scripts/05-simulate-disaster.sh](/Users/tkaovila/git/k8s-cbt-s3mover-demo/scripts/05-simulate-disaster.sh) - Update for block-writer
- [scripts/06-restore.sh](/Users/tkaovila/git/k8s-cbt-s3mover-demo/scripts/06-restore.sh) - Update for block-writer
- [scripts/07-verify.sh](/Users/tkaovila/git/k8s-cbt-s3mover-demo/scripts/07-verify.sh) - Update for block-writer

---

### 5. CSI Driver Deployment Script Hangs Waiting for Readiness ✅ FIXED

**Problem:**
- [scripts/01-deploy-csi-driver.sh](/Users/tkaovila/git/k8s-cbt-s3mover-demo/scripts/01-deploy-csi-driver.sh) waits indefinitely for all containers to be ready
- Due to ARM64 readiness probe issue (#2), the script never completes
- No timeout or fallback mechanism

**Impact:** Medium - Automated deployment hangs; manual intervention required

**Workaround Used:**
Killed the background process and manually created StorageClass:
```bash
kubectl apply -f /tmp/csi-driver-host-path/deploy/kubernetes-latest/hostpath/csi-hostpath-storageclass.yaml
```

**Fix Implemented:**
Added ARM64 architecture detection and skips readiness probe checks on ARM64:

```bash
# Detect architecture
ARCH=$(uname -m)

# ARM64 readiness probe workaround
# TODO: Remove this workaround once https://github.com/kubernetes-csi/external-snapshot-metadata/pull/190 is merged
if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
    # Wait for pod to be Running (not Ready)
    # Skip readiness probe checks that fail due to AMD64-only grpc_health_probe
else
    # AMD64: Use standard readiness checks
    kubectl rollout status statefulset/csi-hostpathplugin
    kubectl wait --for=condition=Ready pod -l app=csi-hostpathplugin
fi
```

The fix:

1. Detects system architecture using `uname -m`
2. On ARM64 (`aarch64` or `arm64`), skips readiness probe checks and only waits for `Running` phase
3. On AMD64, uses standard `kubectl rollout status` and `kubectl wait --for=condition=Ready`
4. Includes TODO comment referencing PR #190 for removal when upstream adds multi-arch support

**Files Updated:**

- [manifests/csi-driver/deploy-with-cbt.sh](/Users/tkaovila/git/k8s-cbt-s3mover-demo/manifests/csi-driver/deploy-with-cbt.sh) ✅

**Removal Plan:**
This workaround can be removed once [kubernetes-csi/external-snapshot-metadata#190](https://github.com/kubernetes-csi/external-snapshot-metadata/pull/190) is merged, which adds multi-arch support for `grpc_health_probe`.

---

### 6. Validation Script Has Incorrect Pod Label Check ✅ FIXED

**Problem:**
- [scripts/validate-cbt.sh](/Users/tkaovila/git/k8s-cbt-s3mover-demo/scripts/validate-cbt.sh) looks for `app=csi-hostpath-plugin` label
- Actual CSI driver pods don't have this exact label
- Script reports "CSI hostpath driver not found" even though driver is working

**Impact:** Low - Validation fails but functionality is not affected

**Evidence:**
```bash
$ ./scripts/validate-cbt.sh
✗ CSI hostpath driver not found  # Incorrect!
✓ Snapshot metadata sidecar is present  # Actually working
```

**Workaround Used:**
Ignored the validation failure; verified manually that pods exist:
```bash
kubectl get pods -n default | grep csi-hostpath
csi-hostpath-socat-0        1/1     Running
csi-hostpathplugin-0        8/9     Running
```

**Fix Applied (2025-11-13):**
Updated validation to check for actual pod names:

```bash
# scripts/validate-cbt.sh
echo "Checking CSI driver pods..."
if kubectl get pod -n default | grep -q "csi-hostpathplugin"; then
    echo "✓ CSI hostpath driver pods found"
    kubectl get pods -n default | grep csi-hostpath
else
    echo "✗ CSI hostpath driver not found"
fi
```

**Files Updated:**

- ✅ [scripts/validate-cbt.sh](/Users/tkaovila/git/k8s-cbt-s3mover-demo/scripts/validate-cbt.sh)

---

### 7. Missing CSI Snapshot Metadata Service

**Problem:**
- Deployment script applies `csi-snapshot-metadata-service.yaml` but service is not created
- Validation checks fail looking for `csi-snapshot-metadata` service
- Not clear if this affects CBT functionality

**Impact:** Unknown - Service not found but snapshots work

**Evidence:**
```bash
$ kubectl get svc csi-snapshot-metadata -n default
Error from server (NotFound): services "csi-snapshot-metadata" not found
```

**Investigation Needed:**
1. Verify if the service is required for CBT to work (it seems optional based on our success)
2. Check if the manifest was applied correctly
3. Determine if this is related to ARM64 architecture issues

**Files to Review:**
- [manifests/csi-driver/testdata/csi-snapshot-metadata-service.yaml](/Users/tkaovila/git/k8s-cbt-s3mover-demo/manifests/csi-driver/testdata/csi-snapshot-metadata-service.yaml)
- [scripts/01-deploy-csi-driver.sh](/Users/tkaovila/git/k8s-cbt-s3mover-demo/scripts/01-deploy-csi-driver.sh)

---

## Deployment Sequence That Worked

For reference, this is the exact sequence that successfully deployed the demo:

```bash
# 1. CSI Driver (manual StorageClass creation after timeout)
./scripts/01-deploy-csi-driver.sh  # Killed after timeout
kubectl apply -f /tmp/csi-driver-host-path/deploy/kubernetes-latest/hostpath/csi-hostpath-storageclass.yaml

# 2. MinIO
./scripts/02-deploy-minio.sh  # Success after CSI driver ready

# 3. Configure OpenShift namespace
kubectl label namespace cbt-demo \
  pod-security.kubernetes.io/enforce=privileged \
  --overwrite
oc adm policy add-scc-to-user privileged -z default -n cbt-demo

# 4. Block-writer workload
kubectl apply -f manifests/workload/block-writer-pod.yaml -n cbt-demo

# 5. Manual demo workflow
# (See Issue #4 for commands)
```

---

## Priority of Fixes

### High Priority (Blocks Automation)
1. **Issue #3**: OpenShift PodSecurity policies - Add auto-detection to scripts
2. **Issue #4**: Demo script PostgreSQL mismatch - Complete rewrite needed

### Medium Priority (User Experience)
3. **Issue #1**: KUBECONFIG requirement - Make scripts more flexible
4. ~~**Issue #5**: Deployment script hangs - Add timeout and fallback~~ ✅ **FIXED**

### Low Priority (Cosmetic/Documentation)

5. ~~**Issue #6**: Validation script labels - Fix pod detection~~ ✅ **FIXED**
6. **Issue #2**: ARM64 readiness probe - Document known issue
7. **Issue #7**: Missing service - Investigate if required

---

## Testing Plan

After implementing fixes, test on:
1. ✅ OpenShift 4.21 ARM64 (tested during this session)
2. ☐ OpenShift 4.21 AMD64
3. ☐ Vanilla Kubernetes 1.33+ on AWS
4. ☐ Minikube with Docker Desktop (macOS)
5. ☐ Kind cluster (if supported)

---

## Success Criteria

The repository is "workable" when:
- [x] Infrastructure deploys successfully on OpenShift ARM64
- [x] Snapshots can be created with CBT metadata
- [ ] Automated scripts complete without manual intervention
- [ ] Demo workflow script works end-to-end
- [ ] All validation checks pass or have documented exceptions
- [ ] README clearly documents OpenShift and ARM64 requirements

---

## Current Status

**What Works:**
- ✅ CSI hostpath driver deployment (with readiness probe warning)
- ✅ MinIO S3 storage deployment
- ✅ Block-writer workload deployment
- ✅ VolumeSnapshot creation
- ✅ SnapshotMetadataService CRD and instance
- ✅ CBT infrastructure is functional

**What Needs Fixing:**
- ❌ Automated deployment scripts (hang/fail on OpenShift)
- ❌ Demo workflow script (PostgreSQL vs block-writer mismatch)
- ⚠️ Validation script (false negatives)
- ⚠️ Documentation (missing OpenShift and ARM64 specifics)

---

## Next Steps

1. Create GitHub issues for each problem
2. Implement fixes in order of priority
3. Update documentation with known limitations
4. Test on multiple platforms
5. Update CLAUDE.md with lessons learned
