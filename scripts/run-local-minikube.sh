#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "K8s CBT Demo - Minikube with Block Devices"
echo "=========================================="
echo ""
echo "This script uses minikube for FULL block device support:"
echo "  ✅ Real block PVCs (volumeMode: Block)"
echo "  ✅ Actual CBT metadata tracking"
echo "  ✅ Same setup as upstream CI tests"
echo ""
echo "Steps:"
echo "  1. Check prerequisites (minikube, kubectl, docker)"
echo "  2. Start minikube cluster"
echo "  3. Deploy MinIO S3 storage"
echo "  4. Deploy CSI driver with CBT"
echo "  5. Deploy PostgreSQL workload"
echo "  6. Run demo workflow with snapshots"
echo ""
echo "⚠️  Note: Minikube is slower than Kind but supports block devices"
echo ""
read -r -p "Press Enter to continue or Ctrl+C to cancel..."

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check version
check_version() {
    local cmd=$1
    local current_version

    case $cmd in
        minikube)
            current_version=$(minikube version --short 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | sed 's/v//')
            ;;
        kubectl)
            current_version=$(kubectl version --client -o json 2>/dev/null | grep -oE '"gitVersion":"v[0-9]+\.[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            ;;
        docker)
            current_version=$(docker version --format '{{.Client.Version}}' 2>/dev/null)
            ;;
    esac

    echo "$current_version"
}

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo "=========================================="
echo "Step 1: Checking Prerequisites"
echo "=========================================="

MISSING_DEPS=0

# Check Docker
echo -n "Checking Docker... "
if command_exists docker; then
    DOCKER_VERSION=$(check_version docker)
    echo -e "${GREEN}✓${NC} Found version $DOCKER_VERSION"

    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}✗${NC} Docker daemon is not running!"
        echo "  Please start Docker Desktop"
        MISSING_DEPS=1
    fi
else
    echo -e "${RED}✗${NC} Not found"
    echo "  Install Docker Desktop from: https://www.docker.com/products/docker-desktop"
    MISSING_DEPS=1
fi

# Check kubectl
echo -n "Checking kubectl... "
if command_exists kubectl; then
    KUBECTL_VERSION=$(check_version kubectl)
    echo -e "${GREEN}✓${NC} Found version $KUBECTL_VERSION"
else
    echo -e "${RED}✗${NC} Not found"
    echo "  Install with: brew install kubectl"
    MISSING_DEPS=1
fi

# Check minikube
echo -n "Checking minikube... "
if command_exists minikube; then
    MINIKUBE_VERSION=$(check_version minikube)
    echo -e "${GREEN}✓${NC} Found version $MINIKUBE_VERSION"
else
    echo -e "${RED}✗${NC} Not found"
    echo "  Install with: brew install minikube"
    MISSING_DEPS=1
fi

# Check Go (optional, for building tools)
echo -n "Checking Go (optional)... "
if command_exists go; then
    GO_VERSION=$(go version | grep -oE 'go[0-9]+\.[0-9]+' | sed 's/go//')
    echo -e "${GREEN}✓${NC} Found version $GO_VERSION"
else
    echo -e "${YELLOW}⚠${NC} Not found (optional for building backup tools)"
    echo "  Install with: brew install go"
fi

if [ $MISSING_DEPS -eq 1 ]; then
    echo ""
    echo -e "${RED}Missing required dependencies!${NC}"
    echo "Please install the missing tools and try again."
    exit 1
fi

echo ""
echo -e "${GREEN}✓ All prerequisites satisfied!${NC}"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

# Step 2: Setup minikube cluster
echo ""
echo "=========================================="
echo "Step 2: Starting Minikube Cluster"
echo "=========================================="

# Check if minikube is already running
if minikube status --profile cbt-demo >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠${NC} Minikube cluster 'cbt-demo' already exists"
    read -r -p "Delete and recreate? (y/N): " response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo "Deleting existing cluster..."
        minikube delete --profile cbt-demo
    else
        echo "Using existing cluster"
    fi
fi

if ! minikube status --profile cbt-demo >/dev/null 2>&1; then
    echo "Starting minikube with Docker driver..."
    echo "  Driver: docker"
    echo "  CPUs: 4"
    echo "  Memory: 8192MB"
    echo "  Kubernetes: v1.34.0 (CBT alpha support)"
    echo ""

    minikube start \
        --profile cbt-demo \
        --driver=docker \
        --cpus=4 \
        --memory=8192 \
        --kubernetes-version=v1.34.0 \
        --container-runtime=containerd \
        --wait=all

    echo -e "${GREEN}✓ Minikube cluster started${NC}"
else
    echo -e "${GREEN}✓ Using existing minikube cluster${NC}"
fi

# Set kubectl context
kubectl config use-context cbt-demo

# Verify cluster
echo ""
echo "Verifying cluster..."
kubectl cluster-info
kubectl get nodes

echo ""
echo -e "${BLUE}ℹ${NC} Minikube provides full block device support via VM"

