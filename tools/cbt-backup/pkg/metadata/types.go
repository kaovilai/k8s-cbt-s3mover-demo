package metadata

import (
	"time"

	"github.com/kaovilai/k8s-cbt-s3mover-demo/tools/cbt-backup/pkg/blocks"
)

// SnapshotManifest describes a backup snapshot
type SnapshotManifest struct {
	Name              string    `json:"name"`
	Namespace         string    `json:"namespace"`
	PVCName           string    `json:"pvcName"`
	SnapshotName      string    `json:"snapshotName"`
	Timestamp         time.Time `json:"timestamp"`
	VolumeSize        int64     `json:"volumeSize"`
	IsIncremental     bool      `json:"isIncremental"`
	BaseSnapshotName  string    `json:"baseSnapshotName,omitempty"`
	TotalBlocks       int       `json:"totalBlocks"`
	TotalSize         int64     `json:"totalSize"`
	CompressedSize    int64     `json:"compressedSize,omitempty"`
	BlockSize         int64     `json:"blockSize"`
	StorageClass      string    `json:"storageClass"`
	VolumeMode        string    `json:"volumeMode"`
	CSIDriver         string    `json:"csiDriver"`
	SnapshotClassName string    `json:"snapshotClassName"`
}

// BlockList contains the list of blocks in a snapshot
type BlockList struct {
	Blocks []blocks.BlockMetadata `json:"blocks"`
}

// SnapshotChain describes the dependency chain
type SnapshotChain struct {
	SnapshotName     string   `json:"snapshotName"`
	BaseSnapshotName string   `json:"baseSnapshotName,omitempty"`
	IsIncremental    bool     `json:"isIncremental"`
	Dependencies     []string `json:"dependencies"` // List of snapshots needed for restore
}

// Catalog is the global catalog of all snapshots
type Catalog struct {
	Version   string              `json:"version"`
	Updated   time.Time           `json:"updated"`
	Snapshots []CatalogEntry      `json:"snapshots"`
	Chains    map[string][]string `json:"chains"` // PVC -> list of snapshots
}

// CatalogEntry represents a snapshot in the catalog
type CatalogEntry struct {
	Name          string    `json:"name"`
	PVCName       string    `json:"pvcName"`
	Timestamp     time.Time `json:"timestamp"`
	IsIncremental bool      `json:"isIncremental"`
	BaseSnapshot  string    `json:"baseSnapshot,omitempty"`
	TotalSize     int64     `json:"totalSize"`
	BlockCount    int       `json:"blockCount"`
}

// RestoreManifest describes what's needed for a restore
type RestoreManifest struct {
	TargetPVC       string    `json:"targetPVC"`
	SourceSnapshots []string  `json:"sourceSnapshots"` // Ordered list (base first)
	Timestamp       time.Time `json:"timestamp"`
	TotalSize       int64     `json:"totalSize"`
	BlockCount      int       `json:"blockCount"`
}

// BackupStats holds statistics about a backup operation
type BackupStats struct {
	StartTime         time.Time     `json:"startTime"`
	EndTime           time.Time     `json:"endTime"`
	Duration          time.Duration `json:"duration"`
	BytesRead         int64         `json:"bytesRead"`
	BytesUploaded     int64         `json:"bytesUploaded"`
	BlocksRead        int           `json:"blocksRead"`
	BlocksUploaded    int           `json:"blocksUploaded"`
	BlocksSkipped     int           `json:"blocksSkipped"`     // For incremental
	CompressionRatio  float64       `json:"compressionRatio"`  // If compression used
	AverageBlockSize  int64         `json:"averageBlockSize"`
	UploadThroughput  float64       `json:"uploadThroughput"`  // MB/s
	IsIncremental     bool          `json:"isIncremental"`
	BaseSnapshotName  string        `json:"baseSnapshotName,omitempty"`
	CBTEnabled        bool          `json:"cbtEnabled"`
	Errors            []string      `json:"errors,omitempty"`
}

// RestoreStats holds statistics about a restore operation
type RestoreStats struct {
	StartTime         time.Time     `json:"startTime"`
	EndTime           time.Time     `json:"endTime"`
	Duration          time.Duration `json:"duration"`
	BytesDownloaded   int64         `json:"bytesDownloaded"`
	BytesWritten      int64         `json:"bytesWritten"`
	BlocksDownloaded  int           `json:"blocksDownloaded"`
	BlocksWritten     int           `json:"blocksWritten"`
	SnapshotsApplied  int           `json:"snapshotsApplied"`
	AverageBlockSize  int64         `json:"averageBlockSize"`
	RestoreThroughput float64       `json:"restoreThroughput"` // MB/s
	ChecksumVerified  int           `json:"checksumVerified"`
	ChecksumFailed    int           `json:"checksumFailed"`
	Errors            []string      `json:"errors,omitempty"`
}
