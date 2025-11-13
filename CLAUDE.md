# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a demonstration of Kubernetes Changed Block Tracking (CBT) using CSI hostpath driver with incremental backup to MinIO S3 storage. The project showcases real CBT API usage for efficient block-level backups and disaster recovery.

**Key Technologies:**
- Kubernetes 1.33+ (for CBT alpha APIs)
- CSI hostpath driver with SnapshotMetadata service
- MinIO for S3-compatible storage
- Go 1.22+ for backup/restore tools
- Block-mode PVCs (required for CBT)

## Architecture

The system consists of three main components:

1. **Infrastructure Layer**: Minikube cluster with CSI hostpath driver supporting CBT metadata APIs (GetMetadataAllocated, GetMetadataDelta)
2. **Storage Layer**: MinIO S3 storage for backup metadata and block data
3. **Application Layer**: Block-writer workload with raw block device access for CBT demonstration

**Data Flow:**
- Initial backup: GetMetadataAllocated() → identifies allocated blocks → upload to S3
- Incremental backup: GetMetadataDelta(baseHandle, targetHandle) → changed blocks only → upload to S3
- Restore: Download metadata + blocks → reconstruct volume → verify integrity

**Important API Note:** As of kubernetes-csi/external-snapshot-metadata PR #180 (Oct 2025), GetMetadataDelta uses CSI snapshot handles (from VolumeSnapshotContent.Status.SnapshotHandle) rather than snapshot names. This allows computing deltas even after base snapshots are deleted.

## Common Development Commands

### Building

```bash
# Build the backup tool
cd tools/cbt-backup
go mod download
go build -o cbt-backup ./cmd

# Build with Docker
docker build -t cbt-backup:latest .

# Build presentation slides
cd demo
npm install
npm run build
```

### Testing

```bash
# Run Go tests for backup tool
cd tools/cbt-backup
go test -v ./...
go test -race ./...

# Lint shell scripts (used in CI)
shellcheck scripts/*.sh
```

### Running the Demo

```bash
# Automated setup with Minikube (recommended for local testing)
./scripts/run-local-minikube.sh

# Manual step-by-step setup
./scripts/00-setup-cluster.sh          # Create Minikube cluster
./scripts/01-deploy-csi-driver.sh      # Deploy CSI driver with CBT
./scripts/02-deploy-minio.sh           # Deploy MinIO S3
./scripts/03-deploy-workload.sh        # Deploy block-writer workload
./scripts/04-run-demo.sh               # Run demo workflow

# Remote cluster setup
export KUBECONFIG=/path/to/kubeconfig
./scripts/run-demo-remote.sh

# Cleanup
./scripts/cleanup.sh                    # Local cleanup
./scripts/cleanup-remote-cluster.sh     # Remote cleanup
```

### Validation and Debugging

```bash
# Validate CBT setup
./scripts/validate-cbt.sh

# Check backup status
./scripts/backup-status.sh

# Verify data integrity
./scripts/integrity-check.sh

# Dry-run restore
./scripts/restore-dry-run.sh cbt-demo snapshot-name

# Check CSI driver logs for metadata service
kubectl logs -n default -l app=csi-hostpathplugin -c hostpath | grep -i metadata

# Verify SnapshotMetadataService CRD
kubectl get crd snapshotmetadataservices.cbt.storage.k8s.io
kubectl get snapshotmetadataservices -A
```

### Using the Backup Tool

```bash
cd tools/cbt-backup

# Full backup (uses GetMetadataAllocated)
./cbt-backup create --pvc block-writer-data --namespace cbt-demo

# Incremental backup (uses GetMetadataDelta)
./cbt-backup create \
  --pvc block-writer-data \
  --snapshot block-snapshot-2 \
  --base-snapshot block-snapshot-1 \
  --namespace cbt-demo

# List backups from S3
./cbt-backup list

# Use custom S3 endpoint
./cbt-backup create \
  --pvc my-pvc \
  --s3-endpoint my-minio:9000 \
  --s3-bucket my-bucket
```

## Code Organization

### Tools Structure

