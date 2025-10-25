---
theme: default
background: https://source.unsplash.com/collection/1065976/1920x1080
class: text-center
highlighter: shiki
lineNumbers: true
info: |
  ## K8s CBT S3Mover Demo
  Kubernetes Changed Block Tracking with S3 Storage
drawings:
  persist: false
transition: slide-left
title: K8s CBT S3Mover Demo
mdc: true
---

# K8s CBT S3Mover Demo

Efficient Backup with Changed Block Tracking

<div class="pt-12">
  <span @click="$slidev.nav.next" class="px-2 py-1 rounded cursor-pointer" hover="bg-white bg-opacity-10">
    Press Space to begin <carbon:arrow-right class="inline"/>
  </span>
</div>

---
transition: fade-out
layout: two-cols
---

# Overview

<v-click>

## What is CBT?

Changed Block Tracking (**KEP-3314**) identifies **only the blocks** that have changed between snapshots, enabling efficient incremental backups.

**Alpha support** announced in Kubernetes for CSI storage drivers

</v-click>

<v-click>

## Key Benefits

- ⏱️ **Shorter Backup Windows** - Hours to minutes for large datasets
- 📉 **Reduced Resource Usage** - Less network bandwidth and I/O
- 💰 **Lower Storage Costs** - Avoid redundant full backups
- 🔄 **Incremental Backups** - Only transfer changed blocks

</v-click>

<v-click>

<div class="text-sm mt-4 p-2 bg-yellow-900 bg-opacity-20 rounded">

⚠️ **Note**: CBT is supported only for **block volumes**, not file volumes

</div>

</v-click>

::right::

<v-click>

```mermaid {scale: 0.7}
graph TB
    PVC[PVC: PostgreSQL Data]
    S1[Snapshot 1<br/>100 rows]
    S2[Snapshot 2<br/>200 rows]
    CBT[CBT Engine]
    S3[S3 Backup<br/>Delta Only]

    PVC -->|Create| S1
    PVC -->|Write +100 rows| S2
    S1 -->|Compare| CBT
    S2 -->|Compare| CBT
    CBT -->|~10MB delta| S3

    style CBT fill:#f96,stroke:#333
    style S3 fill:#9f6,stroke:#333
```

</v-click>

---
layout: default
---

# CBT API Architecture (KEP-3314)

<div grid="~ cols-2 gap-8" class="text-sm">
<div>

## Three Key Components

<v-clicks depth="2">

1. **CSI SnapshotMetadata Service API**
   - `GetMetadataAllocated` RPC
   - `GetMetadataDelta` RPC

2. **SnapshotMetadataService CRD**
   - Advertises service availability
   - Connection details & CA cert

3. **External Snapshot Metadata Sidecar**
   - Validates K8s auth tokens
   - Translates names to handles
   - Forwards requests to CSI

</v-clicks>

</div>
<div>

<v-click>

## Security Model

- **Authentication**: TokenRequest API
- **Authorization**: RBAC + SubjectAccessReview
- **Transport**: Mutual TLS
- **Token scoping**: Audience-bound

</v-click>

<v-click>

<div class="mt-3">

## Metadata Formats

- **FIXED_LENGTH**: Uniform blocks
- **VARIABLE_LENGTH**: Variable extents

<div class="text-xs mt-1 opacity-70">
Both support resumption via `starting_offset`
</div>

</div>

</v-click>

</div>
</div>

---
layout: default
---

# Demo Architecture

<div grid="~ cols-2 gap-4" class="text-xs">
<div>

## Components

<v-clicks>

1. **CSI Driver** with CBT
   - SnapshotMetadata service
   - Block change tracking

2. **MinIO** S3 storage
   - S3-compatible object storage
   - Backup target

3. **PostgreSQL** workload
   - Database for testing
   - Block device PVC

4. **Snapshot Controller**
   - VolumeSnapshot CRDs
   - Lifecycle management

</v-clicks>

</div>
<div v-click>

```mermaid {theme: 'neutral', scale: 0.45}
graph LR
    subgraph ns["cbt-demo namespace"]
        PG[PostgreSQL]
        PVC[PVC<br/>Block]
        VS1[Snap-1]
        VS2[Snap-2]
        MinIO[MinIO<br/>S3]
    end

    subgraph infra[Infrastructure]
        CSI[CSI+CBT]
        SC[Snapshot<br/>Controller]
    end

    PG -.->|Uses| PVC
    PVC -->|Create| VS1
    PVC -->|Create| VS2
    VS1 -->|CBT| CSI
    VS2 -->|CBT| CSI
    CSI -->|Delta| MinIO
    SC --> VS1
    SC --> VS2

    style CSI fill:#f9f,stroke:#333
    style MinIO fill:#9cf,stroke:#333
```

</div>
</div>

---
layout: default
---

# Demo Workflow

<v-clicks depth="2">

## Phase 1: Setup Infrastructure

1. **Deploy Kubernetes Cluster**
   - Minikube (default) or remote cluster
   - 4 CPUs, 8GB RAM, containerd runtime

