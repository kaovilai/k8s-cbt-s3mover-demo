#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Generating TLS Certificates for CSI Snapshot Metadata Service"
echo "=========================================="

NAMESPACE="default"
SECRET_NAME="csi-snapshot-metadata-certs"
SERVICE_NAME="csi-snapshot-metadata"
CERT_DIR="/tmp/csi-certs-$$"

# Create temporary directory for certificates
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

echo "Working directory: $CERT_DIR"

# Step 1: Create OpenSSL extension file for Subject Alternative Names (SANs)
echo "Creating SAN extension file..."
cat > server-ext.cnf <<EOF
subjectAltName=DNS:${SERVICE_NAME},DNS:${SERVICE_NAME}.${NAMESPACE},DNS:${SERVICE_NAME}.${NAMESPACE}.svc,DNS:${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local,IP:0.0.0.0
EOF

# Step 2: Generate CA's private key and self-signed certificate
echo "Generating CA certificate and key..."
openssl req -x509 -newkey rsa:4096 -days 365 -nodes \
    -keyout ca-key.pem \
    -out ca-cert.pem \
    -subj "/CN=${SERVICE_NAME}.${NAMESPACE}" \
    2>/dev/null

echo "✓ CA certificate generated"

# Step 3: Generate server's private key and certificate signing request (CSR)
echo "Generating server certificate signing request..."
openssl req -newkey rsa:4096 -nodes \
    -keyout server-key.pem \
    -out server-req.pem \
    -subj "/CN=${SERVICE_NAME}.${NAMESPACE}" \
    2>/dev/null

echo "✓ Server CSR generated"

# Step 4: Sign the server certificate with the CA
echo "Signing server certificate with CA..."
openssl x509 -req \
    -in server-req.pem \
    -days 60 \
    -CA ca-cert.pem \
    -CAkey ca-key.pem \
    -CAcreateserial \
    -out server-cert.pem \
    -extfile server-ext.cnf \
    2>/dev/null

echo "✓ Server certificate signed"

# Step 5: Verify the certificate
echo ""
echo "Certificate Details:"
echo "-------------------"
openssl x509 -in server-cert.pem -noout -subject -issuer -dates -ext subjectAltName

# Step 6: Create or update Kubernetes TLS secret
echo ""
echo "Creating Kubernetes TLS secret..."

# Check if secret already exists
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "Secret already exists, deleting it first..."
    kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE"
fi

# Create the TLS secret
kubectl create secret tls "$SECRET_NAME" \
    --namespace="$NAMESPACE" \
    --cert=server-cert.pem \
    --key=server-key.pem

echo "✓ TLS secret created: $SECRET_NAME"

# Step 7: Encode CA certificate for SnapshotMetadataService CR
echo ""
echo "Encoding CA certificate for SnapshotMetadataService..."
CA_CERT_BASE64=$(base64 -i ca-cert.pem | tr -d '\n')

# Step 8: Update the SnapshotMetadataService manifest
MANIFEST_FILE="$(dirname "$0")/../manifests/csi-driver/testdata/snapshotmetadataservice.yaml"

if [ -f "$MANIFEST_FILE" ]; then
    echo "Updating $MANIFEST_FILE with generated CA certificate..."

    # Use sed to replace the placeholder with actual base64-encoded CA cert
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS sed requires -i ''
        sed -i '' "s|caCert: PLACEHOLDER_CA_CERT|caCert: $CA_CERT_BASE64|g" "$MANIFEST_FILE"
    else
        # Linux sed
        sed -i "s|caCert: PLACEHOLDER_CA_CERT|caCert: $CA_CERT_BASE64|g" "$MANIFEST_FILE"
    fi

    echo "✓ SnapshotMetadataService manifest updated"
else
    echo "⚠ Warning: SnapshotMetadataService manifest not found at $MANIFEST_FILE"
    echo "You will need to manually update the caCert field with this value:"
    echo "$CA_CERT_BASE64"
fi

# Step 9: Summary
echo ""
echo "=========================================="
echo "✓ TLS Certificate Generation Complete!"
echo "=========================================="
echo ""
echo "Generated files in $CERT_DIR:"
echo "  - ca-cert.pem: CA certificate"
echo "  - ca-key.pem: CA private key"
echo "  - server-cert.pem: Server certificate"
echo "  - server-key.pem: Server private key"
echo ""
echo "Kubernetes resources created:"
echo "  - Secret: $SECRET_NAME (namespace: $NAMESPACE)"
echo ""
echo "Next steps:"
echo "  1. Deploy the CSI driver with snapshot metadata sidecar"
echo "  2. Apply the SnapshotMetadataService CR"
echo "  3. Apply the snapshot metadata service"
echo ""
echo "Note: Certificates will be stored temporarily in $CERT_DIR"
echo "      They will be removed when you restart your system."
echo ""
