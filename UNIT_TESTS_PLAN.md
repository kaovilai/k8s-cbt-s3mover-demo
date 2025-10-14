# Unit Tests Plan for Kubernetes CBT Demo

## Overview

This document outlines the comprehensive testing strategy for the Kubernetes Changed Block Tracking (CBT) demo implementation. Tests are organized by component and include unit tests, integration tests, and end-to-end scenarios.

## Test Framework and Tools

### Required Testing Libraries
```go
// Core testing
testing                     // Standard Go testing
github.com/stretchr/testify // Assertions and test suites

// Mocking
github.com/golang/mock      // Mock generation
github.com/stretchr/testify/mock // Mock assertions

// Kubernetes testing
k8s.io/client-go/fake       // Fake K8s client
k8s.io/apimachinery/pkg/runtime // Runtime objects

// gRPC testing
google.golang.org/grpc/test/bufconn // In-memory gRPC connections

// S3/MinIO testing
github.com/minio/minio-go/v7 // MinIO client with mock server
```

### Test Coverage Goals
- **Unit Tests**: ≥ 80% code coverage
- **Integration Tests**: All critical paths
- **E2E Tests**: Complete backup/restore workflow
- **Performance Tests**: Block processing benchmarks

## Component Test Requirements

### 1. Backup Tool (`tools/backup/`)

#### 1.1 Main Package Tests (`cmd/main_test.go`)
```go
// Test cases:
- TestMainCommandInitialization
  - Verify cobra command setup
  - Validate required flags
  - Test help text generation

- TestConfigValidation
  - Valid configuration acceptance
  - Missing required fields rejection
  - Invalid endpoint format handling
  - Port range validation

- TestSignalHandling
  - Graceful shutdown on SIGTERM
  - Cleanup on SIGINT
  - Resource cleanup verification
```

#### 1.2 Backup Package Tests (`pkg/backup/backup_test.go`)

##### Core Backup Logic
```go
// BackupManager tests
- TestNewBackupManager
  - Successful initialization
  - Invalid K8s config handling
  - MinIO connection failure

- TestCreateVolumeSnapshot
  - Successful snapshot creation
  - PVC not found error
  - Snapshot already exists
  - Timeout handling
  - Status verification

- TestWaitForSnapshotReady
  - Ready state transition
  - Timeout scenario
  - Error state handling
  - Retry logic

- TestProcessChangedBlocks
  - Full backup (no parent)
  - Incremental backup with parent
  - Empty change list
  - Large block count (>10000)
  - Block size validation
```

##### Metadata Service Tests
```go
- TestConnectToSnapshotMetadataService
  - Successful connection
  - Service not available
  - Authentication failure
  - Network timeout
  - Retry backoff

- TestGetChangedBlockMetadata
  - Valid metadata retrieval
  - Invalid snapshot handle
  - Parent snapshot not found
  - Metadata parsing errors
  - Large response handling

- TestGetAllocatedBlockMetadata
  - Full allocation map
  - Sparse allocation
  - Empty volume
  - Metadata version compatibility
```

##### Block Processing Tests
```go
- TestReadBlockFromSnapshot
  - Successful block read
  - Offset boundary validation
  - Size limit enforcement
  - Read permission errors
  - Concurrent reads

- TestUploadBlockToMinIO
  - Successful upload
  - Retry on failure
  - Checksum validation
  - Duplicate block handling
  - Network interruption recovery

- TestCalculateBlockChecksum
  - SHA256 calculation
  - Empty block handling
  - Large block performance
  - Concurrent checksum generation

- TestCreateBackupManifest
  - Manifest structure validation
  - Metadata inclusion
  - Block list accuracy
  - JSON marshaling
  - Parent reference linking

- TestUploadManifestToMinIO
  - Successful upload
  - Overwrite protection
  - Compression handling
  - Error recovery
```

#### 1.3 Storage Package Tests (`pkg/storage/minio_test.go`)

