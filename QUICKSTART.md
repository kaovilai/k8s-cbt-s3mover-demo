# Quick Start Guide

Get the Kubernetes Changed Block Tracking (CBT) demo up and running in minutes!

## Prerequisites Check

```bash
# Check if required tools are installed
kind --version          # Should be v0.20.0 or later
kubectl version         # Should be v1.28.0 or later
go version              # Should be 1.22 or later (optional, for building tools)
docker --version        # Required for Kind

# Check available disk space (need ~10GB)
df -h /tmp
```

## 🚀 5-Minute Setup

### Step 1: Clone and Navigate

```bash
cd k8s-cbt-s3mover-demo
```

### Step 2: Setup Infrastructure

```bash
# This will take ~3-5 minutes
./scripts/00-setup-cluster.sh     # Creates Kind cluster (~60s)
./scripts/01-deploy-csi-driver.sh # Deploys CSI driver with CBT (~60s)
./scripts/02-deploy-minio.sh      # Deploys MinIO (~30s)
./scripts/03-deploy-workload.sh   # Deploys PostgreSQL + data (~120s)
```

### Step 3: Validate Everything Works

```bash
# Run validation checks
./scripts/validate-cbt.sh

# Check backup infrastructure
./scripts/backup-status.sh

# Verify data integrity
./scripts/integrity-check.sh
```

## ✅ What You Have Now

After completing the setup, you have:

1. **Kind Cluster** running with CBT-enabled feature gates
2. **MinIO S3** storage at http://localhost:30900
3. **CSI Hostpath Driver** with SnapshotMetadata service
4. **PostgreSQL Database** with 1000 blocks of test data (~100MB)
5. **Block-mode PVC** ready for CBT-enabled backups

## 🧪 Try It Out

### Create Your First Snapshot

```bash
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: my-first-snapshot
  namespace: cbt-demo
spec:
  volumeSnapshotClassName: csi-hostpath-snapclass
  source:
    persistentVolumeClaimName: block-writer-data
EOF

# Wait for it to be ready
kubectl wait --for=jsonpath='{.status.readyToUse}'=true \
  volumesnapshot/my-first-snapshot -n cbt-demo --timeout=300s

# Check the snapshot
kubectl get volumesnapshot -n cbt-demo my-first-snapshot
```

### Test Restore (Dry Run)

```bash
# See what a restore would look like
./scripts/restore-dry-run.sh cbt-demo my-first-snapshot
```

### Access MinIO Console

```bash
# MinIO Console is available at:
# http://localhost:30901
# Username: minioadmin
# Password: minioadmin123

# Or use port-forward if NodePort doesn't work:
kubectl port-forward -n cbt-demo svc/minio 9000:9000 9001:9001
```

### Inspect Block Device

```bash
# Connect to block-writer pod
kubectl exec -it -n cbt-demo block-writer -- sh

# Inside the pod:
# Show device info
blockdev --getsize64 /dev/xvda

# Check for non-zero blocks (sample a few positions)
dd if=/dev/xvda bs=4K count=1 skip=1 2>/dev/null | od -An -tx1 | head -5

# Sample different positions to see written data
dd if=/dev/xvda bs=4K count=1 skip=3 2>/dev/null | od -An -tx1 | head -5

# Exit
exit
```

## 📊 Monitor the Demo

### Watch Pods

```bash
kubectl get pods -n cbt-demo --watch
```

### Check Logs

```bash
# PostgreSQL logs
kubectl logs -n cbt-demo block-writer --tail=50

# MinIO logs
kubectl logs -n cbt-demo -l app=minio --tail=50

# CSI Driver logs
kubectl logs -n default -l app=csi-hostpathplugin --tail=50
```

### Check Resources

```bash
# All resources in demo namespace
kubectl get all -n cbt-demo

# Persistent volumes
kubectl get pvc,pv -n cbt-demo

# Snapshots
kubectl get volumesnapshot,volumesnapshotcontent -n cbt-demo

# Storage classes
kubectl get storageclass,volumesnapshotclass
```

## 🔍 Verify CBT is Working

```bash
# Run the validation script
./scripts/validate-cbt.sh

# Should show:
# ✓ SnapshotMetadataService CRD is installed
# ✓ CSI hostpath driver pods are running
# ✓ Snapshot metadata sidecar is present
# ✓ VolumeSnapshotClass exists
# ✓ StorageClass exists
```

## 🎓 Understanding the Components

### Kubernetes Resources

```bash
# Namespace for all demo resources
kubectl get namespace cbt-demo

# MinIO for S3 storage
kubectl get deployment,service,pvc -n cbt-demo -l app=minio

# block-writer workload
kubectl get statefulset,service,pvc -n cbt-demo -l app=block-writer

# CSI Driver (in default namespace)
kubectl get pods -n default -l app=csi-hostpathplugin
```

### Storage Resources

