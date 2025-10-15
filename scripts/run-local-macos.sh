#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "K8s CBT Demo - macOS Local Setup"
echo "=========================================="
echo ""
echo "This script will:"
echo "  1. Check prerequisites (kind, kubectl, docker)"
echo "  2. Create Kind cluster"
echo "  3. Deploy MinIO S3 storage"
echo "  4. Deploy CSI driver with CBT"
echo "  5. Deploy PostgreSQL workload"
echo "  6. Run demo workflow with snapshots"
echo ""
echo "⚠️  Note: This uses Kind with filesystem PVCs (not block mode)"
echo "    For full block device testing, use minikube or cloud providers."
echo ""
read -r -p "Press Enter to continue or Ctrl+C to cancel..."

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check version
check_version() {
    local cmd=$1
    local min_version=$2
    local current_version

    case $cmd in
        kind)
            current_version=$(kind version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/v//')
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

# Check kind
echo -n "Checking kind... "
if command_exists kind; then
    KIND_VERSION=$(check_version kind)
    echo -e "${GREEN}✓${NC} Found version $KIND_VERSION"
else
    echo -e "${RED}✗${NC} Not found"
    echo "  Install with: brew install kind"
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

# Step 2: Setup cluster
echo ""
echo "=========================================="
echo "Step 2: Setting up Kind Cluster"
echo "=========================================="

if ./scripts/00-setup-cluster.sh; then
    echo -e "${GREEN}✓ Cluster created${NC}"
else
    echo -e "${RED}✗ Cluster creation failed${NC}"
    exit 1
fi

# Switch to the cluster context
kubectl config use-context kind-cbt-demo

# Step 3: Deploy MinIO
echo ""
echo "=========================================="
echo "Step 3: Deploying MinIO S3 Storage"
echo "=========================================="

if ./scripts/01-deploy-minio.sh; then
    echo -e "${GREEN}✓ MinIO deployed${NC}"
else
    echo -e "${RED}✗ MinIO deployment failed${NC}"
    exit 1
fi

# Step 4: Deploy CSI Driver
echo ""
echo "=========================================="
echo "Step 4: Deploying CSI Driver with CBT"
echo "=========================================="

if ./scripts/02-deploy-csi-driver.sh; then
    echo -e "${GREEN}✓ CSI driver deployed${NC}"
else
    echo -e "${RED}✗ CSI driver deployment failed${NC}"
    exit 1
fi

# Step 5: Validate CBT
echo ""
echo "=========================================="
echo "Step 5: Validating CBT Configuration"
echo "=========================================="

if ./scripts/validate-cbt.sh; then
    echo -e "${GREEN}✓ CBT validation passed${NC}"
else
    echo -e "${YELLOW}⚠ CBT validation had warnings (this is expected)${NC}"
fi

# Step 6: Deploy workload
echo ""
echo "=========================================="
echo "Step 6: Deploying PostgreSQL Workload"
echo "=========================================="

if ./scripts/03-deploy-workload.sh; then
    echo -e "${GREEN}✓ PostgreSQL deployed${NC}"
else
    echo -e "${RED}✗ PostgreSQL deployment failed${NC}"
    exit 1
fi

# Step 7: Run demo workflow
echo ""
echo "=========================================="
echo "Step 7: Running Demo Workflow"
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

# Success summary
echo ""
echo "=========================================="
echo "✓ Local Demo Setup Complete!"
echo "=========================================="
echo ""
echo "Your demo environment is ready:"
echo ""
echo "Cluster:"
echo "  • Kind cluster: cbt-demo"
echo "  • Context: kind-cbt-demo"
echo ""
echo "Services:"
echo "  • MinIO Console: http://localhost:30901"
echo "    Credentials: minioadmin / minioadmin123"
echo ""
echo "Resources created:"
echo "  • Namespace: cbt-demo"
echo "  • PostgreSQL with data"
echo "  • 3 VolumeSnapshots"
echo ""
echo "Next steps:"
echo "  1. Access MinIO:           open http://localhost:30901"
echo "  2. Check backup status:    ./scripts/backup-status.sh"
echo "  3. Check integrity:        ./scripts/integrity-check.sh"
echo "  4. Test disaster recovery: ./scripts/05-simulate-disaster.sh"
echo ""
echo "View resources:"
echo "  kubectl get all -n cbt-demo"
echo "  kubectl get volumesnapshot -n cbt-demo"
echo "  kubectl get pvc -n cbt-demo"
echo ""
echo "Cleanup:"
echo "  ./scripts/cleanup.sh"
echo ""
echo "⚠️  Important Notes:"
echo "  • This demo uses filesystem PVCs (not block mode)"
echo "  • Block devices don't work reliably in Kind"
echo "  • For full CBT testing, use minikube or cloud providers"
echo "  • See docs/MINIKUBE_VS_KIND.md for details"
echo ""