```go
- TestNewMinIOClient
  - Valid configuration
  - Invalid endpoint
  - Authentication failure
  - SSL/TLS configuration
  - Connection pooling

- TestEnsureBucketExists
  - Create new bucket
  - Existing bucket handling
  - Permission errors
  - Bucket naming validation

- TestListBackups
  - Empty bucket
  - Multiple backups
  - Pagination handling
  - Filter by prefix
  - Sorting by timestamp

- TestDownloadBlock
  - Successful download
  - Block not found
  - Partial read handling
  - Concurrent downloads
  - Checksum verification

- TestDeleteOldBackups
  - Retention policy enforcement
  - Keep minimum backups
  - Chain dependency preservation
  - Dry-run mode
```

### 2. Restore Tool (`tools/restore/`)

#### 2.1 Main Package Tests (`cmd/main_test.go`)
```go
- TestRestoreCommandInitialization
  - Command structure validation
  - Required flags verification
  - Default values

- TestRestoreConfigParsing
  - YAML configuration loading
  - Environment variable override
  - Validation rules
```

#### 2.2 Restore Package Tests (`pkg/restore/restore_test.go`)

##### Core Restore Logic
```go
- TestNewRestoreManager
  - Initialization with valid config
  - K8s client creation
  - MinIO client setup
  - Resource validation

- TestSelectBackupToRestore
  - Latest backup selection
  - Specific timestamp selection
  - Invalid backup handling
  - Manifest validation

- TestDownloadBackupManifest
  - Successful download
  - Manifest parsing
  - Corruption detection
  - Version compatibility

- TestCreateTargetPVC
  - New PVC creation
  - Existing PVC handling
  - Size validation
  - StorageClass selection
  - Access mode configuration

- TestRestoreBlocks
  - Sequential block restore
  - Parallel block restore
  - Missing block handling
  - Checksum validation
  - Progress tracking
  - Error recovery

- TestWriteBlockToPVC
  - Direct block device writing
  - Offset calculation
  - Boundary validation
  - Permission handling
  - Concurrent write protection

- TestVerifyRestoration
  - Checksum comparison
  - Block count validation
  - Size verification
  - Data integrity check
```

##### Chain Management Tests
```go
- TestResolveBlockChain
  - Single backup restoration
  - Full chain reconstruction
  - Broken chain detection
  - Circular reference prevention
  - Optimization for minimal downloads

- TestMergeBlockMaps
  - Non-overlapping blocks
  - Overlapping blocks (newer wins)
  - Chain priority ordering
  - Memory efficiency

- TestDownloadBlocksFromChain
  - Parallel downloads
  - Retry logic
  - Cache management
  - Bandwidth throttling
```

### 3. Shared Utilities Tests

#### 3.1 CSI Client Tests (`pkg/csi/client_test.go`)

```go
- TestNewCSIClient
  - Socket connection establishment
  - Unix socket validation
  - Connection timeout
  - Reconnection logic

- TestGetSnapshotMetadata
  - Valid metadata request
  - Invalid snapshot ID
  - Service unavailable
  - Response parsing
  - Timeout handling

- TestGetAllocatedBlocks
  - Full allocation request
  - Partial allocation
  - Large volume handling
  - Token pagination

- TestStreamChangedBlocks
  - Stream initialization
  - Block iteration
  - Error during stream
  - Connection interruption
  - Stream cancellation
```

#### 3.2 Kubernetes Utils Tests (`pkg/k8s/utils_test.go`)

```go
- TestCreateVolumeSnapshotClass
  - Class creation
  - Existing class handling
  - Parameter validation
  - Driver validation

- TestWaitForSnapshotReady
  - State transition monitoring
  - Timeout mechanism
  - Error state detection
  - Retry intervals

- TestGetPVCByName
  - PVC retrieval
  - Namespace isolation
  - Not found handling
  - Label filtering

- TestCreatePVCFromSnapshot
  - PVC creation from snapshot
  - Size specification
  - StorageClass selection
  - Access mode configuration

- TestValidateVolumeMode
  - Block mode validation
  - Filesystem mode rejection
  - Nil mode handling
```

