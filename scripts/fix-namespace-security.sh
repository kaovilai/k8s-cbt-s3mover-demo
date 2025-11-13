#!/bin/bash
set -euo pipefail

echo "Updating cbt-demo namespace security policy to privileged..."

kubectl patch namespace cbt-demo --type=merge -p '{
  "metadata": {
    "labels": {
      "pod-security.kubernetes.io/enforce": "privileged",
      "pod-security.kubernetes.io/audit": "privileged",
      "pod-security.kubernetes.io/warn": "privileged"
    }
  }
}'

echo "✓ Namespace security policy updated to privileged"
