# CBT Restore Tool

A restore tool for Kubernetes block volumes backed up with CBT metadata and block objects in S3-compatible storage.

## Overview

`cbt-restore` reconstructs a target block device from backups produced by `cbt-backup`. For incremental targets, it resolves and applies the full snapshot chain (base first, then incrementals in order).

## Current Status

✅ **Implemented:**
- `restore` command for full chain restore to a block device
- `plan` command for dry-run restore planning
- `list` command to enumerate available backups from S3
- Snapshot chain resolution using `manifest.json` metadata
- Block download and device writes from `blocks/<snapshot>/...`
- Restore statistics output and `restore-stats.json` upload

## Building

```bash
# Install dependencies
go mod download

# Build
go build -o cbt-restore ./cmd

# Or use Docker
docker build -t cbt-restore:latest .
```

## Usage

### Restore a Snapshot

```bash
./cbt-restore restore \
  --snapshot block-snapshot-2 \
  --device /dev/xvda
```

### Plan a Restore (Dry Run)

```bash
./cbt-restore plan \
  --snapshot block-snapshot-2
```

### List Available Backups

```bash
./cbt-restore list
```

## Command-Line Flags

### `restore` flags

- `--snapshot, -s` (required): Target snapshot name to restore
- `--device, -d`: Target block device path (default: `"/dev/xvda"`)
- `--verify`: Verify block checksums during restore (default: `true`)

### `plan` flags

- `--snapshot, -s` (required): Target snapshot name

### Common S3 flags (`restore`, `plan`, `list`)

- `--s3-endpoint, -e`: S3 endpoint (default: `"minio.cbt-demo.svc.cluster.local:9000"`)
- `--s3-access-key, -a`: S3 access key (default: `S3_ACCESS_KEY` environment variable; empty if unset)
- `--s3-secret-key, -k`: S3 secret key (default: `S3_SECRET_KEY` environment variable; empty if unset)
- `--s3-bucket, -B`: S3 bucket name (default: `"snapshots"`)
- `--s3-use-ssl`: Use SSL for S3 connections (default: `false`)

## How Restore Works

1. Connect to S3-compatible storage.
2. Resolve snapshot chain from target snapshot using `metadata/<snapshot>/manifest.json`.
3. Open the destination block device for writing.
4. For each snapshot in chain order:
   - Download `metadata/<snapshot>/blocks.json`
   - Download each block object from `blocks/<snapshot>/block-<offset>-<size>`
   - Write block data at the recorded offset
5. Print restore summary and upload `metadata/<target>/restore-stats.json`.

## Snapshot Chain Resolution

For incremental backups, `cbt-restore` follows `baseSnapshotName` until it reaches a full backup.

Example:

- Target: `block-snapshot-3` (incremental, base=`block-snapshot-2`)
- `block-snapshot-2` (incremental, base=`block-snapshot-1`)
- `block-snapshot-1` (full)

Apply order:

1. `block-snapshot-1` (full)
2. `block-snapshot-2` (incremental)
3. `block-snapshot-3` (incremental target)

## Running in Kubernetes

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: cbt-restore
  namespace: cbt-demo
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: restore
        image: cbt-restore:latest
        command:
        - /usr/local/bin/cbt-restore
        - restore
        - --snapshot=block-snapshot-2
        - --device=/dev/xvda
        env:
        - name: S3_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: access-key
        - name: S3_SECRET_KEY
          valueFrom:
            secretKeyRef:
              name: minio-credentials
              key: secret-key
        securityContext:
          privileged: true
```

## Development

### Package Structure

- `cmd/`: CLI entry point (`restore`, `plan`, `list`)
- `pkg/blocks/`: Block writer and checksum helpers
- `pkg/metadata/`: Snapshot/restore metadata structures
- `pkg/s3/`: MinIO/S3 client wrapper

### Testing

```bash
# Run tests
go test -v ./...

# Run with race detector
go test -race ./...
```
