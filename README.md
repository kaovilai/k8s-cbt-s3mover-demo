# Kubernetes Changed Block Tracking (CBT) Demo

A self-contained demonstration of Kubernetes Changed Block Tracking (CBT) using CSI hostpath driver with incremental backup to MinIO S3 storage and disaster recovery.

## 🎯 Overview

This demo showcases:
- ✅ **Real CBT API** using CSI SnapshotMetadata service (`GetMetadataDelta`, `GetMetadataAllocated`)
- ✅ **Block-mode volumes** required for CBT
- ✅ **Incremental backups** - only changed blocks are uploaded
- ✅ **S3-compatible storage** using MinIO
- ✅ **Disaster recovery** - restore from incremental snapshots
- ✅ **Kind cluster** for fast local testing

## 📋 Prerequisites

- [Kind](https://kind.sigs.k8s.io/) v0.20.0 or later
- [kubectl](https://kubernetes.io/docs/tasks/tools/) v1.28.0 or later
- [Go](https://golang.org/) 1.22 or later (for building tools)
- Docker (for Kind)
- ~10GB free disk space

**CBT Support**: Changed Block Tracking API is available as an alpha feature starting in **Kubernetes 1.33**. For full CBT functionality, use Kubernetes 1.33 or later.

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Kind Cluster                           │
│                                                           │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────┐ │
│  │  PostgreSQL  │  │   MinIO S3    │  │  CSI Driver  │ │
│  │  (Block PVC) │  │   Storage     │  │  with CBT    │ │
│  └──────────────┘  └───────────────┘  └──────────────┘ │
│         │                  │                  │          │
│         └─────────┬────────┴──────────────────┘          │
│                   │                                       │
│           ┌───────▼────────┐                             │
│           │  Backup Tool   │                             │
│           │  (uses CBT)    │                             │
│           └────────────────┘                             │
└─────────────────────────────────────────────────────────┘
```

### Data Flow

1. **Initial Backup**: Full snapshot → All blocks uploaded to MinIO
2. **Incremental Backup**: New snapshot → GetMetadataDelta() → Only changed blocks uploaded
3. **Restore**: Download metadata + blocks → Reconstruct volume → Verify integrity

## 🚀 Quick Start

### Option A: Local Kind Cluster (Development)

**Note**: Block volumes have [known limitations](#known-limitations) in containerized environments.

#### 1. Setup the Cluster

```bash
# Create Kind cluster with CSI support
./scripts/00-setup-cluster.sh
```

### Option B: Remote Cluster (Recommended for Block Volumes)

Use this approach to run the demo on a real Kubernetes cluster with proper block device support.

#### 1. Setup Your Cluster Connection

```bash
# Set your kubeconfig
export KUBECONFIG=/path/to/your/kubeconfig

# Verify connectivity
kubectl cluster-info
```

#### 2. Run Automated Setup

```bash
# Run the complete demo setup on remote cluster
./scripts/run-demo-remote.sh
```

This will:
- Verify cluster connectivity
- Deploy MinIO for S3 storage
- Install VolumeSnapshot CRDs (if needed)
- Optionally install CSI driver
- Deploy PostgreSQL workload
- Validate the setup

#### Manual Remote Cluster Setup

If you prefer step-by-step control:

```bash
# 1. Verify cluster
./scripts/00-setup-remote-cluster.sh

# 2. Continue with standard deployment steps below
```

### 2. Deploy MinIO (S3 Storage)

```bash
# Deploy MinIO for backup storage
./scripts/01-deploy-minio.sh
```

Access MinIO:
- **API**: http://localhost:30900
- **Console**: http://localhost:30901
- **Credentials**: minioadmin / minioadmin123

### 3. Deploy CSI Driver with CBT

```bash
# Deploy hostpath CSI driver with Changed Block Tracking support
./scripts/02-deploy-csi-driver.sh
```

This deploys:
- CSI hostpath driver
- External snapshot metadata sidecar
- SnapshotMetadataService CRD
- VolumeSnapshotClass

### 4. Deploy PostgreSQL Workload

```bash
# Deploy PostgreSQL with block-mode PVC
./scripts/03-deploy-workload.sh
```

This creates:
- PostgreSQL StatefulSet with 2Gi block PVC
- Initial data (~100MB) in demo_data table

## 🧪 Demo Workflow

### Complete Demo (Coming Soon)

```bash
# Run the complete demo workflow
./scripts/04-run-demo.sh
```

### Manual Steps

1. **Create first snapshot** (full backup)
   ```bash
   kubectl create -f - <<EOF
   apiVersion: snapshot.storage.k8s.io/v1
   kind: VolumeSnapshot
   metadata:
     name: postgres-snapshot-1
     namespace: cbt-demo
   spec:
     volumeSnapshotClassName: csi-hostpath-snapclass
     source:
       persistentVolumeClaimName: postgres-data-postgres-0
   EOF
   ```

2. **Backup snapshot 1** (TODO: Implement backup tool)
   ```bash
   # This will upload all allocated blocks
   ./tools/cbt-backup/cbt-backup create --pvc postgres-data-postgres-0 \
     --snapshot postgres-snapshot-1
   ```

3. **Insert more data**
   ```bash
   kubectl exec -it -n cbt-demo postgres-0 -- psql -U demo -d cbtdemo -c \
     "INSERT INTO demo_data (data_block, content, checksum)
      SELECT generate_series(1001, 1100),
             encode(gen_random_bytes(100000), 'base64'),
             md5(random()::text);"
   ```

4. **Create second snapshot** (incremental)
   ```bash
   kubectl create -f - <<EOF
   apiVersion: snapshot.storage.k8s.io/v1
   kind: VolumeSnapshot
   metadata:
     name: postgres-snapshot-2
     namespace: cbt-demo
   spec:
     volumeSnapshotClassName: csi-hostpath-snapclass
     source:
       persistentVolumeClaimName: postgres-data-postgres-0
   EOF
   ```

5. **Incremental backup** (only changed blocks)
   ```bash
   # This will use GetMetadataDelta() to find changed blocks
   ./tools/cbt-backup/cbt-backup create --pvc postgres-data-postgres-0 \
     --snapshot postgres-snapshot-2 \
     --base-snapshot postgres-snapshot-1
   ```

6. **Simulate disaster**
   ```bash
   kubectl delete statefulset postgres -n cbt-demo
   kubectl delete pvc postgres-data-postgres-0 -n cbt-demo
   ```

7. **Restore from backups**
   ```bash
   # TODO: Implement restore tool
   ./tools/cbt-restore/cbt-restore restore --pvc postgres-data \
     --snapshots postgres-snapshot-1,postgres-snapshot-2
   ```

## 🔧 Tools

### Backup Tool (`cbt-backup`)

**Status**: 🏗️ In Development

A Go-based tool that:
- Creates Kubernetes VolumeSnapshots
- Connects to CSI SnapshotMetadata gRPC service
- Calls `GetMetadataDelta()` to identify changed blocks
- Reads block data from PVC
- Uploads only changed blocks to MinIO
- Stores metadata for snapshot chain

**Usage**:
```bash
cd tools/cbt-backup
go build -o cbt-backup ./cmd

# Full backup
./cbt-backup create --pvc my-pvc --snapshot snap-1

# Incremental backup
./cbt-backup create --pvc my-pvc --snapshot snap-2 --base-snapshot snap-1

# List backups
./cbt-backup list
```

### Restore Tool (`cbt-restore`)

**Status**: 📝 Planned

A Go-based tool that:
- Lists available snapshots from MinIO
- Downloads snapshot metadata
- Creates new PVC (block mode)
- Reconstructs volume by applying blocks in order
- Verifies data integrity with checksums

## 📊 Verifying CBT is Working

Check that snapshot metadata service is available:

```bash
# Check if SnapshotMetadataService CRD exists
kubectl get crd snapshotmetadataservices.cbt.storage.k8s.io

# Check if service is registered
kubectl get snapshotmetadataservices -A

# Check CSI driver logs for metadata service
kubectl logs -n default -l app=csi-hostpathplugin -c hostpath | grep -i metadata
```

## 📁 Project Structure

```
k8s-cbt-s3mover-demo/
├── README.md                      # This file
├── PLAN.md                        # Detailed implementation plan
├── cluster/
│   └── kind-config.yaml           # Kind cluster configuration
├── manifests/
│   ├── namespace.yaml
│   ├── minio/                     # MinIO S3 storage
│   ├── csi-driver/                # CSI driver with CBT
│   └── workload/                  # PostgreSQL workload
├── tools/
│   ├── cbt-backup/                # Backup tool (Go)
│   └── cbt-restore/               # Restore tool (Go)
├── scripts/                       # Automation scripts
└── docs/                          # Additional documentation
```

## 🎓 How CBT Works

### Traditional Backup (without CBT)
```
Snapshot 1: Upload 1GB (full)
Snapshot 2: Upload 1.1GB (full, includes 100MB new data)
Snapshot 3: Upload 1.3GB (full, includes 200MB more data)
Total: 3.4GB uploaded
```

### With Changed Block Tracking
```
Snapshot 1: Upload 1GB (full)
Snapshot 2: GetMetadataDelta() → Upload 100MB (only changes)
Snapshot 3: GetMetadataDelta() → Upload 200MB (only changes)
Total: 1.3GB uploaded (saved 2.1GB!)
```

### CBT APIs

```go
// Get all allocated blocks in a snapshot
GetMetadataAllocated(snapshotID) → []BlockMetadata

// Get changed blocks between two snapshots
GetMetadataDelta(baseSnapshotID, targetSnapshotID) → []BlockMetadata

// BlockMetadata contains:
type BlockMetadata struct {
    ByteOffset int64  // Where the block starts
    SizeBytes  int64  // Size of the block
}
```

## ⚠️ Known Limitations

### Block Device Support in Containers

**Issue**: Block device provisioning fails in containerized environments (Codespaces, Docker Desktop, etc.)

**Symptom**: PVCs with `volumeMode: Block` remain in `Pending` state with errors:
```
failed to attach device: makeLoopDevice failed: losetup -f failed: exit status 1
```

**Root Cause**: The CSI hostpath driver requires privileged access to create loop devices using `losetup`. In containerized environments (Docker, Codespaces), the container has a static copy of the host's `/dev` directory, so loop devices created after container startup are not visible, causing `losetup -f` to fail.

**Workaround**:
1. **Use a remote cluster** (GKE, EKS, AKS, or bare metal) - see [Quick Start Option B](#option-b-remote-cluster-recommended-for-block-volumes)
2. Run on VM-based local clusters (e.g., Kind on a Linux VM with host access)
3. Use filesystem volumes (`volumeMode: Filesystem`) for testing (though CBT requires block mode in production)
4. Pre-create loop devices on the host before starting the container (requires host access)

**Status**: This is a fundamental limitation of running block device workloads in nested containerized environments. While specific test infrastructure issues have been resolved, the underlying constraint remains for development environments like Codespaces.

**Related Issues** (Historical):
- [kubernetes-sigs/kind#1248](https://github.com/kubernetes-sigs/kind/issues/1248) - Number of loop devices is fixed and unpredictable (closed - resolved for test infrastructure)
- [kubernetes-csi/csi-driver-host-path#119](https://github.com/kubernetes-csi/csi-driver-host-path/issues/119) - Block tests flaky in containerized environments (closed)

### CBT API Availability

**Status**: Changed Block Tracking API was introduced as an **alpha feature in Kubernetes 1.33**.

**Requirements**:
- Kubernetes 1.33 or later
- CSI driver that implements the SnapshotMetadata gRPC service
- Block volumes (not filesystem volumes)
- No feature gates required (alpha APIs available by default in 1.33+)

**Current Driver Support**:
- ✅ **CSI hostpath driver**: Implements CBT SnapshotMetadata service
- ❌ **AWS EBS CSI driver**: Does not yet implement CBT (uses native EBS snapshots)
- ✅ **Ceph CSI**: Full CBT implementation

**Resources**:
- [Kubernetes Blog: CBT Alpha Announcement](https://kubernetes.io/blog/2025/09/25/csi-changed-block-tracking/)
- [KEP-3314: CSI Changed Block Tracking](https://github.com/kubernetes/enhancements/blob/master/keps/sig-storage/3314-csi-changed-block-tracking/README.md)
- [External Snapshot Metadata Sidecar](https://github.com/kubernetes-csi/external-snapshot-metadata)

### GitHub Actions CI

**Status**: CI workflow runs successfully with the following caveats:
- Block device tests are skipped due to container limitations (Kind cluster mode)
- Full CBT metadata API tests are skipped pending CRD availability
- Basic snapshot and MinIO integration tests pass

**Remote Cluster Support**: You can use a real Kubernetes cluster for full testing:

#### Option 1: Bring Your Own Cluster (BYOC)

1. **Encode your kubeconfig**:
   ```bash
   # MacOS/Linux
   cat ~/.kube/config | base64 | pbcopy

   # Or save to file
   cat ~/.kube/config | base64 > kubeconfig-b64.txt
   ```

2. **Add GitHub Secret**:
   - Go to your repository Settings → Secrets and variables → Actions
   - Create a new secret named `KUBECONFIG`
   - Paste the base64-encoded kubeconfig content

3. **Run the workflow** - it automatically detects and uses your cluster

#### Option 2: Automated EKS Cluster (AWS)

Use the dedicated AWS workflow to automatically create and test on EKS:

1. **Add AWS Secrets**:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_REGION` (optional, defaults to us-east-1)

2. **Run the workflow**:
   - Go to Actions → "K8s CBT Demo on AWS EKS"
   - Click "Run workflow"
   - Optionally specify cluster name
   - Choose whether to keep cluster after tests

3. **Benefits**:
   - ✅ Fully automated cluster creation and deletion
   - ✅ Real block device support (no container limitations)
   - ✅ CSI hostpath driver with CBT support (Kubernetes 1.33+)
   - ✅ Automatic cleanup (unless keep_cluster=true)
   - ⚠️ Incurs AWS charges (~$0.10/hour for t3.medium instances)

**Note**: Uses CSI hostpath driver with CBT support. AWS EBS CSI driver doesn't implement the CBT SnapshotMetadata API yet.

**Common Benefits of Remote Cluster Testing**:
- ✅ Full block device support (no losetup limitations)
- ✅ Real CSI driver testing with block volumes
- ✅ Tests run on actual infrastructure
- ⚠️ Ensure the cluster has sufficient resources and CSI support

See workflows:
- [demo.yaml](.github/workflows/demo.yaml) - Local Kind + BYOC support
- [demo-aws.yaml](.github/workflows/demo-aws.yaml) - Automated EKS testing

## 🐛 Troubleshooting

### CSI Driver not starting
```bash
kubectl logs -n default -l app=csi-hostpathplugin
# Check for errors in CSI driver logs
```

### SnapshotMetadataService not found
```bash
# Ensure driver was deployed with SNAPSHOT_METADATA_TESTS=true
kubectl get pods -n default -l app=csi-hostpathplugin -o yaml | grep -i metadata
```

### Block device issues
```bash
# Check if PVC is using volumeMode: Block
kubectl get pvc -n cbt-demo -o yaml | grep volumeMode

# Check for losetup errors in CSI driver logs
kubectl describe pvc <pvc-name> -n cbt-demo
```

### MinIO connection issues
```bash
# Test MinIO connectivity
kubectl run -it --rm debug --image=minio/mc --restart=Never -- \
  mc alias set myminio http://minio.cbt-demo.svc.cluster.local:9000 \
  minioadmin minioadmin123
```

## 🧹 Cleanup

### Local Kind Cluster

```bash
# Delete everything (Kind cluster and temp directories)
./scripts/cleanup.sh
```

This removes:
- Kind cluster
- Temporary directories
- Downloaded CSI driver repository

### Remote Cluster

```bash
# Clean up demo resources from remote cluster
./scripts/cleanup-remote-cluster.sh
```

This removes:
- `cbt-demo` namespace and all resources
- VolumeSnapshots and VolumeSnapshotContents
- Does NOT remove: CSI driver, CRDs, or storage classes (manual cleanup if needed)

## 📚 References

- [Kubernetes CBT KEP-3314](https://github.com/kubernetes/enhancements/blob/master/keps/sig-storage/3314-csi-changed-block-tracking/README.md)
- [CSI Spec - SnapshotMetadata](https://github.com/container-storage-interface/spec/blob/master/spec.md)
- [CSI Hostpath Driver](https://github.com/kubernetes-csi/csi-driver-host-path)
- [External Snapshot Metadata](https://github.com/kubernetes-csi/external-snapshot-metadata)
- [Kubernetes Volume Snapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/)

## 🔮 Future Enhancements

- [ ] Implement backup tool with real CBT API calls
- [ ] Implement restore tool
- [ ] Add data compression
- [ ] Add encryption at rest
- [ ] Parallel block uploads
- [ ] Deduplication across snapshots
- [ ] GitHub Actions CI/CD workflow
- [ ] Support for multiple volumes
- [ ] Integration with Velero
- [ ] Prometheus metrics

## 📝 License

MIT License - See LICENSE file for details

## 🤝 Contributing

Contributions welcome! This is a demo project to showcase Kubernetes CBT capabilities.

## 📧 Contact

For questions or issues, please open a GitHub issue.

---

**Status**: 🏗️ Work in Progress - Core infrastructure complete, backup/restore tools in development
