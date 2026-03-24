# E2E Test Gap Analysis: demo.yaml vs Upstream CBT Tests

This document compares the CI workflow in this repository (`.github/workflows/demo.yaml`) against
the upstream e2e test suites for CSI Changed Block Tracking (CBT):

1. **kubernetes-csi/external-snapshot-metadata** — integration test in `.github/workflows/integration-test.yaml`
2. **kubernetes/kubernetes** — e2e test suite in `test/e2e/storage/testsuites/snapshot-metadata.go` (PR [#130918](https://github.com/kubernetes/kubernetes/pull/130918), merged Feb 2026)

## Sources

| Source | Location | Purpose |
|--------|----------|---------|
| external-snapshot-metadata CI | [`.github/workflows/integration-test.yaml`](https://github.com/kubernetes-csi/external-snapshot-metadata/blob/main/.github/workflows/integration-test.yaml) | Validates sidecar + CSI driver integration |
| kubernetes/kubernetes e2e | [`test/e2e/storage/testsuites/snapshot-metadata.go`](https://github.com/kubernetes/kubernetes/blob/master/test/e2e/storage/testsuites/snapshot-metadata.go) | CSI driver conformance testing |
| kubernetes/kubernetes e2e utils | [`test/e2e/storage/utils/snapshot-metadata.go`](https://github.com/kubernetes/kubernetes/blob/master/test/e2e/storage/utils/snapshot-metadata.go) | TLS cert generation, service creation, SnapshotMetadataService CR |
| kubernetes/kubernetes e2e setup | [`test/e2e/testing-manifests/storage-csi/external-snapshot-metadata/`](https://github.com/kubernetes/kubernetes/tree/master/test/e2e/testing-manifests/storage-csi/external-snapshot-metadata) | RBAC, CRD, run script |
| This repo CI | [`.github/workflows/demo.yaml`](../../.github/workflows/demo.yaml) | Full backup/restore demo with S3 |

## Infrastructure Setup Comparison

| Setup Step | external-snapshot-metadata | kubernetes/kubernetes | demo.yaml |
|---|---|---|---|
| Cluster | Minikube via `medyagh/setup-minikube` | CSI Prow CI | Minikube via `medyagh/setup-minikube` + BYOC |
| CSI hostpath driver | canary tag, `SNAPSHOT_METADATA_TESTS=true` | `--enable-snapshot-metadata` flag | canary tag, `SNAPSHOT_METADATA_TESTS=true` |
| Snapshot CRDs | external-snapshotter v8.1.0 | external-snapshotter v8.4.0 | external-snapshotter v8.2.0 |
| Snapshot controller | v8.1.0, patched to `default` namespace | v8.4.0, standard deploy | v8.2.0 |
| TLS certificates | Pre-generated testdata in repo | Generated programmatically in Go test code | Script-generated (`scripts/generate-csi-certs.sh`) |
| SnapshotMetadataService CRD | Installed from this repo | Installed from `test/e2e/testing-manifests/` | Installed from external-snapshot-metadata repo |
| Sidecar image | Built from PR SHA (`${{ github.sha }}`) | `gcr.io/k8s-staging-sig-storage` test tag | `gcr.io/k8s-staging-sig-storage` test tag |
| Service endpoint | `csi-snapshot-metadata.default:6443` | `csi-snapshot-metadata.<ns>:6443` | `csi-snapshot-metadata.default:6443` |

**Assessment**: Infrastructure setup is closely aligned with external-snapshot-metadata. The main
difference is snapshot CRD version (v8.2.0 vs v8.4.0 in k/k).

## API Coverage Comparison

| Test Scenario | external-snapshot-metadata | kubernetes/kubernetes | demo.yaml |
|---|---|---|---|
| GetMetadataAllocated | Tested + block-verified | Tested + block-verified | Called, **not verified** |
| GetMetadataDelta (snapshot names) | Tested + block-verified | Tested + block-verified | Called, **not verified** |
| GetMetadataDelta (CSI handle, PR #180) | Tested + block-verified | Not tested | Called, **not verified** |
| Negative test (mismatch detection) | Tested (write + assert fail) | Not tested | **Not tested** |
| Audience/token auth matrix | Tested (with/without) | Not tested | **Not tested** |
| Pagination (`-max-results`) | Tested (10) | Default (driver decides) | Tested (10) |
| S3 metadata upload | Not tested | Not tested | Tested (MinIO) |
| S3 block data upload | Not tested | Not tested | Tested (MinIO) |
| In-cluster backup Job | Not tested | Not tested | Tested (`cbt-backup` Job) |
| In-cluster restore Job | Not tested | Not tested | Tested (`cbt-restore` Job) |
| Restore dry-run | Not tested | Not tested | Tested |

## Verification Tools

### Upstream: `snapshot-metadata-verifier`

Both upstream suites use the [`snapshot-metadata-verifier`](https://github.com/kubernetes-csi/external-snapshot-metadata/tree/main/tools/snapshot-metadata-verifier) tool, which:

1. Calls the CBT gRPC API (GetMetadataAllocated or GetMetadataDelta)
2. Reads actual block data from source and target devices
3. Compares metadata results against real device contents
4. Returns error if blocks don't match

The kubernetes/kubernetes tests install it via an init container:
```bash
go install github.com/kubernetes-csi/external-snapshot-metadata/tools/snapshot-metadata-verifier@main
```

The external-snapshot-metadata tests build it from the PR source code.

### This repo: `snapshot-metadata-lister` only

demo.yaml calls `snapshot-metadata-lister` to display block metadata but **does not run the verifier**.
This proves the API responds but does not prove the metadata is correct.

## Detailed Gaps

### Gap 1: No block-level data verification (HIGH)

**Upstream behavior**: Both suites restore snapshots to PVCs, mount them as block devices in a
verification pod, and run `snapshot-metadata-verifier` to compare metadata against actual device
contents.

**demo.yaml behavior**: Calls `snapshot-metadata-lister` to list blocks, but never verifies that
the returned block metadata matches the actual device data.

**Impact**: Cannot prove CBT metadata correctness. A CSI driver returning wrong block offsets
would not be caught.

**Fix**: Add a step that deploys the verifier pod pattern from upstream:
```yaml
- name: Verify CBT metadata with snapshot-metadata-verifier
  run: |
    # Restore snapshot to source PVC
    # Create empty target PVC
    # Deploy verification pod with both devices + verifier tool
    # Run: snapshot-metadata-verifier -snapshot snap-1 \
    #   -source-device-path /dev/source -target-device-path /dev/target
```

### Gap 2: No negative testing (MEDIUM)

**Upstream behavior** (external-snapshot-metadata only): After successful verification, writes
additional data to the target device and runs the verifier again, asserting it **fails**. This
proves the verifier actually catches mismatches rather than always succeeding.

**demo.yaml behavior**: No negative test cases.

**Fix**: After successful verification, write extra data and assert verifier returns non-zero exit:
```bash
# Write extra data to target device
kubectl exec verifier-pod -- dd if=/dev/urandom of=/dev/target bs=4K count=1 oflag=direct
# Expect verifier to fail
! kubectl exec verifier-pod -- /tools/snapshot-metadata-verifier ...
```

### Gap 3: Snapshot CRD version behind kubernetes/kubernetes (LOW)

**Upstream**: kubernetes/kubernetes uses external-snapshotter v8.4.0.

**demo.yaml**: Uses v8.2.0.

**Fix**: Bump CRD and controller URLs from v8.2.0 to v8.4.0.

### Gap 4: No audience parameter testing (LOW)

**Upstream behavior** (external-snapshot-metadata only): Tests with and without the `audience`
field on the SnapshotMetadataService CR using a GitHub Actions matrix:
```yaml
strategy:
  matrix:
    audience: ["", "test-backup-client"]
```

**demo.yaml behavior**: Does not test audience-based token authentication.

**Fix**: Add a matrix or second workflow run with audience configured.

### Gap 5: RBAC missing `serviceaccounts/token` permission (LOW)

**Upstream** (kubernetes/kubernetes): The backup client RBAC includes permission to create
ServiceAccount tokens via the TokenRequest API:
```yaml
- apiGroups: [""]
  resources: [serviceaccounts/token]
  verbs: [create, get]
```

**demo.yaml**: The `snapshot-metadata-lister` RBAC may not include this permission. The lister
currently works because it uses in-cluster config, but the verifier requires explicit token
creation.

**Fix**: Add `serviceaccounts/token` create permission to the lister/verifier RBAC.

## What demo.yaml Covers That Upstream Does Not

These are unique to this repository and represent the real-world backup/restore value-add:

1. **S3 backup pipeline** — Metadata and block data uploaded to MinIO S3 storage
2. **In-cluster Kubernetes Jobs** — `cbt-backup` and `cbt-restore` run as Jobs (production operator pattern)
3. **BYOC (Bring Your Own Cluster)** — Remote cluster testing via `KUBECONFIG` GitHub secret
4. **PR #180 CSI handle delta testing** — kubernetes/kubernetes does not test this yet
5. **Complete restore flow** — Restore from S3 back to a new PVC with integrity verification
6. **Restore dry-run** — Pre-flight validation before actual restore
7. **Block writer workload** — Simulates real application I/O patterns

## Upstream Test Patterns Worth Adopting

### 1. InitContainer tool installation (from kubernetes/kubernetes)

```yaml
initContainers:
- name: install-verifier
  image: golang:1.25
  command: ["/bin/sh", "-c"]
  args:
  - |
    go install github.com/kubernetes-csi/external-snapshot-metadata/tools/snapshot-metadata-verifier@main
    cp $(go env GOPATH)/bin/snapshot-metadata-verifier /output/
  volumeMounts:
  - name: tools
    mountPath: /output
```

### 2. Programmatic TLS generation (from kubernetes/kubernetes)

The `test/e2e/storage/utils/snapshot-metadata.go` generates TLS certificates in Go test code
with proper SANs for the service DNS name. This is more robust than pre-generated or
script-generated certificates.

### 3. Test data writing pattern (from both)

```bash
# Direct I/O to bypass page cache
dd if=/dev/urandom of=/dev/xvda bs=4K count=6 oflag=direct status=none
sync
```

demo.yaml uses `conv=notrunc` but not `oflag=direct`. Adding `oflag=direct` ensures data
hits the block device immediately, matching upstream behavior.

## Priority Action Items

| Priority | Gap | Effort | Impact |
|----------|-----|--------|--------|
| HIGH | Add `snapshot-metadata-verifier` step | Medium | Proves metadata correctness |
| MEDIUM | Add negative test (mismatch detection) | Low | Validates verifier catches errors |
| LOW | Bump snapshot CRDs to v8.4.0 | Low | Aligns with kubernetes/kubernetes |
| LOW | Add `oflag=direct` to dd commands | Trivial | Matches upstream I/O pattern |
| LOW | Test audience parameter | Low | Covers auth edge case |
| LOW | Add `serviceaccounts/token` RBAC | Trivial | Required for verifier |
