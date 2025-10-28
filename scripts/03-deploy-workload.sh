#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Deploying Block Writer Workload"
echo "=========================================="
echo ""
echo "This pod writes directly to the raw block device (no filesystem)"
echo "This allows CBT to detect actual allocated blocks with data"
echo ""

# Deploy block-writer Pod
echo "Deploying block-writer with block PVC..."
kubectl apply -f manifests/workload/block-writer-pod.yaml

# Wait for block-writer pod to be ready
echo "Waiting for block-writer pod to be ready..."
kubectl wait --for=condition=Ready pod/block-writer -n cbt-demo --timeout=120s || {
    echo "✗ Block-writer pod not ready. Checking logs..."
    kubectl logs -n cbt-demo block-writer --tail=50 || true
    kubectl describe pod -n cbt-demo block-writer
    exit 1
}

# Show results
echo ""
echo "✓ Block writer workload deployed successfully!"
echo ""
echo "Pod info:"
kubectl get pod -n cbt-demo block-writer
echo ""
echo "PVC info:"
kubectl get pvc -n cbt-demo block-writer-data
echo ""
echo "To write data to the raw block device:"
echo "  kubectl exec -n cbt-demo block-writer -- dd if=/dev/urandom of=/dev/xvda bs=4K count=1 seek=0 conv=notrunc"
