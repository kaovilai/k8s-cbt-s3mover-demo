# Integration of kubernetes-csi/external-snapshot-metadata PR #180

**Date**: October 15, 2025
**PR**: https://github.com/kubernetes-csi/external-snapshot-metadata/pull/180
**Status**: Merged to main

## Overview

PR #180 introduces an important API change to the Kubernetes Changed Block Tracking (CBT) snapshot metadata service. The change modifies how base snapshots are identified when computing deltas between snapshots.

## API Changes

### GetMetadataDelta RPC

**Before PR #180:**
```protobuf
message GetMetadataDeltaRequest {
    string security_token = 1;
    string namespace = 2;
    string base_snapshot_name = 3;  // VolumeSnapshot object name
    string target_snapshot_name = 4;
    int64 starting_offset = 5;
    int32 max_results = 6;
}
```

**After PR #180:**
```protobuf
message GetMetadataDeltaRequest {
    string security_token = 1;
    string namespace = 2;
    string base_snapshot_id = 3;    // CSI snapshot handle (preferred) or name
    string target_snapshot_name = 4;
    int64 starting_offset = 5;
    int32 max_results = 6;
}
```

### Key Differences

1. **Field Renamed**: `base_snapshot_name` → `base_snapshot_id`
2. **Value Type**: Now expects the CSI snapshot handle instead of the VolumeSnapshot name
3. **Backward Compatibility**: The iterator package accepts both names and handles, with preference given to the handle

### Obtaining the CSI Snapshot Handle

To get the CSI snapshot handle for use with the new API:

```bash
# 1. Get the VolumeSnapshotContent name from the VolumeSnapshot
VSC_NAME=$(kubectl get volumesnapshot <snapshot-name> -n <namespace> \
  -o jsonpath="{.status.boundVolumeSnapshotContentName}")

# 2. Get the CSI handle from the VolumeSnapshotContent
SNAP_HANDLE=$(kubectl get volumesnapshotcontent $VSC_NAME \
  -o jsonpath="{.status.snapshotHandle}")
```

## Benefits of This Change

### 1. Flexible Snapshot Retention Policies

**Before**: Base snapshots had to be kept as VolumeSnapshot objects to compute deltas
```
Snapshot 1 (VolumeSnapshot + data) ────┐
Snapshot 2 (VolumeSnapshot + data) ────┼─> Both must exist to compute delta
```

**After**: Base snapshot can be deleted; only the CSI handle is needed
```
Snapshot 1 (deleted VolumeSnapshot, but CSI handle saved)
Snapshot 2 (VolumeSnapshot + data)
         ↓
Can still compute delta using saved CSI handle!
```

### 2. Cost Optimization

You can now:
- Delete old VolumeSnapshot objects to reduce Kubernetes API overhead
- Keep only the CSI handles in your backup metadata
- Still perform incremental backups using the handles

### 3. Better Alignment with CSI Driver Implementation

The CSI drivers work with snapshot handles internally. This API change makes the Kubernetes API consistent with the underlying CSI driver expectations.

## Client Tool Updates

The snapshot-metadata-lister and snapshot-metadata-verifier tools now support both approaches:

```bash
# Before PR #180 - Using VolumeSnapshot name
snapshot-metadata-lister -p snap-1 -s snap-2 -n default

# After PR #180 - Using CSI snapshot handle (PREFERRED)
snapshot-metadata-lister -P "csi-handle-abc123" -s snap-2 -n default
```