```bash
# Storage class for CSI hostpath driver
kubectl get storageclass csi-hostpath-sc -o yaml

# Volume snapshot class for snapshots
kubectl get volumesnapshotclass csi-hostpath-snapclass -o yaml

# Persistent Volume Claims (block mode!)
kubectl get pvc -n cbt-demo -o custom-columns=\
NAME:.metadata.name,\
MODE:.spec.volumeMode,\
STATUS:.status.phase,\
SIZE:.spec.resources.requests.storage
```

## 📝 Common Operations

### Write More Data to Block Device

```bash
# Write additional random data at different block offsets for incremental backup demo
kubectl exec -n cbt-demo block-writer -- dd if=/dev/urandom of=/dev/xvda bs=4K count=1 seek=15 conv=notrunc
kubectl exec -n cbt-demo block-writer -- dd if=/dev/urandom of=/dev/xvda bs=4K count=1 seek=17 conv=notrunc
kubectl exec -n cbt-demo block-writer -- dd if=/dev/urandom of=/dev/xvda bs=4K count=1 seek=19 conv=notrunc
kubectl exec -n cbt-demo block-writer -- dd if=/dev/urandom of=/dev/xvda bs=4K count=1 seek=21 conv=notrunc
kubectl exec -n cbt-demo block-writer -- dd if=/dev/urandom of=/dev/xvda bs=4K count=1 seek=23 conv=notrunc
```

### Create Additional Snapshots

```bash
# Snapshot 2 (after adding more data)
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

### Delete a Snapshot

```bash
kubectl delete volumesnapshot my-first-snapshot -n cbt-demo
```

## 🐛 Troubleshooting

### Pods Not Starting

```bash
# Check pod status
kubectl get pods -n cbt-demo -o wide

# Describe pod to see events
kubectl describe pod <pod-name> -n cbt-demo

# Check logs
kubectl logs <pod-name> -n cbt-demo
```

### CSI Driver Issues

```bash
# Check CSI driver pods
kubectl get pods -n default -l app=csi-hostpathplugin

# Check driver logs
kubectl logs -n default -l app=csi-hostpathplugin -c hostpath --tail=100

# Check if SnapshotMetadataService CRD exists
kubectl get crd | grep snapshotmetadata
```

### Snapshot Not Ready

```bash
# Check snapshot status
kubectl get volumesnapshot -n cbt-demo <snapshot-name> -o yaml

# Check snapshot content
kubectl get volumesnapshotcontent -o yaml
```

### MinIO Connection Issues

```bash
# Check MinIO pod
kubectl get pods -n cbt-demo -l app=minio

# Test MinIO connectivity from within cluster
kubectl run -it --rm debug --image=minio/mc --restart=Never -- \
  mc alias set myminio http://minio.cbt-demo.svc.cluster.local:9000 \
  minioadmin minioadmin123
```

## 🧹 Cleanup

When you're done:

```bash
# Delete everything
./scripts/cleanup.sh

# This will:
# - Delete the Kind cluster
# - Clean up temporary directories
# - Remove downloaded CSI driver
```

## 🔄 Reset Demo

To start fresh:

```bash
./scripts/cleanup.sh
# Wait for cleanup to complete
./scripts/00-setup-cluster.sh
./scripts/01-deploy-csi-driver.sh
./scripts/02-deploy-minio.sh
./scripts/03-deploy-workload.sh
```

## 📚 Next Steps

1. **Read the documentation**:
   - [README.md](README.md) - Full documentation
   - [PLAN.md](PLAN.md) - Implementation details
   - [STATUS.md](STATUS.md) - Current status

2. **Explore the scripts**:
   - Browse `scripts/` directory for all automation
   - Read `manifests/` for Kubernetes resources

3. **Try manual operations**:
   - Create multiple snapshots
   - Add/modify data between snapshots
   - Experiment with restore operations

4. **Monitor GitHub Actions**:
   - Push to repository to trigger CI
   - Check workflow in `.github/workflows/demo.yaml`

## ❓ Getting Help

- **Validate setup**: `./scripts/validate-cbt.sh`
- **Check status**: `./scripts/backup-status.sh`
- **Verify integrity**: `./scripts/integrity-check.sh`
- **Check logs**: `kubectl logs -n cbt-demo <pod-name>`

## 🎯 What's Next?

### Current Status (90% Complete)

**Available Now**:
1. ✅ **Backup Tool (90%)**: Create snapshots using real CBT APIs (GetMetadataAllocated, GetMetadataDelta)
   - Metadata operations fully functional
   - Block data upload is the only remaining feature (2-4 hours)
2. ✅ **Infrastructure**: Complete CBT setup with CSI hostpath driver
3. ✅ **Demo Workflows**: Full automation scripts for testing

**In Development**:
1. ⚠️ **Block Data Upload**: Integrate block reader with S3 upload
2. ⚠️ **Restore Tool (0%)**: Reconstruct volumes from S3 storage

Check [STATUS.md](STATUS.md) for detailed progress and remaining work.

---

**Have fun exploring Kubernetes Changed Block Tracking!** 🚀
