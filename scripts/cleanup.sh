#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Cleaning up CBT demo environment"
echo "=========================================="

# Delete the Kind cluster
if kind get clusters | grep -q "^cbt-demo$"; then
    echo "Deleting Kind cluster..."
    kind delete cluster --name cbt-demo
fi

# Clean up temp directories
echo "Cleaning up temporary directories..."
rm -rf /tmp/cbt-demo-csi
rm -rf /tmp/cbt-demo-minio
rm -rf /tmp/csi-driver-host-path

echo ""
echo "✓ Cleanup complete!"