**Flags**:
- `-p, --previous-snapshot`: VolumeSnapshot object name (before PR #180)
- `-P, --previous-snapshot-id`: CSI snapshot handle (after PR #180, preferred)

If both are specified, `-P` (CSI handle) takes precedence.

## Integration Changes Made to This Repository

### 1. Workflow Files Updated

Both `.github/workflows/demo-aws.yaml` and `.github/workflows/demo.yaml` were updated to:
- Create two snapshots for delta testing
- Demonstrate how to extract the CSI snapshot handle
- Document both the before and after PR #180 approaches
- Explain the benefits of the CSI handle approach

### 2. Backup Tool Documentation Updated

`tools/cbt-backup/pkg/metadata/cbt_client.go`:
- Added detailed comments explaining the API change
- Documented how to obtain CSI snapshot handles
- Updated example code to use the new field names
- Noted the preference for CSI handles in production

### 3. README Documentation Updated

`README.md`:
- Added API Change History section
- Documented the after PR #180 approach in the CBT APIs section
- Added implementation notes to the Backup Tool section
- Explained the benefits for snapshot retention policies

### 4. New Documentation

Created `docs/PR180_INTEGRATION.md` (this file) to:
- Document the integration process
- Explain the changes and their implications
- Provide migration guidance
- Serve as a reference for future development

## Migration Guide

### For New Implementations

**Always use CSI snapshot handles** for the base snapshot:

1. When creating a backup, save the CSI snapshot handle in your metadata
2. When computing deltas, use the saved CSI handle
3. Delete old VolumeSnapshot objects according to your retention policy
4. Continue to use saved handles for delta calculations

### Example Backup Metadata Structure

```json
{
  "snapshot": "snap-2",
  "timestamp": "2025-10-15T10:30:00Z",
  "base_snapshot": {
    "name": "snap-1",
    "csi_handle": "csi-handle-abc123",
    "deleted": false
  },
  "size_bytes": 1073741824,
  "changed_bytes": 104857600
}
```

Later, after deleting snap-1:

```json
{
  "snapshot": "snap-3",
  "timestamp": "2025-10-15T11:00:00Z",
  "base_snapshot": {
    "name": "snap-2",
    "csi_handle": "csi-handle-def456",
    "deleted": false
  },
  "previous_base": {
    "name": "snap-1",
    "csi_handle": "csi-handle-abc123",
    "deleted": true  // Can still compute deltas using the handle!
  },
  "size_bytes": 1073741824,
  "changed_bytes": 52428800
}
```

### For Existing Implementations

If you already have code using `base_snapshot_name`:

1. **Immediate**: Continue using snapshot names - the API maintains backward compatibility
2. **Short-term**: Add logic to save CSI handles in your backup metadata
3. **Long-term**: Migrate to using CSI handles exclusively

## Testing

The workflow files now demonstrate:
1. Creating the first snapshot (baseline)
2. **Writing data to the PVC to create changed blocks** (critical for CBT testing!)
3. Creating the second snapshot (with changes)
4. Extracting CSI snapshot handles
5. Documenting how both approaches would work
6. Explaining the advantages of the after PR #180 approach

**Important**: To properly test Changed Block Tracking, you must modify data between snapshots. The workflows insert 100 additional rows (~10MB) of data between snapshot-1 and snapshot-2, so that `GetMetadataDelta` has actual changed blocks to report.

When the snapshot-metadata-lister/verifier tools become available, they should be tested with both:
- `-p postgres-snapshot-1 -s postgres-snapshot-2` (before PR #180, using snapshot names)
- `-P <csi-handle> -s postgres-snapshot-2` (after PR #180, using CSI handle - preferred)

The tools should report the changed blocks corresponding to the data written between the two snapshots.

## References

- **PR #180**: https://github.com/kubernetes-csi/external-snapshot-metadata/pull/180
- **Issue #165**: Original feature request for this change
- **Merged**: October 15, 2025
- **Type**: API change (action required for new implementations)

## Future Enhancements

Potential improvements building on this change:

1. **Handle Catalog**: Maintain a separate catalog of CSI handles for deleted snapshots
2. **Automatic Handle Extraction**: Backup tools that automatically extract and store handles
3. **Delta Chaining**: Compute deltas across multiple generations using saved handles
4. **Handle Validation**: Verify handle validity before attempting delta calculations

## Conclusion

This API change represents a significant improvement in the flexibility and efficiency of Kubernetes CBT operations. By using CSI snapshot handles instead of VolumeSnapshot names, backup applications can implement more sophisticated retention policies while maintaining the ability to perform incremental backups.

The changes have been integrated into this repository's documentation, code comments, and workflow demonstrations to ensure developers understand and can leverage this new capability.