#### 3.3 Block Utils Tests (`pkg/utils/block_test.go`)

```go
- TestCalculateSHA256
  - Correct hash calculation
  - Empty data handling
  - Large data performance
  - Concurrent calculations

- TestCompareChecksums
  - Matching checksums
  - Different checksums
  - Case sensitivity
  - Invalid format

- TestBlockRange
  - Offset calculation
  - Size validation
  - Boundary conditions
  - Overlap detection

- TestReadBlockFromDevice
  - Direct device reading
  - Offset seeking
  - Buffer management
  - EOF handling

- TestWriteBlockToDevice
  - Direct device writing
  - Offset positioning
  - Partial write handling
  - Sync operations
```

### 4. Integration Tests

#### 4.1 Backup Integration Tests (`tests/integration/backup_test.go`)

```go
- TestFullBackupWorkflow
  Setup:
    - Create Kind/Minikube cluster
    - Deploy CSI driver with CBT
    - Setup MinIO instance
    - Create test PVC with data

  Test:
    - Create snapshot
    - Connect to metadata service
    - Read all blocks
    - Upload to MinIO
    - Verify manifest creation

  Validation:
    - All blocks uploaded
    - Manifest contains metadata
    - Checksums match

- TestIncrementalBackupWorkflow
  Setup:
    - Complete full backup
    - Modify data in PVC
    - Create new snapshot

  Test:
    - Detect changed blocks
    - Upload only changes
    - Link to parent backup

  Validation:
    - Only changed blocks uploaded
    - Parent reference correct
    - Block count matches changes

- TestConcurrentBackups
  - Multiple PVCs simultaneously
  - Resource contention handling
  - Isolation verification
```

#### 4.2 Restore Integration Tests (`tests/integration/restore_test.go`)

```go
- TestFullRestoreWorkflow
  Setup:
    - Complete backup available
    - Fresh cluster/namespace
    - MinIO accessible

  Test:
    - Download manifest
    - Create target PVC
    - Restore all blocks
    - Mount and verify data

  Validation:
    - Data integrity check
    - Checksum comparison
    - Application functionality

- TestIncrementalRestoreWorkflow
  Setup:
    - Multiple incremental backups
    - Chain of dependencies

  Test:
    - Resolve block chain
    - Download from multiple backups
    - Merge blocks correctly

  Validation:
    - Latest data restored
    - No missing blocks
    - Chain integrity

- TestDisasterRecovery
  Setup:
    - Simulate cluster failure
    - New cluster provisioned

  Test:
    - Restore from remote backup
    - Recreate all PVCs
    - Restore application state

  Validation:
    - Full recovery achieved
    - Data consistency
    - Application operational
```

#### 4.3 CSI Driver Integration Tests (`tests/integration/csi_test.go`)

```go
- TestSnapshotMetadataService
  - Service discovery
  - Connection establishment
  - Metadata retrieval
  - Error handling

- TestChangedBlockTracking
  - Initial snapshot (all blocks)
  - Incremental changes detection
  - Block allocation tracking
  - Metadata accuracy

- TestCSIDriverFailover
  - Primary driver failure
  - Backup driver activation
  - State preservation
  - Recovery verification
```

### 5. End-to-End Tests

#### 5.1 Complete Workflow Tests (`tests/e2e/workflow_test.go`)

```go
- TestCompleteBackupRestoreScenario
  Scenario:
    1. Deploy PostgreSQL with data
    2. Create initial backup (T0)
    3. Insert 100MB data
    4. Create incremental backup (T1)
    5. Insert 200MB data
    6. Create incremental backup (T2)
    7. Simulate disaster
    8. Restore to T2
    9. Verify all data

  Assertions:
    - Backup sizes: T0=1GB, T1=100MB, T2=200MB
    - Restore completes successfully
    - PostgreSQL query returns expected rows
    - Performance within thresholds

- TestMultiVolumeScenario
  - Multiple PVCs per application
  - Consistent backup point
  - Atomic restore operation
  - Cross-volume integrity

- TestLargeScaleScenario
  - 50+ PVCs
  - 100GB+ total data
  - Parallel processing
  - Performance benchmarks
```