# Step 3: Install VolumeSnapshot CRDs
echo ""
echo "=========================================="
echo "Step 3: Installing VolumeSnapshot CRDs"
echo "=========================================="

echo "Installing VolumeSnapshot CRDs..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v8.2.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v8.2.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v8.2.0/client/config/crd/snapshot.storage.k8s.io_volumesnapshots.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v8.2.0/client/config/crd/groupsnapshot.storage.k8s.io_volumegroupsnapshotclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v8.2.0/client/config/crd/groupsnapshot.storage.k8s.io_volumegroupsnapshotcontents.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/external-snapshotter/v8.2.0/client/config/crd/groupsnapshot.storage.k8s.io_volumegroupsnapshots.yaml

echo -e "${GREEN}✓ VolumeSnapshot CRDs installed${NC}"

# Step 4: Deploy MinIO
echo ""
echo "=========================================="
echo "Step 4: Deploying MinIO S3 Storage"
echo "=========================================="

if ./scripts/01-deploy-minio.sh; then
    echo -e "${GREEN}✓ MinIO deployed${NC}"
else
    echo -e "${RED}✗ MinIO deployment failed${NC}"
    exit 1
fi

# Step 5: Deploy CSI Driver
echo ""
echo "=========================================="
echo "Step 5: Deploying CSI Driver with CBT"
echo "=========================================="

if ./scripts/02-deploy-csi-driver.sh; then
    echo -e "${GREEN}✓ CSI driver deployed${NC}"
else
    echo -e "${RED}✗ CSI driver deployment failed${NC}"
    exit 1
fi

# Step 6: Validate CBT
echo ""
echo "=========================================="
echo "Step 6: Validating CBT Configuration"
echo "=========================================="

if ./scripts/validate-cbt.sh; then
    echo -e "${GREEN}✓ CBT validation passed${NC}"
else
    echo -e "${YELLOW}⚠ CBT validation had warnings${NC}"
fi

# Step 7: Deploy workload
echo ""
echo "=========================================="
echo "Step 7: Deploying PostgreSQL Workload"
echo "=========================================="

if ./scripts/03-deploy-workload.sh; then
    echo -e "${GREEN}✓ PostgreSQL deployed${NC}"
else
    echo -e "${RED}✗ PostgreSQL deployment failed${NC}"
    exit 1
fi

# Step 8: Run demo workflow
echo ""
echo "=========================================="
echo "Step 8: Running Demo Workflow"
echo "=========================================="
echo ""
echo "This will create snapshots and demonstrate CBT..."
echo ""

if ./scripts/04-run-demo.sh; then
    echo -e "${GREEN}✓ Demo workflow completed${NC}"
else
    echo -e "${RED}✗ Demo workflow failed${NC}"
    exit 1
fi

# Get minikube IP for service access
MINIKUBE_IP=$(minikube ip --profile cbt-demo)

# Success summary
echo ""
echo "=========================================="
echo "✓ Minikube Demo Setup Complete!"
echo "=========================================="
echo ""
echo "Your demo environment is ready with FULL block device support:"
echo ""
echo "Cluster:"
echo "  • Minikube profile: cbt-demo"
echo "  • Kubernetes: v1.34.0 (CBT alpha enabled)"
echo "  • Driver: docker (VM-based)"
echo "  • Context: cbt-demo"
echo ""
echo "Services:"
echo "  • MinIO Console: http://$MINIKUBE_IP:30901"
echo "    Credentials: minioadmin / minioadmin123"
echo "  • Or use port-forward: kubectl port-forward -n cbt-demo svc/minio 9001:9001"
echo ""
echo "Resources created:"
echo "  • Namespace: cbt-demo"
echo "  • PostgreSQL with data"
echo "  • 3 VolumeSnapshots"
echo ""
echo "Next steps:"
echo "  1. Access MinIO:           minikube service minio -n cbt-demo --profile cbt-demo"
echo "  2. Check backup status:    ./scripts/backup-status.sh"
echo "  3. Check integrity:        ./scripts/integrity-check.sh"
echo "  4. Test disaster recovery: ./scripts/05-simulate-disaster.sh"
echo ""
echo "View resources:"
echo "  kubectl get all -n cbt-demo"
echo "  kubectl get volumesnapshot -n cbt-demo"
echo "  kubectl get pvc -n cbt-demo"
echo ""
echo "Minikube commands:"
echo "  minikube dashboard --profile cbt-demo  # Open Kubernetes dashboard"
echo "  minikube ssh --profile cbt-demo       # SSH into VM"
echo "  minikube stop --profile cbt-demo      # Stop cluster"
echo "  minikube start --profile cbt-demo     # Start cluster"
echo ""
echo "Cleanup:"
echo "  minikube delete --profile cbt-demo"
echo ""
echo "✅ Block Device Support:"
echo "  • This setup uses minikube's VM, providing FULL block device support"
echo "  • Block PVCs work reliably (unlike Kind)"
echo "  • Can test actual CBT block-level metadata"
echo "  • Same setup as upstream kubernetes-csi/external-snapshot-metadata CI"
echo ""
