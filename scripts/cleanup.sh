#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Cleaning up CBT demo environment"
echo "=========================================="

# Delete the Minikube cluster
if command -v minikube &>/dev/null && minikube status --profile cbt-demo >/dev/null 2>&1; then
    echo "Deleting Minikube cluster 'cbt-demo'..."
    minikube delete --profile cbt-demo
    echo "✓ Minikube cluster deleted"
else
    echo "  Minikube cluster 'cbt-demo' not found, skipping"
fi

# Clean up temp directories and files
echo "Cleaning up temporary directories and files..."
rm -rf /tmp/cbt-demo-csi
rm -rf /tmp/cbt-demo-minio
rm -rf /tmp/csi-driver-host-path
rm -f /tmp/cbt-demo-pre-disaster-checksum.txt

echo ""
echo "✓ Cleanup complete!"
