# CBT Backup Tool

A backup tool for Kubernetes block volumes using Changed Block Tracking (CBT).

## Overview

This tool creates VolumeSnapshots of Kubernetes PVCs and backs up block-level data to S3-compatible storage. It's designed to work with the CSI SnapshotMetadata service for incremental backups.

## Current Status

✅ **Implemented:**
- Kubernetes VolumeSnapshot creation and management
- S3/MinIO client for backup storage
- Block device reader/writer
- Backup metadata structures
- CLI with create and list commands

⚠️ **TODO:**
- Full gRPC client for CSI SnapshotMetadata service
- GetMetadataDelta RPC for incremental backups
- GetMetadataAllocated RPC for full backups
- Block data upload to S3

See [`pkg/metadata/cbt_client.go`](pkg/metadata/cbt_client.go) for detailed implementation notes.

## Building

```bash
# Install dependencies
go mod download

# Build
go build -o cbt-backup ./cmd

# Or use Docker
docker build -t cbt-backup:latest .
```

## Usage

### Create a Backup

```bash
# Full backup
./cbt-backup create \
  --pvc postgres-data-postgres-0 \
  --namespace cbt-demo

# Incremental backup
./cbt-backup create \
  --pvc postgres-data-postgres-0 \
  --base-snapshot postgres-snapshot-1 \
  --namespace cbt-demo
```

### List Backups

```bash
./cbt-backup list
```

## Command-Line Flags

### Common Flags

- `--namespace, -n`: Kubernetes namespace (default: "cbt-demo")
- `--s3-endpoint, -e`: S3 endpoint (default: "minio.cbt-demo.svc.cluster.local:9000")
- `--s3-access-key, -a`: S3 access key (default: "minioadmin")
- `--s3-secret-key, -k`: S3 secret key (default: "minioadmin123")
- `--s3-bucket, -B`: S3 bucket name (default: "snapshots")
- `--s3-use-ssl`: Use SSL for S3 connections (default: false)

### Backup Flags

- `--pvc, -p`: PVC name to backup (required)
- `--snapshot, -s`: Snapshot name (auto-generated if not provided)
- `--base-snapshot, -b`: Base snapshot for incremental backup
- `--device, -d`: Block device path (auto-detected if not provided)
- `--block-size`: Block size in bytes (default: 1048576 = 1MB)
- `--kubeconfig`: Path to kubeconfig file
- `--snapshot-class`: VolumeSnapshotClass name (default: "csi-hostpath-snapclass")

## S3 Storage Layout

```
s3://snapshots/
├── metadata/
│   └── <snapshot-name>/
│       ├── manifest.json      # Snapshot metadata
│       ├── blocks.json         # Block list
│       └── chain.json          # Dependency chain
└── blocks/
    └── <snapshot-name>/
        └── block-<offset>-<size>  # Block data
```

## Metadata Structures

### Manifest (`manifest.json`)

```json
{
  "name": "postgres-snapshot-1",
  "namespace": "cbt-demo",
  "pvcName": "postgres-data-postgres-0",
  "timestamp": "2025-01-15T10:30:00Z",
  "volumeSize": 2147483648,
  "isIncremental": false,
  "totalBlocks": 2048,
  "totalSize": 2147483648,
  "blockSize": 1048576,
  "volumeMode": "Block",
  "csiDriver": "hostpath.csi.k8s.io"
}
```

### Block List (`blocks.json`)

```json
{
  "blocks": [
    {"offset": 0, "size": 1048576},
    {"offset": 1048576, "size": 1048576}
  ]
}
```

### Chain (`chain.json`)

```json
{
  "snapshotName": "postgres-snapshot-2",
  "baseSnapshotName": "postgres-snapshot-1",
  "isIncremental": true,
  "dependencies": ["postgres-snapshot-1"]
}
```

## Running in Kubernetes

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: backup-postgres
  namespace: cbt-demo
spec:
  template:
    spec:
      serviceAccountName: cbt-backup
      containers:
      - name: backup
        image: cbt-backup:latest
        command:
        - /cbt-backup
        - create
        - --pvc=postgres-data-postgres-0
        - --namespace=cbt-demo
      restartPolicy: OnFailure
```

## Development

### Package Structure

- `cmd/`: CLI entry point
- `pkg/snapshot/`: Kubernetes VolumeSnapshot operations
- `pkg/s3/`: S3/MinIO client
- `pkg/blocks/`: Block device reader/writer
- `pkg/metadata/`: Backup metadata and CBT client

### Testing

```bash
# Run tests
go test -v ./...

# Run with race detector
go test -race ./...
```

## Future Enhancements

- [ ] Complete gRPC client implementation
- [ ] Block compression (gzip, zstd)
- [ ] Encryption at rest
- [ ] Parallel block uploads
- [ ] Progress bars
- [ ] Retry logic with exponential backoff
- [ ] Deduplication across snapshots
- [ ] Support for multiple PVCs
- [ ] Backup scheduling
- [ ] Prometheus metrics

## Contributing

See the main project [README.md](../../README.md) for contributing guidelines.

## License

MIT License - See [LICENSE](../../LICENSE) for details.
