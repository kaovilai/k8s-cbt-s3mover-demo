# Minikube vs Kind for CBT Block Device Testing

## Executive Summary

**The upstream `external-snapshot-metadata` project uses minikube for CI testing because it provides better block device support than Kind.** This is why their GitHub Actions workflow successfully creates and tests block PVCs, while our Kind-based approach encounters limitations.

## Key Differences

| Aspect | Minikube | Kind |
|--------|----------|------|
| **Architecture** | Full VM (KVM/VirtualBox/Docker) | Docker containers only |
| **Kernel** | Dedicated VM kernel | Shared host kernel |
| **Loop Devices** | ✅ Dynamic creation | ❌ Static from host |
| **Block PVCs** | ✅ Full support | ⚠️ Limited/unreliable |
| **CBT Testing** | ✅ Ideal for CI | ⚠️ Filesystem mode only |
| **Startup Time** | Slower (~2-3 min) | Faster (~30 sec) |
| **Resource Usage** | Higher (VM overhead) | Lower (containers) |

## Why Minikube Works for Block Devices

### 1. Real VM with Full Kernel Access

Minikube runs a complete virtual machine with its own kernel:

```bash
# Minikube architecture
GitHub Actions Runner
  └── VM (minikube)
      └── Kubernetes
          └── CSI hostpath driver
              └── /dev/loop* ✅ Can create dynamically
```

The CSI driver can:
- Call `losetup -f` to find free loop devices
- Create new `/dev/loop*` devices on demand
- Mount block devices without restrictions

### 2. Kind's Container Limitation

Kind runs Kubernetes nodes as Docker containers:

```bash
# Kind architecture
GitHub Actions Runner
  └── Docker
      └── Kind container (Kubernetes node)
          └── CSI hostpath driver
              └── /dev/loop* ❌ Static copy from host
```

The problem:
- Kind containers get a **static copy** of `/dev` from the host at startup
- New loop devices created after container start are **not visible**
- `losetup -f` fails because it can't see dynamically created devices

## Upstream Integration Test Strategy

The `kubernetes-csi/external-snapshot-metadata` project uses this approach in their CI:

### GitHub Actions Workflow (.github/workflows/integration-test.yaml)

```yaml
jobs:
  minikube-ci:
    runs-on: ubuntu-latest
    steps:
      - name: Start minikube
        uses: medyagh/setup-minikube@latest  # ← Uses minikube, not Kind!

      - name: Execute tests
        run: |
          # Create raw block PVC
          kubectl create -f ~/csi-driver-host-path/examples/csi-pvc-block.yaml

          # Write data to block device
          kubectl exec pod-raw -- dd if=/dev/urandom of=/dev/block bs=4K count=1

          # Create snapshots and test CBT
          # ✅ All of this works because minikube supports block devices!
```

### What They Test

1. **Raw block PVCs** with `volumeMode: Block`
2. **Direct block device access** (`/dev/block`, `/dev/source`, `/dev/target`)
3. **snapshot-metadata-lister** tool with actual CBT API calls
4. **snapshot-metadata-verifier** tool to validate changed blocks
5. **Both `-p <name>` and `-P <csi-handle>` approaches** from PR #180

All of this works reliably in GitHub Actions because minikube provides proper block device support.

## Our Demo Strategy

### Current Approach (Kind)

We use Kind with **filesystem-mode PVCs** and PostgreSQL:

**Pros:**
- ✅ Faster startup for development
- ✅ Lower resource usage
- ✅ Works in Codespaces/container environments
- ✅ Demonstrates realistic application scenario (PostgreSQL)
- ✅ Can still test snapshot functionality (just not true block-level CBT)

**Cons:**
- ❌ Can't test raw block PVCs reliably
- ❌ Can't demonstrate actual block-level CBT metadata
- ❌ PostgreSQL uses filesystem mode, not block mode

### Recommended: Hybrid Approach

We should maintain **both approaches**:

#### 1. Kind-based Demo (Current)
- **Target**: Local development, quick testing, concept demonstration
- **PVC Mode**: Filesystem
- **Workload**: PostgreSQL (realistic scenario)
- **CBT**: Conceptual (shows workflow, but not actual block tracking)
- **Where**: `demo.yaml` workflow, local development

#### 2. Minikube-based Integration Test (New)
- **Target**: Full CBT validation in CI
- **PVC Mode**: Block
- **Workload**: Raw block devices with dd
- **CBT**: Real block-level tracking with metadata tools
- **Where**: New `integration-test.yaml` workflow

## Implementation Recommendations

### Option 1: Add Minikube-based Integration Test

Create a new workflow that mirrors the upstream approach:

```yaml
name: CBT Integration Test

on:
  push:
    branches: [ main ]
  pull_request:

jobs:
  minikube-integration:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Start minikube
        uses: medyagh/setup-minikube@latest

      - name: Build snapshot-metadata tools
        run: |
          # Clone external-snapshot-metadata
          git clone https://github.com/kubernetes-csi/external-snapshot-metadata.git
          cd external-snapshot-metadata
          go build -o snapshot-metadata-lister ./examples/snapshot-metadata-lister/
          go build -o snapshot-metadata-verifier ./examples/snapshot-metadata-verifier/

      - name: Deploy CSI driver with CBT
        run: ./scripts/02-deploy-csi-driver.sh

      - name: Test block PVCs and CBT
        run: |
          # Create raw block PVC
          # Write data with dd
          # Create snapshots
          # Use snapshot-metadata-lister to verify CBT
          # Test both -p and -P flags (PR #180)
```

### Option 2: Update README to Clarify

Update the README Known Limitations section:

```markdown
## Known Limitations

### Block Device Support

**Status**: Block PVCs work with **minikube** but have limitations with **Kind**.

- ✅ **Minikube**: Full block device support (used by upstream CI)
- ⚠️ **Kind**: Limited to filesystem PVCs in container environments
- ✅ **EKS/GKE/AKS**: Full block device support

This demo uses:
- **Kind** for local development (filesystem mode)
- **EKS** for full CBT testing (block mode)
- See `docs/MINIKUBE_VS_KIND.md` for details
```

## Testing Matrix

Here's what works where:

| Feature | Kind (Local) | Minikube (CI) | EKS/Cloud |
|---------|-------------|---------------|-----------|
| Filesystem PVCs | ✅ | ✅ | ✅ |
| Block PVCs | ❌ | ✅ | ✅ |
| PostgreSQL workload | ✅ | ✅ | ✅ |
| Raw block devices | ❌ | ✅ | ✅ |
| CBT metadata tools | ⚠️ | ✅ | ✅ |
| PR #180 features | ⚠️ | ✅ | ✅ |

Legend:
- ✅ Works reliably
- ⚠️ Conceptual/limited
- ❌ Does not work

## Conclusion

The upstream project made the right choice using minikube for their integration tests. For our demo:

1. **Keep Kind** for local development and conceptual demos
2. **Add minikube-based integration test** for full CBT validation
3. **Use EKS** for real-world testing with actual block devices
4. **Update documentation** to clarify the different testing approaches

This gives users multiple paths forward depending on their needs:
- Want quick local testing? Use Kind
- Want full CI validation? Use minikube
- Want production testing? Use cloud providers

The key is **transparency** about what each approach can and cannot do.