#### 5.2 Failure Scenario Tests (`tests/e2e/failure_test.go`)

```go
- TestBackupInterruption
  - Network failure during upload
  - Resume capability
  - Partial backup handling
  - Cleanup verification

- TestRestoreInterruption
  - Failure during block download
  - Partial restore rollback
  - Retry mechanism
  - Data consistency

- TestMinIOOutage
  - Temporary unavailability
  - Retry with backoff
  - Queue management
  - Recovery procedures

- TestCSIDriverCrash
  - Driver pod termination
  - Graceful degradation
  - Reconnection logic
  - State recovery

- TestCorruptedBackup
  - Checksum mismatch detection
  - Block corruption handling
  - Chain break recovery
  - Alert generation
```

### 6. Performance Tests

#### 6.1 Benchmark Tests (`tests/benchmark/benchmark_test.go`)

```go
- BenchmarkBlockChecksum
  - Various block sizes (1MB, 4MB, 16MB)
  - Parallel computation
  - Memory usage

- BenchmarkBlockUpload
  - Single vs parallel uploads
  - Network bandwidth utilization
  - Compression impact

- BenchmarkBlockDownload
  - Sequential vs parallel
  - Cache effectiveness
  - Bandwidth throttling

- BenchmarkMetadataProcessing
  - Large metadata sets (10K+ blocks)
  - Parsing performance
  - Memory efficiency

- BenchmarkChainResolution
  - Deep chain traversal (10+ backups)
  - Optimization effectiveness
  - Cache impact
```

#### 6.2 Load Tests (`tests/load/load_test.go`)

```go
- TestHighVolumeBackups
  - 100+ concurrent backups
  - Resource utilization
  - Queue management
  - Error rates

- TestLargeBlockVolumes
  - 1TB+ volume backup
  - Memory management
  - Streaming efficiency
  - Completion time

- TestRapidChangeRate
  - High frequency changes
  - CBT accuracy
  - Metadata service load
  - Block deduplication
```

### 7. Mock Implementations

#### 7.1 Mock Services (`tests/mocks/`)

```go
// K8s Client Mock
type MockK8sClient struct {
    mock.Mock
}

// MinIO Client Mock
type MockMinIOClient struct {
    mock.Mock
}

// CSI Client Mock
type MockCSIClient struct {
    mock.Mock
}

// Snapshot Metadata Service Mock
type MockMetadataService struct {
    mock.Mock
}
```

### 8. Test Data Fixtures

#### 8.1 Test Data (`tests/fixtures/`)

```yaml
# sample-backup-manifest.yaml
apiVersion: cbt.io/v1alpha1
kind: BackupManifest
metadata:
  name: test-backup-001
  timestamp: "2024-01-15T10:00:00Z"
spec:
  volumeSize: 1073741824
  blockSize: 1048576
  totalBlocks: 1024
  changedBlocks: 10
  parentBackup: ""
  blocks:
    - offset: 0
      size: 1048576
      checksum: "abc123..."
```

```go
// block-data.go
var TestBlocks = [][]byte{
    GenerateRandomBlock(1048576),  // 1MB blocks
    GenerateZeroBlock(1048576),
    GeneratePatternBlock(1048576, 0xFF),
}
```

### 9. Test Execution Strategy

#### 9.1 Test Organization
```bash
# Directory structure
tests/
├── unit/           # Unit tests for individual functions
├── integration/    # Integration tests with real components
├── e2e/           # End-to-end workflow tests
├── benchmark/     # Performance benchmarks
├── load/          # Load and stress tests
├── mocks/         # Mock implementations
└── fixtures/      # Test data and configurations
```

