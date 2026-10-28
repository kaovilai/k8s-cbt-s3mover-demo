# Kubernetes Changed Block Tracking (CBT) Demo

A self-contained demonstration of Kubernetes Changed Block Tracking (CBT) using CSI hostpath driver with incremental backup to MinIO S3 storage and disaster recovery.

## 🎯 Overview

This demo showcases:
- ✅ **Real CBT API** using CSI SnapshotMetadata service (`GetMetadataDelta`, `GetMetadataAllocated`)
- ✅ **Block-mode volumes** required for CBT
- ✅ **Incremental backups** - only changed blocks are uploaded
- ✅ **S3-compatible storage** using MinIO
- ✅ **Disaster recovery** - restore from incremental snapshots
- ✅ **Local testing** with Minikube or cloud clusters

## Prerequisites

- [Minikube](https://minikube.sigs.k8s.io/) or a cloud Kubernetes cluster
- [kubectl](https://kubernetes.io/docs/tasks/tools/) v1.28.0 or later
- [Go](https://golang.org/) 1.26 or later (for building tools)
- ~10GB free disk space

**CBT Support**: Changed Block Tracking API was introduced as an alpha feature in **Kubernetes 1.33** and graduated to **beta in Kubernetes 1.36** (KEP-3314). For full CBT functionality, use Kubernetes 1.33 or later; the demo scripts default to Kubernetes 1.36.

```bash
# Verify prerequisites
minikube version         # v1.39.0 or later recommended (Kubernetes 1.36 support)
kubectl version --client # v1.28.0 or later
go version               # 1.26 or later (optional, for building tools)
df -h /tmp               # Need ~10GB free
```

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────┐
│                Kubernetes Cluster                        │
│                                                           │
│  ┌──────────────┐  ┌───────────────┐  ┌──────────────┐ │
│  │Block Writer  │  │   MinIO S3    │  │  CSI Driver  │ │
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

⚠️ **Note**: Kind is not supported for this demo due to limited block device support, which is required for CBT functionality. Use Minikube for local testing or a cloud Kubernetes cluster for production validation.

### Option A: Local Setup with Minikube (macOS/Linux)

```bash
# Run with minikube - Full block device support
./scripts/run-local-minikube.sh
```

**Features**:
- ✅ Full block device support (VM-based)
- ✅ Testing actual CBT metadata
- ✅ Same setup as upstream CI tests

**Requirements**: `minikube`, `kubectl`, and a **VM-based driver**

**Install prerequisites** (macOS):
```bash
brew install minikube kubectl

# For macOS: Choose a VM-based driver (block volume support required)
# Option 1: vfkit (recommended - native Apple virtualization, requires macOS 13+)
#   Automatically used by minikube 1.36+, no additional installation needed

# Option 2: Docker Desktop (well-tested alternative)
#   Download from: https://www.docker.com/products/docker-desktop/

# Option 3: QEMU (open source alternative)
brew install qemu
```

**macOS Driver Compatibility** (Tested on macOS 26.1, Minikube 1.37.0):

- ✅ **vfkit** - Native Apple virtualization (preferred for Minikube 1.36+)
- ✅ **Docker Desktop** - VM-based, well-tested
- ✅ **QEMU** - Open source VM solution
- ❌ **Podman** - Does NOT support block volumes (minikube-hostpath limitation)

**What the script does**:
1. ✅ Check prerequisites
2. ✅ Create Kubernetes cluster
3. ✅ Deploy MinIO S3 storage
4. ✅ Deploy CSI driver with CBT support
5. ✅ Deploy block-writer workload with raw block device access
6. ✅ Create snapshots demonstrating CBT workflow

#### Manual Step-by-Step Setup

If you prefer to run each step manually:

```bash
# 1. Setup the Cluster
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
- Deploy block-writer workload with raw block device access
- Validate the setup

#### Manual Remote Cluster Setup

If you prefer step-by-step control:

```bash
# 1. Verify cluster
./scripts/00-setup-remote-cluster.sh

# 2. Continue with standard deployment steps below
```

```bash
# 2. Deploy hostpath CSI driver with Changed Block Tracking support
./scripts/01-deploy-csi-driver.sh
```

This deploys (following upstream external-snapshot-metadata integration test pattern):
- Snapshot controller with VolumeSnapshot CRDs
- TLS certificates for secure gRPC communication
- CSI hostpath driver with snapshot metadata sidecar
- SnapshotMetadataService CRD and CR
- ClusterIP service for snapshot metadata (port 6443)
- StorageClass and VolumeSnapshotClass

**Key Features:**
- ✅ TLS-secured gRPC endpoint (`csi-snapshot-metadata.default:6443`)
- ✅ Uses upstream release images (`registry.k8s.io/sig-storage`: hostpathplugin v1.18.0, csi-snapshot-metadata v1.1.0)
- ✅ Matches official external-snapshot-metadata integration tests

```bash
# 3. Deploy MinIO for backup storage
./scripts/02-deploy-minio.sh
```

Access MinIO:
- **API**: http://localhost:30900
- **Console**: http://localhost:30901
- **Credentials**: minioadmin / minioadmin123

```bash
# 4. Deploy block-writer with block-mode PVC
./scripts/03-deploy-workload.sh

# 5. Run the demo workflow
./scripts/04-run-demo.sh
```

This creates:
- Block-writer pod with 1Gi block PVC for raw device access
- Writes data directly to raw block device (no filesystem layer)

## Demo Workflow

### Validate Setup

```bash
./scripts/validate-cbt.sh      # Validates CBT configuration
./scripts/backup-status.sh     # Shows backup status and S3 usage
./scripts/integrity-check.sh   # Verifies data and backup integrity
```

### Run Complete Demo

```bash
./scripts/04-run-demo.sh
```

### Inspect Block Device

```bash
# Connect to block-writer pod
kubectl exec -it -n cbt-demo block-writer -- sh

# Inside the pod:
blockdev --getsize64 /dev/xvda
dd if=/dev/xvda bs=4K count=1 skip=1 2>/dev/null | od -An -tx1 | head -5
exit
```

### Monitor Resources

```bash
kubectl get pods -n cbt-demo --watch
kubectl get all -n cbt-demo
kubectl get pvc,pv -n cbt-demo
kubectl get volumesnapshot,volumesnapshotcontent -n cbt-demo
```

### Manual Steps

1. **Create first snapshot** (full backup)
   ```bash
   kubectl create -f - <<EOF
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
   ```

2. **Backup snapshot 1**
   ```bash
   # This creates snapshot and uploads metadata (CBT APIs functional)
   cd tools/cbt-backup
   go build -o cbt-backup ./cmd
   ./cbt-backup create --pvc block-writer-data \
     --snapshot block-snapshot-1
   ```

3. **Write more data to block device**
   ```bash
   # Write random data at different block offsets (incremental changes)
   kubectl exec -n cbt-demo block-writer -- dd if=/dev/urandom of=/dev/xvda bs=4K count=1 seek=15 conv=notrunc
   kubectl exec -n cbt-demo block-writer -- dd if=/dev/urandom of=/dev/xvda bs=4K count=1 seek=17 conv=notrunc
   kubectl exec -n cbt-demo block-writer -- dd if=/dev/urandom of=/dev/xvda bs=4K count=1 seek=19 conv=notrunc
   ```

4. **Create second snapshot** (incremental)
   ```bash
   kubectl create -f - <<EOF
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

5. **Incremental backup** (only changed blocks)
   ```bash
   # This uses GetMetadataDelta() to find changed blocks
   cd tools/cbt-backup
   ./cbt-backup create --pvc block-writer-data \
     --snapshot block-snapshot-2 \
     --base-snapshot block-snapshot-1
   ```

6. **Simulate disaster**
   ```bash
   kubectl delete pod block-writer -n cbt-demo
   kubectl delete pvc block-writer-data -n cbt-demo
   ```

7. **Restore from backups**
   ```bash
   cd tools/cbt-restore
   go build -o cbt-restore ./cmd

   # Plan a restore (dry-run)
   ./cbt-restore plan --snapshot block-snapshot-2

   # Restore to a block device
   ./cbt-restore restore --snapshot block-snapshot-2 --device /dev/xvda

   # In-place restore: zero the volume extent first so unallocated blocks
   # do not keep stale data from the previous use of the device
   ./cbt-restore restore --snapshot block-snapshot-2 --device /dev/xvda --zero-device
   ```

## 🔧 Tools

### Backup Tool (`cbt-backup`)

**Status**: ✅ 100% Complete

A Go-based tool that:
- ✅ Creates Kubernetes VolumeSnapshots
- ✅ Connects to CSI SnapshotMetadata gRPC service
- ✅ Calls `GetMetadataAllocated()` and `GetMetadataDelta()` to identify blocks
- ✅ Stores complete metadata for snapshot chain in S3
- ✅ Uploads block data to S3

**Usage**:
```bash
cd tools/cbt-backup
go build -o cbt-backup ./cmd

# Full backup
./cbt-backup create --pvc my-pvc --snapshot snap-1

# Incremental backup (uses CSI snapshot handle internally)
./cbt-backup create --pvc my-pvc --snapshot snap-2 --base-snapshot snap-1

# List backups
./cbt-backup list
```

**Implementation Note**: This tool uses the CSI snapshot handle
(from `VolumeSnapshotContent.Status.SnapshotHandle`) for incremental backups, following
the API changes in kubernetes-csi/external-snapshot-metadata PR #180. This allows computing
deltas even after the base VolumeSnapshot object has been deleted, enabling more flexible
snapshot retention policies.

### Restore Tool (`cbt-restore`)

**Status**: ✅ 100% Complete

A Go-based tool that:
- ✅ Lists available snapshots from MinIO
- ✅ Downloads snapshot metadata and resolves snapshot chains
- ✅ Applies blocks in order to reconstruct the volume
- ✅ Verifies data integrity with checksums

**Usage**:
```bash
cd tools/cbt-restore

# Plan restore (shows what would be done)
./cbt-restore plan --snapshot block-snapshot-2

# Restore to a block device
./cbt-restore restore --snapshot block-snapshot-2 --device /dev/xvda

# List available backups
./cbt-restore list
```

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
├── manifests/
│   ├── namespace.yaml
│   ├── minio/                     # MinIO S3 storage
│   ├── csi-driver/                # CSI driver with CBT
│   └── workload/                  # Block-writer workload (raw block device)
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
Snapshot 1: GetMetadataAllocated() → Upload 500MB (only allocated blocks, not empty space)
Snapshot 2: GetMetadataDelta() → Upload 100MB (only changes)
Snapshot 3: GetMetadataDelta() → Upload 200MB (only changes)
Total: 800MB uploaded (saved 2.6GB!)
```

### CBT APIs

```go
// Get all allocated blocks in a snapshot
// Used for initial full backups - identifies data ranges that were targets of write operations
// This avoids backing up empty/unallocated space, significantly reducing initial backup size
// Example: 10GB volume with only 2GB written → backup only 2GB
GetMetadataAllocated(snapshotID) → []BlockMetadata

// Get changed blocks between two snapshots
// Used for incremental backups - identifies only the blocks that changed between snapshots
// NOTE: As of kubernetes-csi/external-snapshot-metadata PR #180 (merged Oct 2025):
//   - baseSnapshotID is now the CSI snapshot handle (not the VolumeSnapshot name)
//   - Get the CSI handle from VolumeSnapshotContent.Status.SnapshotHandle
//   - This allows computing deltas even after the base snapshot is deleted
GetMetadataDelta(baseSnapshotID, targetSnapshotID) → []BlockMetadata

// BlockMetadata contains:
type BlockMetadata struct {
    ByteOffset int64  // Where the block starts
    SizeBytes  int64  // Size of the block
}
```

**API Change History:**
- **October 2025**: PR [kubernetes-csi/external-snapshot-metadata#180](https://github.com/kubernetes-csi/external-snapshot-metadata/pull/180) changed `GetMetadataDelta` to use CSI snapshot handles instead of snapshot names for the base snapshot parameter
  - Field renamed: `base_snapshot_name` → `base_snapshot_id`
  - Client tools now support both `-p <name>` and `-P <csi-handle>` flags
  - The CSI handle approach avoids depending on the VolumeSnapshot object; the driver may still require the snapshot itself (Case 2, for example Ceph RBD)

### Why Direct Block Device Access Is Required (Not Just `volumeMode: Block`)

**Critical Understanding**: CBT operates at the **raw block device layer**, not the filesystem layer. This creates a fundamental visibility barrier when applications write through a filesystem - **even when using `volumeMode: Block` PVCs**.

**Important Clarification**:
- `volumeMode: Block` only controls how Kubernetes **exposes** the volume to the pod (as `/dev/xvda` instead of a mounted filesystem path like `/var/lib/postgresql/data`)
- It does NOT prevent applications from **creating their own filesystem** on top of that block device
- PostgreSQL, MySQL, and most databases will format the block device with ext4/xfs and write through that filesystem
- **CBT requires the application to write directly to the raw block device**, bypassing all filesystem layers

#### Filesystem Writes Remain Invisible Due to Multiple Abstraction Layers

When applications write data through a filesystem (like ext4, xfs, or NTFS), those writes traverse multiple kernel abstraction layers before reaching the block device - **regardless of whether the PVC is `volumeMode: Block` or `volumeMode: Filesystem`**:

**1. Page Cache and Buffer Cache: The Primary Invisibility Barrier**

The Linux kernel's page cache and buffer cache create the primary invisibility barrier between filesystem writes and block device I/O:

```
Application (PostgreSQL) → Filesystem (ext4) → Page Cache → [INVISIBLE TO CBT] → Block Device
                                                    ↓
                                            Dirty Pages (5-30 seconds)
                                                    ↓
                                            Background Flush (bdflush)
                                                    ↓
                                            [VISIBLE TO CBT] → Block Device I/O
```

**Example: PostgreSQL Writing Through ext4**

When PostgreSQL writes data through ext4:

1. **Initial Write** (0ms): PostgreSQL executes `write()` syscall
   - Data lands in kernel page cache as "dirty" pages
   - ext4 filesystem metadata updated in memory
   - **PostgreSQL receives success immediately**
   - **CBT sees**: Nothing - no block device I/O has occurred

2. **Dirty Page Window** (5-30 seconds): Kernel memory only
   - Dirty pages remain in RAM, marked for eventual flush
   - Kernel's background flush daemons (`bdflush`, `pdflush`) wait
   - Default flush intervals: 5-30 seconds (tunable via `/proc/sys/vm/dirty_*`)
   - **CBT sees**: Still nothing - data exists only in page cache

3. **Background Flush** (5-30s later): Block device I/O begins
   - Kernel flushes dirty pages to block device
   - ext4 journal commits and data blocks written
   - **CBT sees**: Block writes - but they're scattered across filesystem structures
   - **Problem**: CBT sees filesystem metadata blocks, journal blocks, and data blocks mixed together

4. **Snapshot Captured**: What CBT observes
   - Most blocks contain zeros (unallocated filesystem space)
   - Some blocks contain ext4 superblocks, inodes, directory entries
   - Some blocks contain actual data - but heavily fragmented
   - **Result**: Empty `[]` metadata array because PostgreSQL data is "hidden" inside filesystem structures

**Visual Representation of Data Flow:**

```
┌────────────────────────────────────────────────────────────────┐
│ Application Layer (PostgreSQL)                                 │
│   write(fd, data, size) → Returns SUCCESS immediately          │
└────────────────────────────────────────────────────────────────┘
                            ↓
┌────────────────────────────────────────────────────────────────┐
│ Filesystem Layer (ext4)                                        │
│   - Updates inode metadata                                     │
│   - Marks pages as dirty                                       │
│   - Journals the change                                        │
└────────────────────────────────────────────────────────────────┘
                            ↓
┌────────────────────────────────────────────────────────────────┐
│ Page Cache Layer (INVISIBLE TO CBT)                            │
│   - Dirty pages: 5-30 second window                            │
│   - No block device I/O yet                                    │
│   ❌ CBT CANNOT SEE THIS LAYER                                 │
└────────────────────────────────────────────────────────────────┘
                            ↓ (after flush delay)
┌────────────────────────────────────────────────────────────────┐
│ Block Device Layer (VISIBLE TO CBT)                            │
│   - Actual disk writes occur                                   │
│   - Scattered across filesystem structures                     │
│   ✅ CBT SEES THIS - but data is fragmented/mixed              │
└────────────────────────────────────────────────────────────────┘
```

**Real-World Impact: Our Actual Experimental Results**

**Experiment 1: PostgreSQL + ext4 (Initial Attempt - FAILED)**

We initially tested with PostgreSQL StatefulSet using `volumeMode: Block` PVC (see [commit 94c5aaaa](https://github.com/kaovilai/k8s-cbt-s3mover-demo/commit/94c5aaaaff6f43af114427d3ba637ce4ed794fe4)):

```bash
# PostgreSQL received /dev/xvda (volumeMode: Block)
# PostgreSQL formatted it with ext4 and wrote data through the filesystem
kubectl exec postgres-0 -- psql -U postgres -c "INSERT INTO demo_data ..."

# Created snapshot
kubectl create -f postgres-snapshot-1.yaml

# Ran snapshot-metadata-lister
kubectl exec csi-client -- /tools/snapshot-metadata-lister \
  -s postgres-snapshot-1 -n cbt-demo
```

**Result**: **NO OUTPUT** - snapshot-metadata-lister returned empty array `[]`

**Root Cause Analysis (from commit message)**:
> "PostgreSQL creates an ext4 filesystem on the block device and writes data to logical filesystem blocks. However, CBT reads raw device blocks which remain mostly zeros despite the filesystem having data. This is why snapshot-metadata-lister produces no output."

**Why PostgreSQL Failed (Even with `volumeMode: Block`):**
- PostgreSQL received `/dev/xvda` as a raw block device from Kubernetes
- PostgreSQL's entrypoint/initialization **formatted the device with ext4**
- PostgreSQL wrote data through the ext4 filesystem layer
- Page cache barrier: data existed in kernel memory for 5-30 seconds
- Filesystem fragmentation: data scattered across superblocks, inodes, journal, data blocks
- **CBT saw raw blocks**: mostly zeros and ext4 metadata structures
- **Database data was "hidden"** inside filesystem abstractions

**Experiment 2: Raw Block Device Writes (EC2 Test - SUCCESS)**

After discovering the PostgreSQL failure, we tested on EC2 with direct block device writes:

```bash
# Created test pod with volumeMode: Block, but NO filesystem formatting
# Pod: busybox with /dev/xvdb exposed as raw device
kubectl apply -f cbt-test-volume.yaml

# Wrote 100 blocks of random data directly to raw device
kubectl exec block-writer -- dd if=/dev/urandom of=/dev/xvdb bs=4096 count=100 seek=0

# Created first snapshot
kubectl create -f cbt-test-snap-1.yaml

# Checked raw snapshot file - data is visible!
kubectl exec csi-hostpathplugin-0 -- \
  dd if=/csi-data-dir/78580429-b3c1-11f0-ae5a-9ede7a3ad1de.snap bs=4096 count=1 | od -An -tx1
# Output: f2 5b 6c 18 3d e0 36 73 ... (random data visible!)

# Ran GetMetadataAllocated
kubectl exec csi-client -- /tools/snapshot-metadata-lister \
  -s cbt-test-snap-1 -n cbt-demo -o json
```

**Result**: **SUCCESS!** GetMetadataAllocated returned **100 blocks** ✅

```json
{
  "block_metadata_type": 1,
  "volume_capacity_bytes": 104857600,
  "block_metadata": [
    {"byte_offset": 0, "size_bytes": 4096},
    {"byte_offset": 4096, "size_bytes": 4096},
    ... (100 blocks total)
  ]
}
```

**Incremental Test (GetMetadataDelta)**:

```bash
# Wrote additional changes:
# - 30 modified blocks at offset 20 (blocks 20-49): overwritten with zeros
# - 50 new blocks at offset 200 (blocks 200-249): new random data

# Created second snapshot
kubectl create -f cbt-test-snap-2.yaml

# Ran GetMetadataDelta
kubectl exec csi-client -- /tools/snapshot-metadata-lister \
  -p cbt-test-snap-1 -s cbt-test-snap-2 -n cbt-demo -o json
```

**Result**: **SUCCESS!** GetMetadataDelta returned **80 changed blocks** ✅ (30 modified + 50 new)

**Why Raw Block Writes Worked:**
- `dd` wrote directly to `/dev/xvdb` (raw block device)
- **No filesystem layer** - data went straight to blocks
- **No page cache delay** - data visible immediately after sync
- **CBT saw exactly what was written** - 100 blocks of random data, then 80 changed blocks

**Key Takeaways:**

1. **`volumeMode: Block` is necessary but NOT sufficient** - it only controls how Kubernetes exposes the device to the pod
2. **Applications must write directly to raw block devices** - if the application creates a filesystem (like PostgreSQL does), CBT won't see the data
3. **Filesystem writes are invisible to CBT** because data exists in page cache for 5-30 seconds before block I/O, and then is scattered across filesystem structures
4. **Production workloads** using CBT must either:
   - Use applications that write directly to raw block devices (databases with DirectIO like Cassandra, ScyllaDB)
   - Implement custom backup agents that trigger filesystem sync before snapshots
   - Accept limitations and understand timing/visibility constraints

**Experimental Evidence**: We proved this by testing both approaches - PostgreSQL with ext4 returned empty results, while direct `dd` writes to raw blocks successfully produced CBT metadata.

## ⚠️ Known Limitations

### Block Device Support

**Requirements**: This demo reads snapshots through a **block-mode PVC**. The
source volume may be Filesystem or Block; `scripts/demo-fs-to-block.sh`
demonstrates the Filesystem-to-Block path.

**Supported Environments**:
- ✅ **Minikube**: Full support (VM-based, used by upstream CI)
- ✅ **EKS/GKE/AKS**: Full support (production environments)

**Note**: Kind is not supported due to container-based limitations with loop device creation, which is required for block PVCs with the CSI hostpath driver.

### OpenShift Compatibility

**Status**: ✅ **Fully supported** with automatic configuration

The demo works seamlessly on OpenShift 4.20+ with automatic PodSecurity policy configuration. OpenShift namespaces enforce `restricted` PodSecurity policies by default, which would normally block the privileged pods required for raw block device access.

**Automatic Configuration**: The deployment script ([scripts/02-deploy-minio.sh](scripts/02-deploy-minio.sh)) automatically detects OpenShift and configures the namespace:

1. **Detects OpenShift** by checking for SecurityContextConstraints API
2. **Labels namespace** with `pod-security.kubernetes.io/enforce=privileged`
3. **Grants privileged SCC** to the default service account in `cbt-demo` namespace

**Manual Configuration** (if needed):
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

**Tested On**:
- ✅ OpenShift 4.21 (Kubernetes 1.34.1) on AWS ARM64
- ✅ OpenShift 4.20+ with vanilla Kubernetes CSI drivers

**Known Issues on ARM64 OpenShift**:
- CSI snapshot metadata container readiness probe may fail (functional despite warning)
- Pod shows 8/9 containers ready (expected on ARM64, CBT functionality works correctly)

### CBT API Availability

**Status**: Changed Block Tracking API was introduced as an **alpha feature in Kubernetes 1.33** and graduated to **beta in Kubernetes 1.36** (`SnapshotMetadataService` is `cbt.storage.k8s.io/v1beta1`; external-snapshot-metadata v1.x is beta).

**Requirements**:
- Kubernetes 1.33 or later
- CSI driver that implements the SnapshotMetadata gRPC service
- A block device the backup tool can read; this demo restores snapshots into
  block-mode PVCs, and the source volume may be Filesystem or Block
- No feature gates required (APIs available by default in 1.33+)

**Current Driver Support**:
- ✅ **CSI hostpath driver**: Implements CBT SnapshotMetadata service
- ❌ **AWS EBS CSI driver**: Does not yet implement CBT (uses native EBS snapshots)
- ✅ **Ceph CSI (RBD)**: Implements CBT snapshot metadata. `GetMetadataDelta` requires the base snapshot to still exist (see the Velero status section below)

**Resources**:
- [Kubernetes Blog: CBT Alpha Announcement (1.33)](https://kubernetes.io/blog/2025/09/25/csi-changed-block-tracking/)
- [KEP-3314: CSI Changed Block Tracking](https://github.com/kubernetes/enhancements/blob/master/keps/sig-storage/3314-csi-changed-block-tracking/README.md)
- [External Snapshot Metadata Sidecar](https://github.com/kubernetes-csi/external-snapshot-metadata)

### Velero CBT / Block Data Mover Status (2026-10-27)

This section records the status agreed at the Velero community meeting on 2026-10-27. It
describes Velero, not this demo; the demo keeps its base snapshot for the whole run.

**Short version.** Case 1 = storage can work out changes without the old snapshot; Case 2
= storage needs the old snapshot kept (for example, Ceph RBD). Velero 1.19.0 supports
Case 1 only. On Case 2 it falls back to a full copy. A 1.19.x patch is being designed; it
is targeted for OADP 1.7 (OpenShift's backup product, built on Velero), not committed.

**Terms used below.** CBT (Changed Block Tracking) means the storage tells Velero which
blocks changed. A base snapshot is the earlier snapshot the change is measured from. A
delta is the set of changed blocks. The block data mover is the Velero component that
copies block data.

**Case 1 vs Case 2.**
- Case 1: storage computes the delta without keeping the base snapshot (for example,
  vSphere). Supported in 1.19.0.
- Case 2: storage needs the base snapshot kept to compute the delta (for example, Ceph
  RBD). Not supported in 1.19.0.

AWS EBS is not applicable because its CSI driver does not implement the SnapshotMetadata
service (the storage driver's changed-block API).

**Snapshot retention: 1.19.0 always deletes.** 1.19.0 behaves like 1.18 (the previous
release). Velero ignores the VolumeSnapshotClass `deletionPolicy` (the class setting for
what happens to the storage snapshot when the cluster object is deleted). Velero always
marks the backup's VolumeSnapshotContent (VSC, the cluster object that points at the
storage snapshot) as `Delete`. After each backup, Velero deletes the backup's
VolumeSnapshot; because the VSC says `Delete`, the storage erases the snapshot. Deleting a
backup does the same. The change that would copy the class policy
([#10307](https://github.com/velero-io/velero/pull/10307)) was merged to Velero's
development branch (main) but was not in 1.19.0; it is being undone on main so the code
matches 1.19.0's behavior. The fix that keeps the base-snapshot lookup working
(the step that finds the previous snapshot)
([#10294](https://github.com/velero-io/velero/pull/10294)) stays in place.

**Consequence for Ceph RBD on 1.19.0.** The base snapshot is the previous backup's
VolumeSnapshot, so the retention rule above deletes it. Ceph then cannot compute the
delta, so `GetMetadataDelta` fails (ceph-csi returns `no snap source in omap`) and Velero
copies the whole volume instead (`fallbackFull`). Backup data is still correct; the
incremental saving is lost. The file system data mover never retains snapshots.

**Case 2 design (proposal, not settled).** Tracked in
[#10743](https://github.com/velero-io/velero/issues/10743), with the design in
[#10744](https://github.com/velero-io/velero/issues/10744). Case 2 support was not ready
for 1.19.0, so it is pushed to a 1.19.x patch targeted at OADP 1.7. It is delayed, not
dropped, and not committed. The current proposal:

Decision order (first match wins):

1. the volume policy parameter, if an admin set it (a Velero setting; working name
   `retainBaseSnapshot`). Use its value (keep or do not keep) and stop; ignore the driver
   flag.
2. the storage driver says "I need the old snapshot" with a flag on its
   SnapshotMetadataService (`requireBaseSnapshotForDelta`), and Velero keeps the base.
   - Catch: Velero cannot read this flag until
     [#10722](https://github.com/velero-io/velero/issues/10722) lands (a 1.20 candidate),
     so 1.19.x may have only the volume policy.
3. none applies: do not keep it (it is deleted, as today).

Other rules in the proposal:

- Same as 1.19.0: the VolumeSnapshotClass `deletionPolicy` plays no part. Velero's own
  keep/delete order (steps 1-3) decides.
- A volume chain (the series of snapshots of one volume) keeps only the newest snapshot.
  That snapshot is the base for the next backup; once that backup succeeds, Velero
  deletes the older one automatically.
- When you delete a backup, Velero also deletes the snapshot it retained.

If neither the volume policy nor the driver flag applies, the old snapshot is still
deleted after each backup, as in 1.19.0, so Ceph still does a full copy.

**Validated on Ceph RBD with pre-release builds that kept the base snapshot:**

| Check | Result |
|-------|--------|
| True incremental on OpenShift (OCP) with Rook and with ODF (two ways to run Ceph on OpenShift) | Only changed blocks were sent: 150,994,944 bytes (144 MiB). No full-size number was recorded, so the saving cannot be quantified |
| Restore integrity | Whole-device SHA-256 matched at every restore point |
| KubeVirt | VM booted; multi-disk VM, including hotplug, matched checksums |
| In-place incremental restore (`existingVolumeDataPolicy: incremental`; restore onto the existing volume instead of a new one) | 30 GiB volume: 270,532,608 bytes transferred in 22 s |
| Negative test | Setup: the base snapshot was deleted after the backup (Velero always does this). Result: `no snap source in omap`, then full fallback |

The negative test is the evidence for Case 2 and the basis for the design. These results
were produced with a retained base snapshot on pre-release builds; they are not 1.19.0
behavior as shipped.

**Related work.**

All PR numbers below are in `velero-io/velero` unless the link says otherwise. The list is
context: none of these items changes the 1.19.0 Case 1 / Case 2 status.

- [external-snapshot-metadata#258](https://github.com/kubernetes-csi/external-snapshot-metadata/pull/258)
  merged the `requireBaseSnapshotForDelta` field; it is not in a release yet.
- [ceph-csi#6680](https://github.com/ceph/ceph-csi/issues/6680) asks RBD to set the field.
- [velero#10722](https://github.com/velero-io/velero/issues/10722) proposes that Velero
  read it. It is currently a 1.20 candidate, after the 1.19.x design.
- Merged Velero PRs: #10698 (fix: zero block ranges on restore), #10696 (docs: swap the
  two case descriptions), #10700 (fix: retry after an interrupted backup deletion).
- Open Velero PRs: #10699 (fix: in-place restore leaked a base snapshot), #10708 (fix:
  clean up the source VSC when the snapshot step is interrupted), #10710 (fix: clean up a
  failed backup's VolumeSnapshot), #10718 (docs).
- Open Velero PR #10740 adds parallel upload/download control. It is not in 1.19.0, so
  1.19.0 users are not affected.
  - Only if you test this PR: on a 96 vCPU node with its defaults, the data mover pod
    runs out of memory (OOM) and is killed. The default run's peak memory was not
    recorded, and the pod's memory limit is not known. The data mover is a Go program; it
    sizes its parallel work from the node's CPU count (96 here; `GOMAXPROCS=96`), so
    memory use grows.
  - Workaround: the cluster admin sets `cpu` in the `podResources` ConfigMap of the
    node-agent (the Velero pod on each node that runs the data mover). Set `cpu` to a
    small number, e.g. 2. Pod memory used: CPU limit 2 -> 384 MiB, 8 -> 690 MiB, 16 ->
    928 MiB. Lower CPU limit = fewer parallel jobs = less memory.
- #10691 (delete retained snapshots) is a draft and the candidate implementation for
  #10744. #10716 is closed and superseded by the revert of #10307 (revert PR number not
  available yet).

**OCP note.** With Rook / ceph-csi-operator on OpenShift (OCP), set
`enableSeLinuxHostMount: true` on the node plugin. Without it, RBD Filesystem volumes
mount without the expected SELinux label (`unlabeled_t`), and pods using the volume get a
permission-denied error (EACCES)
([ceph-csi#6679](https://github.com/ceph/ceph-csi/issues/6679)). Docs:
[ceph-csi-operator#649](https://github.com/ceph/ceph-csi-operator/pull/649),
[rook#18636](https://github.com/rook/rook/pull/18636).

**Sources.**

- [KEP-3314, retention requirement](https://github.com/kubernetes/enhancements/blob/ea3e81a0d41dd3df7dae584ea584c31de56cd3cb/keps/sig-storage/3314-csi-changed-block-tracking/README.md#L956-L972)
- [ceph-csi RBD metadata service](https://github.com/ceph/ceph-csi/blob/a930eb0a54cd0b3ee247286966a08777e2b9489b/internal/rbd/sms_controllerserver.go#L196-L210)
- [Block data mover design, Case 1/2](https://github.com/velero-io/velero/blob/bcd162299f51c1dc9e9fa7e96bbc6af7483d5580/design/block-data-mover/block-data-mover.md#L361-L374)

### GitHub Actions CI

**Status**: The workflow runs the full demo on Minikube, or on a remote
cluster via BYOC:
- Block device tests require Minikube or a cloud cluster
- `GetMetadataAllocated`, `GetMetadataDelta`, and the upstream verifier run
  when the CSI driver provides the SnapshotMetadata service
- In-cluster backup, list, and restore Jobs run against MinIO; a failed backup
  or restore Job fails the workflow
- After restore, a verifier pod compares the source and restored block devices
  by SHA-256

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
- [demo.yaml](.github/workflows/demo.yaml) - BYOC support
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

## Cleanup

### Minikube Cluster

```bash
# Delete minikube cluster
minikube delete --profile cbt-demo
```

### Remote Cluster

```bash
# Clean up demo resources from remote cluster
./scripts/cleanup-remote-cluster.sh
```

This removes:
- `cbt-demo` namespace and all resources
- VolumeSnapshots and VolumeSnapshotContents
- Does NOT remove: CSI driver, CRDs, or storage classes (manual cleanup if needed)

### Reset Demo

To start fresh without deleting the cluster:
```bash
./scripts/cleanup.sh
./scripts/00-setup-cluster.sh
./scripts/01-deploy-csi-driver.sh
./scripts/02-deploy-minio.sh
./scripts/03-deploy-workload.sh
```

## 📚 References

- [Kubernetes CBT KEP-3314](https://github.com/kubernetes/enhancements/blob/master/keps/sig-storage/3314-csi-changed-block-tracking/README.md)
- [CSI Spec - SnapshotMetadata](https://github.com/container-storage-interface/spec/blob/master/spec.md)
- [CSI Hostpath Driver](https://github.com/kubernetes-csi/csi-driver-host-path)
- [External Snapshot Metadata](https://github.com/kubernetes-csi/external-snapshot-metadata)
- [Kubernetes Volume Snapshots](https://kubernetes.io/docs/concepts/storage/volume-snapshots/)

## 🔮 Future Enhancements

- [ ] Add data compression
- [ ] Add encryption at rest
- [ ] Parallel block uploads
- [ ] Deduplication across snapshots
- [ ] Support for multiple volumes
- [ ] Integration with Velero (waits on the Case 2 retention design for Ceph RBD; see the status section above)
- [ ] Prometheus metrics

## 📝 License

MIT License - See LICENSE file for details

## 🤝 Contributing

Contributions welcome! This is a demo project to showcase Kubernetes CBT capabilities.

## 📧 Contact

For questions or issues, please open a GitHub issue.

---

**Status**: ✅ Complete — Infrastructure, backup tool, and restore tool all fully implemented

**Current Capabilities**:
- ✅ Full CBT infrastructure with CSI hostpath driver
- ✅ Backup tool with working CBT gRPC APIs (GetMetadataAllocated, GetMetadataDelta)
- ✅ Snapshot metadata operations and S3 storage
- ✅ Block data upload to S3
- ✅ Restore tool with snapshot chain resolution and data integrity verification