**tools/cbt-backup/** - Backup tool (90% complete)
- `cmd/main.go`: CLI entry point with Cobra commands (create, list)
- `pkg/metadata/cbt_client.go`: gRPC client for CSI SnapshotMetadata service - **core CBT implementation**
  - `GetAllocatedBlocks()`: Calls GetMetadataAllocated RPC for full backups
  - `GetDeltaBlocks()`: Calls GetMetadataDelta RPC for incremental backups
  - Uses CSI snapshot handles per PR #180
- `pkg/metadata/types.go`: Metadata structures (SnapshotManifest, BlockList, SnapshotChain, BackupStats)
- `pkg/snapshot/snapshot.go`: Kubernetes VolumeSnapshot creation and management
- `pkg/s3/client.go`: MinIO client for metadata/block upload/download
- `pkg/blocks/reader.go`: Block device reader for extracting block data

**TODO:** Block data upload is not yet implemented (currently metadata-only). The infrastructure is complete; need to add actual block reading and S3 upload in `runBackup()`.

**tools/cbt-restore/** - Restore tool (planned, not yet started)

### Scripts Organization

Scripts are numbered for execution order:
- `00-*`: Cluster setup (local or remote)
- `01-*`: MinIO deployment
- `02-*`: CSI driver deployment
- `03-*`: Workload deployment
- `04-07-*`: Demo workflow steps (run, simulate disaster, restore, verify)
- `run-*`: Automated full workflows
- Other scripts: Validation, status checking, cleanup

### Manifests Structure

- `manifests/namespace.yaml`: cbt-demo namespace
- `manifests/minio/`: MinIO StatefulSet, Service, PVC, Secret
- `manifests/csi-driver/`: CSI hostpath driver with external-snapshot-metadata sidecar
  - `deploy-with-cbt.sh`: Main deployment script following upstream pattern
  - `testdata/`: Example manifests for snapshot metadata service
    - `snapshotmetadataservice.yaml`: SnapshotMetadataService CR
    - `csi-snapshot-metadata-service.yaml`: ClusterIP service for gRPC communication
    - `csi-snapshot-metadata-tls-secret.yaml`: TLS secret template (created by script)
  - `storage-class.yaml`: StorageClass for CSI hostpath driver
  - `snapshot-class.yaml`: VolumeSnapshotClass for snapshots
- `manifests/workload/`: Block-writer pod with block-mode PVC for raw device access

## Important Implementation Details

### CSI Driver Deployment with TLS

The CSI driver deployment follows the upstream external-snapshot-metadata integration test pattern. The deployment process (`manifests/csi-driver/deploy-with-cbt.sh`) executes these steps:

1. **Deploy Snapshot Controller** (`scripts/deploy-snapshot-controller.sh`):
   - Installs VolumeSnapshot CRDs (VolumeSnapshot, VolumeSnapshotContent, VolumeSnapshotClass)
   - Deploys snapshot controller pod
   - Uses snapshot version v8.1.0 from upstream external-snapshotter

2. **Generate TLS Certificates** (`scripts/generate-csi-certs.sh`):
   - Creates self-signed CA certificate and key
   - Generates server certificate with Subject Alternative Names (SANs)
   - Creates Kubernetes TLS secret: `csi-snapshot-metadata-certs`
   - Updates `snapshotmetadataservice.yaml` with base64-encoded CA cert

3. **Clone CSI Hostpath Driver**:
   - Clones from `https://github.com/kubernetes-csi/csi-driver-host-path.git`
   - Uses temporary directory `/tmp/csi-driver-host-path`

4. **Install SnapshotMetadataService CRD**:
   - Applies from external-snapshot-metadata repository (v0.1.0 or main)
   - Waits for CRD to be established

5. **Deploy CSI Driver with Environment Variables**:
   - `CSI_SNAPSHOT_METADATA_REGISTRY=gcr.io/k8s-staging-sig-storage`
   - `UPDATE_RBAC_RULES=false` (RBAC already configured)
   - `CSI_SNAPSHOT_METADATA_TAG=test` (uses test image)
   - `SNAPSHOT_METADATA_TESTS=true` (enables metadata sidecar)
   - `HOSTPATHPLUGIN_REGISTRY=gcr.io/k8s-staging-sig-storage`
   - `HOSTPATHPLUGIN_TAG=canary` (latest development version)

6. **Apply Testdata Manifests**:
   - Creates SnapshotMetadataService CR (`hostpath.csi.k8s.io`)
   - Creates ClusterIP service (`csi-snapshot-metadata`) on port 6443
   - Service routes to snapshot metadata sidecar on port 50051

7. **Wait for Pod Readiness**:
   - Waits for `csi-hostpathplugin-0` pod to be Running
   - Verifies StatefulSet rollout status

**Key Configuration Details:**
- **gRPC Endpoint**: `csi-snapshot-metadata.default:6443` (TLS-secured)
- **TLS Secret**: `csi-snapshot-metadata-certs` in `default` namespace
- **Service Selectors**: Targets pods with labels:
  - `app.kubernetes.io/name=csi-hostpathplugin`
  - `app.kubernetes.io/component=plugin`
  - `app.kubernetes.io/instance=hostpath.csi.k8s.io`

### CSI SnapshotMetadata gRPC Client

The CBT functionality is in `tools/cbt-backup/pkg/metadata/cbt_client.go`:

1. **Connection**: Establishes gRPC connection to CSI driver socket at `unix:///csi/csi.sock`
2. **GetAllocatedBlocks**: Retrieves VolumeSnapshot → VolumeSnapshotContent → CSI handle → calls GetMetadataAllocated RPC
3. **GetDeltaBlocks**: Gets both base and target CSI handles → calls GetMetadataDelta RPC with handles (not names)
4. **Streaming**: Both RPCs return streaming responses that are collected into BlockMetadata lists

### S3 Storage Layout

```
s3://snapshots/
├── metadata/<snapshot-name>/
│   ├── manifest.json    # Snapshot info (size, blocks, timestamp, type)
│   ├── blocks.json      # List of blocks with offset/size
│   └── chain.json       # Dependency chain for incremental restores
└── blocks/<snapshot-name>/
    └── block-<offset>-<size>  # Actual block data (TODO: not yet uploaded)
```

### Block Mode Volumes

CBT requires `volumeMode: Block` (not Filesystem). Check with:
```bash
kubectl get pvc -n cbt-demo -o yaml | grep volumeMode
```

All workload PVCs in this demo use block mode.

### Environment Constraints

- **Minikube with VM drivers (Docker Desktop, QEMU)**: Full support (VM-based, used by upstream CI)
- **Minikube with Podman**: LIMITED support - works for Filesystem volumes only, NOT for Block volumes
- **Kind**: NOT supported (container-based limitations with loop devices)
- **EKS/GKE/AKS**: Full support (production environments)

**Block Device Limitation**: The CSI hostpath driver requires loop device support for `volumeMode: Block`. Podman on macOS (via AppleHV) cannot create loop devices (`/dev/loop*`), resulting in `losetup: failed to set up loop device` errors. This affects the CBT demo which requires block-mode PVCs.

**Podman Setup**: For running Minikube with Podman for non-CBT workloads (Filesystem volumes), see [CNCF guide](https://www.cncf.io/blog/2025/05/13/how-to-install-and-run-minikube-with-rootless-podman-on-arm-based-macbooks/):
```bash
# Initialize Podman machine (if not already done)
podman machine init --cpus 4 --memory 4096 --disk-size 25
podman machine start

# Configure and start Minikube with rootless mode
minikube config set rootless true
minikube start --driver=podman --container-runtime=containerd
```

**For CBT Demo**: Use VM-based drivers (Docker Desktop with HyperKit/Virtualization.framework, QEMU) or cloud clusters for full block device support.

**macOS Note**: Requires GNU sed for deployment scripts. Install with `brew install gnu-sed` and add to PATH:
```bash
PATH="$HOMEBREW_PREFIX/opt/gnu-sed/libexec/gnubin:$PATH"
```

**OpenShift Requirements**: The demo requires privileged pods for raw block device access. OpenShift namespaces enforce `restricted` PodSecurity policies by default. The deployment script ([scripts/02-deploy-minio.sh](scripts/02-deploy-minio.sh)) automatically detects OpenShift and configures the namespace:

1. **Auto-detection**: Checks for SecurityContextConstraints API resource
2. **Namespace labeling**: Sets `pod-security.kubernetes.io/enforce=privileged`
3. **SCC assignment**: Grants `privileged` SCC to default service account

Manual configuration (if needed):
```bash
# Label namespace for privileged pods
kubectl label namespace cbt-demo \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged \
  --overwrite

# Grant privileged SCC (requires oc CLI)
oc adm policy add-scc-to-user privileged -z default -n cbt-demo
```

**Tested On:**
- ✅ OpenShift 4.21 (Kubernetes 1.34.1) on AWS ARM64
- ✅ Vanilla Kubernetes 1.33+ (Minikube, cloud providers)

**Known Limitations on ARM64:**
- CSI snapshot metadata readiness probe fails (container remains functional)
- `grpc_health_probe` binary in upstream images is AMD64-only
- Impact: Low - pod shows 8/9 containers ready but CBT functionality works correctly

### CI/CD Workflows

- `.github/workflows/demo.yaml`: Main workflow with Minikube or BYOC (Bring Your Own Cluster)
- `.github/workflows/demo-aws.yaml`: Automated EKS cluster creation and testing
- `.github/workflows/build-presentation.yaml`: Builds Slidev presentation
- `.github/workflows/claude*.yml`: AI-assisted code review workflows

**BYOC**: Set GitHub secret `KUBECONFIG` with base64-encoded kubeconfig for testing on real clusters.

## Development Guidelines

### When Adding New Features

1. **Backup tool changes**: Work in `tools/cbt-backup/`, update `pkg/` packages
2. **New scripts**: Follow numbering convention, add to README.md
3. **Manifest changes**: Update in `manifests/` directory, test with validation scripts
4. **Documentation**: Update README.md, STATUS.md, and this file

### Testing Changes

1. Run `./scripts/cleanup.sh` to ensure clean state
2. Run `./scripts/run-local-minikube.sh` for full integration test
3. Verify with `./scripts/validate-cbt.sh` and `./scripts/integrity-check.sh`
4. Check STATUS.md and update completion percentages

### Working with the Backup Tool

To complete the backup tool's block upload functionality:

1. The gRPC client in `pkg/metadata/cbt_client.go` is **fully functional**
2. The `runBackup()` function in `cmd/main.go` successfully calls `GetAllocatedBlocks()` or `GetDeltaBlocks()`
3. **TODO**: After getting block metadata, read actual block data using `pkg/blocks/reader.go` and upload to S3 using `pkg/s3/client.go`
4. The S3 path should be: `blocks/<snapshot-name>/block-<offset>-<size>`

### Kubernetes API Interactions

The backup tool interacts with Kubernetes via:
- **Snapshot API**: Creates VolumeSnapshots, queries VolumeSnapshotContents for CSI handles
- **gRPC**: Direct connection to CSI driver's SnapshotMetadata service (not through Kubernetes API server)
- **Core API**: Queries PVCs for source volume information (via snapshot manager)

### MinIO Access

- **Inside cluster**: `minio.cbt-demo.svc.cluster.local:9000`
- **Outside cluster**: `http://localhost:30900` (API), `http://localhost:30901` (Console)
- **Credentials**: minioadmin / minioadmin123
- **Bucket**: snapshots (auto-created)

## Known Issues and Limitations

1. **CBT API Alpha Status**: Requires Kubernetes 1.33+ (alpha feature, no feature gates needed)
2. **CSI Driver Support**: Only CSI hostpath driver implements CBT; AWS EBS CSI does not yet support it
3. **Block Mode Required**: Filesystem-mode volumes do not support CBT
4. **Backup Tool Status**: Metadata infrastructure complete, block data upload TODO
5. **Restore Tool**: Not yet implemented (planned)

## References

- [KEP-3314: CSI Changed Block Tracking](https://github.com/kubernetes/enhancements/blob/master/keps/sig-storage/3314-csi-changed-block-tracking/README.md)
- [External Snapshot Metadata Sidecar](https://github.com/kubernetes-csi/external-snapshot-metadata)
- [PR #180: Change base snapshot parameter to CSI handle](https://github.com/kubernetes-csi/external-snapshot-metadata/pull/180)
- [Kubernetes Blog: CBT Alpha Announcement](https://kubernetes.io/blog/2025/09/25/csi-changed-block-tracking/)
- [CSI Spec - SnapshotMetadata](https://github.com/container-storage-interface/spec/blob/master/spec.md)

## Claude Code Workflow Best Practices

### GitHub Actions Commands

**`gh run watch` behavior:**
When `gh run watch` exits cleanly (exit code 0), the run has already completed successfully. **No need to sleep and check status again** - the command blocks until the run finishes.

```bash
# ✓ MOST EFFICIENT: Pipe watch to /dev/null and immediately view on success
gh run watch 18798961487 --exit-status > /dev/null && gh run view 18798961487

# ✓ ALSO CORRECT: Just check the logs or details directly
gh run view 18798961487 --log
gh run view 18798961487 --job=<job-id> --log

# ✗ WRONG: Don't do this after gh run watch succeeds
sleep 180 && gh run view 18798961487
```

### Git Commit Practices

**Use specific file paths, not `git add -A`:**
Multiple agents may be working simultaneously and committing. Use specific file paths to avoid staging other agents' changes:

```bash
# ✗ WRONG: Adds all files including other agents' changes
git add -A

# ✓ CORRECT: Add specific files only
git add manifests/snapshot-metadata-lister/rbac.yaml
git add .github/workflows/demo.yaml
git add tools/cbt-backup/pkg/metadata/cbt_client.go
```

## Project Status Summary

See STATUS.md for detailed tracking, but key points:
- Infrastructure: 100% complete
- Backup tool: 90% complete (metadata infrastructure done, block upload TODO)
- Restore tool: 0% complete (planned)
- All automation scripts: 100% complete
- Documentation: 100% complete
