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
| Snapshot CRDs | external-snapshotter v8.1.0 | external-snapshotter v8.4.0 | external-snapshotter v8.4.0 |
| Snapshot controller | v8.1.0, patched to `default` namespace | v8.4.0, standard deploy | v8.4.0 |
| TLS certificates | Pre-generated testdata in repo | Generated programmatically in Go test code | Script-generated (`scripts/generate-csi-certs.sh`) |
| SnapshotMetadataService CRD | Installed from this repo | Installed from `test/e2e/testing-manifests/` | Installed from external-snapshot-metadata repo |
| Sidecar image | Built from PR SHA (`${{ github.sha }}`) | `gcr.io/k8s-staging-sig-storage` test tag | `gcr.io/k8s-staging-sig-storage` test tag |
| Service endpoint | `csi-snapshot-metadata.default:6443` | `csi-snapshot-metadata.<ns>:6443` | `csi-snapshot-metadata.default:6443` |

**Assessment**: Infrastructure setup is closely aligned with both upstream suites. Snapshot CRDs
now match kubernetes/kubernetes at v8.4.0.

## API Coverage Comparison

| Test Scenario | external-snapshot-metadata | kubernetes/kubernetes | demo.yaml |
|---|---|---|---|
| GetMetadataAllocated | Tested + block-verified | Tested + block-verified | Called + block-verified |
| GetMetadataDelta (snapshot names) | Tested + block-verified | Tested + block-verified | Called + block-verified |
| GetMetadataDelta (CSI handle, PR #180) | Tested + block-verified | Not tested | Called, **not verified** |
| Negative test (mismatch detection) | Tested (write + assert fail) | Not tested | Tested (write + assert fail) |
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

### This repo: `snapshot-metadata-lister` + `snapshot-metadata-verifier`

demo.yaml calls `snapshot-metadata-lister` to display block metadata and runs the
`snapshot-metadata-verifier` to validate metadata correctness against actual device contents.
The verifier pod (`manifests/snapshot-metadata-verifier/`) builds both tools from upstream source
and mounts source/target block PVCs for comparison.

## Detailed Gaps

### Gap 1: No block-level data verification (HIGH) -- CLOSED

**Status**: Implemented. Added `snapshot-metadata-verifier` steps for both GetMetadataAllocated
and GetMetadataDelta. Verifier pod manifest at `manifests/snapshot-metadata-verifier/pod.yaml`
builds both lister and verifier from upstream source, mounts source/target block PVCs, and
validates metadata against actual device contents.

### Gap 2: No negative testing (MEDIUM) -- CLOSED

**Status**: Implemented. After GetMetadataAllocated verification succeeds, a "Negative test"
step writes extra data to the target device and re-runs the verifier, asserting it fails.
This matches the external-snapshot-metadata upstream pattern.

### Gap 3: Snapshot CRD version behind kubernetes/kubernetes (LOW) -- CLOSED

**Status**: Bumped all snapshot CRD and controller URLs from v8.2.0 to v8.4.0, matching
kubernetes/kubernetes.

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

### Gap 5: RBAC missing `serviceaccounts/token` permission (LOW) -- ALREADY CLOSED

**Status**: The existing `manifests/snapshot-metadata-lister/rbac.yaml` already includes
`serviceaccounts/token` with `create` and `get` verbs. The verifier pod reuses the same
`csi-client-sa` ServiceAccount and RBAC. No changes needed.

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

### 3. Test data writing pattern (from both) -- ADOPTED

```bash
# Direct I/O to bypass page cache
dd if=/dev/urandom of=/dev/xvda bs=4K count=6 oflag=direct status=none
sync
```

demo.yaml now uses `oflag=direct` on all dd commands and adds `sync` after each batch of
writes, matching upstream behavior.

## Priority Action Items

| Priority | Gap | Status | Impact |
|----------|-----|--------|--------|
| HIGH | Add `snapshot-metadata-verifier` step | CLOSED | Proves metadata correctness |
| MEDIUM | Add negative test (mismatch detection) | CLOSED | Validates verifier catches errors |
| LOW | Bump snapshot CRDs to v8.4.0 | CLOSED | Aligns with kubernetes/kubernetes |
| LOW | Add `oflag=direct` to dd commands | CLOSED | Matches upstream I/O pattern |
| LOW | Test audience parameter | OPEN | Covers auth edge case |
| LOW | Add `serviceaccounts/token` RBAC | ALREADY CLOSED | Required for verifier |