2. **Install Snapshot CRDs**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/\
   external-snapshotter/v8.2.0/client/config/crd/...
   ```

3. **Deploy CSI Driver with CBT**
   ```bash
   ./scripts/02-deploy-csi-driver.sh
   ```
   - Installs `SnapshotMetadataService` CRD
   - Enables CBT API

</v-clicks>

---

# Demo Workflow (cont.)

<v-clicks depth="2">

## Phase 2: Deploy Workload

4. **Deploy MinIO S3 Storage**
   ```bash
   ./scripts/01-deploy-minio.sh
   ```

5. **Deploy PostgreSQL**
   ```bash
   ./scripts/03-deploy-workload.sh
   ```
   - Creates block device PVC
   - Initializes database with 100 rows

6. **Verify Setup**
   ```bash
   ./scripts/backup-status.sh
   ./scripts/integrity-check.sh
   ```

</v-clicks>

---
layout: two-cols
---

# Creating Snapshots

<v-clicks>

## Initial Snapshot

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: postgres-snapshot-1
  namespace: cbt-demo
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: postgres-data-0
```

Wait for ready state:
```bash
kubectl wait volumesnapshot postgres-snapshot-1 \
  -n cbt-demo \
  --for=jsonpath='{.status.readyToUse}'=true
```

</v-clicks>

::right::

<v-clicks>

## Delta Snapshot

First, create changes:
```sql
INSERT INTO demo_data (data_block, content, checksum)
SELECT generate_series(101, 200),
       encode(gen_random_bytes(100000), 'base64'),
       md5(random()::text);
```

Then create second snapshot:
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: postgres-snapshot-2
  namespace: cbt-demo
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: postgres-data-0
```

</v-clicks>

---
layout: default
---

# Use Cases

<v-clicks depth="2">

## Full Snapshot Backup

1. Create VolumeSnapshot
2. Query `GetMetadataAllocated` for all allocated blocks
3. Mount snapshot with Block VolumeMode
4. Selectively read and backup only allocated blocks

**Benefits**: Skip empty/unallocated space - significantly reduces initial backup size

*Example: 10GB volume with 2GB data → backup only 2GB*

## Incremental Snapshot Backup

1. Create new VolumeSnapshot
2. Query `GetMetadataDelta` comparing to previous snapshot
3. Mount snapshot with Block VolumeMode
4. Backup only changed blocks

**Benefits**: Significantly reduced backup size and duration

</v-clicks>

---
layout: default
---

<div class="text-sm">

# CBT API Demonstration

<div class="text-xs mb-2 opacity-70">
Note: CBT API is currently in alpha and subject to change
</div>

<v-clicks depth="2">

## 1. GetMetadataAllocated

List all allocated blocks in a snapshot:

```bash
snapshot-metadata-lister -s postgres-snapshot-1 -n cbt-demo
```

Shows all blocks containing the initial 100 rows of data

## 2. GetMetadataDelta - Before PR #180

Using snapshot names:

```bash
snapshot-metadata-lister \
  -p postgres-snapshot-1 \
  -s postgres-snapshot-2 \
  -n cbt-demo
```

## 2. GetMetadataDelta - After PR #180

**Enhancement: PR #180** added CSI handle support

```bash
# Get CSI snapshot handle
VSC=$(kubectl get volumesnapshot postgres-snapshot-1 -n cbt-demo \
  -o jsonpath="{.status.boundVolumeSnapshotContentName}")
HANDLE=$(kubectl get volumesnapshotcontent $VSC \
  -o jsonpath="{.status.snapshotHandle}")

# Use CSI handle (allows base snapshot deletion)
snapshot-metadata-lister -P "$HANDLE" -s postgres-snapshot-2 -n cbt-demo
```

Reports only changed blocks (100 new rows, ~10MB)

</v-clicks>

</div>

---
layout: two-cols
---

# Build Tools

<v-click>

## Backup Tool

```bash
cd tools/cbt-backup
go build -v -o cbt-backup ./cmd

./cbt-backup --help
./cbt-backup create --help
./cbt-backup list --help
```

</v-click>

<v-click>

**Features:**
- Create incremental backups
- List backup sets
- Upload to S3 storage
- CBT metadata tracking

</v-click>

::right::

<v-click>

## Restore Tool

```bash
./scripts/restore-dry-run.sh \
  cbt-demo postgres-snapshot-1