#### 9.2 Test Commands
```bash
# Run all unit tests
go test ./tools/backup/... ./tools/restore/... -v

# Run with coverage
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out

# Run integration tests
go test ./tests/integration/... -tags=integration

# Run E2E tests
go test ./tests/e2e/... -tags=e2e

# Run benchmarks
go test -bench=. ./tests/benchmark/...

# Run specific test
go test -run TestFullBackupWorkflow ./tests/integration/
```

#### 9.3 CI/CD Integration
```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: actions/setup-go@v2
      - run: go test ./...

  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - run: |
          kind create cluster
          kubectl apply -f manifests/
          go test -tags=integration ./tests/integration/...
```

### 10. Test Quality Metrics

#### 10.1 Coverage Requirements
- **Critical Paths**: 100% coverage required
  - Backup creation
  - Block processing
  - Restore operations
  - Error handling

- **Standard Paths**: ≥ 80% coverage
  - Configuration parsing
  - Utility functions
  - Logging

- **UI/CLI**: ≥ 60% coverage
  - Command parsing
  - Flag validation
  - Help text

#### 10.2 Test Execution Time Targets
- Unit tests: < 10 seconds
- Integration tests: < 5 minutes
- E2E tests: < 15 minutes
- Full test suite: < 30 minutes

#### 10.3 Test Maintenance Guidelines
1. **Test Naming**: Use descriptive names that explain what is being tested
2. **Test Independence**: Each test should be runnable in isolation
3. **Test Data**: Use fixtures and factories instead of hardcoded values
4. **Mock Usage**: Prefer real implementations for integration tests
5. **Assertions**: Use specific assertions with meaningful error messages
6. **Cleanup**: Always cleanup resources in defer statements

### 11. Testing Checklist

#### Pre-Implementation
- [ ] Test structure defined
- [ ] Mock interfaces created
- [ ] Test data fixtures prepared
- [ ] CI/CD pipeline configured

#### During Implementation
- [ ] Unit tests written alongside code
- [ ] Integration tests for each component
- [ ] E2E tests for critical workflows
- [ ] Performance benchmarks established

#### Post-Implementation
- [ ] Coverage goals met (≥80%)
- [ ] All tests passing
- [ ] Performance benchmarks documented
- [ ] Test documentation updated
- [ ] CI/CD pipeline green

### 12. Known Testing Challenges

1. **CSI Driver Mocking**: Complex gRPC service requiring careful mock setup
2. **MinIO Integration**: Need embedded MinIO server for tests
3. **Kubernetes Resources**: Require fake client or Kind cluster
4. **Block Device Access**: May need privileged containers for testing
5. **Large Data Sets**: Memory constraints for large volume tests
6. **Timing Issues**: Snapshot readiness requires careful polling

### 13. Future Test Enhancements

1. **Chaos Testing**: Introduce controlled failures
2. **Property-Based Testing**: Generate random test cases
3. **Mutation Testing**: Verify test effectiveness
4. **Contract Testing**: Ensure API compatibility
5. **Security Testing**: Vulnerability scanning
6. **Compliance Testing**: Verify data handling policies

<function_calls>
<invoke name="TodoWrite">
<parameter name="todos">[{"content": "Create UNIT_TESTS_PLAN.md structure", "status": "completed", "activeForm": "Creating UNIT_TESTS_PLAN.md structure"}, {"content": "Define test requirements for backup tool", "status": "in_progress", "activeForm": "Defining test requirements for backup tool"}, {"content": "Define test requirements for restore tool", "status": "pending", "activeForm": "Defining test requirements for restore tool"}, {"content": "Define test requirements for shared utilities", "status": "pending", "activeForm": "Defining test requirements for shared utilities"}, {"content": "Add integration and E2E test scenarios", "status": "pending", "activeForm": "Adding integration and E2E test scenarios"}]