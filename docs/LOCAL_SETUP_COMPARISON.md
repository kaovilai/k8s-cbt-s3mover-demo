# Local Setup: Kind vs Minikube

## Quick Decision Guide

**Use Kind if you want to:**
- ✅ Learn CBT concepts quickly
- ✅ Test snapshot workflow
- ✅ Iterate fast on development
- ✅ Run in any environment (Codespaces, limited resources)

**Use Minikube if you want to:**
- ✅ Test actual block devices
- ✅ Run the same tests as upstream CI
- ✅ Verify CBT metadata APIs work correctly
- ✅ Test with real block-level changed tracking

## Detailed Comparison

| Feature | Kind | Minikube |
|---------|------|----------|
| **Setup Command** | `./scripts/run-local-macos.sh` | `./scripts/run-local-minikube.sh` |
| **Architecture** | Docker containers | Docker + VM |
| **Startup Time** | ~2 minutes | ~5 minutes |
| **Memory Usage** | ~2GB | ~8GB |
| **Block PVCs** | ❌ Unreliable | ✅ Full support |
| **Loop Devices** | ❌ Static /dev | ✅ Dynamic creation |
| **CBT Metadata** | ⚠️ Conceptual only | ✅ Actual tracking |
| **PostgreSQL Mode** | Filesystem | Filesystem or Block |
| **Upstream Alignment** | Different | ✅ Same as CI |
| **Resource Impact** | Low | Medium |
| **Works in Codespaces** | ✅ Yes | ❌ No (needs nested virt) |

## What Each Script Does

### Kind Script (`run-local-macos.sh`)

```bash
./scripts/run-local-macos.sh
```

**Process:**
1. Checks: kind, kubectl, docker
2. Creates Kind cluster (30 seconds)
3. Deploys MinIO (30 seconds)
4. Deploys CSI driver (1 minute)
5. Deploys PostgreSQL (1 minute)
6. Creates 3 snapshots (30 seconds)

**Total Time**: ~3-4 minutes

**Result:**
- PostgreSQL with filesystem PVC
- 3 VolumeSnapshots
- Snapshot workflow demonstrated
- CBT concepts shown (but not actual block tracking)

### Minikube Script (`run-local-minikube.sh`)

```bash
./scripts/run-local-minikube.sh
```

**Process:**
1. Checks: minikube, kubectl, docker
2. Starts minikube VM (2-3 minutes)
3. Installs VolumeSnapshot CRDs (30 seconds)
4. Deploys MinIO (30 seconds)
5. Deploys CSI driver (1 minute)
6. Deploys PostgreSQL (1 minute)
7. Creates 3 snapshots (30 seconds)

**Total Time**: ~6-8 minutes

**Result:**
- PostgreSQL with block or filesystem PVC
- 3 VolumeSnapshots with real block tracking
- Full CBT metadata available
- Can test snapshot-metadata-lister/verifier tools

## Testing Capabilities

### Kind - What Works

✅ **Snapshots**: Create VolumeSnapshots
✅ **Workflow**: Demonstrate backup/restore flow
✅ **MinIO**: S3 storage integration
✅ **PostgreSQL**: Application-level backups
✅ **Learning**: Understand CBT concepts

⚠️ **Limitations**:
- Block PVCs may fail
- CBT metadata APIs won't return actual block changes
- Can't test snapshot-metadata-lister tool properly

### Minikube - What Works

✅ **Everything in Kind**, plus:
✅ **Block PVCs**: Create and mount block devices
✅ **CBT Metadata**: GetMetadataDelta returns actual changes
✅ **Upstream Tools**: Can run snapshot-metadata-lister
✅ **Verification**: Can run snapshot-metadata-verifier
✅ **Real Testing**: Same as kubernetes-csi CI

## Use Cases

### Kind is Perfect For:

1. **Learning Phase**
   ```bash
   # Quick exploration of CBT concepts
   ./scripts/run-local-macos.sh
   ```

2. **Development Iteration**
   ```bash
   # Fast cycles when changing scripts/manifests
   kind create cluster --config cluster/kind-config.yaml
   # ... make changes ...
   kind delete cluster
   ```

3. **CI/CD for Application Code**
   ```yaml
   # .github/workflows/app-test.yaml
   - uses: helm/kind-action@v1
   - run: ./scripts/run-local-macos.sh
   ```

4. **Constrained Environments**
   - GitHub Codespaces
   - Low-memory laptops
   - Docker Desktop with limited resources

### Minikube is Perfect For:

1. **CBT Validation**
   ```bash
   # Test that CBT actually works
   ./scripts/run-local-minikube.sh
   ```

2. **Integration Testing**
   ```bash
   # Run upstream snapshot-metadata tools
   go build ./examples/snapshot-metadata-lister/
   kubectl exec ... -- /snapshot-metadata-lister -P <handle> -s snap-2
   ```

3. **CI/CD for CBT Features**
   ```yaml
   # .github/workflows/cbt-integration.yaml
   - uses: medyagh/setup-minikube@latest
   - run: ./scripts/run-local-minikube.sh
   ```

4. **Pre-production Validation**
   - Before deploying to EKS/GKE
   - Testing CSI driver changes
   - Verifying block device behavior

## Migration Path

### Start with Kind
```bash
# Day 1: Learn the concepts
./scripts/run-local-macos.sh

# Explore the setup
kubectl get all -n cbt-demo
kubectl get volumesnapshot -n cbt-demo
```

### Graduate to Minikube
```bash
# When ready for real testing
kind delete cluster --name cbt-demo
./scripts/run-local-minikube.sh

# Now test actual CBT
# Build snapshot-metadata tools
# Test with block devices
```

### Move to Cloud
```bash
# For production validation
# Use demo-aws.yaml workflow
# Full EKS testing with real block devices
```

## Resource Requirements

### Kind

**Minimum:**
- RAM: 4GB total (2GB for cluster)
- CPU: 2 cores
- Disk: 10GB free

**Recommended:**
- RAM: 8GB total
- CPU: 4 cores
- Disk: 20GB free

### Minikube

**Minimum:**
- RAM: 8GB total (4GB for VM)
- CPU: 4 cores
- Disk: 20GB free

**Recommended:**
- RAM: 16GB total (8GB for VM)
- CPU: 4+ cores
- Disk: 30GB free

## Troubleshooting

### Kind Issues

**PVC Pending**:
```bash
# Expected with block PVCs - use filesystem mode instead
kubectl get pvc -n cbt-demo
kubectl describe pvc <name> -n cbt-demo
```

**Solution**: This is normal for Kind. Use minikube for block PVCs.

### Minikube Issues

**Won't Start**:
```bash
# Check Docker is running
docker info

# Delete and recreate
minikube delete --profile cbt-demo
minikube start --profile cbt-demo --driver=docker
```

**Slow Performance**:
```bash
# Allocate more resources
minikube delete --profile cbt-demo
minikube start --profile cbt-demo --cpus=4 --memory=8192
```

## Summary

**Choose Kind for:**
- 🚀 Speed
- 💻 Learning
- 🔄 Fast iteration
- 📚 Concept demonstration

**Choose Minikube for:**
- ✅ Validation
- 🧪 Testing
- 🔬 Verification
- 📊 Real CBT metrics

**Choose Cloud (EKS) for:**
- 🏭 Production
- 🌍 Real workloads
- 💾 Persistent storage
- 🔐 Security testing

Both approaches are valuable - use the right tool for the job!