```

</v-click>

<v-click>

**Status:**
- Currently in development
- Placeholder implementation
- Future enhancement

See `STATUS.md` and `IMPLEMENTATION_COMPLETE.md` for details.

</v-click>

---
layout: center
class: text-center
---

<div class="text-sm">

# Data Integrity

<v-clicks>

## Verification Process

```bash
./scripts/integrity-check.sh
```

<div class="text-xs">

Checks: Snapshot checksums • Block-level consistency • PostgreSQL data • Backup metadata

</div>

</v-clicks>

<v-click>

## Results

<div class="text-left mx-auto max-w-2xl mt-4">

| Check | Snapshot 1 | Snapshot 2 |
|-------|-----------|-----------|
| Rows | 100 | 200 |
| Size | ~10MB | ~20MB |
| Delta | - | ~10MB |
| Checksum | ✓ MD5 | ✓ MD5 |

</div>

</v-click>

</div>

---
layout: default
---

# Troubleshooting

<v-clicks depth="2">

## Common Issues

1. **Snapshot not ready**
   ```bash
   kubectl describe volumesnapshot postgres-snapshot-1 -n cbt-demo
   kubectl logs -n kube-system -l app.kubernetes.io/name=snapshot-controller
   ```

2. **CSI Driver issues**
   ```bash
   kubectl logs -n default csi-hostpathplugin-0 --all-containers
   kubectl describe pod -n default csi-hostpathplugin-0
   ```

3. **CBT CRD missing**
   ```bash
   kubectl get crd snapshotmetadataservices.cbt.storage.k8s.io
   ./scripts/validate-cbt.sh
   ```

</v-clicks>

---
layout: default
---

# CI/CD Pipeline

<div grid="~ cols-3 gap-4">
<div>

<v-click>

## demo

**End-to-end test**
- Setup cluster
- Deploy components
- Create snapshots
- Test CBT

</v-click>

</div>
<div>

<v-click>

## build-backup-tool

**Build & test**
- Go 1.22
- Download deps
- Build binary
- Run tests

</v-click>

</div>
<div>

<v-click>

## lint

**Code quality**
- shellcheck scripts
- go fmt
- go vet

</v-click>

</div>
</div>

<v-click>

## Workflow Triggers

```yaml
on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:
```

</v-click>

---
layout: center
class: text-center
---

# Demo Results

<v-clicks>

## What We Demonstrated

1. ✅ Kubernetes CSI snapshots with CBT support
2. ✅ Changed block tracking between snapshots
3. ✅ Efficient delta backup (~10MB vs ~20MB full)
4. ✅ S3-compatible storage integration
5. ✅ Real workload (PostgreSQL) testing
6. ✅ Automated CI/CD validation

## Key Takeaway

<div class="text-2xl mt-8 text-green-400">
CBT enables <strong>efficient incremental backups</strong> by tracking only changed blocks
</div>

</v-clicks>

---
layout: default
---

# Try It Yourself

<v-clicks>

## Quick Start

```bash
# Clone repository
git clone <repo-url>

# Run the demo locally
./scripts/01-deploy-minio.sh
./scripts/02-deploy-csi-driver.sh
./scripts/03-deploy-workload.sh

# Create snapshots
kubectl apply -f manifests/snapshot-1.yaml
kubectl apply -f manifests/snapshot-2.yaml

# Check status
./scripts/backup-status.sh
./scripts/integrity-check.sh
```

## Demo Resources

- 📖 **Demo Docs**: `README.md`, `STATUS.md`
- 🔧 **Scripts**: `scripts/` directory
- 🛠️ **Tools**: `tools/cbt-backup/`
- 🚀 **Workflow**: `.github/workflows/demo.yaml`

</v-clicks>

---
layout: default
---

# Official Resources

<div grid="~ cols-2 gap-4">
<div>

<v-click>

## Kubernetes Documentation

- 📘 [KEP-3314: CSI Changed Block Tracking](https://github.com/kubernetes/enhancements/tree/master/keps/sig-storage/3314-csi-changed-block-tracking)
- 📚 [CSI Developer Docs](https://kubernetes-csi.github.io/docs/external-snapshot-metadata.html)
- 📝 [Kubernetes Blog Post](https://github.com/kubernetes/website/pull/48456) (upcoming)

</v-click>

</div>
<div>

<v-click>

## Implementation References

- 🔧 [external-snapshot-metadata](https://github.com/kubernetes-csi/external-snapshot-metadata) repo
- 📋 [schema.proto](https://github.com/kubernetes-csi/external-snapshot-metadata/blob/main/proto/schema.proto) - gRPC API definitions
- 💡 [snapshot-metadata-lister](https://github.com/kubernetes-csi/external-snapshot-metadata/tree/main/examples/snapshot-metadata-lister) example
- 🔨 [csi-hostpath-driver](https://github.com/kubernetes-csi/csi-driver-host-path) with CBT

</v-click>

</div>
</div>

<v-click>

## Get Involved

- 🤝 Join [SIG Storage](https://github.com/kubernetes/community/tree/master/sig-storage)
- 🗓️ Attend [Data Protection Working Group](https://docs.google.com/document/d/15tLCV3csvjHbKb16DVk-mfUmFry_Rlwo-2uG6KNGsfw/edit) meetings

</v-click>

---
layout: center
class: text-center
---

# Thank You!

Questions?

<div class="pt-12 text-sm opacity-50">
  <p>K8s CBT S3Mover Demo</p>
  <p>Efficient backup with Changed Block Tracking</p>
</div>
